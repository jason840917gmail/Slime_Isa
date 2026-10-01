import test from 'node:test';
import assert from 'node:assert/strict';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

globalThis.HTMLElement ??= class {};
const shell = await loadTypescriptModule('src/game/features/shell/tooling.ts');

const quietTarget = () => {
  const listeners = new Set();
  return {
    listeners,
    addEventListener: (_type, listener) => listeners.add(listener),
    removeEventListener: (_type, listener) => listeners.delete(listener),
    press(key, extra = {}) {
      const event = { key, repeat: false, defaultPrevented: false, target: null, preventDefault() { this.defaultPrevented = true; }, stopPropagation() {}, ...extra };
      for (const listener of [...listeners]) listener(event);
      return event;
    },
  };
};
const modalStack = () => new shell.ModalStack(quietTarget());
const memorySettings = (initial) => {
  const saved = [];
  const service = new shell.GameSettingsService({ load: () => initial ?? shell.DEFAULT_GAME_SETTINGS, save: (value) => saved.push(value) });
  return { service, saved };
};

test('settings edit the service, which saves each change and tells the mixer; reduce motion turns shake off', () => {
  const { service, saved } = memorySettings();
  const pauses = [];
  let controlsOpened = 0;
  const port = new shell.SettingsSurfacePort({ modalStack: modalStack(), settings: service, onPausedChange: (paused) => pauses.push(paused), openControls: () => { controlsOpened += 1; } });
  port.open();
  port.invoke('settings', 'set-value', { control: 'Music', value: 0.25 });
  port.invoke('settings', 'set-value', { control: 'Shake', value: 0.5 });
  port.invoke('settings', 'set-value', { control: 'Unknown', value: 0.1 });
  assert.equal(service.settings.music, 0.25);
  assert.equal(service.shakeScale, 0.5);
  assert.equal(saved.length, 2);
  port.invoke('settings', 'toggle-reduce-motion');
  assert.equal(service.shakeScale, 0);
  assert.equal(port.snapshot('settings').shakeDisabled, true);
  assert.match(port.snapshot('settings').shakeLabel, /off/);
  port.invoke('settings', 'controls');
  assert.equal(controlsOpened, 1);
  port.invoke('settings', 'reset');
  assert.deepEqual(service.settings, shell.DEFAULT_GAME_SETTINGS);
  port.invoke('settings', 'close');
  assert.deepEqual(pauses, [true, false]);

  const applied = [];
  const mixer = { setMasterVolume: (v) => applied.push(['master', v]), setMasterMuted: (v) => applied.push(['muted', v]), setVolume: (bus, v) => applied.push([bus, v]) };
  shell.applyMix(mixer, { ...shell.DEFAULT_GAME_SETTINGS, effects: 0.4 });
  assert.deepEqual(applied.find(([bus]) => bus === 'ambience'), ['ambience', 0.4], 'ambience follows the effects slider');
});

test('Esc opens the pause menu only when nothing else is open and play allows it', () => {
  const target = quietTarget();
  const stack = modalStack();
  const calls = [];
  let allowed = false;
  const pause = new shell.PauseMenuSurfacePort({
    modalStack: stack, keyTarget: target,
    actions: {
      canOpen: () => allowed,
      openJournal: () => calls.push('journal'), openInventory: () => calls.push('inventory'), openMap: () => calls.push('map'),
      openSettings: () => calls.push('settings'), openSaves: () => calls.push('saves'), quitToTitle: () => calls.push('quit'),
      openLoad: () => calls.push('load'), hasLoadable: () => true,
    },
  });
  target.press('Escape');
  assert.equal(pause.isOpen(), false, 'blocked while play forbids pausing (title, defeat)');
  allowed = true;
  target.press('Escape', { defaultPrevented: true });
  assert.equal(pause.isOpen(), false, 'an Escape the modal stack already used never opens it');
  target.press('Escape');
  assert.equal(pause.isOpen(), true);
  pause.invoke('pause-menu', 'settings');
  assert.equal(pause.isOpen(), true, 'settings open on top of the menu');
  pause.invoke('pause-menu', 'journal');
  assert.equal(pause.isOpen(), false, 'journal replaces the menu');
  pause.open();
  pause.invoke('pause-menu', 'load');
  assert.equal(pause.isOpen(), true, 'load opens on top of the menu');
  pause.invoke('pause-menu', 'quit');
  assert.deepEqual(calls, ['settings', 'journal', 'load', 'quit']);
  pause.destroy();
  assert.equal(target.listeners.size, 0);
});

test('save slots save to empty slots, ask before overwriting, and only load filled slots', async () => {
  const saves = [];
  const log = [];
  const storage = {
    list: () => saves,
    create: (name) => { saves.push({ saveId: `id-${name}`, name, updatedAt: 0, currentMapId: 'level-1', playTimeMs: 125 * 60_000 }); log.push(['create', name]); return { ok: true }; },
    overwrite: (saveId) => { log.push(['overwrite', saveId]); return { ok: true }; },
    load: async (saveId) => { log.push(['load', saveId]); return { ok: false, message: 'The authored map is unavailable.' }; },
    unreadable: () => [],
    autosave: () => undefined,
    loadAutosave: () => ({ ok: false, message: 'There is no autosave yet.' }),
  };
  const port = new shell.SaveSlotsSurfacePort({ modalStack: modalStack(), storage, placeName: () => 'Slimeshire Meadow', formatTime: () => 'today' });
  port.openFor('save');
  assert.equal(port.snapshot('save-slots').slot1Label, 'Slot 1  ·  Empty');
  port.invoke('save-slots', 'slot-1');
  assert.deepEqual(log, [['create', 'Slot 1']]);
  assert.equal(port.snapshot('save-slots').slot1Label, 'Slot 1  ·  Slimeshire Meadow  ·  2:05 played  ·  today');
  port.invoke('save-slots', 'slot-1');
  assert.equal(port.snapshot('save-slots').confirming, true, 'a filled slot asks first');
  port.invoke('save-slots', 'confirm');
  assert.deepEqual(log.at(-1), ['overwrite', 'id-Slot 1']);

  port.openFor('load');
  assert.equal(port.snapshot('save-slots').slot2Disabled, true, 'empty slots cannot be loaded');
  port.invoke('save-slots', 'slot-2');
  port.invoke('save-slots', 'slot-1');
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.deepEqual(log.at(-1), ['load', 'id-Slot 1']);
  assert.equal(port.snapshot('save-slots').status, 'The authored map is unavailable.');
});

test('loading lists the autosave first, says why a slot cannot be read, and recovers from a thrown load', async () => {
  const log = [];
  const storage = {
    list: () => [{ saveId: 'id-2', name: 'Slot 2', updatedAt: 0, currentMapId: 'level-1', playTimeMs: 60_000 }],
    unreadable: () => [{ name: 'Slot 1', reason: 'The snapshot failed schema validation.' }],
    create: () => ({ ok: true }),
    overwrite: () => ({ ok: true }),
    load: async (saveId) => { log.push(['load', saveId]); throw new Error('storage exploded'); },
    autosave: () => ({ mapId: 'gloop-forest', playTimeMs: 3 * 60_000 }),
    loadAutosave: () => { log.push(['autosave']); return { ok: true }; },
  };
  const port = new shell.SaveSlotsSurfacePort({ modalStack: modalStack(), storage, placeName: (mapId) => mapId === 'gloop-forest' ? 'Gloop Forest' : 'Slimeshire Meadow', formatTime: () => 'today' });
  port.openFor('save');
  assert.equal(port.snapshot('save-slots').autosaveVisible, false, 'saving never offers the autosave');
  port.openFor('load');
  let model = port.snapshot('save-slots');
  assert.equal(model.autosaveVisible, true);
  assert.equal(model.autosaveLabel, 'Autosave (latest)  ·  Gloop Forest  ·  0:03 played');
  assert.equal(model.slot1Label, "Slot 1  ·  Can't be loaded: The snapshot failed schema validation.");
  assert.equal(model.slot1Disabled, true);
  port.invoke('save-slots', 'slot-2');
  await new Promise((resolve) => setTimeout(resolve, 0));
  model = port.snapshot('save-slots');
  assert.equal(model.status, 'storage exploded', 'a thrown load reports instead of staying busy');
  assert.equal(model.slot2Disabled, false);
  port.invoke('save-slots', 'autosave');
  assert.deepEqual(log, [['load', 'id-2'], ['autosave']]);
  assert.equal(port.snapshot('save-slots').status, 'Loading the autosave…');
});

test('the title screen confirms a new game over an autosave and cannot be dismissed with Escape', () => {
  const stackTarget = quietTarget();
  const stack = new shell.ModalStack(stackTarget);
  const calls = [];
  const title = new shell.TitleSurfacePort({
    modalStack: stack, version: '0.1.0',
    actions: {
      canContinue: () => true, hasLoadable: () => false, hasAutosave: () => true,
      newGame: () => calls.push('new'), continueGame: () => calls.push('continue'),
      openLoad: () => calls.push('load'), openSettings: () => calls.push('settings'), openCredits: () => calls.push('credits'),
    },
  });
  title.open();
  assert.equal(title.snapshot('title-screen').version, 'v0.1.0');
  assert.equal(title.snapshot('title-screen').loadDisabled, true);
  title.invoke('title-screen', 'new-game');
  assert.equal(title.snapshot('title-screen').confirming, true);
  assert.deepEqual(calls, []);
  title.invoke('title-screen', 'confirm-new-game');
  title.invoke('title-screen', 'continue');
  assert.deepEqual(calls, ['new', 'continue']);
  stackTarget.press('Escape');
  assert.equal(title.isOpen(), true);
});

test('game over names the cause and waking closes it exactly once', () => {
  const calls = [];
  const over = new shell.GameOverSurfacePort({ modalStack: modalStack(), actions: { wake: () => calls.push('wake'), openLoad: () => calls.push('load'), hasLoadable: () => true } });
  over.show({ cause: 'Worm Brawler', playTimeMs: 61 * 60_000, hasBed: true });
  const model = over.snapshot('game-over');
  assert.equal(model.cause, 'Defeated by Worm Brawler');
  assert.equal(model.playTime, '1:01 played');
  assert.equal(model.wakeLabel, 'Wake at your bed');
  over.invoke('game-over', 'wake');
  over.invoke('game-over', 'wake');
  assert.deepEqual(calls, ['wake']);
  assert.equal(over.isOpen(), false);
  over.show({ playTimeMs: 0, hasBed: false });
  assert.equal(over.snapshot('game-over').wakeLabel, 'Wake in Slimeshire');
  assert.equal(over.snapshot('game-over').cause, 'You were defeated');
});

test('an end card appears when its flag is newly set, never for flags a loaded save already had', () => {
  const flags = new Set(['old-flag']);
  let returned = 0;
  const cards = [{ flagId: 'old-flag', title: 'Old', subtitle: '', body: '' }, { flagId: 'new-flag', title: 'New', subtitle: 'Sub', body: 'Body' }];
  const card = new shell.EndCardSurfacePort({ modalStack: modalStack(), cards, hasFlag: (id) => flags.has(id), returnToTitle: () => { returned += 1; } });
  card.checkFlags();
  assert.equal(card.isOpen(), false);
  flags.add('new-flag');
  card.checkFlags();
  assert.equal(card.isOpen(), true);
  assert.equal(card.snapshot('end-card').title, 'New');
  card.invoke('end-card', 'return-to-title');
  assert.equal(returned, 1);
  card.checkFlags();
  assert.equal(card.isOpen(), false, 'a card shows once');
});

test('credits read every section and CC0 source from the data file; controls list every action key', () => {
  const text = shell.creditsText();
  for (const section of shell.CREDIT_SECTIONS) assert.match(text, new RegExp(section.heading.toUpperCase()));
  assert.match(text, /Home Town/);
  assert.match(text, /CC0 1\.0/);
  const keys = shell.controlRows().map(([key]) => key);
  for (const key of ['WASD', 'Left click', 'Right click', 'Space', '1', 'Q', 'E', 'Mouse wheel', 'Esc']) assert.ok(keys.includes(key), key);
});
