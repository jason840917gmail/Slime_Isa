/**
 * Sound-effect cue catalog for `pnpm audio:bake`.
 *
 * Each cue produces `variants` takes. The synth flavour renders every take
 * from `synth(k, v)` where k is a small per-take pitch factor and v the take
 * index. The optional `library` list names Kenney CC0 files (by file name,
 * searched in the unpacked packs) for the A/B library flavour; takes beyond
 * that list reuse its entries cyclically. Cues without `library` fall back to
 * synth in library mode (Kenney has no creature voices, whooshes or music).
 */

// ── Building blocks ─────────────────────────────────────────────────────────

const whoosh = ({ at = 0, dur = 0.22, from = 500, peak = 2400, to = 700, gain = 1, q = 1.4, color = 'white' } = {}) => ({
  type: 'noise', color, at, dur, gain,
  env: { peak: 0.45, curve: 1.8 },
  filters: [{ type: 'bp', cutoff: [from, peak], q }, { type: 'lp', cutoff: [peak * 1.6, to] }],
});

const thump = ({ at = 0, f0 = 160, f1 = 50, dur = 0.18, gain = 1, glide } = {}) => ({
  type: 'tone', wave: 'sine', at, dur, gain, freq: [f0, f1], glide: glide ?? dur * 0.6, env: { a: 0.002, d: dur },
});

const burst = ({ at = 0, dur = 0.05, type = 'lp', cutoff = 1500, q = 0.8, gain = 0.6, color = 'white' } = {}) => ({
  type: 'noise', color, at, dur, gain, env: { a: 0.001, d: dur }, filter: { type, cutoff, q },
});

const metal = ({ at = 0, freq = 1800, dur = 0.3, gain = 0.5, ratios = [1, 1.47, 2.09, 2.76, 3.52], detune = 0.01 } = {}) => ({
  type: 'modal', at, dur, gain, freq, detune,
  partials: ratios.map((ratio, index) => ({ ratio, gain: 1 / (index + 1), decay: dur / (1 + index * 0.45) })),
});

const wood = ({ at = 0, freq = 420, dur = 0.14, gain = 0.8 } = {}) => ({
  type: 'modal', at, dur, gain, freq, detune: 0.02,
  partials: [{ ratio: 1, gain: 1, decay: dur }, { ratio: 2.32, gain: 0.45, decay: dur * 0.5 }, { ratio: 4.1, gain: 0.2, decay: dur * 0.3 }],
});

const crystal = ({ at = 0, freq = 2400, dur = 0.55, gain = 0.5 } = {}) => ({
  type: 'modal', at, dur, gain, freq, detune: 0.004,
  partials: [{ ratio: 1, gain: 1, decay: dur }, { ratio: 1.5, gain: 0.6, decay: dur * 0.8 }, { ratio: 2.13, gain: 0.35, decay: dur * 0.6 }, { ratio: 3.01, gain: 0.2, decay: dur * 0.4 }],
});

const blip = ({ at = 0, f0 = 600, f1 = 900, dur = 0.08, wave = 'triangle', gain = 0.7, glide } = {}) => ({
  type: 'tone', wave, at, dur, gain, freq: [f0, f1], glide: glide ?? dur * 0.5, env: { a: 0.003, d: dur },
});

/** Slime body: a wobbly, low-passed sine glide ("blorp"). */
const blorp = ({ at = 0, f0 = 480, f1 = 170, dur = 0.2, gain = 0.9, wobble = 9, depth = 0.08 } = {}) => ({
  type: 'tone', wave: 'sine', at, dur, gain, freq: [f0, f1], vibrato: { rate: wobble, depth },
  env: { a: 0.004, d: dur }, filter: { type: 'lp', cutoff: [2400, 700] },
});

const squelch = ({ at = 0, dur = 0.09, gain = 0.45, cutoff = [1600, 500] } = {}) => ({
  type: 'noise', at, dur, gain, env: { a: 0.004, d: dur }, filter: { type: 'bp', cutoff, q: 2.2 },
});

const notes = (freqs, { at = 0, step = 0.08, dur = 0.22, wave = 'triangle', gain = 0.6, decay } = {}) => freqs.map((freq, index) => ({
  type: 'tone', wave, at: at + index * step, dur, gain, freq, env: decay ? { a: 0.004, d: decay } : { a: 0.004, d: dur },
}));

const sparkle = ({ at = 0, dur = 0.35, gain = 0.25 } = {}) => ({
  type: 'noise', at, dur, gain, grains: { rate: [60, 20], size: 0.01 }, env: { a: 0.01, d: dur }, filter: { type: 'hp', cutoff: 5000 },
});

const gravel = ({ at = 0, dur = 0.2, rate = [180, 40], cutoff = 2600, gain = 0.6, size = 0.006 } = {}) => ({
  type: 'noise', at, dur, gain, grains: { rate, size }, env: { a: 0.002, d: dur }, filter: { type: 'bp', cutoff, q: 0.9 },
});

const creak = ({ at = 0, dur = 0.5, freq = [70, 110], gain = 0.5, cutoff = 1400 } = {}) => ({
  type: 'tone', wave: 'saw', at, dur, gain, freq, tremolo: { rate: 38, depth: 0.85 },
  env: { a: 0.04, s: 1, r: 0.08 }, filters: [{ type: 'bp', cutoff, q: 3 }],
});

/** Holds a loop layer at full level from start to end (the loop fold hides the edges). */
const SUSTAIN = { a: 0.01, s: 1, r: 0.01 };

const C5 = 523.25; const D5 = 587.33; const E5 = 659.26; const G5 = 783.99; const A5 = 880; const C6 = 1046.5; const E6 = 1318.5; const G4 = 392;

// ── Catalog ─────────────────────────────────────────────────────────────────

/** @type {Record<string, Record<string, { variants?: number, synth: (k: number, v: number) => object, library?: string[] }>>} */
export const CUES = {
  weapon: {
    'swing-light': { library: ['swish-12', 'swish-13'], variants: 2, synth: (k) => ({ layers: [whoosh({ dur: 0.15, from: 900 * k, peak: 3200 * k, to: 1200, q: 1.8 })] }) },
    'swing-blade': { library: ['swish-1', 'swish-5', 'swish-6'], variants: 3, synth: (k) => ({ layers: [whoosh({ dur: 0.22, from: 700 * k, peak: 3800 * k, to: 900, q: 2.2 }), whoosh({ at: 0.03, dur: 0.14, from: 3000 * k, peak: 6500, to: 3000, gain: 0.25, q: 3 })] }) },
    thrust: { library: ['swish-2', 'swish-11'], variants: 2, synth: (k) => ({ layers: [whoosh({ dur: 0.13, from: 600 * k, peak: 2800 * k, to: 1400, q: 1.6, gain: 1 }), burst({ at: 0.1, dur: 0.02, type: 'hp', cutoff: 3000, gain: 0.3 })] }) },
    'swing-heavy': { library: ['swish-9', 'swish-7'], variants: 2, synth: (k) => ({ layers: [whoosh({ dur: 0.42, from: 180 * k, peak: 1100 * k, to: 300, q: 1.2, color: 'pink' }), thump({ f0: 90 * k, f1: 60, dur: 0.4, gain: 0.35 })] }) },
    'swing-tool': { library: ['swish-3', 'swish-4'], variants: 2, synth: (k) => ({ layers: [whoosh({ dur: 0.2, from: 400 * k, peak: 1900 * k, to: 600, q: 1.3 })] }) },
    'hit-punch': { variants: 3, library: ['impactPunch_medium_000', 'impactPunch_medium_001', 'impactPunch_medium_002'], synth: (k) => ({ layers: [thump({ f0: 200 * k, f1: 70, dur: 0.14 }), burst({ dur: 0.04, cutoff: 1400, gain: 0.5 }), squelch({ at: 0.01, dur: 0.1, gain: 0.5, cutoff: [1800 * k, 600] })] }) },
    'hit-slash': { variants: 3, library: ['knifeSlice', 'knifeSlice2', 'impactMetal_light_000'], synth: (k) => ({ layers: [burst({ dur: 0.09, type: 'hp', cutoff: 1800 * k, gain: 0.8 }), metal({ freq: 2100 * k, dur: 0.18, gain: 0.25 }), thump({ f0: 170, f1: 80, dur: 0.1, gain: 0.7 })] }) },
    'hit-stab': { variants: 3, library: ['impactPunch_medium_003', 'impactPunch_medium_004', 'impactSoft_medium_000'], synth: (k) => ({ layers: [thump({ f0: 190 * k, f1: 80, dur: 0.11 }), burst({ dur: 0.035, type: 'bp', cutoff: 1500 * k, q: 1.5, gain: 0.8 }), burst({ dur: 0.012, type: 'hp', cutoff: 4000, gain: 0.4 })] }) },
    'hit-heavy': { variants: 2, library: ['impactPunch_heavy_000', 'impactPunch_heavy_001'], synth: (k) => ({ drive: 2.2, echo: { delay: 0.07, feedback: 0.3, mix: 0.25 }, layers: [thump({ f0: 110 * k, f1: 34, dur: 0.5 }), burst({ dur: 0.3, cutoff: [900, 200], gain: 0.9, color: 'pink' }), gravel({ at: 0.02, dur: 0.25, cutoff: 1200, gain: 0.35 })] }) },
    'chop-wood': { variants: 4, library: ['chop', 'impactWood_medium_000', 'impactWood_medium_001', 'impactWood_medium_002'], synth: (k) => ({ layers: [wood({ freq: 360 * k, dur: 0.16, gain: 1 }), burst({ dur: 0.05, type: 'bp', cutoff: 900 * k, q: 3, gain: 0.8 }), thump({ f0: 130, f1: 70, dur: 0.1, gain: 0.5 }), gravel({ at: 0.01, dur: 0.08, rate: [300, 80], cutoff: 3000, gain: 0.25 })] }) },
    'mine-stone': { variants: 4, library: ['impactMining_000', 'impactMining_001', 'impactMining_002', 'impactMining_003'], synth: (k) => ({ layers: [metal({ freq: 1750 * k, dur: 0.28, gain: 0.5, ratios: [1, 1.52, 2.35, 3.37] }), burst({ dur: 0.04, type: 'bp', cutoff: 2600, q: 1.2, gain: 0.8 }), gravel({ at: 0.01, dur: 0.18, rate: [260, 50], cutoff: 3200, gain: 0.45 }), thump({ f0: 150, f1: 90, dur: 0.07, gain: 0.35 })] }) },
    'hit-dull': { variants: 2, library: ['impactSoft_heavy_000', 'impactSoft_heavy_001'], synth: (k) => ({ layers: [thump({ f0: 150 * k, f1: 85, dur: 0.12 }), burst({ dur: 0.07, cutoff: 500, gain: 0.7 })] }) },
    'hit-blocked': { variants: 2, library: ['impactMetal_medium_000', 'impactMetal_medium_001'], synth: (k) => ({ layers: [metal({ freq: 2600 * k, dur: 0.35, gain: 0.7, ratios: [1, 1.34, 2.71] }), burst({ dur: 0.02, type: 'hp', cutoff: 3500, gain: 0.5 })] }) },
    crit: { library: ['impactBell_heavy_000'], synth: () => ({ echo: { delay: 0.05, feedback: 0.25, mix: 0.3 }, layers: [blip({ f0: 1200, f1: 2400, dur: 0.12, wave: 'square', gain: 0.35 }), metal({ freq: 3000, dur: 0.4, gain: 0.35 }), thump({ f0: 220, f1: 60, dur: 0.16 }), sparkle({ dur: 0.3 })] }) },
    'combo-1': { library: ['jingles_HIT00'], synth: () => ({ layers: notes([E5], { dur: 0.14, wave: 'triangle' }) }) },
    'combo-2': { library: ['jingles_HIT07'], synth: () => ({ layers: notes([G5], { dur: 0.14, wave: 'triangle' }) }) },
    'combo-3': { library: ['jingles_HIT08'], synth: () => ({ layers: notes([C6], { dur: 0.16, wave: 'triangle' }) }) },
    'combo-finisher': { library: ['jingles_HIT11'], synth: () => ({ echo: { delay: 0.06, feedback: 0.3, mix: 0.3 }, layers: [...notes([C5, E5, G5, C6], { step: 0.045, dur: 0.2, wave: 'square', gain: 0.3 }), whoosh({ dur: 0.25, from: 500, peak: 3500, to: 800, gain: 0.6 }), thump({ at: 0.12, f0: 140, f1: 40, dur: 0.3 })] }) },
    'equip-blade': { library: ['drawKnife1'], synth: () => ({ layers: [{ type: 'noise', dur: 0.35, gain: 0.6, env: { peak: 0.25 }, filters: [{ type: 'bp', cutoff: [2500, 7000], q: 4 }] }, metal({ at: 0.05, freq: 3300, dur: 0.45, gain: 0.3 })] }) },
    'equip-tool': { library: ['beltHandle1'], synth: () => ({ layers: [wood({ freq: 700, dur: 0.07 }), wood({ at: 0.07, freq: 520, dur: 0.09 })] }) },
  },

  player: {
    hurt: { library: ['rubberduck-creature-1/cute_07', 'rubberduck-creature-1/cute_08', 'rubberduck-creature-1/cute_01'], variants: 3, synth: (k) => ({ layers: [blorp({ f0: 620 * k, f1: 200 * k, dur: 0.22, wobble: 14, depth: 0.12 }), squelch({ dur: 0.12, gain: 0.5 }), thump({ f0: 140, f1: 70, dur: 0.1, gain: 0.5 })] }) },
    death: { library: ['rubberduck-creature-2/die_02'], synth: () => ({ echo: { delay: 0.09, feedback: 0.3, mix: 0.25 }, layers: [blorp({ f0: 700, f1: 70, dur: 1.0, wobble: 7, depth: 0.15, gain: 0.9 }), ...[0.15, 0.32, 0.5, 0.66].map((at, index) => blip({ at, f0: 300 + index * 60, f1: 700 + index * 80, dur: 0.06, wave: 'sine', gain: 0.35 })), squelch({ at: 0.85, dur: 0.25, gain: 0.6, cutoff: [900, 300] })] }) },
    respawn: { library: ['maximize_009'], synth: () => ({ echo: { delay: 0.08, feedback: 0.35, mix: 0.3 }, layers: [{ type: 'tone', wave: 'sine', dur: 0.6, freq: [200, 800], env: { peak: 0.7 }, gain: 0.5, vibrato: { rate: 10, depth: 0.03 } }, ...notes([C5, E5, G5, C6], { at: 0.3, step: 0.07, dur: 0.3, gain: 0.35 }), sparkle({ at: 0.3, dur: 0.5 })] }) },
    dodge: { library: ['swish-10', 'swish-8'], variants: 2, synth: (k) => ({ layers: [whoosh({ dur: 0.18, from: 500 * k, peak: 2600 * k, to: 900, q: 1.2 }), squelch({ dur: 0.07, gain: 0.3 })] }) },
    jump: { library: ['rubberduck-slime/slime_12', 'rubberduck-slime/slime_06'], variants: 2, synth: (k) => ({ layers: [{ type: 'tone', wave: 'sine', dur: 0.2, freq: [220 * k, 560 * k], glide: 0.12, vibrato: { rate: 18, depth: 0.04 }, env: { a: 0.005, d: 0.2 }, gain: 0.8 }, squelch({ dur: 0.08, gain: 0.35 })] }) },
    land: { variants: 2, library: ['rubberduck-slime/slime_03', 'rubberduck-slime/slime_08'], synth: (k) => ({ layers: [thump({ f0: 140 * k, f1: 55, dur: 0.14 }), squelch({ dur: 0.14, gain: 0.7, cutoff: [1300, 350] })] }) },
    'slam-windup': { library: ['rubberduck-slime/bubble_01'], synth: () => ({ layers: [{ type: 'tone', wave: 'triangle', dur: 0.38, freq: [140, 420], env: { peak: 0.9 }, tremolo: { rate: 22, depth: 0.5 }, gain: 0.5 }, { type: 'noise', dur: 0.38, env: { peak: 0.95 }, filter: { type: 'bp', cutoff: [300, 1600], q: 1.5 }, gain: 0.4 }] }) },
    'slam-impact': { library: ['impactPunch_heavy_002'], synth: () => ({ drive: 2.5, echo: { delay: 0.08, feedback: 0.3, mix: 0.25 }, layers: [thump({ f0: 95, f1: 28, dur: 0.65 }), burst({ dur: 0.35, cutoff: [1100, 200], gain: 0.9, color: 'pink' }), squelch({ dur: 0.3, gain: 0.7, cutoff: [1200, 250] })] }) },
    lash: { library: ['swish-8', 'swish-4'], variants: 2, synth: (k) => ({ layers: [{ type: 'tone', wave: 'sine', dur: 0.12, freq: [300 * k, 1500 * k], glide: 0.1, env: { a: 0.004, d: 0.12 }, gain: 0.55 }, whoosh({ dur: 0.14, from: 800, peak: 3600, to: 1500, gain: 0.7 }), burst({ at: 0.11, dur: 0.02, type: 'hp', cutoff: 2500, gain: 0.7 })] }) },
    'teleport-out': { library: ['minimize_005'], synth: () => ({ layers: [{ type: 'tone', wave: 'sine', dur: 0.35, freq: [1400, 180], fm: { ratio: 3.5, index: [0.4, 0] }, env: { a: 0.01, d: 0.35 }, gain: 0.6 }, sparkle({ dur: 0.3 })] }) },
    'teleport-in': { library: ['maximize_005'], synth: () => ({ layers: [{ type: 'tone', wave: 'sine', dur: 0.35, freq: [180, 1400], fm: { ratio: 3.5, index: [0, 0.4] }, env: { peak: 0.8 }, gain: 0.6 }, sparkle({ at: 0.15, dur: 0.3 })] }) },
    eat: { library: ['rubberduck-creature-1/eat_01', 'rubberduck-creature-1/eat_04'], variants: 2, synth: (k) => ({ layers: [blorp({ f0: 320 * k, f1: 150, dur: 0.12, wobble: 20 }), blorp({ at: 0.13, f0: 260 * k, f1: 110, dur: 0.16, wobble: 16 }), squelch({ at: 0.02, dur: 0.1, gain: 0.35 })] }) },
    heal: { library: ['maximize_004'], synth: () => ({ echo: { delay: 0.09, feedback: 0.35, mix: 0.35 }, layers: [...notes([C5, E5, G5], { step: 0.07, dur: 0.35, wave: 'sine', gain: 0.5 }), sparkle({ at: 0.1, dur: 0.4, gain: 0.15 })] }) },
    'potion-drink': { library: ['rubberduck-slime/bubble_03'], synth: () => ({ layers: [...[0, 0.09, 0.18].map((at, index) => blip({ at, f0: 380 + index * 40, f1: 780 + index * 60, dur: 0.07, wave: 'sine', gain: 0.6 })), crystal({ at: 0.27, freq: 2800, dur: 0.25, gain: 0.3 })] }) },
    'energy-restore': { library: ['maximize_002'], synth: () => ({ layers: [{ type: 'tone', wave: 'square', dur: 0.3, freq: [300, 1200], env: { a: 0.01, d: 0.3 }, gain: 0.25, filter: { type: 'lp', cutoff: 3000 } }, sparkle({ dur: 0.3 })] }) },
    // PLACEHOLDER: the old level-up jingle until an ability-learned sting is made (roadmap 5).
    'ability-learned': { library: ['jingles_NES05'], synth: () => ({ echo: { delay: 0.1, feedback: 0.35, mix: 0.3 }, layers: [...notes([C5, E5, G5], { step: 0.09, dur: 0.14, wave: 'square', gain: 0.28 }), ...notes([C6], { at: 0.27, dur: 0.5, wave: 'square', gain: 0.3 }), ...notes([E6], { at: 0.27, dur: 0.5, wave: 'triangle', gain: 0.3 }), sparkle({ at: 0.27, dur: 0.6 })] }) },
    coin: { variants: 2, library: ['handleCoins', 'handleCoins2'], synth: (k) => ({ layers: [{ type: 'tone', wave: 'square', dur: 0.06, freq: 988 * k, env: { a: 0.001, s: 1, r: 0.005 }, gain: 0.3 }, { type: 'tone', wave: 'square', at: 0.06, dur: 0.28, freq: 1319 * k, env: { a: 0.001, d: 0.28 }, gain: 0.3 }] }) },
    // Looped while asleep. Synth-only: a pause (leading, so it survives silence trimming),
    // a slow airy inhale and a longer, darker exhale with a faint slimy hum underneath.
    'sleep-breath': { synth: () => ({ layers: [
      { type: 'noise', color: 'pink', at: 0.9, dur: 1.5, env: { peak: 0.7, curve: 1.5 }, filter: { type: 'lp', cutoff: [280, 760], q: 0.7 }, gain: 0.9 },
      { type: 'noise', color: 'pink', at: 2.5, dur: 2.0, env: { peak: 0.2, curve: 1.8 }, filter: { type: 'lp', cutoff: [620, 220], q: 0.7 }, gain: 0.75 },
      { type: 'tone', wave: 'sine', at: 2.55, dur: 1.7, freq: [118, 104], env: { peak: 0.25, curve: 1.8 }, gain: 0.08 },
    ] }) },
    // Once, when sleep has restored all HP: two soft, slow sine notes.
    rested: { synth: () => ({ echo: { delay: 0.14, feedback: 0.3, mix: 0.25 }, layers: notes([G5, C6], { step: 0.22, dur: 1.1, wave: 'sine', gain: 0.45, decay: 0.9 }) }) },
    'web-struggle': { library: ['rubberduck-slime/slime_09'], synth: () => ({ layers: [squelch({ dur: 0.12, gain: 0.6 }), squelch({ at: 0.14, dur: 0.12, gain: 0.5, cutoff: [1100, 400] }), { type: 'tone', wave: 'saw', dur: 0.3, freq: [180, 150], tremolo: { rate: 16, depth: 0.7 }, filter: { type: 'lp', cutoff: 800 }, env: { a: 0.02, d: 0.3 }, gain: 0.3 }] }) },
  },

  footstep: {
    grass: { variants: 3, library: ['footstep_grass_000', 'footstep_grass_001', 'footstep_grass_002'], synth: (k) => ({ layers: [squelch({ dur: 0.06, gain: 0.35, cutoff: [900 * k, 400] }), gravel({ dur: 0.07, rate: [400, 150], cutoff: 4000 * k, gain: 0.35, size: 0.003 })] }) },
    forest: { variants: 3, library: ['footstep00', 'footstep01', 'footstep02'], synth: (k) => ({ layers: [squelch({ dur: 0.07, gain: 0.4, cutoff: [800 * k, 350] }), gravel({ dur: 0.09, rate: [250, 90], cutoff: 2200 * k, gain: 0.4 })] }) },
    stone: { variants: 3, library: ['footstep_concrete_000', 'footstep_concrete_001', 'footstep_concrete_002'], synth: (k) => ({ layers: [squelch({ dur: 0.05, gain: 0.35, cutoff: [900, 400] }), burst({ dur: 0.02, type: 'bp', cutoff: 2200 * k, q: 2, gain: 0.35 })] }) },
    snow: { variants: 3, library: ['footstep_snow_000', 'footstep_snow_001', 'footstep_snow_002'], synth: (k) => ({ layers: [gravel({ dur: 0.12, rate: [500, 200], cutoff: 1600 * k, gain: 0.5, size: 0.004 })] }) },
    sand: { variants: 3, library: ['footstep_carpet_000', 'footstep_carpet_001', 'footstep_carpet_002'], synth: (k) => ({ layers: [gravel({ dur: 0.1, rate: [600, 250], cutoff: 3500 * k, gain: 0.35, size: 0.003 }), squelch({ dur: 0.05, gain: 0.2 })] }) },
    water: { library: ['rubberduck-slime/splash_09', 'rubberduck-slime/splash_10', 'rubberduck-slime/splash_15'], variants: 3, synth: (k) => ({ layers: [{ type: 'noise', dur: 0.14, gain: 0.5, env: { a: 0.005, d: 0.14 }, filter: { type: 'bp', cutoff: [900 * k, 2600], q: 1.4 } }, blip({ at: 0.03, f0: 500 * k, f1: 1100 * k, dur: 0.05, wave: 'sine', gain: 0.35 })] }) },
  },

  status: {
    burn: { synth: () => ({ layers: [{ type: 'noise', dur: 0.4, gain: 0.7, env: { peak: 0.2 }, filter: { type: 'bp', cutoff: [600, 2400], q: 1 } }, gravel({ dur: 0.4, rate: [60, 25], cutoff: 3000, gain: 0.5 })] }) },
    poison: { library: ['rubberduck-slime/bubble_02'], synth: () => ({ layers: [...[0, 0.08, 0.17, 0.25].map((at, index) => blip({ at, f0: 250 + index * 30, f1: 420 + index * 40, dur: 0.07, wave: 'sine', gain: 0.5 })), { type: 'tone', wave: 'saw', dur: 0.35, freq: [220, 160], filter: { type: 'lp', cutoff: 600 }, env: { a: 0.02, d: 0.35 }, gain: 0.25 }] }) },
    slow: { library: ['minimize_007'], synth: () => ({ layers: [{ type: 'tone', wave: 'triangle', dur: 0.45, freq: [500, 180], env: { a: 0.01, d: 0.45 }, vibrato: { rate: 5, depth: 0.05 }, gain: 0.5 }] }) },
    sticky: { library: ['rubberduck-slime/slime_05'], synth: () => ({ layers: [squelch({ dur: 0.25, gain: 0.8, cutoff: [1400, 300] }), thump({ f0: 160, f1: 70, dur: 0.15, gain: 0.5 }), squelch({ at: 0.1, dur: 0.15, gain: 0.4, cutoff: [900, 300] })] }) },
    bouncy: { library: ['rubberduck-slime/slime_14'], synth: () => ({ layers: [{ type: 'tone', wave: 'sine', dur: 0.4, freq: [200, 700], vibrato: { rate: 12, depth: [0.2, 0.02] }, env: { a: 0.005, d: 0.4 }, gain: 0.7 }] }) },
    frenzy: { library: ['rubberduck-creature-1/roar_01'], synth: () => ({ drive: 2, layers: [{ type: 'tone', wave: 'saw', dur: 0.45, freq: [180, 260], vibrato: { rate: 25, depth: 0.05 }, filter: { type: 'lp', cutoff: 1500 }, env: { a: 0.02, d: 0.45 }, gain: 0.6 }, whoosh({ dur: 0.3, from: 300, peak: 1800, to: 500, gain: 0.5 })] }) },
    expire: { library: ['minimize_003'], synth: () => ({ layers: [blip({ f0: 900, f1: 500, dur: 0.12, wave: 'sine', gain: 0.4 })] }) },
  },

  enemy: {
    'worm-hurt': { library: ['rubberduck-creature-1/hurt_01', 'rubberduck-creature-1/hurt_02', 'rubberduck-creature-1/hurt_03'], variants: 3, synth: (k) => ({ layers: [{ type: 'tone', wave: 'saw', dur: 0.18, freq: [950 * k, 620 * k], vibrato: { rate: 30, depth: 0.05 }, filter: { type: 'bp', cutoff: 1400 * k, q: 1.5 }, env: { a: 0.005, d: 0.18 }, gain: 0.8 }, squelch({ dur: 0.08, gain: 0.4 })] }) },
    'worm-death': { library: ['rubberduck-creature-2/die_01', 'rubberduck-creature-2/die_03'], variants: 2, synth: (k) => ({ layers: [{ type: 'tone', wave: 'saw', dur: 0.45, freq: [850 * k, 180 * k], vibrato: { rate: 24, depth: 0.06 }, filter: { type: 'bp', cutoff: [1500, 500], q: 1.3 }, env: { a: 0.005, d: 0.45 }, gain: 0.8 }, blip({ at: 0.35, f0: 300, f1: 900, dur: 0.06, wave: 'sine', gain: 0.6 }), squelch({ at: 0.35, dur: 0.12, gain: 0.5 })] }) },
    'worm-alert': { library: ['rubberduck-creature-1/weird_03'], synth: () => ({ layers: [blip({ f0: 700, f1: 1150, dur: 0.07, wave: 'sine', gain: 0.6 }), blip({ at: 0.09, f0: 800, f1: 1300, dur: 0.08, wave: 'sine', gain: 0.6 })] }) },
    'worm-windup': { library: ['rubberduck-creature-1/grunt_02', 'rubberduck-creature-1/grunt_04'], variants: 2, synth: (k) => ({ layers: [{ type: 'tone', wave: 'saw', dur: 0.22, freq: [130 * k, 175 * k], filter: { type: 'lp', cutoff: 650 }, env: { peak: 0.7 }, gain: 0.7 }, { type: 'noise', dur: 0.22, env: { peak: 0.7 }, filter: { type: 'lp', cutoff: 500 }, gain: 0.3 }] }) },
    'bow-draw': { library: ['creak1'], synth: () => ({ layers: [creak({ dur: 0.35, freq: [60, 95], cutoff: 1100, gain: 0.7 })] }) },
    'arrow-release': { library: ['swish-13', 'swish-10'], variants: 2, synth: (k) => ({ layers: [{ type: 'pluck', freq: 170 * k, dur: 0.35, damping: 0.994, brightness: 0.6, gain: 0.7 }, whoosh({ at: 0.02, dur: 0.14, from: 1200, peak: 4200, to: 2000, gain: 0.4, q: 2 })] }) },
    'arrow-hit': { variants: 2, library: ['impactPunch_medium_001', 'impactPunch_medium_002'], synth: (k) => ({ layers: [burst({ dur: 0.04, type: 'bp', cutoff: 1100 * k, q: 1.5, gain: 0.8 }), thump({ f0: 220 * k, f1: 90, dur: 0.09 })] }) },
    'arrow-thunk': { variants: 2, library: ['impactWood_light_000', 'impactWood_light_001'], synth: (k) => ({ layers: [wood({ freq: 300 * k, dur: 0.12 }), { type: 'tone', wave: 'triangle', dur: 0.25, freq: 95 * k, tremolo: { rate: 45, depth: 0.9 }, env: { a: 0.002, d: 0.25 }, gain: 0.3 }] }) },
    'spider-hurt': { library: ['rubberduck-creature-2/bug_05', 'rubberduck-creature-2/bug_06'], variants: 2, synth: (k) => ({ layers: [{ type: 'noise', dur: 0.2, gain: 0.7, env: { a: 0.003, d: 0.2 }, filter: { type: 'bp', cutoff: [3200 * k, 1800], q: 2 } }, { type: 'tone', wave: 'saw', dur: 0.16, freq: [1300 * k, 900 * k], fm: { ratio: 1.41, index: 0.3 }, filter: { type: 'bp', cutoff: 2000, q: 1.2 }, env: { a: 0.003, d: 0.16 }, gain: 0.5 }] }) },
    'spider-death': { library: ['rubberduck-creature-1/bug_01'], synth: () => ({ layers: [{ type: 'tone', wave: 'saw', dur: 0.6, freq: [1400, 250], fm: { ratio: 1.41, index: 0.35 }, filter: { type: 'bp', cutoff: [2500, 600], q: 1.2 }, env: { a: 0.004, d: 0.6 }, gain: 0.7 }, gravel({ at: 0.35, dur: 0.3, rate: [200, 40], cutoff: 1800, gain: 0.6 }), squelch({ at: 0.45, dur: 0.2, gain: 0.5 })] }) },
    'spider-hiss': { library: ['rubberduck-creature-1/bug_02'], synth: () => ({ layers: [{ type: 'noise', dur: 0.55, gain: 0.8, env: { peak: 0.35 }, filters: [{ type: 'hp', cutoff: 2800 }, { type: 'bp', cutoff: [3500, 5500], q: 0.9 }] }] }) },
    'web-spit': { library: ['rubberduck-creature-1/spit_01', 'rubberduck-creature-1/spit_03'], variants: 2, synth: (k) => ({ layers: [{ type: 'tone', wave: 'sine', dur: 0.12, freq: [380 * k, 950 * k], env: { a: 0.004, d: 0.12 }, gain: 0.6 }, squelch({ dur: 0.14, gain: 0.6, cutoff: [2200, 700] })] }) },
    'web-splat': { variants: 2, library: ['rubberduck-slime/slime_01', 'rubberduck-slime/slime_02'], synth: (k) => ({ layers: [squelch({ dur: 0.26, gain: 0.9, cutoff: [1300 * k, 280] }), thump({ f0: 160 * k, f1: 60, dur: 0.16, gain: 0.6 }), ...[0.06, 0.12].map((at) => blip({ at, f0: 300, f1: 600, dur: 0.05, wave: 'sine', gain: 0.25 }))] }) },
    telegraph: { library: ['question_001'], synth: () => ({ layers: [blip({ f0: 1400, f1: 1400, dur: 0.07, wave: 'square', gain: 0.25 }), blip({ at: 0.11, f0: 1400, f1: 1400, dur: 0.07, wave: 'square', gain: 0.25 })] }) },
  },

  boss: {
    'fatty-roar': { library: ['rubberduck-creature-2/roar_05'], synth: () => ({ drive: 2.2, echo: { delay: 0.11, feedback: 0.3, mix: 0.25 }, layers: [{ type: 'tone', wave: 'saw', dur: 1.1, freq: [75, 58], vibrato: { rate: 21, depth: [0.02, 0.08] }, filter: { type: 'lp', cutoff: [500, 900] }, env: { peak: 0.3 }, gain: 0.9 }, { type: 'noise', color: 'pink', dur: 1.1, env: { peak: 0.3 }, filter: { type: 'lp', cutoff: 450 }, gain: 0.6 }] }) },
    'fatty-step': { variants: 2, library: ['rubberduck-creature-2/stomp_01', 'impactSoft_heavy_000'], synth: (k) => ({ layers: [thump({ f0: 80 * k, f1: 40, dur: 0.28 }), squelch({ dur: 0.15, gain: 0.45, cutoff: [700, 250] })] }) },
    'fatty-hop': { library: ['rubberduck-slime/slime_13', 'rubberduck-slime/slime_10'], variants: 2, synth: (k) => ({ layers: [thump({ f0: 100 * k, f1: 42, dur: 0.32 }), squelch({ dur: 0.2, gain: 0.6, cutoff: [900, 250] }), blorp({ f0: 200 * k, f1: 120, dur: 0.18, gain: 0.35 })] }) },
    'fatty-leap': { library: ['rubberduck-creature-2/grunt_07'], synth: () => ({ layers: [whoosh({ dur: 0.5, from: 150, peak: 1400, to: 400, q: 1, color: 'pink' }), { type: 'tone', wave: 'saw', dur: 0.3, freq: [110, 160], filter: { type: 'lp', cutoff: 700 }, env: { peak: 0.5 }, gain: 0.5 }] }) },
    'fatty-fall': { synth: () => ({ layers: [{ type: 'tone', wave: 'sine', dur: 0.8, freq: [1500, 380], env: { a: 0.05, s: 1, r: 0.05 }, gain: 0.35, vibrato: { rate: 6, depth: 0.01 } }, whoosh({ dur: 0.8, from: 300, peak: 1400, to: 900, gain: 0.35 })] }) },
    'fatty-land': { library: ['rubberduck-slime/splash_01'], synth: () => ({ drive: 2.8, echo: { delay: 0.1, feedback: 0.35, mix: 0.3 }, layers: [thump({ f0: 70, f1: 24, dur: 1.0 }), burst({ dur: 0.8, cutoff: [900, 120], gain: 1, color: 'pink' }), squelch({ dur: 0.45, gain: 0.8, cutoff: [1100, 200] }), gravel({ at: 0.05, dur: 0.7, rate: [150, 20], cutoff: 1400, gain: 0.5 })] }) },
    'fatty-hurt': { library: ['rubberduck-creature-1/grunt_01', 'rubberduck-creature-1/grunt_05'], variants: 2, synth: (k) => ({ layers: [{ type: 'tone', wave: 'saw', dur: 0.28, freq: [170 * k, 110 * k], vibrato: { rate: 18, depth: 0.05 }, filter: { type: 'lp', cutoff: 900 }, env: { a: 0.01, d: 0.28 }, gain: 0.8 }, thump({ f0: 120, f1: 60, dur: 0.12, gain: 0.5 })] }) },
    'fatty-recover': { library: ['rubberduck-creature-1/breath'], synth: () => ({ layers: [0, 0.35, 0.7].map((at) => ({ type: 'noise', at, dur: 0.28, env: { peak: 0.4 }, filter: { type: 'bp', cutoff: 700, q: 1.3 }, gain: 0.5 })) }) },
    'fatty-death': { library: ['rubberduck-creature-2/monster_20'], synth: () => ({ drive: 1.8, echo: { delay: 0.12, feedback: 0.35, mix: 0.3 }, layers: [{ type: 'tone', wave: 'saw', dur: 1.6, freq: [150, 38], vibrato: { rate: 8, depth: [0.02, 0.1] }, filter: { type: 'lp', cutoff: [1100, 250] }, env: { a: 0.05, d: 1.6 }, gain: 0.9 }, thump({ at: 1.3, f0: 70, f1: 25, dur: 0.8 }), squelch({ at: 1.3, dur: 0.4, gain: 0.7, cutoff: [800, 200] })] }) },
    victory: { library: ['jingles_NES00'], synth: () => ({ echo: { delay: 0.12, feedback: 0.35, mix: 0.3 }, layers: [...notes([G4, C5, E5], { step: 0.12, dur: 0.2, wave: 'square', gain: 0.25 }), ...notes([G5], { at: 0.36, dur: 0.3, wave: 'square', gain: 0.25 }), ...notes([E5], { at: 0.66, dur: 0.18, wave: 'square', gain: 0.25 }), ...[C6, E6, G5].map((freq) => ({ type: 'tone', wave: 'triangle', at: 0.84, dur: 0.9, freq, env: { a: 0.01, d: 0.9 }, gain: 0.3 })), sparkle({ at: 0.84, dur: 0.8 })] }) },
  },

  resource: {
    'leaf-rustle': { variants: 2, library: ['cloth1', 'cloth2'], synth: (k) => ({ layers: [{ type: 'noise', dur: 0.3, gain: 0.5, env: { peak: 0.3 }, grains: { rate: [350, 120], size: 0.008, jitter: 1.4 }, filter: { type: 'bp', cutoff: 4000 * k, q: 0.8 } }] }) },
    'tree-fall': { library: ['impactWood_heavy_000'], synth: () => ({ echo: { delay: 0.09, feedback: 0.3, mix: 0.25 }, layers: [creak({ dur: 0.7, freq: [55, 90], cutoff: 900, gain: 0.6 }), whoosh({ at: 0.55, dur: 0.4, from: 300, peak: 1600, to: 500, gain: 0.5, color: 'pink' }), thump({ at: 0.9, f0: 90, f1: 30, dur: 0.6 }), burst({ at: 0.9, dur: 0.5, cutoff: [1500, 250], gain: 0.8, color: 'pink' }), gravel({ at: 0.9, dur: 0.6, rate: [400, 60], cutoff: 3800, gain: 0.35 })] }) },
    'stone-crumble': { library: ['impactMining_004'], synth: () => ({ layers: [thump({ f0: 120, f1: 45, dur: 0.3 }), gravel({ dur: 0.75, rate: [260, 30], cutoff: 1800, gain: 0.9, size: 0.01 }), gravel({ dur: 0.5, rate: [300, 50], cutoff: 3500, gain: 0.4 })] }) },
    'ore-clink': { variants: 3, library: ['impactGlass_light_000', 'impactGlass_light_001', 'impactGlass_light_002'], synth: (k) => ({ layers: [crystal({ freq: 2300 * k, dur: 0.5 }), metal({ freq: 1600 * k, dur: 0.12, gain: 0.3 }), burst({ dur: 0.02, type: 'hp', cutoff: 3000, gain: 0.4 })] }) },
    'ore-shatter': { library: ['impactGlass_heavy_000'], synth: () => ({ echo: { delay: 0.07, feedback: 0.3, mix: 0.25 }, layers: [burst({ dur: 0.15, type: 'hp', cutoff: 2500, gain: 0.8 }), ...[0, 0.04, 0.09, 0.15, 0.22, 0.31].map((at, index) => crystal({ at, freq: 1900 + index * 430, dur: 0.4 - index * 0.03, gain: 0.35 })), gravel({ dur: 0.4, rate: [300, 40], cutoff: 5000, gain: 0.4 })] }) },
    'wrong-tool': { variants: 2, library: ['impactMetal_heavy_000', 'impactMetal_heavy_001'], synth: (k) => ({ layers: [metal({ freq: 240 * k, dur: 0.25, gain: 0.8, ratios: [1, 2.02, 3.1] }), thump({ f0: 130, f1: 80, dur: 0.1, gain: 0.6 })] }) },
    'drop-pop': { variants: 2, library: ['drop_001', 'drop_002'], synth: (k) => ({ layers: [blip({ f0: 320 * k, f1: 950 * k, dur: 0.08, wave: 'sine', gain: 0.8 })] }) },
    'drop-land': { variants: 2, library: ['impactGeneric_light_000', 'impactGeneric_light_001'], synth: (k) => ({ layers: [thump({ f0: 240 * k, f1: 130, dur: 0.06, gain: 0.8 }), burst({ dur: 0.02, cutoff: 1800, gain: 0.3 })] }) },
  },

  pickup: {
    wood: { library: ['impactPlank_medium_000'], synth: () => ({ layers: [wood({ freq: 520, dur: 0.08 }), wood({ at: 0.06, freq: 690, dur: 0.1 })] }) },
    stone: { library: ['impactPlate_light_000'], synth: () => ({ layers: [burst({ dur: 0.025, type: 'bp', cutoff: 2600, q: 2, gain: 0.8 }), wood({ freq: 900, dur: 0.06, gain: 0.5 }), burst({ at: 0.07, dur: 0.025, type: 'bp', cutoff: 3100, q: 2, gain: 0.6 })] }) },
    ore: { library: ['impactGlass_light_003'], synth: () => ({ layers: [crystal({ freq: 1568, dur: 0.35, gain: 0.45 }), crystal({ at: 0.07, freq: 2349, dur: 0.45, gain: 0.45 })] }) },
    silk: { library: ['cloth3'], synth: () => ({ layers: [whoosh({ dur: 0.18, from: 1500, peak: 5000, to: 3000, gain: 0.5, q: 0.8 }), blip({ at: 0.1, f0: 1800, f1: 2400, dur: 0.06, wave: 'sine', gain: 0.35 })] }) },
    berry: { library: ['drop_003'], synth: () => ({ layers: [blip({ f0: 480, f1: 1250, dur: 0.09, wave: 'sine', gain: 0.8 }), squelch({ dur: 0.06, gain: 0.3 })] }) },
    potion: { library: ['impactGlass_medium_000'], synth: () => ({ layers: [crystal({ freq: 2650, dur: 0.3, gain: 0.5 }), crystal({ at: 0.05, freq: 3950, dur: 0.25, gain: 0.3 })] }) },
    key: { library: ['metalClick'], synth: () => ({ layers: [0, 0.05, 0.11].map((at, index) => metal({ at, freq: 3100 + index * 380, dur: 0.18, gain: 0.35 })) }) },
    generic: { library: ['handleSmallLeather'], synth: () => ({ layers: [blip({ f0: 600, f1: 1000, dur: 0.08, wave: 'triangle', gain: 0.7 })] }) },
    'inventory-full': { library: ['error_004'], synth: () => ({ layers: [blip({ f0: 160, f1: 150, dur: 0.1, wave: 'square', gain: 0.3 }), blip({ at: 0.13, f0: 140, f1: 130, dur: 0.14, wave: 'square', gain: 0.3 })] }) },
  },

  world: {
    'chest-open': { library: ['doorOpen_1'], synth: () => ({ layers: [creak({ dur: 0.45, freq: [80, 130], cutoff: 1300, gain: 0.5 }), wood({ at: 0.42, freq: 260, dur: 0.12 }), metal({ freq: 1800, dur: 0.08, gain: 0.25 })] }) },
    'chest-close': { library: ['doorClose_1'], synth: () => ({ layers: [wood({ freq: 220, dur: 0.16 }), thump({ f0: 130, f1: 70, dur: 0.12, gain: 0.6 }), metal({ at: 0.03, freq: 1900, dur: 0.07, gain: 0.3 })] }) },
    'chest-locked': { library: ['metalLatch'], synth: () => ({ layers: [0, 0.05, 0.1, 0.16].map((at, index) => metal({ at, freq: 1500 + (index % 2) * 300, dur: 0.07, gain: 0.45 })) }) },
    'gate-locked': { library: ['doorClose_4'], synth: () => ({ layers: [...[0, 0.07, 0.14].map((at) => metal({ at, freq: 700, dur: 0.1, gain: 0.5, ratios: [1, 2.3, 3.9] })), thump({ f0: 110, f1: 70, dur: 0.1, gain: 0.4 })] }) },
    'gate-unlock': { library: ['doorOpen_2'], synth: () => ({ echo: { delay: 0.09, feedback: 0.3, mix: 0.3 }, layers: [metal({ freq: 2200, dur: 0.08, gain: 0.4 }), metal({ at: 0.12, freq: 1700, dur: 0.1, gain: 0.45 }), creak({ at: 0.25, dur: 0.7, freq: [55, 85], cutoff: 900, gain: 0.5 }), ...notes([C5, G5, C6], { at: 0.3, step: 0.1, dur: 0.4, wave: 'sine', gain: 0.35 })] }) },
    'area-transition': { synth: () => ({ layers: [{ type: 'noise', color: 'pink', dur: 0.7, gain: 0.7, env: { peak: 0.5 }, filter: { type: 'lp', cutoff: [300, 2500] } }] }) },
    'area-title': { library: ['jingles_STEEL09'], synth: () => ({ echo: { delay: 0.14, feedback: 0.4, mix: 0.35 }, layers: [...notes([C5, G5, D5, A5], { step: 0.14, dur: 0.6, wave: 'triangle', gain: 0.35 }), sparkle({ at: 0.4, dur: 0.6, gain: 0.12 })] }) },
    'npc-blip': { library: ['rubberduck-creature-1/cute_02', 'rubberduck-creature-1/cute_05', 'rubberduck-creature-1/cute_10'], variants: 3, synth: (k) => ({ layers: [{ type: 'tone', wave: 'square', dur: 0.06, freq: 440 * k, env: { a: 0.002, s: 1, r: 0.015 }, gain: 0.3, filter: { type: 'lp', cutoff: 2500 } }] }) },
    interact: { library: ['tick_001'], synth: () => ({ layers: [blip({ f0: 1500, f1: 1500, dur: 0.03, wave: 'sine', gain: 0.5 })] }) },
    save: { library: ['confirmation_004'], synth: () => ({ echo: { delay: 0.08, feedback: 0.3, mix: 0.3 }, layers: notes([G5, C6], { step: 0.08, dur: 0.3, wave: 'sine', gain: 0.4 }) }) },
    // A ruined building is restored (roadmap 6.3): hammer knocks, a settling thud and a bright finish.
    'restore-building': { library: ['magnific/restore-building'], synth: () => ({ echo: { delay: 0.11, feedback: 0.3, mix: 0.25 }, layers: [
      ...[0, 0.16, 0.32, 0.5].map((at, index) => wood({ at, freq: 360 + (index % 2) * 60, dur: 0.12, gain: 0.8 })),
      ...[0, 0.16, 0.32, 0.5].map((at) => thump({ at, f0: 150, f1: 80, dur: 0.07, gain: 0.35 })),
      thump({ at: 0.72, f0: 120, f1: 45, dur: 0.3, gain: 0.8 }),
      gravel({ at: 0.72, dur: 0.45, rate: [220, 30], cutoff: 1600, gain: 0.45, size: 0.008 }),
      ...notes([C5, E5, G5, C6], { at: 0.95, step: 0.08, dur: 0.45, wave: 'triangle', gain: 0.3 }),
      sparkle({ at: 1.1, dur: 0.5, gain: 0.15 }),
    ] }) },
    // Seamless loops for props and places (roadmap 3.9). Synth-only placeholders until final recordings.
    'campfire-loop': { synth: () => ({ loop: { seconds: 6 }, maxRmsDb: -20, layers: [
      { type: 'noise', color: 'brown', dur: 6.5, gain: 0.5, env: SUSTAIN, filter: { type: 'lp', cutoff: 380 } },
      { type: 'noise', dur: 6.5, gain: 0.9, env: SUSTAIN, grains: { rate: 14, size: 0.004, jitter: 1.6 }, filter: { type: 'hp', cutoff: 1400 } },
      { type: 'noise', dur: 6.5, gain: 0.6, env: SUSTAIN, grains: { rate: 3, size: 0.012, jitter: 1.8 }, filter: { type: 'bp', cutoff: 900, q: 1.2 } },
    ] }) },
    'cauldron-loop': { synth: () => ({ loop: { seconds: 6 }, maxRmsDb: -20, layers: [
      { type: 'noise', color: 'brown', dur: 6.5, gain: 0.5, env: SUSTAIN, filter: { type: 'lp', cutoff: 260 } },
      ...[0.3, 0.9, 1.2, 1.9, 2.6, 2.8, 3.5, 4.1, 4.4, 5.0, 5.6, 6.1].map((at, index) => ({
        type: 'tone', wave: 'sine', at, dur: 0.07 + (index % 3) * 0.02, freq: [260 + (index * 53) % 180, 620 + (index * 71) % 300],
        glide: 0.06, env: { a: 0.003, d: 0.09 }, gain: 0.35,
      })),
    ] }) },
    'grindstone-loop': { synth: () => ({ loop: { seconds: 4 }, maxRmsDb: -20, layers: [
      { type: 'noise', color: 'brown', dur: 4.5, gain: 0.3, env: SUSTAIN, filter: { type: 'lp', cutoff: 300 } },
      ...[0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4].map((at) => ({ type: 'noise', at, dur: 0.45, gain: 0.55, env: { peak: 0.5, curve: 1.3 }, filters: [{ type: 'bp', cutoff: [2200, 3400], q: 2.5 }] })),
    ] }) },
    'anvil-loop': { synth: () => ({ loop: { seconds: 4.8 }, maxRmsDb: -18, layers: [
      ...[[0.2, 1], [1.0, 0.97], [2.6, 1], [3.2, 1.02], [3.8, 0.98]].map(([at, k]) => metal({ at, freq: 1650 * k, dur: 0.9, gain: 0.55, ratios: [1, 2.76, 5.4, 8.9] })),
      ...[0.2, 1.0, 2.6, 3.2, 3.8].map((at) => thump({ at, f0: 170, f1: 90, dur: 0.08, gain: 0.4 })),
    ] }) },
    'meadow-ambience': { synth: () => ({ loop: { seconds: 12, crossfade: 1.5 }, maxRmsDb: -24, layers: [
      { type: 'noise', color: 'pink', dur: 13.5, gain: 0.5, env: SUSTAIN, filter: { type: 'lp', cutoff: 650 } },
      { type: 'noise', color: 'pink', dur: 7, gain: 0.5, env: { peak: 0.5, curve: 1.4 }, filter: { type: 'bp', cutoff: 700, q: 0.8 } },
      { type: 'noise', color: 'pink', at: 6, dur: 7.5, gain: 0.5, env: { peak: 0.5, curve: 1.4 }, filter: { type: 'bp', cutoff: 550, q: 0.8 } },
      ...[[1.2, 1], [1.35, 1.1], [4.8, 0.9], [4.95, 0.95], [5.1, 1.05], [8.3, 1.15], [8.42, 1.2], [10.6, 0.85]].map(([at, k]) => ({
        type: 'tone', wave: 'sine', at, dur: 0.09, freq: [2600 * k, 4100 * k], glide: 0.07, env: { a: 0.004, d: 0.09 }, vibrato: { rate: 40, depth: 0.03 }, gain: 0.12,
      })),
    ] }) },
    'interior-ambience': { synth: () => ({ loop: { seconds: 8 }, maxRmsDb: -26, layers: [
      { type: 'noise', color: 'brown', dur: 8.5, gain: 0.5, env: SUSTAIN, filter: { type: 'lp', cutoff: 220 } },
      { type: 'noise', dur: 8.5, gain: 0.7, env: SUSTAIN, grains: { rate: 6, size: 0.004, jitter: 1.6 }, filter: { type: 'hp', cutoff: 1600 } },
    ] }) },
  },

  ui: {
    hover: { library: ['tick_002'], synth: () => ({ layers: [blip({ f0: 2200, f1: 2200, dur: 0.02, wave: 'sine', gain: 0.4 })] }) },
    click: { library: ['click_001'], synth: () => ({ layers: [blip({ f0: 1300, f1: 900, dur: 0.045, wave: 'triangle', gain: 0.7 })] }) },
    confirm: { library: ['confirmation_001'], synth: () => ({ layers: notes([A5, E6], { step: 0.06, dur: 0.12, wave: 'triangle', gain: 0.5 }) }) },
    cancel: { library: ['back_001'], synth: () => ({ layers: notes([E5, A5 / 2], { step: 0.06, dur: 0.12, wave: 'triangle', gain: 0.5 }) }) },
    error: { library: ['error_001'], synth: () => ({ layers: [blip({ f0: 190, f1: 180, dur: 0.09, wave: 'square', gain: 0.3 }), blip({ at: 0.11, f0: 190, f1: 180, dur: 0.12, wave: 'square', gain: 0.3 })] }) },
    open: { library: ['open_001'], synth: () => ({ layers: [blip({ f0: 400, f1: 950, dur: 0.12, wave: 'triangle', gain: 0.6 }), whoosh({ dur: 0.12, from: 800, peak: 3000, to: 2000, gain: 0.2 })] }) },
    close: { library: ['close_001'], synth: () => ({ layers: [blip({ f0: 950, f1: 400, dur: 0.12, wave: 'triangle', gain: 0.6 })] }) },
    'craft-success': { library: ['confirmation_002'], synth: () => ({ echo: { delay: 0.08, feedback: 0.3, mix: 0.3 }, layers: [metal({ freq: 1200, dur: 0.25, gain: 0.5, ratios: [1, 2.4, 3.9] }), metal({ at: 0.14, freq: 1250, dur: 0.25, gain: 0.5, ratios: [1, 2.4, 3.9] }), ...notes([C6, E6], { at: 0.3, step: 0.07, dur: 0.35, wave: 'sine', gain: 0.4 }), sparkle({ at: 0.3, dur: 0.4 })] }) },
    'craft-fail': { library: ['error_002'], synth: () => ({ layers: [thump({ f0: 160, f1: 90, dur: 0.12, gain: 0.7 }), blip({ at: 0.06, f0: 500, f1: 250, dur: 0.18, wave: 'triangle', gain: 0.5 })] }) },
    'quest-accept': { library: ['jingles_PIZZI04'], synth: () => ({ layers: notes([C5, G5], { step: 0.08, dur: 0.3, wave: 'triangle', gain: 0.5 }) }) },
    'quest-progress': { library: ['pluck_001'], synth: () => ({ layers: [{ type: 'pluck', freq: 1175, dur: 0.25, damping: 0.995, brightness: 0.5, gain: 0.7 }] }) },
    'quest-complete': { library: ['jingles_STEEL07'], synth: () => ({ echo: { delay: 0.11, feedback: 0.35, mix: 0.3 }, layers: [...notes([C5, E5, G5, C6], { step: 0.1, dur: 0.18, wave: 'square', gain: 0.25 }), ...[C6, E6, G5].map((freq) => ({ type: 'tone', wave: 'triangle', at: 0.42, dur: 0.8, freq, env: { a: 0.01, d: 0.8 }, gain: 0.3 })), sparkle({ at: 0.4, dur: 0.7 })] }) },
    'quest-failed': { library: ['jingles_SAX07'], synth: () => ({ layers: notes([E5, D5 * 0.9, C5 * 0.85], { step: 0.14, dur: 0.3, wave: 'triangle', gain: 0.45 }) }) },
    'hotbar-switch': { library: ['switch_001'], synth: () => ({ layers: [blip({ f0: 900, f1: 1200, dur: 0.04, wave: 'square', gain: 0.25 }), wood({ at: 0.02, freq: 800, dur: 0.05, gain: 0.4 })] }) },
    'ability-denied': { library: ['error_006'], synth: () => ({ layers: [blip({ f0: 400, f1: 220, dur: 0.16, wave: 'triangle', gain: 0.55 })] }) },
    'ability-ready': { library: ['select_002'], synth: () => ({ layers: [crystal({ freq: 1760, dur: 0.3, gain: 0.4 })] }) },
    'journal-open': { library: ['bookOpen'], synth: () => ({ layers: [whoosh({ dur: 0.2, from: 1500, peak: 4500, to: 2000, gain: 0.5, q: 0.7 }), burst({ at: 0.17, dur: 0.03, cutoff: 3000, gain: 0.3 })] }) },
    toast: { library: ['drop_004'], synth: () => ({ layers: [blip({ f0: 700, f1: 1050, dur: 0.07, wave: 'sine', gain: 0.5 })] }) },
  },
};

/** Per-take pitch factor so variants differ audibly but stay the same cue. */
export function variantPitch(variant) {
  return [1, 1.07, 0.93, 1.13, 0.88][variant % 5];
}
