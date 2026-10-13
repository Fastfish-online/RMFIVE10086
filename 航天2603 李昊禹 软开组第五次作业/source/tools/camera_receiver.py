"""Minimal external receiver for the simulator camera/status endpoints."""
from pathlib import Path
from time import sleep
from urllib.request import urlopen
import json

BASE = "http://127.0.0.1:8080"
OUTPUT = Path(__file__).with_name("latest_frame.jpg")

print("Receiving robot camera. Press Ctrl+C to stop.")
while True:
    try:
        status = json.loads(urlopen(BASE + "/status", timeout=2).read())
        OUTPUT.write_bytes(urlopen(BASE + "/frame.jpg", timeout=2).read())
        print(
            f"frame={status['frame_id']} hp={status['health']} "
            f"ammo={status['ammo']} camera={status['camera']}",
            end="\r",
            flush=True,
        )
    except Exception as exc:
        print(f"waiting for simulator: {exc}", end="\r", flush=True)
    sleep(0.2)
