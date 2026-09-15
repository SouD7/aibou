"""Small, original interaction tones. No external audio or network dependency."""
import math
import struct
import sys
import wave
from pathlib import Path

destination = Path(sys.argv[1]) / "WorkshopSounds"
destination.mkdir(parents=True, exist_ok=True)
rate = 22050
for name, notes, duration in [
    ("switch", [(0, 700)], 0.07),
    ("connect", [(0, 520), (0.055, 780)], 0.16),
    ("success", [(0, 523.25), (0.10, 659.25), (0.20, 783.99)], 0.62),
]:
    values = []
    for i in range(int(duration * rate)):
        time = i / rate
        sample = 0
        for onset, frequency in notes:
            age = time - onset
            if age >= 0:
                envelope = min(1, age / 0.004) * math.exp(-age * (35 if name == "switch" else 11))
                sample += 0.16 * envelope * (math.sin(2 * math.pi * frequency * age) + 0.15 * math.sin(4 * math.pi * frequency * age))
        fade = min(1, (duration - time) / 0.012)
        values.append(struct.pack("<h", int(max(-1, min(1, sample * fade)) * 32767)))
    with wave.open(str(destination / (name + ".wav")), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(rate)
        audio.writeframes(b"".join(values))
