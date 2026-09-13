"""Encode the actual SpriteKit capture sequence as a compact review animation."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "QA/animated-room/sequence"
OUTPUT = ROOT / "previews/white-room-avatar-motion.webp"


def main():
    metadata = json.loads((SOURCE / "metadata.json").read_text())
    frames = []
    for record in metadata["frames"]:
        with Image.open(SOURCE / record["file"]) as image:
            frames.append(image.convert("RGB").resize((1672, 941), Image.Resampling.LANCZOS))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(OUTPUT, save_all=True, append_images=frames[1:],
                   duration=100, loop=0, quality=90, method=4)
    with Image.open(OUTPUT) as result:
        assert result.n_frames == len(frames)
        assert result.size == (1672, 941)
    print(f"Exported {len(frames)} frames: {OUTPUT}")


if __name__ == "__main__":
    main()
