#!/usr/bin/env python3
"""
Eye tracker sidecar process for neovim-eye-tracker.

Captures camera frames, runs MediaPipe iris tracking, and streams
gaze ratios as newline-delimited JSON on stdout.

Protocol:
  stdout line 1: {"status": "ready"}
  stdout lines:  {"rx": float, "ry": float, "valid": bool, "confidence": float}
  stdin:         "quit\n" to shut down
"""

import argparse
import json
import signal
import sys
import threading
import time


def check_dependencies():
    """Verify opencv and mediapipe are available."""
    try:
        import cv2  # noqa: F401
    except ImportError:
        print(
            json.dumps({"status": "error", "message": "opencv-python not installed"}),
            flush=True,
        )
        sys.exit(1)

    try:
        import mediapipe  # noqa: F401
    except ImportError:
        print(
            json.dumps({"status": "error", "message": "mediapipe not installed"}),
            flush=True,
        )
        sys.exit(1)


def emit(obj):
    """Write a JSON line to stdout."""
    print(json.dumps(obj), flush=True)


def make_result(rx=0, ry=0, valid=False, confidence=0.0):
    return {"rx": rx, "ry": ry, "valid": valid, "confidence": confidence}


def main():
    parser = argparse.ArgumentParser(description="Eye tracker sidecar")
    parser.add_argument(
        "--device", default="0", help="Camera device index or path (default: 0)"
    )
    parser.add_argument(
        "--fps", type=int, default=30, help="Target capture rate (default: 30)"
    )
    args = parser.parse_args()

    check_dependencies()

    import cv2

    from gaze_estimator import GazeEstimator

    # Parse device: integer index or string path
    try:
        device = int(args.device)
    except ValueError:
        device = args.device

    cap = cv2.VideoCapture(device)
    if not cap.isOpened():
        emit({"status": "error", "message": f"cannot open camera device: {device}"})
        sys.exit(1)

    estimator = GazeEstimator()

    # Warm up camera: discard initial frames so auto-exposure settles.
    # Run one process_frame() call so the MediaPipe model loads before "ready".
    for i in range(20):
        ret, frame = cap.read()
        if ret and i == 19:
            estimator.process_frame(frame)

    # Signal that we're ready
    emit({"status": "ready"})

    # Stdin reader thread for quit command
    shutdown = threading.Event()

    def stdin_reader():
        try:
            for line in sys.stdin:
                if line.strip() == "quit":
                    shutdown.set()
                    return
        except (EOFError, OSError):
            shutdown.set()

    reader_thread = threading.Thread(target=stdin_reader, daemon=True)
    reader_thread.start()

    # Handle signals
    def handle_signal(signum, frame):
        shutdown.set()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    frame_interval = 1.0 / args.fps

    try:
        while not shutdown.is_set():
            t_start = time.monotonic()

            ret, frame = cap.read()
            if not ret:
                emit(make_result())
                time.sleep(frame_interval)
                continue

            result = estimator.process_frame(frame)

            if result is not None:
                rx, ry, confidence = result
                emit(make_result(
                    rx=round(rx, 4),
                    ry=round(ry, 4),
                    valid=True,
                    confidence=round(confidence, 2),
                ))
            else:
                emit(make_result())

            # Rate limit
            elapsed = time.monotonic() - t_start
            remaining = frame_interval - elapsed
            if remaining > 0:
                time.sleep(remaining)

    finally:
        estimator.close()
        cap.release()


if __name__ == "__main__":
    main()
