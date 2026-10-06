"""Prepare the takes of a Sound Picker round for the picker page and the game.

    python scripts/audio/prep-takes.py scripts/audio/picker/round-<n>.json

The round manifest (scripts/audio/picker/) lists each cue's options and their source takes (paths
from the repository root: Magnific downloads, steps cut by slice-steps.py, or takes already in
godot/asset). Each option has a `kind`: `step` (cut to MAX_STEP_S, peak STEP level), `oneshot`
(only the loudest event is kept) or `loop` (untouched), and an optional `max` length in seconds.

For every take it writes, under the manifest's `takes` folder, `<cue id>/<option>-<n>`:
- `.wav`: mono 44.1 kHz 16-bit, leading and trailing silence trimmed (short fades), peak-normalised
  to the kind's level, so takes compare fairly and ship as they were heard;
- `.mp3`: a 96 kbps copy of that WAV for the picker page and the in-game audition.

Needs `pip install miniaudio lameenc numpy` (no ffmpeg).
"""

import json
import sys
import wave
from pathlib import Path

import lameenc
import miniaudio
import numpy as np

RATE = 44100
## Peak level per kind (dBFS): steps sit lower than one-shots so a walk never shouts.
PEAK_DB = {"step": -6.0, "oneshot": -1.0, "loop": -3.0}
## Trim threshold relative to the take's peak.
TRIM_DB = -42.0
FADE_IN_S = 0.002
FADE_OUT_S = 0.03
## Steps are cut to this length at most (a footstep's tail never overlaps the next step).
MAX_STEP_S = 0.45
## One-shots keep only their loudest event: frames within EVENT_DB of the peak, gaps under
## EVENT_GAP_S bridged.
EVENT_DB = -30.0
EVENT_GAP_S = 0.25


def decode(path: Path) -> np.ndarray:
    decoded = miniaudio.decode_file(str(path), output_format=miniaudio.SampleFormat.FLOAT32, nchannels=1, sample_rate=RATE)
    return np.frombuffer(decoded.samples, dtype=np.float32).copy()


def loudest_event(samples: np.ndarray) -> np.ndarray:
    """The event holding the take's peak: generated one-shots often hold a second, separate event
    (a splash, a pause, another splash). Events are runs of 10 ms frames above EVENT_DB of the
    peak, merged across gaps shorter than EVENT_GAP_S."""
    frame = int(0.01 * RATE)
    count = samples.size // frame
    if count < 2:
        return samples
    rms = np.sqrt(np.mean(samples[: count * frame].reshape(count, frame) ** 2, axis=1))
    loud = rms > float(np.max(rms)) * 10 ** (EVENT_DB / 20)
    peak_frame = int(np.argmax(rms))
    gap = int(EVENT_GAP_S / 0.01)
    start = peak_frame
    quiet = 0
    while start > 0 and quiet < gap:
        start -= 1
        quiet = 0 if loud[start] else quiet + 1
    start += quiet
    end = peak_frame
    quiet = 0
    while end < count - 1 and quiet < gap:
        end += 1
        quiet = 0 if loud[end] else quiet + 1
    end -= quiet
    return samples[start * frame : min(samples.size, (end + 1) * frame + int(0.15 * RATE))]


def trim(samples: np.ndarray, kind: str, max_s: float | None = None) -> np.ndarray:
    if samples.size == 0:
        return samples
    if kind == "loop":
        return samples
    if kind == "oneshot":
        samples = loudest_event(samples)
    peak = float(np.max(np.abs(samples))) or 1.0
    threshold = peak * 10 ** (TRIM_DB / 20)
    loud = np.nonzero(np.abs(samples) > threshold)[0]
    if loud.size == 0:
        return samples[:0]
    start = max(0, int(loud[0]) - int(0.004 * RATE))
    end = min(samples.size, int(loud[-1]) + int(0.02 * RATE))
    limit = max_s or (MAX_STEP_S if kind == "step" else None)
    if limit:
        end = min(end, start + int(limit * RATE))
    out = samples[start:end].copy()
    fade_in = min(out.size, int(FADE_IN_S * RATE))
    fade_out = min(out.size, int(FADE_OUT_S * RATE))
    if fade_in:
        out[:fade_in] *= np.linspace(0.0, 1.0, fade_in, dtype=np.float32)
    if fade_out:
        out[-fade_out:] *= np.linspace(1.0, 0.0, fade_out, dtype=np.float32)
    return out


def normalise(samples: np.ndarray, kind: str) -> np.ndarray:
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    if peak <= 0.0:
        return samples
    return samples * (10 ** (PEAK_DB.get(kind, -1.0) / 20) / peak)


def write_wav(path: Path, samples: np.ndarray) -> None:
    pcm = (np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())


def write_mp3(path: Path, samples: np.ndarray) -> None:
    encoder = lameenc.Encoder()
    encoder.set_bit_rate(96)
    encoder.set_in_sample_rate(RATE)
    encoder.set_channels(1)
    encoder.set_quality(2)
    pcm = (np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    path.write_bytes(encoder.encode(pcm.tobytes()) + encoder.flush())


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out_dir = root / manifest["takes"]
    for cue in manifest["cues"]:
        cue_dir = out_dir / cue["id"]
        cue_dir.mkdir(parents=True, exist_ok=True)
        for option in cue["options"]:
            kind = option.get("kind", "oneshot")
            for index, take in enumerate(option["takes"], start=1):
                src = root / take
                stem = cue_dir / f"{option['key']}-{index}"
                wav = stem.with_suffix(".wav")
                if wav.exists() and wav.stat().st_mtime >= src.stat().st_mtime:
                    continue
                samples = normalise(trim(decode(src), kind, option.get("max")), kind)
                write_wav(wav, samples)
                write_mp3(stem.with_suffix(".mp3"), samples)
                print(f"{cue['id']} {option['key']}-{index}: {samples.size / RATE:.2f} s")


if __name__ == "__main__":
    main()
