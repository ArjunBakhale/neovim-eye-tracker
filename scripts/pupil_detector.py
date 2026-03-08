"""
Self-contained pupil detector based on JEOresearch/EyeTracker algorithm.

Re-implements the OrloskyPupilDetector pipeline as a single module:
  crop → darkest area → multi-threshold → contour filter → ellipse fit

Entry point: process_frame(frame) -> rotated_rect or None
"""

import cv2
import numpy as np

TARGET_WIDTH = 640
TARGET_HEIGHT = 480
MASK_SIZE = 250
MIN_CONTOUR_AREA = 1000
MAX_ASPECT_RATIO = 3.0
ANGLE_THRESHOLD_DEG = 60.0

# Threshold offsets above darkest pixel value
THRESHOLD_OFFSETS = [5, 15, 25]


def crop_to_aspect_ratio(frame):
    """Crop and resize frame to 640x480 (4:3)."""
    h, w = frame.shape[:2]
    target_ratio = TARGET_WIDTH / TARGET_HEIGHT

    current_ratio = w / h
    if current_ratio > target_ratio:
        new_w = int(h * target_ratio)
        offset = (w - new_w) // 2
        frame = frame[:, offset : offset + new_w]
    elif current_ratio < target_ratio:
        new_h = int(w / target_ratio)
        offset = (h - new_h) // 2
        frame = frame[offset : offset + new_h, :]

    return cv2.resize(frame, (TARGET_WIDTH, TARGET_HEIGHT))


def get_darkest_area(gray, block_size=20, step=10):
    """Sparse scan for darkest block_size x block_size block.

    Returns (x, y, darkest_value) where (x,y) is the center of the block.
    """
    h, w = gray.shape
    best_val = 256
    best_x, best_y = w // 2, h // 2

    for y in range(0, h - block_size, step):
        for x in range(0, w - block_size, step):
            block = gray[y : y + block_size, x : x + block_size]
            mean_val = block.mean()
            if mean_val < best_val:
                best_val = mean_val
                best_x = x + block_size // 2
                best_y = y + block_size // 2

    # Get actual darkest pixel value near that center
    region = gray[
        max(0, best_y - block_size) : best_y + block_size,
        max(0, best_x - block_size) : best_x + block_size,
    ]
    darkest_pixel = int(region.min()) if region.size > 0 else int(best_val)

    return best_x, best_y, darkest_pixel


def apply_binary_threshold(gray, darkest_val, offset, darkest_point):
    """Apply binary threshold and mask to a square around the darkest point."""
    thresh_val = darkest_val + offset
    _, binary = cv2.threshold(gray, thresh_val, 255, cv2.THRESH_BINARY_INV)

    # Mask outside a square around the darkest point
    mask = np.zeros_like(binary)
    cx, cy = darkest_point
    half = MASK_SIZE // 2
    x1 = max(0, cx - half)
    y1 = max(0, cy - half)
    x2 = min(binary.shape[1], cx + half)
    y2 = min(binary.shape[0], cy + half)
    mask[y1:y2, x1:x2] = 255

    masked = cv2.bitwise_and(binary, mask)

    # Dilate to fill gaps
    kernel = np.ones((5, 5), np.uint8)
    dilated = cv2.dilate(masked, kernel, iterations=2)

    return dilated


def find_best_contour(binary):
    """Find the largest valid contour (area > MIN_CONTOUR_AREA, aspect < MAX_ASPECT_RATIO)."""
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)

    best = None
    best_area = 0

    for cnt in contours:
        area = cv2.contourArea(cnt)
        if area < MIN_CONTOUR_AREA:
            continue

        x, y, w, h = cv2.boundingRect(cnt)
        if h == 0:
            continue
        ratio = max(w / h, h / w)
        if ratio > MAX_ASPECT_RATIO:
            continue

        if area > best_area:
            best_area = area
            best = cnt

    return best


def check_ellipse_goodness(contour):
    """Score how well the contour fits an ellipse (0-1)."""
    if len(contour) < 5:
        return 0.0

    ellipse = cv2.fitEllipse(contour)
    center, axes, angle = ellipse
    a, b = axes[0] / 2, axes[1] / 2

    if a <= 0 or b <= 0:
        return 0.0

    # Create ellipse mask and contour mask, compute overlap
    h = int(center[1] + b + 50)
    w = int(center[0] + a + 50)
    if h <= 0 or w <= 0:
        return 0.0

    ellipse_mask = np.zeros((h, w), dtype=np.uint8)
    contour_mask = np.zeros((h, w), dtype=np.uint8)

    cv2.ellipse(ellipse_mask, ellipse, 255, -1)
    cv2.drawContours(contour_mask, [contour], -1, 255, -1)

    intersection = cv2.bitwise_and(ellipse_mask, contour_mask)
    union = cv2.bitwise_or(ellipse_mask, contour_mask)

    union_area = np.count_nonzero(union)
    if union_area == 0:
        return 0.0

    return np.count_nonzero(intersection) / union_area


def check_contour_pixels(contour, binary):
    """Fraction of contour boundary pixels that are white in the binary image."""
    if len(contour) == 0:
        return 0.0

    h, w = binary.shape
    count = 0
    total = len(contour)

    for pt in contour:
        px, py = pt[0]
        if 0 <= px < w and 0 <= py < h and binary[py, px] > 0:
            count += 1

    return count / total if total > 0 else 0.0


def score_threshold_level(contour, binary):
    """Score = ellipse_goodness * contour_pixel_check^2."""
    goodness = check_ellipse_goodness(contour)
    pixel_check = check_contour_pixels(contour, binary)
    return goodness * pixel_check * pixel_check


def optimize_contours_by_angle(contour):
    """Drop contour points not curving toward the centroid."""
    if len(contour) < 10:
        return contour

    M = cv2.moments(contour)
    if M["m00"] == 0:
        return contour

    cx = M["m10"] / M["m00"]
    cy = M["m01"] / M["m00"]

    optimized = []
    pts = contour.reshape(-1, 2)
    n = len(pts)

    for i in range(n):
        p_prev = pts[(i - 1) % n]
        p_curr = pts[i]
        p_next = pts[(i + 1) % n]

        # Vector from prev to next (tangent approximation)
        tangent = p_next - p_prev
        tangent_norm = np.linalg.norm(tangent)
        if tangent_norm == 0:
            continue

        # Vector from point to centroid
        to_center = np.array([cx - p_curr[0], cy - p_curr[1]])
        to_center_norm = np.linalg.norm(to_center)
        if to_center_norm == 0:
            optimized.append(p_curr)
            continue

        # Normal to tangent (perpendicular, pointing inward ideally)
        normal = np.array([-tangent[1], tangent[0]]) / tangent_norm

        # Check if normal aligns with direction to centroid
        cos_angle = np.dot(normal, to_center / to_center_norm)
        angle_deg = np.degrees(np.arccos(np.clip(abs(cos_angle), 0, 1)))

        if angle_deg < ANGLE_THRESHOLD_DEG:
            optimized.append(p_curr)

    if len(optimized) < 5:
        return contour

    return np.array(optimized).reshape(-1, 1, 2)


def process_frame(frame):
    """Process a single frame and return pupil ellipse or None.

    Args:
        frame: BGR image (numpy array)

    Returns:
        rotated_rect: ((cx, cy), (w, h), angle) or None if no pupil found.
        cx, cy are pixel coordinates within the 640x480 processed frame.
    """
    if frame is None or frame.size == 0:
        return None

    frame = crop_to_aspect_ratio(frame)
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    darkest_x, darkest_y, darkest_val = get_darkest_area(gray)
    darkest_point = (darkest_x, darkest_y)

    best_score = -1
    best_contour = None
    best_binary = None

    for offset in THRESHOLD_OFFSETS:
        binary = apply_binary_threshold(gray, darkest_val, offset, darkest_point)
        contour = find_best_contour(binary)
        if contour is None:
            continue

        score = score_threshold_level(contour, binary)
        if score > best_score:
            best_score = score
            best_contour = contour
            best_binary = binary

    if best_contour is None or len(best_contour) < 5:
        return None

    optimized = optimize_contours_by_angle(best_contour)
    if len(optimized) < 5:
        optimized = best_contour

    try:
        ellipse = cv2.fitEllipse(optimized)
    except cv2.error:
        return None

    (cx, cy), (w, h), angle = ellipse

    # Sanity check: reject degenerate ellipses
    if w <= 0 or h <= 0:
        return None

    return ellipse
