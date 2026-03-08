#!/usr/bin/env python3
"""
Eye tracker sidecar process for neovim-eye-tracker.

Captures camera frames, runs pupil detection, and streams
pupil coordinates as newline-delimited JSON on stdout.

Protocol:
  stdout line 1: {"status": "ready"}
  stdout lines:  {"cx": float, "cy": float, "w": float, "h": float, "valid": bool}
  stdin:         "quit\n" to shut down
"""

import argparse
import json
import signal
import sys
import threading
import time


def check_dependencies():
    """Verify numpy < 2.0 and opencv are available."""
    try:
        import numpy as np
    except ImportError:
        print(
            json.dumps({"status": "error", "message": "numpy not installed"}),
            flush=True,
        )
        sys.exit(1)

    np_version = tuple(int(x) for x in np.__version__.split(".")[:2])
    if np_version >= (2, 0):
        print(
            json.dumps(
                {
                    "status": "error",
                    "message": f"numpy {np.__version__} not supported, need < 2.0",
                }
            ),
            flush=True,
        )
        sys.exit(1)

    try:
        import cv2  # noqa: F401
    except ImportError:
        print(
            json.dumps({"status": "error", "message": "opencv-python not installed"}),
            flush=True,
        )
        sys.exit(1)


def emit(obj):
    """Write a JSON line to stdout."""
    print(json.dumps(obj), flush=True)


def make_result(cx=0, cy=0, w=0, h=0, valid=False):
    return {"cx": cx, "cy": cy, "w": w, "h": h, "valid": valid}


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

    from pupil_detector import process_frame

    # Parse device: integer index or string path
    try:
        device = int(args.device)
    except ValueError:
        device = args.device

    cap = cv2.VideoCapture(device)
    if not cap.isOpened():
        emit({"status": "error", "message": f"cannot open camera device: {device}"})
        sys.exit(1)

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

            result = process_frame(frame)

            if result is not None:
                (cx, cy), (w, h), angle = result
                if w > 0 and h > 0:
                    emit(make_result(cx=round(cx, 1), cy=round(cy, 1),
                                     w=round(w, 1), h=round(h, 1), valid=True))
                else:
                    emit(make_result())
            else:
                emit(make_result())

            # Rate limit
            elapsed = time.monotonic() - t_start
            remaining = frame_interval - elapsed
            if remaining > 0:
                time.sleep(remaining)

    finally:
        cap.release()


if __name__ == "__main__":
    main()
