/**
 * Parity between the pre-scene layered animation runtime and the generated
 * weapon/effect scenes. For every weapon attack direction (including the
 * mirrored/inherited ones), every weapon idle clip and every effect
 * direction, each timeline frame is composed exactly the way the old runtime
 * rendered it (`resolveLayeredAnimationFrame` + `composeAnimationVisualTransform`
 * with the host transform from the old `WeaponVisual` / `WorldEffectAdapter`),
 * and compared with the value the generated AnimationPlayer tracks produce.
 * The scenes are generated fresh: the authored copies are Scene Studio's to
 * retune (combat-entity-conversion checks they keep the generated structure).
 */
import assert from 'node:assert/strict';
import { mkdtemp, readdir, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { effectSceneAdapter, weaponSceneAdapter } from '../../lib/scene-conversion/combat-entities.mjs';
import { ConversionRunner } from '../../lib/scene-conversion/ConversionRunner.mjs';
import { loadAnimationSampling } from '../../lib/scene-conversion/load-animation-sampling.mjs';
import { validateSceneWriteSet } from '../../lib/scene-conversion/validate-scene-write-set.mjs';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));
const generatedRoot = await generateCombatScenes();

/** Replays the weapon and effect conversion into a temporary root. */
async function generateCombatScenes() {
  const productionLedger = await readJsonFile('scripts/migrations/universal-scene-conversion-ledger.json');
  const unitKeys = productionLedger.rows
    .filter((row) => ['weapon', 'effect'].includes(row.family) && row.classification === 'convert')
    .map((row) => row.key);
  const selected = new Set(unitKeys);
  const manifest = await readJsonFile('asset/assets.json');
  const runner = new ConversionRunner({
    repositoryRoot,
    ledger: { ...productionLedger, rows: productionLedger.rows.map((row) => selected.has(row.key) ? { ...row, writerState: 'legacy' } : row) },
    adapters: { weapon: weaponSceneAdapter, effect: effectSceneAdapter },
    outputRoot: await mkdtemp(path.join(os.tmpdir(), 'layered-animation-parity-')),
    validateWriteSet: (outputs) => validateSceneWriteSet(outputs, { hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId) }),
  });
  await runner.run({ unitKeys, mode: 'apply' });
  return runner.outputRoot;
}

const DIRECTIONS = ['right', 'left', 'up', 'down'];
/** Old `CombatController`: `getDepth: () => player.depth + 0.01`. */
const OLD_WEAPON_BASE_DEPTH = 0.01;
const STEP_PROPERTIES = new Set(['frame', 'flipX', 'flipY', 'depthOffset']);
const EPSILON = 1e-9;

async function readJsonFile(relativePath) {
  return JSON.parse(await readFile(path.join(repositoryRoot, relativePath), 'utf8'));
}

async function contentFiles(directory, fileName) {
  const entries = await readdir(path.join(repositoryRoot, directory), { withFileTypes: true });
  return entries.filter((entry) => entry.isDirectory()).map((entry) => `${directory}/${entry.name}/${fileName}`).sort();
}

function title(value) {
  const name = value.replace(/[^a-zA-Z0-9]+(.)/g, (_match, next) => next.toUpperCase());
  return `${name[0]?.toUpperCase() ?? ''}${name.slice(1)}`;
}

/** Evaluates a track exactly like `AnimationBinding.apply`. */
function evaluate(track, frame) {
  const sorted = [...track.keys].sort((left, right) => left.at - right.at);
  let left = sorted[0];
  let right = sorted.at(-1) ?? left;
  for (const key of sorted) {
    if (key.at <= frame) left = key;
    if (key.at >= frame) { right = key; break; }
  }
  if (STEP_PROPERTIES.has(track.property) || right.at <= left.at) return left.value;
  const ratio = (frame - left.at) / (right.at - left.at);
  const lerp = (a, b) => a + (b - a) * ratio;
  return Array.isArray(left.value) ? left.value.map((value, index) => lerp(value, right.value[index])) : lerp(left.value, right.value);
}

function close(actual, expected, message) {
  assert.ok(Math.abs(actual - expected) <= EPSILON, `${message}: expected ${expected}, got ${actual}`);
}

function sceneModel(scene) {
  const resources = new Map(scene.subresources.map((resource) => [resource.resourceId, resource]));
  const library = scene.subresources.find((resource) => resource.kind === 'animation-library');
  const sprites = scene.nodes.filter((node) => node.type === 'Sprite2D').map((node) => ({
    node,
    assetId: resources.get(node.properties.texture.resourceId)?.assetId,
  }));
  return { library, sprites };
}

function spriteForLayer(model, layer, context) {
  const prefix = title(layer.layerId);
  const matches = model.sprites.filter(({ node, assetId }) => assetId === layer.assetId
    && node.name.startsWith(prefix) && /^\d+$/.test(node.name.slice(prefix.length))
    && node.properties.origin[0] === layer.originX && node.properties.origin[1] === layer.originY);
  assert.equal(matches.length, 1, `${context}: exactly one Sprite2D renders layer '${layer.layerId}' (${layer.assetId})`);
  return matches[0].node;
}

/**
 * Compares one clip. `host` is the old runtime host transform relative to the
 * node the generated sprites are parented to (the weapon/effect root).
 */
function assertClipParity(sampling, model, clipId, animation, host, context) {
  const clip = model.library.animations[clipId];
  assert.ok(clip, `${context}: generated clip '${clipId}' exists`);
  const normalized = sampling.normalizeLayeredAnimation(animation);
  const frameCount = sampling.layeredTimelineFrameCount(normalized);
  assert.equal(clip.durationSeconds, normalized.durationSeconds, `${context}: duration`);
  assert.equal(clip.framesPerSecond, normalized.framesPerSecond, `${context}: fps`);
  const tracksFor = (node) => new Map(clip.tracks.filter((track) => track.binding === `../${node.name}`).map((track) => [track.property, track]));
  let comparedLayers = 0;
  for (let frame = 0; frame < frameCount; frame += 1) {
    const at = `${context} frame ${frame}`;
    const visible = new Set();
    for (const resolved of sampling.resolveLayeredAnimationFrame(normalized, frame)) {
      const expected = sampling.composeAnimationVisualTransform(resolved, host);
      const layer = { ...resolved, originX: expected.originX, originY: expected.originY };
      const node = spriteForLayer(model, layer, at);
      visible.add(node.name);
      const tracks = tracksFor(node);
      const value = (property) => {
        const track = tracks.get(property);
        assert.ok(track, `${at}: '${node.name}' has a '${property}' track`);
        return evaluate(track, frame);
      };
      assert.equal(value('frame'), resolved.sourceFrame, `${at} ${node.name}.frame`);
      assert.equal(value('alpha'), 1, `${at} ${node.name}.alpha`);
      const [x, y] = value('position');
      close(x, expected.x, `${at} ${node.name}.position.x`);
      close(y, expected.y, `${at} ${node.name}.position.y`);
      const [scaleX, scaleY] = value('scale');
      close(scaleX, expected.scaleX, `${at} ${node.name}.scale.x`);
      close(scaleY, expected.scaleY, `${at} ${node.name}.scale.y`);
      close(value('rotation'), expected.rotationRad, `${at} ${node.name}.rotation`);
      assert.equal(value('flipX'), expected.flipX, `${at} ${node.name}.flipX`);
      assert.equal(value('flipY'), expected.flipY, `${at} ${node.name}.flipY`);
      close(value('depthOffset'), expected.depth, `${at} ${node.name}.depthOffset`);
      assert.equal(node.properties.depthMode, 'relative', `${at} ${node.name} draws relative to its depth source`);
      comparedLayers += 1;
    }
    for (const { node } of model.sprites) {
      if (visible.has(node.name)) continue;
      const alpha = clip.tracks.find((track) => track.binding === `../${node.name}` && track.property === 'alpha');
      assert.ok(alpha, `${at}: hidden '${node.name}' has an alpha track`);
      assert.equal(evaluate(alpha, frame), 0, `${at}: '${node.name}' is hidden`);
    }
  }
  return comparedLayers;
}

/** Old `Weapon.resolveDirectionalOffset`. */
function oldDirectionalOffset(direction, offsetX, offsetY) {
  if (direction === 'right') return [offsetX, offsetY];
  if (direction === 'left') return [-offsetX, offsetY];
  if (direction === 'up') return [offsetY, -offsetX];
  return [-offsetY, offsetX];
}

test('generated weapon scenes reproduce the old layered weapon visuals and hitbox placement frame by frame', async () => {
  const sampling = await loadAnimationSampling();
  let compared = 0;
  let mirroredDirections = 0;
  for (const file of await contentFiles('src/game/content/weapons', 'weapon.json')) {
    const weapon = sampling.normalizeWeaponDefinition(await readJsonFile(file));
    const scene = JSON.parse(await readFile(path.join(generatedRoot, `weapons/${weapon.weaponId}.scene.json`), 'utf8'));
    const model = sceneModel(scene);
    compared += assertClipParity(sampling, model, 'idle', weapon.animations.idle, {
      x: 0, y: 0, baseDepth: OLD_WEAPON_BASE_DEPTH, rotationRad: 0, mirrorX: false, mirrorY: false,
    }, `${weapon.weaponId} idle`);
    for (const direction of DIRECTIONS) {
      const attack = weapon.directionalAttacks[direction];
      // Old `WeaponVisual.getAnimationHostTransform`.
      const host = {
        x: 0,
        y: attack.presentationOffsetY ?? 0,
        baseDepth: OLD_WEAPON_BASE_DEPTH,
        rotationRad: 0,
        mirrorX: attack.presentation === 'mirror-right',
        mirrorY: attack.presentation === 'mirror-down',
      };
      if (host.mirrorX || host.mirrorY) mirroredDirections += 1;
      compared += assertClipParity(sampling, model, `attack-${direction}`, attack.animation, host, `${weapon.weaponId} attack-${direction}`);

      for (const [hitboxId, hitbox] of Object.entries(attack.hitboxes)) {
        const node = scene.nodes.find((candidate) => candidate.id === `shape-${direction}-${hitboxId}`);
        assert.ok(node, `${weapon.weaponId} ${direction}: hitbox '${hitboxId}' exists`);
        const [offsetX, offsetY] = oldDirectionalOffset(direction, hitbox.offsetX, hitbox.offsetY);
        // Old `Weapon.toHitboxConfig`: y + snapshot.presentationOffsetY.
        close(node.properties.position[0], offsetX, `${weapon.weaponId} ${direction} ${hitboxId}.x`);
        close(node.properties.position[1], offsetY + (attack.presentationOffsetY ?? 0), `${weapon.weaponId} ${direction} ${hitboxId}.y`);
        if (hitbox.shape === 'sector') {
          const shape = scene.subresources.find((resource) => resource.resourceId === node.properties.shape.resourceId).value;
          close(shape.arcWidthRad, hitbox.arcWidthRad, `${weapon.weaponId} ${direction} ${hitboxId}.arcWidthRad`);
        }
      }
    }
  }
  assert.ok(compared > 300, `compared ${compared} layer samples`);
  assert.ok(mirroredDirections >= 10, `covered ${mirroredDirections} inherited (mirrored) weapon directions`);
});

test('generated effect scenes reproduce the old layered effect visuals for every direction', async () => {
  const sampling = await loadAnimationSampling();
  let compared = 0;
  for (const file of await contentFiles('src/game/content/effects', 'effect.json')) {
    const effect = await readJsonFile(file);
    const scene = JSON.parse(await readFile(path.join(generatedRoot, `effects/${effect.effectId}.scene.json`), 'utf8'));
    const model = sceneModel(scene);
    const root = scene.nodes.find((node) => node.id === scene.rootNodeId);
    assert.deepEqual(root.properties.depthAnchor, [0, 0], `${effect.effectId}: the effect root is its layers' depth source`);
    for (const direction of sampling.EFFECT_DIRECTIONS) {
      const variant = sampling.resolveEffectVariant(effect, direction);
      assert.ok(variant, `${effect.effectId} resolves '${direction}'`);
      // Old `WorldEffectAdapter.getAnimationHostTransform`, relative to the spawn point and requested depth.
      compared += assertClipParity(sampling, model, direction, variant.animation, {
        x: 0, y: 0, baseDepth: 0, rotationRad: 0, mirrorX: variant.mirrorX, mirrorY: variant.mirrorY,
      }, `${effect.effectId} ${direction}`);
    }
  }
  assert.ok(compared > 0);
});
