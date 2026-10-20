"""Cut a seamless music loop out of a longer take (a Magnific song).

    python scripts/audio/make-music-loop.py <source.mp3> <start s> <out stem> [--end <s>] [--xfade <s>] [--avoid-highs]

- The start is moved to the strongest beat onset within 0.6 s of the asked time, so the loop begins
  on a beat.
- The end is the asked `--end`, else the take's end with any closing fade-out or silence trimmed off;
  then it is pulled in so the loop is a whole number of four-bar phrases (the tempo is found from the
  take, to a fraction of a sample: the beat's autocorrelation peak, interpolated and refined on the
  peak sixteen beats on), and moved by at most END_REFINE_S to where the music before the end lines
  up best with the music before the start (their cross-correlation), so the crossfade stays in phase.
  A take shorter than four bars from the start stops with a message.
- `--avoid-highs` moves the start (within two phrases) and the length (whole phrases, at least 60%
  of the asked span) so neither seam window holds a cymbal or hi-hat burst.
- The loop's last `--xfade` seconds (default 2.5) are blended (equal power) with the music that
  came just before the start, so when the loop wraps from its end to its start the music flows on
  as if it had never jumped.

Writes `<out stem>.wav` (44.1 kHz stereo 16-bit, the file the game imports with loop on, QOA
compressed; its start is not faded, as it is also where every wrap lands: the game's music director
fades each track in itself), `<out stem>.mp3` (192 kbps, to listen to: its first pass starts with a
15 ms fade in, then it plays the loop again) and `<out stem>-seam.mp3` (the loop's last 12 s straight
into its first 12 s: listen there for the jump). Needs `pip install miniaudio lameenc numpy` (no
ffmpeg).
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
# How far the loop's end may move to put the crossfade in phase.
END_REFINE_S = 0.04
# The tempo is refined on the autocorrelation peak this many beats on (four bars of four).
REFINE_BEATS = 16


def load(path: str) -> np.ndarray:
	decoded = miniaudio.decode_file(path, output_format=miniaudio.SampleFormat.FLOAT32, nchannels=2, sample_rate=RATE)
	return np.frombuffer(decoded.samples, dtype=np.float32).reshape(-1, 2).copy()


def onset_envelope(x: np.ndarray, hop: int = 512) -> np.ndarray:
	mono = x.mean(axis=1)
	frames = len(mono) // hop
	energy = np.array([np.sqrt(np.mean(mono[i * hop:(i + 1) * hop] ** 2)) for i in range(frames)])
	flux = np.maximum(0.0, np.diff(np.log1p(energy * 1000.0), prepend=0.0))
	return flux


def peak_lag(ac: np.ndarray, i: int) -> float:
	"""The autocorrelation peak at frame `i`, to a fraction of a frame (a parabola through it and its
	neighbours)."""
	if i <= 0 or i >= len(ac) - 1:
		return float(i)
	a, b, c = float(ac[i - 1]), float(ac[i]), float(ac[i + 1])
	den = a - 2.0 * b + c
	return i + (0.5 * (a - c) / den if den < 0.0 else 0.0)


def tempo_beat_s(env: np.ndarray, hop: int = 512) -> float:
	"""The beat length (s) from the onset envelope's autocorrelation, between 60 and 180 BPM: the
	peak's lag interpolated between frames (a frame is 11.6 ms), then refined on the peak
	REFINE_BEATS beats on, where a frame's error is that many times smaller per beat."""
	e = env - env.mean()
	ac = np.correlate(e, e, mode="full")[len(e) - 1:]
	fps = RATE / hop
	lo, hi = int(fps * 60 / 180), int(fps * 60 / 60)
	lag = peak_lag(ac, lo + int(np.argmax(ac[lo:hi])))
	far = lag * REFINE_BEATS
	a, b = int(far - lag * 0.25), int(far + lag * 0.25) + 1
	if b < len(ac) - 1:
		lag = peak_lag(ac, a + int(np.argmax(ac[a:b]))) / REFINE_BEATS
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


def refine_end(x: np.ndarray, s: int, e: int, c: int) -> int:
	"""The end moved by at most END_REFINE_S to where the loop's last `c` samples line up best with
	the `c` before its start (their normalized cross-correlation, mono), so the crossfade between
	them is in phase."""
	reach = int(END_REFINE_S * RATE)
	ref = x[s - c:s].mean(axis=1)
	ref = ref / (np.linalg.norm(ref) or 1.0)
	mono = x.mean(axis=1)
	best, best_e = -2.0, e
	for d in range(-reach, reach + 1):
		end = e + d
		if end - c < 0 or end > len(x) or end <= s + c:
			continue
		seg = mono[end - c:end]
		score = float(np.dot(seg, ref)) / (float(np.linalg.norm(seg)) or 1.0)
		if score > best:
			best, best_e = score, end
	return best_e


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
	if bars <= 0:
		raise SystemExit("the take is shorter than four bars from the start (%.1f s at %.0f BPM): start earlier or end later"
			% ((e - s) / RATE, 60.0 / beat))
	e = s + bars * bar
	c = int(xfade_s * RATE)
	if "--avoid-highs" in args:
		s, e = best_seam(x, s, music_end(x) if end_s is None else int(end_s * RATE), int(round(beat * RATE)), bar, c, env)
		bars = (e - s) // bar
	if s < c:
		raise SystemExit("the start is too early for a %.1f s crossfade" % xfade_s)
	if e - s <= 2 * c:
		raise SystemExit("the loop (%.1f s) is too short for a %.1f s crossfade" % ((e - s) / RATE, xfade_s))
	phrase_end = e
	e = refine_end(x, s, e, c)
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
	print("%s: %.2f BPM, start %.2f s (asked %.2f), loop %.2f s = %d bars, end %.2f s (moved %+.1f ms into phase), xfade %.1f s" % (
		Path(src).name, 60.0 / beat, s / RATE, start_s, (e - s) / RATE, bars, e / RATE, (e - phrase_end) * 1000.0 / RATE, xfade_s))


if __name__ == "__main__":
	main()
