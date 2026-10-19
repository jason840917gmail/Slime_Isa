"""Cut a seamless music loop out of a longer take (a Magnific song).

    python scripts/audio/make-music-loop.py <source.mp3> <start s> <out stem> [--end <s>] [--xfade <s>] [--avoid-highs]

- The start is moved to the strongest beat onset within 0.6 s of the asked time, so the loop begins
  on a beat (and the first play starts cleanly with a 15 ms fade in).
- The end is the asked `--end`, else the take's end with any closing fade-out or silence trimmed off;
  then it is pulled in so the loop is a whole number of four-bar phrases (the tempo is found from the take).
- `--avoid-highs` moves the start (within two phrases) and the length (whole phrases, at least 60%
  of the asked span) so neither seam window holds a cymbal or hi-hat burst.
- The loop's last `--xfade` seconds (default 2.5) are blended (equal power) with the music that
  came just before the start, so when the loop wraps from its end to its start the music flows on
  as if it had never jumped.

Writes `<out stem>.wav` (44.1 kHz stereo 16-bit, the file the game imports with loop on, QOA
compressed), `<out stem>.mp3` (192 kbps, to listen to) and `<out stem>-seam.mp3` (the loop's last
12 s straight into its first 12 s: listen there for the jump). Needs `pip install miniaudio lameenc
numpy` (no ffmpeg).
"""

import sys
import wave
from pathlib import Path

import lameenc
import miniaudio
import numpy as np

RATE = 44100
SNAP_S = 0.6
FADE_IN_S = 0.015
SEAM_S = 12.0


def load(path: str) -> np.ndarray:
	decoded = miniaudio.decode_file(path, output_format=miniaudio.SampleFormat.FLOAT32, nchannels=2, sample_rate=RATE)
	return np.frombuffer(decoded.samples, dtype=np.float32).reshape(-1, 2).copy()


def onset_envelope(x: np.ndarray, hop: int = 512) -> np.ndarray:
	mono = x.mean(axis=1)
	frames = len(mono) // hop
	energy = np.array([np.sqrt(np.mean(mono[i * hop:(i + 1) * hop] ** 2)) for i in range(frames)])
	flux = np.maximum(0.0, np.diff(np.log1p(energy * 1000.0), prepend=0.0))
	return flux


def tempo_beat_s(env: np.ndarray, hop: int = 512) -> float:
	"""The beat length (s) from the onset envelope's autocorrelation, between 60 and 180 BPM."""
	e = env - env.mean()
	ac = np.correlate(e, e, mode="full")[len(e) - 1:]
	fps = RATE / hop
	lo, hi = int(fps * 60 / 180), int(fps * 60 / 60)
	lag = lo + int(np.argmax(ac[lo:hi]))
	return lag / fps


def snap_start(x: np.ndarray, start_s: float, env: np.ndarray, hop: int = 512) -> int:
	fps = RATE / hop
	a, b = int((start_s - SNAP_S) * fps), int((start_s + SNAP_S) * fps)
	a, b = max(a, 0), min(b, len(env))
	frame = a + int(np.argmax(env[a:b]))
	return frame * hop


def music_end(x: np.ndarray) -> int:
	"""The end with a closing fade or silence trimmed: the last point still within 9 dB of the
	take's typical loudness (median of 1 s windows)."""
	win = RATE
	rms = np.array([np.sqrt(np.mean(x[i:i + win] ** 2)) for i in range(0, len(x) - win, win // 4)])
	level = np.median(rms) * 10 ** (-9 / 20)
	loud = np.nonzero(rms >= level)[0]
	return int(loud[-1] * (win // 4) + win) if len(loud) else len(x)


def highs(x: np.ndarray, a: int, b: int) -> float:
	"""Mean energy above 5 kHz in x[a:b] (cymbals, hi-hats): where a seam must not fall."""
	seg = x[max(a, 0):b].mean(axis=1)
	if len(seg) < 2048:
		return 0.0
	n = 2048
	total = 0.0
	frames = 0
	for i in range(0, len(seg) - n, n):
		spec = np.abs(np.fft.rfft(seg[i:i + n] * np.hanning(n)))
		freqs = np.fft.rfftfreq(n, 1.0 / RATE)
		total += float(np.sum(spec[freqs > 5000.0] ** 2))
		frames += 1
	return total / max(frames, 1)


def best_seam(x: np.ndarray, s0: int, e0: int, beat: int, bar: int, c: int, env: np.ndarray) -> tuple:
	"""Tries starts on the beats of the first two phrases after s0 and loop lengths of whole
	four-bar phrases; keeps the pair whose two seam windows (the loop's last c samples and the c
	before its start) hold the least high-frequency energy, so no cymbal crash sits on the jump."""
	best = None
	typical = float(np.median([np.sqrt(np.mean(x[i:i + RATE] ** 2)) for i in range(0, len(x) - RATE, RATE)]))
	for k in range(0, 8 * 4 + 1):
		s = snap_start(x, (s0 + k * beat) / RATE, env)
		for phrases in range(1, (e0 - s) // (bar * 4) + 1):
			e = s + phrases * 4 * bar
			if e > e0 or s < c:
				continue
			loud = min(float(np.sqrt(np.mean(x[e - c:e] ** 2))), float(np.sqrt(np.mean(x[s - c:s] ** 2))))
			if loud < 0.7 * typical:
				continue  # a quiet break or the closing fade: the seam would dip
			cost = highs(x, e - c, e) + highs(x, s - c, s)
			if phrases * 4 * bar < (e0 - s0) * 0.6:
				continue
			if best is None or cost < best[0]:
				best = (cost, s, e)
	return (best[1], best[2]) if best else (s0, e0)


def to_mp3(x: np.ndarray, path: Path, kbps: int = 192) -> None:
	enc = lameenc.Encoder()
	enc.set_bit_rate(kbps)
	enc.set_in_sample_rate(RATE)
	enc.set_channels(2)
	enc.set_quality(2)
	pcm = (np.clip(x, -1.0, 1.0) * 32767).astype("<i2").tobytes()
	path.write_bytes(enc.encode(pcm) + enc.flush())


def to_wav(x: np.ndarray, path: Path) -> None:
	with wave.open(str(path), "wb") as w:
		w.setnchannels(2)
		w.setsampwidth(2)
		w.setframerate(RATE)
		w.writeframes((np.clip(x, -1.0, 1.0) * 32767).astype("<i2").tobytes())


def main() -> None:
	args = sys.argv[1:]
	src, start_s, stem = args[0], float(args[1]), args[2]
	end_s = float(args[args.index("--end") + 1]) if "--end" in args else None
	xfade_s = float(args[args.index("--xfade") + 1]) if "--xfade" in args else 2.5
	x = load(src)
	env = onset_envelope(x)
	beat = tempo_beat_s(env)
	bar = int(round(beat * 4 * RATE))
	s = snap_start(x, start_s, env)
	e = int(end_s * RATE) if end_s is not None else music_end(x)
	# A multiple of four bars, so the seam lands on a phrase even if the tempo was read at double
	# or half speed.
	bars = (e - s) // bar // 4 * 4
	e = s + bars * bar
	c = int(xfade_s * RATE)
	if "--avoid-highs" in args:
		s, e = best_seam(x, s, music_end(x) if end_s is None else int(end_s * RATE), int(round(beat * RATE)), bar, c, env)
		bars = (e - s) // bar
	if s < c:
		raise SystemExit("the start is too early for a %.1f s crossfade" % xfade_s)
	body = x[s:e].copy()
	t = np.linspace(0.0, 1.0, c, dtype=np.float32)[:, None]
	tail_out, tail_in = np.cos(t * np.pi / 2), np.sin(t * np.pi / 2)
	body[-c:] = body[-c:] * tail_out + x[s - c:s] * tail_in
	first = body.copy()
	n = int(FADE_IN_S * RATE)
	first[:n] *= np.linspace(0.0, 1.0, n, dtype=np.float32)[:, None]
	peak = np.max(np.abs(body))
	gain = (10 ** (-1.0 / 20)) / peak if peak > 0 else 1.0
	out = Path(stem)
	out.parent.mkdir(parents=True, exist_ok=True)
	to_wav(body * gain, out.with_suffix(".wav"))
	to_mp3(np.concatenate([first, body]) * gain, out.with_suffix(".mp3"))
	seam = int(SEAM_S * RATE)
	to_mp3(np.concatenate([body[-seam:], body[:seam]]) * gain, out.parent / (out.name + "-seam.mp3"))
	print("%s: %.0f BPM, start %.2f s (asked %.2f), loop %.2f s = %d bars, end %.2f s, xfade %.1f s" % (
		Path(src).name, 60.0 / beat, s / RATE, start_s, (e - s) / RATE, bars, e / RATE, xfade_s))


if __name__ == "__main__":
	main()
