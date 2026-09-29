#!/usr/bin/env node
/**
 * audio:wire — authors audio nodes into scene JSON from one declarative table.
 *
 *   node scripts/audio/wire-scene-audio.mjs [--check]
 *
 * For every scene rule below it (re)creates AudioStreamPlayer/AudioStreamPlayer2D
 * nodes (ids `sfx-*`), their inline `audio` stream resources (ids `sfx.*`, `music.*`) and
 * the signal connections that trigger them. Everything previously generated
 * (sfx-* nodes, sfx.* and music.* resources, connections targeting sfx-* nodes) is removed
 * first, so the script is idempotent and the table is the single source of
 * truth for *where* a cue plays. The cue catalog (scripts/audio/cues.mjs)
 * owns *what* it sounds like; scenes keep ownership of volume/pitch/bus.
 *
 * --check exits non-zero when any scene differs from the table (CI guard).
 */

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { CUES } from './cues.mjs';

const repoRoot = fileURLToPath(new URL('../..', import.meta.url));
const authoredRoot = join(repoRoot, 'src/game/content/scenes/authored');
const checkOnly = process.argv.includes('--check');

// ── Cue helpers ─────────────────────────────────────────────────────────────

function cueAssets(cueRef) {
  const [category, cue] = cueRef.split('/');
  // Music tracks are hand-authored manifest entries (audio.music.<name>), not catalog cues.
  if (category === 'music') return { resourceId: `music.${cue}`, assetId: `audio.music.${cue}`, variants: [] };
  const definition = CUES[category]?.[cue];
  if (!definition) throw new Error(`Unknown cue '${cueRef}' (see scripts/audio/cues.mjs)`);
  const count = definition.variants ?? 1;
  const ids = Array.from({ length: count }, (_, index) => `audio.sfx.${category}.${cue}.${index + 1}`);
  return { resourceId: `sfx.${category}.${cue}`, assetId: ids[0], variants: ids.slice(1) };
}

/**
 * One audio node.
 *   name      node name (PascalCase); id becomes sfx-<kebab name>
 *   cue       'category/cue' from the catalog
 *   on        [{ signal, source?: scriptId | node id, filter? }] triggering play (source defaults to the scene's script node)
 *   positional  AudioStreamPlayer2D (default true) vs AudioStreamPlayer
 *   props     extra node properties (volume, pitchRandomness, minIntervalMs, detached, autoplay, maxDistance, ...)
 */
const sfx = (name, cue, on = [], props = {}, positional = true) => ({ name, cue, on, props, positional });

const kebab = (name) => name.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase();

// ── Wiring table ────────────────────────────────────────────────────────────

const ONE_SHOT = { pitchRandomness: 0.06 };
const DETACHED = { ...ONE_SHOT, detached: true };
const IMPACT = { autoplay: true, detached: true, pitchRandomness: 0.07 };

const ENEMY_WORM = (windupCue) => [
  sfx('HurtSfx', 'enemy/worm-hurt', [{ signal: 'damaged' }], { ...ONE_SHOT, minIntervalMs: 90 }),
  sfx('DeathSfx', 'enemy/worm-death', [{ signal: 'defeated' }], DETACHED),
  sfx('AlertSfx', 'enemy/worm-alert', [{ signal: 'alerted' }], { ...ONE_SHOT, volume: 0.7 }),
  sfx('WindupSfx', windupCue, [{ signal: 'attack_started' }], { ...ONE_SHOT, volume: 0.8 }),
];

const TREE = [
  sfx('RustleSfx', 'resource/leaf-rustle', [{ signal: 'resource_hit' }], { ...ONE_SHOT, volume: 0.8 }),
  sfx('WrongToolSfx', 'resource/wrong-tool', [{ signal: 'harvest_blocked' }], { ...ONE_SHOT, minIntervalMs: 200 }),
  sfx('FallSfx', 'resource/tree-fall', [{ signal: 'drops_requested' }], DETACHED),
];

const PICKUP = (cue) => [
  sfx('PickupSfx', cue, [{ signal: 'pickup_resolved', filter: 'status=collected|partial' }], DETACHED),
  sfx('InventoryFullSfx', 'pickup/inventory-full', [{ signal: 'pickup_resolved', filter: 'status=rejected' }], { minIntervalMs: 600 }),
];

const UI_CONTROLS = { buttons: 'ui/click', lists: 'ui/hover' };

/** scene file (relative to authored/) or predicate → nodes */
const RULES = [
  // Impact effects: autoplay on spawn, outlive the effect node.
  ['effects/basic-sword-impact.scene.json', [sfx('ImpactSfx', 'weapon/hit-slash', [], IMPACT)]],
  ['effects/basic-spear-impact.scene.json', [sfx('ImpactSfx', 'weapon/hit-stab', [], IMPACT)]],
  ['effects/slam-hammer-impact.scene.json', [sfx('ImpactSfx', 'weapon/hit-heavy', [], IMPACT)]],
  ['effects/wood-impact.scene.json', [sfx('ImpactSfx', 'weapon/chop-wood', [], IMPACT)]],
  ['effects/stone-impact.scene.json', [sfx('ImpactSfx', 'weapon/mine-stone', [], IMPACT)]],
  ['effects/boss-ground-crack.scene.json', [sfx('ImpactSfx', 'resource/stone-crumble', [], { ...IMPACT, volume: 0.6 })]],
  ['effects/enemy-worm-brawler-hit.scene.json', [sfx('ImpactSfx', 'weapon/hit-punch', [], IMPACT)]],
  ['effects/spider-web-cover.scene.json', [sfx('ImpactSfx', 'enemy/web-splat', [], IMPACT)]],

  // Weapons: swing on attack start. The player's own sounds are non-positional so a
  // camera clamped at the map edge never makes them quieter.
  ['weapons/goo-gauntlet.scene.json', [sfx('SwingSfx', 'weapon/swing-light', [{ signal: 'attack_started' }], ONE_SHOT, false)]],
  ['weapons/basic-sword.scene.json', [sfx('SwingSfx', 'weapon/swing-blade', [{ signal: 'attack_started' }], ONE_SHOT, false)]],
  ['weapons/basic-spear.scene.json', [sfx('SwingSfx', 'weapon/thrust', [{ signal: 'attack_started' }], ONE_SHOT, false)]],
  ['weapons/wooden-spear.scene.json', [sfx('SwingSfx', 'weapon/thrust', [{ signal: 'attack_started' }], ONE_SHOT, false)]],
  ['weapons/stone-spear.scene.json', [sfx('SwingSfx', 'weapon/thrust', [{ signal: 'attack_started' }], ONE_SHOT, false)]],
  ['weapons/slam-hammer.scene.json', [sfx('SwingSfx', 'weapon/swing-heavy', [{ signal: 'attack_started' }], ONE_SHOT, false)]],
  ['weapons/wooden-axe.scene.json', [sfx('SwingSfx', 'weapon/swing-tool', [{ signal: 'attack_started' }], ONE_SHOT, false)]],
  ['weapons/stone-axe.scene.json', [sfx('SwingSfx', 'weapon/swing-tool', [{ signal: 'attack_started' }], ONE_SHOT, false)]],
  ['weapons/pickaxe.scene.json', [sfx('SwingSfx', 'weapon/swing-tool', [{ signal: 'attack_started' }], ONE_SHOT, false)]],
  ['weapons/stone-pickaxe.scene.json', [sfx('SwingSfx', 'weapon/swing-tool', [{ signal: 'attack_started' }], ONE_SHOT, false)]],

  // Characters.
  ['characters/player-slime.scene.json', [
    sfx('HurtSfx', 'player/hurt', [{ signal: 'damaged' }], { ...ONE_SHOT, minIntervalMs: 120 }, false),
    sfx('DeathSfx', 'player/death', [{ signal: 'defeated' }], {}, false),
  ]],
  ['characters/worm-archer.scene.json', ENEMY_WORM('enemy/bow-draw')],
  ['characters/worm-brawler.scene.json', ENEMY_WORM('enemy/worm-windup')],
  ['characters/worm-swordsman.scene.json', ENEMY_WORM('enemy/worm-windup')],
  ['characters/slime-spider.scene.json', [
    sfx('HurtSfx', 'enemy/spider-hurt', [{ signal: 'damaged' }], { ...ONE_SHOT, minIntervalMs: 90 }),
    sfx('DeathSfx', 'enemy/spider-death', [{ signal: 'defeated' }], DETACHED),
    sfx('AlertSfx', 'enemy/spider-hiss', [{ signal: 'alerted' }], { ...ONE_SHOT, volume: 0.8 }),
  ]],
  ['characters/fatty-one-eye.scene.json', [
    sfx('HurtSfx', 'boss/fatty-hurt', [{ signal: 'damaged' }], { ...ONE_SHOT, minIntervalMs: 150 }),
    sfx('HopSfx', 'boss/fatty-hop', [{ signal: 'phase_changed', filter: 'phase=contact-hop|small-hop' }], ONE_SHOT),
    sfx('LeapSfx', 'boss/fatty-leap', [{ signal: 'phase_changed', filter: 'phase=airborne' }], {}),
    sfx('FallSfx', 'boss/fatty-fall', [{ signal: 'phase_changed', filter: 'phase=airborne' }], { volume: 0.7 }),
    sfx('LandSfx', 'boss/fatty-land', [{ signal: 'phase_changed', filter: 'phase=landing' }], { maxDistance: 1400 }),
    sfx('RecoverSfx', 'boss/fatty-recover', [{ signal: 'phase_changed', filter: 'phase=recovery' }], { volume: 0.7 }),
    sfx('DeathSfx', 'boss/fatty-death', [{ signal: 'phase_changed', filter: 'phase=dead' }], { detached: true, maxDistance: 1400 }),
  ]],
  ['encounters/level-1-fatty-camp.scene.json', [
    sfx('RoarSfx', 'boss/fatty-roar', [{ signal: 'boss_spawn_requested' }], { maxDistance: 1600 }),
  ]],

  // Interactables and pickups.
  ['objects/chest-wooden.scene.json', [
    sfx('LockedSfx', 'world/chest-locked', [{ signal: 'guard_blocked' }], { minIntervalMs: 400 }),
    sfx('OpenSfx', 'world/chest-open', [{ signal: 'open_requested' }], {}),
    sfx('CloseSfx', 'world/chest-close', [{ signal: 'closed' }], {}),
    sfx('TakeSfx', 'pickup/generic', [{ signal: 'stack_transferred' }], ONE_SHOT),
  ]],
  ['objects/collectible-charcoal-pile.scene.json', PICKUP('pickup/stone')],
  ['objects/collectible-crystal-shard.scene.json', PICKUP('pickup/ore')],
  ['objects/collectible-energy-potion.scene.json', PICKUP('pickup/potion')],
  ['objects/collectible-hp-potion.scene.json', PICKUP('pickup/potion')],
  ['objects/collectible-green-key.scene.json', PICKUP('pickup/key')],
  ['objects/collectible-iron-ore-pile.scene.json', PICKUP('pickup/ore')],
  ['objects/collectible-purple-berry.scene.json', PICKUP('pickup/berry')],
  ['objects/collectible-silk-clump.scene.json', PICKUP('pickup/silk')],
  ['objects/collectible-small-stone-pile.scene.json', PICKUP('pickup/stone')],
  ['objects/collectible-stone-pile.scene.json', PICKUP('pickup/stone')],
  ['objects/collectible-small-wood-pile.scene.json', PICKUP('pickup/wood')],
  ['objects/collectible-wood-pile.scene.json', PICKUP('pickup/wood')],

  // Resource nodes.
  [(file) => file.startsWith('objects/tree-world-solid'), TREE],
  [(file) => file.startsWith('objects/resource-stone-node'), [
    sfx('WrongToolSfx', 'resource/wrong-tool', [{ signal: 'harvest_blocked' }], { ...ONE_SHOT, minIntervalMs: 200 }),
    sfx('CrumbleSfx', 'resource/stone-crumble', [{ signal: 'drops_requested' }], DETACHED),
  ]],
  ['objects/rock-amber-ore-mineable.scene.json', [
    sfx('ClinkSfx', 'resource/ore-clink', [{ signal: 'resource_hit' }], ONE_SHOT),
    sfx('WrongToolSfx', 'resource/wrong-tool', [{ signal: 'harvest_blocked' }], { ...ONE_SHOT, minIntervalMs: 200 }),
    sfx('ShatterSfx', 'resource/ore-shatter', [{ signal: 'drops_requested' }], DETACHED),
  ]],

  // Projectiles.
  ['projectiles/worm-arrow.scene.json', [
    sfx('ReleaseSfx', 'enemy/arrow-release', [{ signal: 'launched' }], ONE_SHOT),
    sfx('ThunkSfx', 'enemy/arrow-thunk', [{ signal: 'expired' }], DETACHED),
  ]],
  ['projectiles/spider-web.scene.json', [
    sfx('SpitSfx', 'enemy/web-spit', [{ signal: 'launched' }], ONE_SHOT),
  ]],

  // World music: a looping, non-positional track on the music bus while the world is mounted.
  ['worlds/level-1.scene.json', [
    sfx('MusicPlayer', 'music/level-1-home-town', [], { bus: 'music', loop: true, autoplay: true, volume: 0.55, polyphony: 1 }, false),
  ]],

  // Global cues driven by features/audio/AudioEventBridge (names must match its cue names).
  ['audio/global.scene.json', [
    ...[
      ['Dodge', 'player/dodge'], ['Eat', 'player/eat'], ['Jump', 'player/jump'], ['Land', 'player/land'],
      ['TeleportOut', 'player/teleport-out'], ['TeleportIn', 'player/teleport-in'], ['SlamWindup', 'player/slam-windup'],
      ['SlamImpact', 'player/slam-impact'], ['Lash', 'player/lash'], ['AbilityDenied', 'ui/ability-denied'],
      ['Heal', 'player/heal'], ['Respawn', 'player/respawn'], ['EnergyRestore', 'player/energy-restore'],
      ['Coin', 'player/coin'], ['LevelUp', 'player/level-up'], ['PerkChoose', 'ui/perk-choose'],
      ['StatusBurn', 'status/burn'], ['StatusPoison', 'status/poison'], ['StatusSlow', 'status/slow'],
      ['StatusSticky', 'status/sticky'], ['StatusBouncy', 'status/bouncy'], ['StatusFrenzy', 'status/frenzy'],
      ['StatusExpire', 'status/expire'], ['EquipBlade', 'weapon/equip-blade'], ['EquipTool', 'weapon/equip-tool'],
      ['CraftSuccess', 'ui/craft-success'], ['NpcBlip', 'world/npc-blip'], ['QuestAccept', 'ui/quest-accept'],
      ['QuestProgress', 'ui/quest-progress'], ['QuestComplete', 'ui/quest-complete'], ['QuestFailed', 'ui/quest-failed'],
      ['Victory', 'boss/victory'], ['AreaTransition', 'world/area-transition'], ['MenuOpen', 'ui/open'],
      ['MenuClose', 'ui/close'], ['JournalOpen', 'ui/journal-open'],
    ].map(([name, cue]) => sfx(name, cue, [], { ...ONE_SHOT, minIntervalMs: 60 }, false)),
    // Sleeping: a quiet breathing loop started/stopped by player.sleep, and one soft chime when rested.
    sfx('SleepBreath', 'player/sleep-breath', [], { loop: true, volume: 0.3, polyphony: 1 }, false),
    sfx('Rested', 'player/rested', [], { volume: 0.35, minIntervalMs: 1000 }, false),
  ], 'effects'],

  // UI scenes: every Button press clicks, list selections and slider steps tick.
  [(file) => file.startsWith('ui/'), UI_CONTROLS],
];

// ── Scene editing ───────────────────────────────────────────────────────────

function listScenes(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    if (entry.isDirectory()) return listScenes(join(dir, entry.name), `${prefix}${entry.name}/`);
    return entry.name.endsWith('.scene.json') ? [`${prefix}${entry.name}`] : [];
  });
}

function ruleFor(file) {
  return RULES.find(([match]) => (typeof match === 'string' ? match === file : match(file)));
}

function stripGenerated(scene) {
  const nodes = scene.nodes.filter((node) => !node.id.startsWith('sfx-'));
  const connections = (scene.connections ?? []).filter((connection) => !connection.target.nodeId?.startsWith('sfx-'));
  const subresources = (scene.subresources ?? []).filter((resource) => !resource.resourceId.startsWith('sfx.') && !resource.resourceId.startsWith('music.'));
  return { ...scene, nodes, connections, subresources };
}

function scriptNodeId(scene) {
  const script = scene.nodes.find((node) => node.scriptId);
  if (!script) throw new Error(`${scene.sceneId} has no script node to connect audio signals from`);
  return script.id;
}

function addNodes(scene, specs, parentId = scene.rootNodeId) {
  const siblingOrders = [
    ...scene.nodes.filter((node) => node.parentId === parentId).map((node) => node.order),
    ...scene.instances.filter((instance) => instance.parentNodeId === parentId).map((instance) => instance.order),
  ];
  let order = Math.max(-1, ...siblingOrders) + 1;
  for (const spec of specs) {
    const { resourceId, assetId, variants } = cueAssets(spec.cue);
    if (!scene.subresources.some((resource) => resource.resourceId === resourceId)) {
      scene.subresources.push({ version: 1, resourceId, kind: 'audio', assetId, ...(variants.length ? { variants } : {}) });
    }
    const id = `sfx-${kebab(spec.name)}`;
    scene.nodes.push({
      id, name: spec.name, type: spec.positional ? 'AudioStreamPlayer2D' : 'AudioStreamPlayer', parentId, order: order++,
      properties: { stream: { resourceId }, ...spec.props },
    });
    for (const trigger of spec.on) {
      scene.connections.push({ source: { nodeId: trigger.source ?? scriptNodeId(scene) }, signal: trigger.signal, target: { nodeId: id }, handler: 'play' });
      if (trigger.filter) scene.nodes.at(-1).properties.payloadFilter = trigger.filter;
    }
  }
}

function addUiControls(scene, controls) {
  const buttons = scene.nodes.filter((node) => node.type === 'Button');
  const lists = scene.nodes.filter((node) => node.type === 'ItemList');
  const sliders = scene.nodes.filter((node) => node.type === 'Slider');
  const specs = [];
  if (buttons.length) specs.push(sfx('ClickSfx', controls.buttons, [], { minIntervalMs: 40 }, false));
  if (lists.length || sliders.length) specs.push(sfx('SelectSfx', controls.lists, [], { minIntervalMs: 40, volume: 0.8 }, false));
  if (!specs.length) return;
  addNodes(scene, specs);
  for (const button of buttons) scene.connections.push({ source: { nodeId: button.id }, signal: 'pressed', target: { nodeId: 'sfx-click-sfx' }, handler: 'play' });
  for (const list of lists) scene.connections.push({ source: { nodeId: list.id }, signal: 'item_selected', target: { nodeId: 'sfx-select-sfx' }, handler: 'play' });
  // Slider ticks double as a loudness preview while dragging (throttled by minIntervalMs).
  for (const slider of sliders) scene.connections.push({ source: { nodeId: slider.id }, signal: 'value_changed', target: { nodeId: 'sfx-select-sfx' }, handler: 'play' });
}

let changed = 0;
let wired = 0;
for (const file of listScenes(authoredRoot)) {
  const rule = ruleFor(file);
  const path = join(authoredRoot, file);
  const raw = readFileSync(path, 'utf8');
  const crlf = raw.includes('\r\n');
  const original = JSON.parse(raw);
  const scene = stripGenerated(original);
  if (rule) {
    const [, specs, parentName] = rule;
    if (Array.isArray(specs)) {
      const parentId = parentName ? scene.nodes.find((node) => node.id === parentName)?.id : scene.rootNodeId;
      if (!parentId) throw new Error(`${file}: parent node '${parentName}' not found`);
      addNodes(scene, specs, parentId);
    } else {
      addUiControls(scene, specs);
    }
    wired += 1;
  }
  if (!scene.connections.length && original.connections === undefined) delete scene.connections;
  if (!scene.subresources.length && original.subresources === undefined) delete scene.subresources;
  const next = `${JSON.stringify(scene, null, 2)}\n`;
  if (next === raw.replace(/\r\n/g, '\n')) continue;
  changed += 1;
  if (checkOnly) { console.error(`audio:wire drift: ${file}`); continue; }
  writeFileSync(path, crlf ? next.replace(/\n/g, '\r\n') : next);
}

if (checkOnly && changed) process.exit(1);
console.log(`audio:wire ${checkOnly ? 'check ' : ''}OK — ${wired} scene(s) wired, ${changed} ${checkOnly ? 'out of date' : 'updated'}.`);
