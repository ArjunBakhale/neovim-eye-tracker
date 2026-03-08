"""
Iris/pupil detector using OpenCV Haar cascades.

Ships with OpenCV — no downloads or external models needed.
Pipeline: face detection → eye ROI → darkest-point pupil within eye region.

Entry point: process_frame(frame) -> rotated_rect or None
rotated_rect: ((cx, cy), (w, h), angle) — pupil center in 640x480 frame pixels.
"""

import os
import cv2
import numpy as np

TARGET_WIDTH = 640
TARGET_HEIGHT = 480

_cascade_dir = os.path.join(os.path.dirname(cv2.__file__), "data")
_face_cascade = None
_eye_cascade = None


def _get_cascades():
    global _face_cascade, _eye_cascade
    if _face_cascade is None:
        _face_cascade = cv2.CascadeClassifier(
            os.path.join(_cascade_dir, "haarcascade_frontalface_default.xml")
        )
        _eye_cascade = cv2.CascadeClassifier(
            os.path.join(_cascade_dir, "haarcascade_eye.xml")
        )
    return _face_cascade, _eye_cascade


def crop_to_aspect_ratio(frame):
    h, w = frame.shape[:2]
    target_ratio = TARGET_WIDTH / TARGET_HEIGHT
    current_ratio = w / h
    if current_ratio > target_ratio:
        new_w = int(h * target_ratio)
        offset = (w - new_w) // 2
        frame = frame[:, offset:offset + new_w]
    elif current_ratio < target_ratio:
        new_h = int(w / target_ratio)
        offset = (h - new_h) // 2
        frame = frame[offset:offset + new_h, :]
    return cv2.resize(frame, (TARGET_WIDTH, TARGET_HEIGHT))


def _find_pupil_in_eye(eye_roi_gray):
    """Find pupil center within an eye ROI using darkest-region search."""
    # Blur to suppress noise
    blurred = cv2.GaussianBlur(eye_roi_gray, (7, 7), 0)
    # Find darkest point
    _, _, _, max_loc = cv2.minMaxLoc(blurred)
    min_val = blurred.min()
    # Focus on bottom half of eye ROI (avoids eyebrow)
    h, w = blurred.shape
    roi = blurred[h // 3:, :]
    min_val = roi.min()
    min_loc_y, min_loc_x = np.unravel_index(roi.argmin(), roi.shape)
    cx = min_loc_x
    cy = min_loc_y + h // 3
    return cx, cy


def process_frame(frame):
    """Detect pupil center using face → eye → darkest-point pipeline.

    Returns:
        rotated_rect: ((cx, cy), (diameter, diameter), 0.0)
        cx, cy are pixel coordinates in the 640x480 frame, or None on failure.
    """
    if frame is None or frame.size == 0:
        return None

    frame = crop_to_aspect_ratio(frame)
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.equalizeHist(gray)

    face_cascade, eye_cascade = _get_cascades()

    faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(80, 80))
    if not len(faces):
        return None

    # Use the largest face
    faces = sorted(faces, key=lambda f: f[2] * f[3], reverse=True)
    fx, fy, fw, fh = faces[0]
    face_gray = gray[fy:fy + fh, fx:fx + fw]

    eyes = eye_cascade.detectMultiScale(face_gray, scaleFactor=1.1, minNeighbors=5, minSize=(20, 20))
    if not len(eyes):
        return None

    # Use the largest detected eye only
    eyes = sorted(eyes, key=lambda e: e[2] * e[3], reverse=True)
    ex, ey, ew, eh = eyes[0]
    eye_roi = face_gray[ey:ey + eh, ex:ex + ew]
    px, py = _find_pupil_in_eye(eye_roi)
    cx = fx + ex + px
    cy = fy + ey + py
    diameter = min(ew, eh) * 0.4

    return (cx, cy), (diameter, diameter), 0.0
