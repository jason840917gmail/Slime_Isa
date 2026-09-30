import test from 'node:test';
import assert from 'node:assert/strict';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { MusicDirector, MUSIC_FADE_IN_MS, MUSIC_CROSSFADE_MS, MUSIC_PAUSE_DUCK } = await loadTypescriptModule('src/game/features/audio/MusicDirector.ts');

function track(playing = false) {
  return {
    playing,
    gains: [],
    play() { this.playing = true; },
    stop() { this.playing = false; },
    setGain(gain) { this.gains.push(gain); },
    get gain() { return this.gains.at(-1); },
  };
}

function director({ unlocked = true, boss = true } = {}) {
  const world = track(true);
  const bossTrack = boss ? track(false) : undefined;
  const ducks = [];
  const state = { unlocked };
  const music = new MusicDirector({
    world,
    boss: bossTrack,
    isAudioUnlocked: () => state.unlocked,
    setMusicDuck: (factor) => ducks.push(factor),
  });
  return { music, world, boss: bossTrack, ducks, state };
}

test('world music starts silent and rises over the fade-in, never jumping to full volume', () => {
  const { music, world } = director();
  assert.equal(world.gain, 0);
  music.update(MUSIC_FADE_IN_MS / 2);
  assert.ok(Math.abs(world.gain - 0.5) < 1e-9);
  music.update(MUSIC_FADE_IN_MS);
  assert.equal(world.gain, 1);
});

test('fades wait while the browser keeps audio locked', () => {
  const { music, world, state } = director({ unlocked: false });
  music.update(5000);
  assert.equal(world.gain, 0);
  state.unlocked = true;
  music.update(MUSIC_FADE_IN_MS / 4);
  assert.ok(world.gain > 0 && world.gain < 1);
});

test('a boss fight crossfades to boss music and back, and the boss track stops once silent', () => {
  const { music, world, boss } = director();
  music.update(MUSIC_FADE_IN_MS);
  music.setBossFight(true);
  assert.equal(boss.playing, true);
  music.update(MUSIC_CROSSFADE_MS / 2);
  assert.ok(world.gain > 0 && world.gain < 1 && boss.gain > 0 && boss.gain < 1, 'both tracks overlap mid-crossfade');
  music.update(MUSIC_CROSSFADE_MS);
  assert.deepEqual([world.gain, boss.gain], [0, 1]);
  music.setBossFight(false);
  music.update(MUSIC_CROSSFADE_MS / 2);
  assert.equal(boss.playing, true, 'the boss track keeps playing while it fades');
  music.update(MUSIC_CROSSFADE_MS);
  assert.deepEqual([world.gain, boss.gain], [1, 0]);
  assert.equal(boss.playing, false);
});

test('without boss music the world track keeps playing through a fight', () => {
  const { music, world } = director({ boss: false });
  music.update(MUSIC_FADE_IN_MS);
  music.setBossFight(true);
  music.update(MUSIC_CROSSFADE_MS);
  assert.equal(world.gain, 1);
});

test('pausing ducks the music bus and resuming restores it', () => {
  const { music, ducks } = director();
  music.setPaused(true);
  music.update(1000);
  assert.equal(ducks.at(-1), MUSIC_PAUSE_DUCK);
  music.setPaused(false);
  music.update(1000);
  assert.equal(ducks.at(-1), 1);
});

test('leaving the area fades every track out over the requested time', () => {
  const { music, world, boss } = director();
  music.update(MUSIC_FADE_IN_MS);
  music.fadeOut(300);
  music.update(150);
  assert.ok(Math.abs(world.gain - 0.5) < 1e-9);
  music.update(150);
  assert.equal(world.gain, 0);
  assert.equal(boss.gain, 0);
});
