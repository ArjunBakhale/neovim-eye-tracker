"""
Gaze estimator using MediaPipe Face Mesh iris landmarks.

Computes iris ratio — where the iris sits within the eye socket — which is
head-position-invariant. Averages both eyes for stability.

Entry point: GazeEstimator.process_frame(frame) -> (rx, ry, confidence) | None
  rx, ry are in [0, 1] representing normalized gaze direction.
"""

import cv2
import mediapipe as mp

# MediaPipe Face Mesh landmark indices
# Iris centers
LEFT_IRIS_CENTER = 468
RIGHT_IRIS_CENTER = 473

# Left eye corners and vertical bounds
LEFT_EYE_INNER = 133
LEFT_EYE_OUTER = 33
LEFT_EYE_TOP = 159
LEFT_EYE_BOTTOM = 145

# Right eye corners and vertical bounds
RIGHT_EYE_INNER = 362
RIGHT_EYE_OUTER = 263
RIGHT_EYE_TOP = 386
RIGHT_EYE_BOTTOM = 374


class GazeEstimator:
    def __init__(self):
        self.face_mesh = mp.solutions.face_mesh.FaceMesh(
            max_num_faces=1,
            refine_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )

    def process_frame(self, frame):
        """Process a BGR frame and return (rx, ry, confidence) or None.

        rx, ry are normalized iris ratios in [0, 1].
        confidence is a float in [0, 1] indicating detection quality.
        """
        if frame is None or frame.size == 0:
            return None

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = self.face_mesh.process(rgb)

        if not results.multi_face_landmarks:
            return None

        landmarks = results.multi_face_landmarks[0].landmark

        left = self._iris_ratio(
            landmarks,
            LEFT_IRIS_CENTER,
            LEFT_EYE_INNER,
            LEFT_EYE_OUTER,
            LEFT_EYE_TOP,
            LEFT_EYE_BOTTOM,
        )
        right = self._iris_ratio(
            landmarks,
            RIGHT_IRIS_CENTER,
            RIGHT_EYE_INNER,
            RIGHT_EYE_OUTER,
            RIGHT_EYE_TOP,
            RIGHT_EYE_BOTTOM,
        )

        if left is None and right is None:
            return None

        if left is not None and right is not None:
            # Right eye x-axis is mirrored relative to left eye
            rx = (left[0] + (1.0 - right[0])) / 2.0
            ry = (left[1] + right[1]) / 2.0
            confidence = 0.9
        else:
            # Only one eye detected
            eye = left if left is not None else right
            rx = eye[0] if left is not None else (1.0 - eye[0])
            ry = eye[1]
            confidence = 0.5

        # Clamp to [0, 1]
        rx = max(0.0, min(1.0, rx))
        ry = max(0.0, min(1.0, ry))

        return (rx, ry, confidence)

    def _iris_ratio(self, landmarks, iris_idx, inner_idx, outer_idx, top_idx, bottom_idx):
        """Compute where the iris sits within the eye socket as a ratio.

        Returns (ratio_x, ratio_y) in [0, 1] or None if the eye span is too small.
        """
        iris = landmarks[iris_idx]
        inner = landmarks[inner_idx]
        outer = landmarks[outer_idx]
        top = landmarks[top_idx]
        bottom = landmarks[bottom_idx]

        dx = outer.x - inner.x
        dy = bottom.y - top.y

        # Guard against degenerate cases (eye closed, etc.)
        if abs(dx) < 1e-6 or abs(dy) < 1e-6:
            return None

        ratio_x = (iris.x - inner.x) / dx
        ratio_y = (iris.y - top.y) / dy

        return (ratio_x, ratio_y)

    def close(self):
        self.face_mesh.close()
