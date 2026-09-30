/**
 * Deterministic offline sound synthesizer for `pnpm audio:bake`.
 *
 * A cue is a list of layers rendered into one mono buffer:
 *   - tone:  oscillator (sine/triangle/square/saw/pulse) with pitch glide,
 *            vibrato and optional FM.
 *   - noise: white/pink/brown noise, optionally granulated into crackles.
 *   - pluck: Karplus-Strong string (bow twang, plucks).
 *   - modal: sum of decaying inharmonic partials (metal, glass, crystal, wood).
 * Every layer has an envelope, a start offset and an optional state-variable
 * filter whose cutoff can sweep. The mix then goes through drive, echo,
 * peak normalization and a de-click fade before being written as 16-bit WAV.
 *
 * No dependencies; output depends only on the recipe and its seed.
 */

export const SAMPLE_RATE = 22050;
const TAU = Math.PI * 2;

/** mulberry32: small, fast, deterministic PRNG. */
export function createRng(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function hashSeed(text) {
  let hash = 2166136261;
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

/** Interpolates a sweep value at progress p in [0,1]: number or [start, end] (optionally [start, end, 'lin']). */
function sweep(value, p) {
  if (!Array.isArray(value)) return value;
  const [start, end, curve = 'exp'] = value;
  if (curve === 'lin' || start <= 0 || end <= 0) return start + (end - start) * p;
  return start * (end / start) ** p;
}

/**
 * Envelope gain at time t (seconds since layer start) for a layer of length dur.
 *   { a, d }            percussive: linear attack then exponential decay (d = time to -60 dB)
 *   { a, s, r }         sustain: attack, hold at 1 until dur - r, linear release
 *   { a, peak, r }      swell: rise to peak (fraction of dur) then fall (shaped)
 */
function envelope(env, t, dur) {
  const attack = Math.max(env.a ?? 0.002, 1e-4);
  if (env.peak !== undefined) {
    const peakAt = dur * env.peak;
    if (t < peakAt) return (t / peakAt) ** (env.curve ?? 1.6);
    const rest = Math.max(dur - peakAt, 1e-4);
    return Math.max(0, 1 - (t - peakAt) / rest) ** (env.curve ?? 1.6);
  }
  if (t < attack) return t / attack;
  if (env.d !== undefined) return Math.exp(-6.9 * (t - attack) / env.d);
  const release = env.r ?? 0.02;
  if (t > dur - release) return Math.max(0, (dur - t) / release);
  return env.s ?? 1;
}

function oscillator(wave, phase, duty = 0.5) {
  const cycle = phase - Math.floor(phase);
  switch (wave) {
    case 'sine': return Math.sin(TAU * cycle);
    case 'triangle': return 1 - 4 * Math.abs(cycle - 0.5);
    case 'square': return cycle < 0.5 ? 1 : -1;
    case 'pulse': return cycle < duty ? 1 : -1;
    case 'saw': return 2 * cycle - 1;
    default: throw new Error(`Unknown wave '${wave}'`);
  }
}

/** Chamberlin state-variable filter with sweepable cutoff and resonance. */
function createFilter(spec) {
  let low = 0;
  let band = 0;
  return (input, p) => {
    const cutoff = Math.min(sweep(spec.cutoff, p), SAMPLE_RATE * 0.45);
    const f = 2 * Math.sin(Math.PI * cutoff / SAMPLE_RATE);
    const damping = 1 / Math.max(spec.q ?? 0.707, 0.5);
    // Two passes (oversampled) keep the Chamberlin topology stable near Nyquist.
    let high = 0;
    for (let pass = 0; pass < 2; pass += 1) {
      low += (f / 2) * band;
      high = input - low - damping * band;
      band += (f / 2) * high;
    }
    if (spec.type === 'lp') return low;
    if (spec.type === 'hp') return high;
    if (spec.type === 'bp') return band;
    if (spec.type === 'notch') return low + high;
    throw new Error(`Unknown filter '${spec.type}'`);
  };
}

function renderTone(layer, out, rng) {
  const start = Math.round((layer.at ?? 0) * SAMPLE_RATE);
  const length = Math.round(layer.dur * SAMPLE_RATE);
  const filters = (layer.filters ?? (layer.filter ? [layer.filter] : [])).map(createFilter);
  let phase = rng();
  let modPhase = 0;
  for (let index = 0; index < length && start + index < out.length; index += 1) {
    const t = index / SAMPLE_RATE;
    const p = index / length;
    let frequency = sweep(layer.freq, layer.glide !== undefined ? Math.min(1, t / layer.glide) : p);
    if (layer.vibrato) frequency *= 1 + sweep(layer.vibrato.depth, p) * Math.sin(TAU * layer.vibrato.rate * t);
    if (layer.fm) {
      modPhase += (frequency * layer.fm.ratio) / SAMPLE_RATE;
      const index_ = sweep(layer.fm.index, p);
      frequency *= 1 + index_ * Math.sin(TAU * modPhase);
    }
    phase += frequency / SAMPLE_RATE;
    let sample = oscillator(layer.wave ?? 'sine', phase, layer.duty);
    for (const filter of filters) sample = filter(sample, p);
    let gain = envelope(layer.env ?? { a: 0.005, d: layer.dur }, t, layer.dur) * (layer.gain ?? 1);
    if (layer.tremolo) gain *= 1 - layer.tremolo.depth * (0.5 + 0.5 * Math.sin(TAU * layer.tremolo.rate * t));
    out[start + index] += sample * gain;
  }
}

function renderNoise(layer, out, rng) {
  const start = Math.round((layer.at ?? 0) * SAMPLE_RATE);
  const length = Math.round(layer.dur * SAMPLE_RATE);
  const filters = (layer.filters ?? (layer.filter ? [layer.filter] : [])).map(createFilter);
  const color = layer.color ?? 'white';
  let brown = 0;
  let pink = [0, 0, 0];
  // Granular mode: sparse short bursts (gravel, crackle, crunch).
  const grains = [];
  if (layer.grains) {
    const { rate, size = 0.006, jitter = 1 } = layer.grains;
    let cursor = 0;
    while (cursor < layer.dur) {
      const localRate = sweep(rate, cursor / layer.dur);
      cursor += (1 / localRate) * (1 - jitter / 2 + rng() * jitter);
      grains.push({ at: cursor, size: size * (0.5 + rng()), gain: 0.4 + rng() * 0.6 });
    }
  }
  let grainIndex = 0;
  for (let index = 0; index < length && start + index < out.length; index += 1) {
    const t = index / SAMPLE_RATE;
    const p = index / length;
    const white = rng() * 2 - 1;
    let sample = white;
    if (color === 'brown') { brown = (brown + 0.02 * white) / 1.02; sample = brown * 3.5; }
    if (color === 'pink') {
      pink = [0.99765 * pink[0] + white * 0.099046, 0.963 * pink[1] + white * 0.2965164, 0.57 * pink[2] + white * 1.0526913];
      sample = (pink[0] + pink[1] + pink[2] + white * 0.1848) * 0.25;
    }
    if (layer.grains) {
      while (grainIndex < grains.length && grains[grainIndex].at + grains[grainIndex].size < t) grainIndex += 1;
      const grain = grains[grainIndex];
      sample *= grain && t >= grain.at ? grain.gain * Math.exp(-5 * (t - grain.at) / grain.size) : 0;
    }
    for (const filter of filters) sample = filter(sample, p);
    out[start + index] += sample * envelope(layer.env ?? { a: 0.002, d: layer.dur }, t, layer.dur) * (layer.gain ?? 1);
  }
}

/** Karplus-Strong plucked string. */
function renderPluck(layer, out, rng) {
  const start = Math.round((layer.at ?? 0) * SAMPLE_RATE);
  const length = Math.round(layer.dur * SAMPLE_RATE);
  const period = Math.max(2, Math.round(SAMPLE_RATE / layer.freq));
  const buffer = Float32Array.from({ length: period }, () => rng() * 2 - 1);
  const damping = layer.damping ?? 0.996;
  const brightness = layer.brightness ?? 0.5;
  for (let index = 0; index < length && start + index < out.length; index += 1) {
    const slot = index % period;
    const next = (index + 1) % period;
    const sample = buffer[slot];
    buffer[slot] = damping * (brightness * buffer[slot] + (1 - brightness) * buffer[next]);
    const t = index / SAMPLE_RATE;
    out[start + index] += sample * envelope(layer.env ?? { a: 0.001, s: 1, r: 0.03 }, t, layer.dur) * (layer.gain ?? 1);
  }
}

/** Sum of decaying partials: [{ ratio | freq, gain, decay }] over a base frequency. */
function renderModal(layer, out, rng) {
  const start = Math.round((layer.at ?? 0) * SAMPLE_RATE);
  const length = Math.round(layer.dur * SAMPLE_RATE);
  const partials = layer.partials.map((partial) => ({
    frequency: (partial.freq ?? layer.freq * partial.ratio) * (1 + ((rng() * 2 - 1) * (layer.detune ?? 0))),
    gain: partial.gain ?? 1,
    decay: partial.decay ?? layer.dur,
    phase: rng(),
  }));
  const attack = layer.attack ?? 0.001;
  for (let index = 0; index < length && start + index < out.length; index += 1) {
    const t = index / SAMPLE_RATE;
    let sample = 0;
    for (const partial of partials) sample += Math.sin(TAU * (partial.phase + partial.frequency * t)) * partial.gain * Math.exp(-6.9 * t / partial.decay);
    const attackGain = t < attack ? t / attack : 1;
    out[start + index] += sample * attackGain * (layer.gain ?? 1);
  }
}

const RENDERERS = { tone: renderTone, noise: renderNoise, pluck: renderPluck, modal: renderModal };

function layerEnd(layer) { return (layer.at ?? 0) + layer.dur; }

/**
 * Renders a recipe: { layers, gain?, drive?, echo?: { delay, feedback, mix }, tail?, peak?, loop? }.
 * `loop: { seconds, crossfade? }` makes a seamless loop of exactly `seconds`: layers may run past
 * the end, and everything after it is crossfaded back over the start (no end fade, no trimming).
 * Returns Float32Array samples in [-1, 1].
 */
export function renderRecipe(recipe, seed) {
  const rng = createRng(seed);
  const echoTail = recipe.echo ? recipe.echo.delay * Math.ceil(Math.log(0.01) / Math.log(recipe.echo.feedback)) : 0;
  const loopCrossfade = recipe.loop ? (recipe.loop.crossfade ?? 0.5) : 0;
  const duration = Math.max(...recipe.layers.map(layerEnd), recipe.loop ? recipe.loop.seconds + loopCrossfade : 0)
    + echoTail + (recipe.tail ?? 0.01);
  const out = new Float32Array(Math.ceil(duration * SAMPLE_RATE));
  for (const layer of recipe.layers) {
    const renderer = RENDERERS[layer.type];
    if (!renderer) throw new Error(`Unknown layer type '${layer.type}'`);
    renderer(layer, out, rng);
  }
  if (recipe.drive) for (let index = 0; index < out.length; index += 1) out[index] = Math.tanh(out[index] * recipe.drive) / Math.tanh(recipe.drive);
  if (recipe.echo) {
    const delay = Math.round(recipe.echo.delay * SAMPLE_RATE);
    const wet = new Float32Array(out.length);
    for (let index = delay; index < out.length; index += 1) wet[index] = (out[index - delay] + wet[index - delay]) * recipe.echo.feedback;
    for (let index = 0; index < out.length; index += 1) out[index] += wet[index] * recipe.echo.mix;
  }
  let peak = 0;
  for (const sample of out) peak = Math.max(peak, Math.abs(sample));
  // Peak-normalize, then pull sustained tones (squares, drones) down to a loudness ceiling so
  // every cue sits in the same range before per-node volume.
  let sumSquares = 0;
  for (const sample of out) sumSquares += sample ** 2;
  const peakScale = peak > 0 ? (recipe.peak ?? 0.89) / peak : 0;
  const rmsAfterPeak = Math.sqrt(sumSquares / Math.max(out.length, 1)) * peakScale;
  const ceiling = 10 ** ((recipe.maxRmsDb ?? -15) / 20);
  const scale = rmsAfterPeak > ceiling ? peakScale * (ceiling / rmsAfterPeak) : peakScale;
  if (recipe.loop) {
    for (let index = 0; index < out.length; index += 1) out[index] *= scale;
    return foldLoop(out, Math.round(recipe.loop.seconds * SAMPLE_RATE), Math.round(loopCrossfade * SAMPLE_RATE));
  }
  const fade = Math.min(out.length, Math.round(0.006 * SAMPLE_RATE));
  for (let index = 0; index < out.length; index += 1) {
    out[index] *= scale;
    const fromEnd = out.length - 1 - index;
    if (fromEnd < fade) out[index] *= fromEnd / fade;
  }
  return trimSilence(out);
}

/**
 * Seamless loop of `length` samples: the first `crossfade` samples blend from the audio that
 * followed the loop end into the loop's own start, so the wrap point continues the material.
 * Anything later than that overflow is added back on as well, so no event is lost.
 */
function foldLoop(samples, length, crossfade) {
  const loop = new Float32Array(length);
  loop.set(samples.subarray(0, length));
  for (let index = 0; index < crossfade && length + index < samples.length; index += 1) {
    const toStart = index / crossfade;
    loop[index] = loop[index] * toStart + samples[length + index] * (1 - toStart);
  }
  for (let index = length + crossfade; index < samples.length; index += 1) loop[(index - length) % length] += samples[index];
  let peak = 0;
  for (const sample of loop) peak = Math.max(peak, Math.abs(sample));
  if (peak > 0.99) for (let index = 0; index < length; index += 1) loop[index] *= 0.99 / peak;
  return loop;
}

/** Drops trailing samples below -60 dB so echo/decay tails do not pad files. */
function trimSilence(samples) {
  let end = samples.length;
  while (end > 1 && Math.abs(samples[end - 1]) < 0.001) end -= 1;
  return samples.subarray(0, Math.min(samples.length, end + Math.round(0.004 * SAMPLE_RATE)));
}

export function encodeWav(samples) {
  const dataBytes = samples.length * 2;
  const buffer = Buffer.alloc(44 + dataBytes);
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + dataBytes, 4);
  buffer.write('WAVE', 8);
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(SAMPLE_RATE, 24);
  buffer.writeUInt32LE(SAMPLE_RATE * 2, 28);
  buffer.writeUInt16LE(2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataBytes, 40);
  for (let index = 0; index < samples.length; index += 1) {
    buffer.writeInt16LE(Math.round(Math.max(-1, Math.min(1, samples[index])) * 32767), 44 + index * 2);
  }
  return buffer;
}

/** Quick descriptors used by the bake report to sanity-check renders. */
export function describe(samples) {
  let sumSquares = 0;
  let crossings = 0;
  for (let index = 0; index < samples.length; index += 1) {
    sumSquares += samples[index] ** 2;
    if (index > 0 && (samples[index - 1] < 0) !== (samples[index] < 0)) crossings += 1;
  }
  const seconds = samples.length / SAMPLE_RATE;
  return {
    seconds: Number(seconds.toFixed(3)),
    rmsDb: Number((10 * Math.log10(sumSquares / Math.max(samples.length, 1) + 1e-12)).toFixed(1)),
    brightnessHz: Math.round(crossings / 2 / Math.max(seconds, 1e-6)),
  };
}
