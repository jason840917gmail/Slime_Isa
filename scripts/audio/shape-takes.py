"""Cut and shape generated sounds into tight source takes for a Sound Picker round.

    python scripts/audio/shape-takes.py scripts/audio/picker/round-<n>-shape.json

Magnific's sound effects come as one-second files: the event starts late or swells in, rings on,
often sits on a sub-bass rumble, and one file can hold several events. A round's shape file lists
the source takes to make from them (`out` folder, `takes`: [{"name", "layers": [...]}]); each take is
written as `<out>/<name>.src.wav` (mono 44.1 kHz 16-bit, peak -1 dBFS), which the round's manifest
names as an option's take, so prep-takes.py only has to trim and level it.

A take is one layer, or several mixed (a pop from one file under the glitter of another). A layer:
- `src`: the sound, a path from the repository root;
- `hp` / `lp`: high-pass / low-pass corner in Hz (fourth order), applied to the whole file first
  (`hp` takes the rumble out from under a whoosh or a bell);
- `from`: where the cut starts, in ms of the source; with `onset_db` the cut starts 2 ms before the
  first sample after `from` that is louder than `onset_db` under the loudest sample of the cut, so
  an impact starts on its attack;
- `len`: the cut's length in ms;
- `fade_in` / `fade_out`: ms (defaults 1.5 and 30);
- `tail`: {"from": ms into the cut, "db": level at the cut's end}: a ramp, straight in dB, that
  brings a long ring down inside the cut;
- `at`: where the layer starts in the take, in ms (default 0); `gain_db`: its level against the
  other layers, each layer's peak being 0 dB (default 0).

It prints each take's length, the time of its loudest sample, and where its energy sits.
Needs `pip install miniaudio numpy`.
"""

import json
import sys
import wave
from pathlib import Path

import miniaudio
import numpy as np

RATE = 44100
PEAK_DB = -1.0
ONSET_PRE_MS = 2.0
BANDS = ((0, 80), (80, 400), (400, 2000), (2000, 6000), (6000, RATE // 2))


def decode(path: Path) -> np.ndarray:
    decoded = miniaudio.decode_file(str(path), output_format=miniaudio.SampleFormat.FLOAT32, nchannels=1, sample_rate=RATE)
    return np.frombuffer(decoded.samples, dtype=np.float32).astype(np.float64)


def biquad(samples: np.ndarray, kind: str, corner: float) -> np.ndarray:
    """One Butterworth second-order section (two in a row make the fourth-order filter)."""
    omega = 2 * np.pi * corner / RATE
    alpha = np.sin(omega) / (2 * 0.7071)
    cosine = np.cos(omega)
    if kind == "hp":
        b0, b1, b2 = (1 + cosine) / 2, -(1 + cosine), (1 + cosine) / 2
    else:
        b0, b1, b2 = (1 - cosine) / 2, 1 - cosine, (1 - cosine) / 2
    a0, a1, a2 = 1 + alpha, -2 * cosine, 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    out = np.empty_like(samples)
    x1 = x2 = y1 = y2 = 0.0
    for index, x0 in enumerate(samples):
        y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out[index] = y0
        x2, x1, y2, y1 = x1, x0, y1, y0
    return out


def ms(value: float) -> int:
    return int(round(value * RATE / 1000))


def layer_samples(root: Path, layer: dict) -> np.ndarray:
    samples = decode(root / layer["src"])
    for kind in ("hp", "lp"):
        if layer.get(kind):
            samples = biquad(biquad(samples, kind, float(layer[kind])), kind, float(layer[kind]))
    start = ms(layer.get("from", 0))
    length = ms(layer["len"])
    if "onset_db" in layer:
        region = np.abs(samples[start : start + length + ms(100)])
        loud = np.nonzero(region > float(np.max(region)) * 10 ** (layer["onset_db"] / 20))[0]
        if loud.size:
            start = max(0, start + int(loud[0]) - ms(ONSET_PRE_MS))
    cut = samples[start : start + length].copy()
    if cut.size == 0:
        raise SystemExit(f"{layer['src']}: nothing at {layer.get('from', 0)} ms")
    if "tail" in layer:
        tail_from = min(cut.size, ms(layer["tail"]["from"]))
        ramp = np.linspace(0.0, float(layer["tail"]["db"]), cut.size - tail_from)
        cut[tail_from:] *= 10 ** (ramp / 20)
    fade_in = min(cut.size, ms(layer.get("fade_in", 1.5)))
    fade_out = min(cut.size, ms(layer.get("fade_out", 30)))
    if fade_in:
        cut[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
    if fade_out:
        # A raised cosine: no click at the cut's end, and less of a dip than a straight line.
        cut[-fade_out:] *= 0.5 * (1 + np.cos(np.linspace(0.0, np.pi, fade_out)))
    peak = float(np.max(np.abs(cut))) or 1.0
    return cut / peak * 10 ** (layer.get("gain_db", 0.0) / 20)


def describe(samples: np.ndarray) -> str:
    # No window: the take is already faded at both ends, and a window would hide its attack.
    spectrum = np.abs(np.fft.rfft(samples)) ** 2
    freqs = np.fft.rfftfreq(samples.size, 1 / RATE)
    total = float(np.sum(spectrum)) or 1.0
    centroid = float(np.sum(freqs * spectrum) / total)
    bands = " ".join(f"{100 * float(np.sum(spectrum[(freqs >= lo) & (freqs < hi)])) / total:3.0f}" for lo, hi in BANDS)
    energy = np.cumsum(samples ** 2)
    most = float(np.searchsorted(energy, 0.9 * energy[-1])) * 1000 / RATE
    return (f"{samples.size * 1000 / RATE:4.0f} ms, peak at {int(np.argmax(np.abs(samples))) * 1000 / RATE:5.1f} ms, "
            f"90% of the energy by {most:4.0f} ms, centre {centroid:5.0f} Hz, % under 80 / 400 / 2k / 6k / over: {bands}")


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    recipe = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out_dir = root / recipe["out"]
    out_dir.mkdir(parents=True, exist_ok=True)
    for take in recipe["takes"]:
        layers = [(ms(layer.get("at", 0)), layer_samples(root, layer)) for layer in take["layers"]]
        mixed = np.zeros(max(at + samples.size for at, samples in layers))
        for at, samples in layers:
            mixed[at : at + samples.size] += samples
        mixed *= 10 ** (PEAK_DB / 20) / (float(np.max(np.abs(mixed))) or 1.0)
        with wave.open(str(out_dir / f"{take['name']}.src.wav"), "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(RATE)
            out.writeframes((np.clip(mixed, -1.0, 1.0) * 32767.0).astype("<i2").tobytes())
        print(f"{take['name']:20s} {describe(mixed)}")


if __name__ == "__main__":
    main()
