#!/usr/bin/env node
/**
 * Sound Picker round 11 (2026-11-16): the synth option of each throw cue, rendered from the
 * building blocks of scripts/audio/cues.mjs into temp/sound-round-11/cut/synth-<cue>-<n>.src.wav
 * (the round's manifest names them as takes; prep-takes.py trims and levels them).
 *
 *   node scripts/audio/picker/round-11-synth.mjs
 *
 * `k` is the take's pitch factor (variantPitch), as in the cue catalog.
 */

import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { BLOCKS, variantPitch } from '../cues.mjs';
import { describe, encodeWav, hashSeed, renderRecipe } from '../synth.mjs';

const { whoosh, thump, burst, wood, blip, crystal, sparkle } = BLOCKS;

const RECIPES = {
  // The toss: a short whoosh falling in pitch, with a small elastic twang under its start.
  toss: { takes: 3, synth: (k) => ({ layers: [
    whoosh({ dur: 0.15, from: 2600 * k, peak: 1500 * k, to: 700, q: 1.2 }),
    { type: 'tone', wave: 'sine', dur: 0.1, freq: [640 * k, 300 * k], glide: 0.08, vibrato: { rate: 34, depth: 0.05 }, env: { a: 0.004, d: 0.1 }, gain: 0.22 },
  ] }) },
  // The body blow: a low-mid thump under a short dull snap and a knock.
  impact: { takes: 3, synth: (k) => ({ layers: [
    thump({ f0: 230 * k, f1: 85, dur: 0.16 }),
    burst({ dur: 0.03, cutoff: 1700, gain: 0.5 }),
    wood({ freq: 310 * k, dur: 0.07, gain: 0.3 }),
  ] }) },
  // The heavy blow: a deeper, longer thump, driven a little, under a dark noise burst.
  heavy: { takes: 3, synth: (k) => ({ drive: 1.8, layers: [
    thump({ f0: 130 * k, f1: 42, dur: 0.3 }),
    thump({ f0: 260 * k, f1: 110, dur: 0.09, gain: 0.45 }),
    burst({ dur: 0.1, cutoff: [900, 220], gain: 0.6, color: 'pink' }),
  ] }) },
  // The kill: a round rising pop, one glass note and a pinch of sparkle. One take, so the game's
  // rising pitch over chained kills is heard.
  kill: { takes: 1, synth: () => ({ layers: [
    blip({ f0: 620, f1: 1500, dur: 0.07, wave: 'sine', gain: 0.8 }),
    crystal({ at: 0.045, freq: 2637, dur: 0.2, gain: 0.3 }),
    sparkle({ at: 0.04, dur: 0.18, gain: 0.2 }),
  ] }) },
};

const outDir = fileURLToPath(new URL('../../../temp/sound-round-11/cut/', import.meta.url));
mkdirSync(outDir, { recursive: true });
for (const [cue, { takes, synth }] of Object.entries(RECIPES)) {
  for (let take = 0; take < takes; take += 1) {
    const name = `synth-${cue}-${take + 1}`;
    const samples = renderRecipe(synth(variantPitch(take), take), hashSeed(`round-11/${name}`));
    writeFileSync(`${outDir}${name}.src.wav`, encodeWav(samples));
    console.log(name, JSON.stringify(describe(samples)));
  }
}
