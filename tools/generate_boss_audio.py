"""Original short combat cues; deterministic synthesis, no sampled game audio."""
from pathlib import Path
import math, random, struct, wave
ROOT = Path(__file__).resolve().parents[1] / "assets" / "combat"
ROOT.mkdir(parents=True, exist_ok=True)
RATE = 22050
for name, duration, hz, end_hz, noise in [
    ("tell", .28, 240, 650, .05), ("rush", .22, 150, 70, .55),
    ("shot", .14, 780, 290, .07), ("impact", .24, 110, 42, .48),
    ("hit", .10, 1050, 180, .20), ("phase", .50, 330, 660, .02),
    ("perfect", .22, 740, 1180, .015), ("stagger", .36, 210, 65, .34)]:
    rng = random.Random(name)
    samples = []
    phase = 0
    for i in range(int(RATE*duration)):
        t = i/RATE
        fraction = t/duration
        phase += math.tau*(hz+(end_hz-hz)*fraction)/RATE
        envelope = min(1, t/.008)*(1-fraction)**2
        tone = math.sin(phase)+.2*math.sin(phase*2.01)
        value = (tone*(1-noise)+rng.uniform(-1,1)*noise)*envelope*.45
        samples.append(struct.pack("<h", max(-32768,min(32767,int(value*32767)))))
    with wave.open(str(ROOT / ("boss_"+name+".wav")), "wb") as output:
        output.setparams((1,2,RATE,0,"NONE","not compressed"))
        output.writeframes(b"".join(samples))
print("Generated eight original boss cues in", ROOT)
