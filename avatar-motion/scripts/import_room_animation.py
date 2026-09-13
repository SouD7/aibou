"""Unpack the selected animated room without changing its pixels or frame timing."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "design/room-2d/v3/previews/white-horizontal-motion.webp"
DESTINATION = ROOT / "Assets/RoomAnimation"


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    frames, durations = [], []
    with Image.open(SOURCE) as animation:
        for index in range(animation.n_frames):
            animation.seek(index)
            animation.load()  # WebP publishes duration after decoding each frame.
            duration = animation.info["duration"] / 1000
            if duration <= 0:
                raise ValueError("Room frames must have positive durations")
            name = f"frame-{index:03d}.png"
            animation.convert("RGB").save(DESTINATION / name)
            frames.append(name)
            durations.append(duration)
        canvas = list(animation.size)
    manifest = {
        "source": str(SOURCE.relative_to(ROOT.parent)),
        "sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "canvas": canvas,
        "frames": frames,
        "durations": durations,
    }
    (DESTINATION / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Imported {len(frames)} frames, {sum(durations):.1f}s, {canvas}")


if __name__ == "__main__":
    main()
