"""Cut single footsteps out of a generated walk (a clip of several steps) for the Sound Picker.

    python scripts/audio/slice-steps.py <out-prefix> <walk.mp3|wav>... [--count 4] [--length 0.3] [--decay 0.09]

Generated walks are textures: the steps blend into shuffle. This finds the steps as the strongest
onsets of the loudness envelope (at least MIN_GAP_S apart), cuts each from just before its onset,
and shapes it into one percussive step: an exponential decay with time constant `--decay` seconds
and a short fade, at most `--length` seconds. The `--count` clearest steps (highest ratio of the
step's peak to the loudness just before it), across all the given walks, are written as
<out-prefix>-<n>.src.wav in time order, ready for prep-takes.py (which trims and normalises them).

Needs `pip install miniaudio numpy`.
"""

import argparse
import wave
from pathlib import Path

import miniaudio
import numpy as np

RATE = 44100
FRAME_S = 0.005
MIN_GAP_S = 0.35
PRE_ROLL_S = 0.012


def decode(path: str) -> np.ndarray:
    decoded = miniaudio.decode_file(path, output_format=miniaudio.SampleFormat.FLOAT32, nchannels=1, sample_rate=RATE)
    return np.frombuffer(decoded.samples, dtype=np.float32).copy()


def envelope(samples: np.ndarray) -> np.ndarray:
    frame = int(FRAME_S * RATE)
    count = samples.size // frame
    blocks = samples[: count * frame].reshape(count, frame)
    return np.sqrt(np.mean(blocks ** 2, axis=1) + 1e-12)


def onsets(env: np.ndarray) -> list[tuple[int, float]]:
    """(frame, clarity) of each step onset: rises of the envelope, strongest first, MIN_GAP_S apart."""
    db = 20 * np.log10(env)
    # Rise over 20 ms against the minimum of the 60 ms before.
    look = int(0.06 / FRAME_S)
    rise_frames = int(0.02 / FRAME_S)
    candidates = []
    for i in range(look, db.size - rise_frames):
        before = float(np.min(db[i - look : i]))
        after = float(np.max(db[i : i + rise_frames]))
        candidates.append((after - before, i))
    candidates.sort(reverse=True)
    gap = int(MIN_GAP_S / FRAME_S)
    chosen: list[tuple[int, float]] = []
    for clarity, i in candidates:
        if clarity < 6.0:
            break
        if all(abs(i - j) >= gap for j, _ in chosen):
            chosen.append((i, clarity))
    return chosen


def shape(samples: np.ndarray, start: int, length_s: float, decay_s: float) -> np.ndarray:
    cut = samples[start : start + int(length_s * RATE)].copy()
    t = np.arange(cut.size, dtype=np.float32) / RATE
    # Hold the attack for 25 ms, then decay exponentially.
    gain = np.where(t < 0.025, 1.0, np.exp(-(t - 0.025) / decay_s)).astype(np.float32)
    cut *= gain
    fade = min(cut.size, int(0.02 * RATE))
    cut[-fade:] *= np.linspace(1.0, 0.0, fade, dtype=np.float32)
    attack = min(cut.size, int(0.002 * RATE))
    cut[:attack] *= np.linspace(0.0, 1.0, attack, dtype=np.float32)
    return cut


def write_wav(path: Path, samples: np.ndarray) -> None:
    peak = float(np.max(np.abs(samples))) or 1.0
    pcm = (samples / peak * 0.9 * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("prefix")
    parser.add_argument("sources", nargs="+")
    parser.add_argument("--count", type=int, default=4)
    parser.add_argument("--length", type=float, default=0.3)
    parser.add_argument("--decay", type=float, default=0.09)
    parser.add_argument("--skip", type=int, default=0, help="drop the N clearest steps first (to take others from a clip)")
    args = parser.parse_args()
    found = []
    for source in args.sources:
        samples = decode(source)
        found += [(clarity, source, i, samples) for i, clarity in onsets(envelope(samples))]
    found.sort(key=lambda step: -step[0])
    picked = sorted(found[args.skip : args.skip + args.count], key=lambda step: (step[1], step[2]))
    frame = int(FRAME_S * RATE)
    prefix = Path(args.prefix)
    prefix.parent.mkdir(parents=True, exist_ok=True)
    for n, (clarity, source, i, samples) in enumerate(picked, start=1):
        start = max(0, i * frame - int(PRE_ROLL_S * RATE))
        write_wav(prefix.with_name(f"{prefix.name}-{n}.src.wav"), shape(samples, start, args.length, args.decay))
        print(f"{prefix.name}-{n}: {Path(source).name} at {i * FRAME_S:.2f} s, clarity {clarity:.1f} dB")
    if len(picked) < args.count:
        print(f"only {len(picked)} clear steps found")


if __name__ == "__main__":
    main()
