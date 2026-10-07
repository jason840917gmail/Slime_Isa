import sys, numpy as np, miniaudio
BARS = " .:-=+*#%@"
def env(path, frame=0.02):
    d = miniaudio.decode_file(path, output_format=miniaudio.SampleFormat.FLOAT32, nchannels=1, sample_rate=44100)
    s = np.frombuffer(d.samples, dtype=np.float32)
    n = int(frame * 44100)
    rms = [float(np.sqrt(np.mean(s[i:i+n]**2))) for i in range(0, len(s), n)]
    peak = max(rms) or 1
    db = [20*np.log10(max(r/peak, 1e-5)) for r in rms]
    line = "".join(BARS[max(0, min(9, int((d_+50)/50*9.99)))] for d_ in db)
    # spectral centroid of the loudest 100 ms
    i = int(np.argmax(rms)) * n
    seg = s[i:i+4410]
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) if len(seg) > 64 else np.zeros(2)
    freqs = np.fft.rfftfreq(len(seg), 1/44100) if len(seg) > 64 else np.zeros(2)
    cen = float((spec*freqs).sum()/max(spec.sum(),1e-9))
    return f"{len(s)/44100:5.2f}s peak@{int(np.argmax(rms))*frame:4.2f}s centroid {cen/1000:4.1f}kHz |{line}|"
for p in sys.argv[1:]:
    print(f"{p:32s} {env(p)}")
