"""Generate original short PCM tones for A gameplay. No external samples."""
from pathlib import Path
import math
import struct
import wave

folder = Path(__file__).resolve().parents[1] / "assets" / "combat"
folder.mkdir(parents=True, exist_ok=True)
for name, frequency, duration in [("strike", 540, 0.07), ("spell", 740, 0.14), ("chime", 880, 0.22)]:
    rate = 22050
    frames = []
    for i in range(int(rate * duration)):
        t = i / rate
        sample = 0.12 * math.exp(-t * 20) * (
            math.sin(2 * math.pi * frequency * t)
            + 0.25 * math.sin(2 * math.pi * frequency * 1.5 * t)
        )
        frames.append(struct.pack("<h", int(sample * 24000)))
    with wave.open(str(folder / (name + ".wav")), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(rate)
        stream.writeframes(b"".join(frames))
