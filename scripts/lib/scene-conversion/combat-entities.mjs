import { convertedOutput, readJson, shapeValue } from './adapter-utils.mjs';
import { collision } from './collision-layers.mjs';
import { loadAnimationSampling } from './load-animation-sampling.mjs';

const DIRECTIONS = ['right', 'left', 'up', 'down'];
const WEAPON_KEYS = new Set([
  'weapon:basic-spear', 'weapon:basic-sword', 'weapon:goo-gauntlet', 'weapon:pickaxe', 'weapon:slam-hammer',
  'weapon:stone-axe', 'weapon:stone-pickaxe', 'weapon:stone-spear', 'weapon:wooden-axe', 'weapon:wooden-spear',
  'weapon:reinforced-pickaxe', 'weapon:iron-spear', 'weapon:iron-axe',
]);
const PROJECTILE_KEYS = new Set(['projectile:worm-arrow']);
const EFFECT_KEYS = new Set([
  'effect:basic-spear-impact', 'effect:basic-sword-impact', 'effect:slam-hammer-impact', 'effect:stone-impact', 'effect:wood-impact',
]);

function requireUnit(unit, supported) {
  if (!supported.has(unit.key)) throw new Error(`Scene conversion adapter does not support unit '${unit.key}' yet`);
}

function title(value) {
  const name = value.replace(/[^a-zA-Z0-9]+(.)/g, (_match, next) => next.toUpperCase());
  return `${name[0]?.toUpperCase() ?? ''}${name.slice(1)}`;
}

function assetResource(resourceId, assetId, manifest) {
  const frame = manifest.assets[assetId]?.source?.frame;
  if (!manifest.assets[assetId]) throw new Error(`Unknown combat scene asset '${assetId}'`);
  if (!frame) return { version: 1, resourceId, kind: 'texture', assetId };
  return {
    version: 1, resourceId, kind: 'sprite-sheet', assetId,
    frameWidth: frame.w, frameHeight: frame.h, frameCount: frame.count,
  };
}

function collisionShape(shape, angleRad = 0) {
  if (shape.shape === 'circle') return { shape: 'circle', radius: shape.radius ?? shape.width / 2 };
  if (shape.shape === 'ellipse') return { shape: 'ellipse', radiusX: shape.radiusX ?? shape.width / 2, radiusY: shape.radiusY ?? shape.height / 2 };
  if (shape.shape === 'sector') return {
    shape: 'sector', angleRad,
    innerRadius: shape.innerRadius ?? 0,
    outerRadius: shape.outerRadius ?? Math.max(shape.width, shape.height) / 2,
    arcWidthRad: shape.arcWidthRad ?? 0.8,
  };
  return { shape: 'rectangle', width: shape.width, height: shape.height };
}

/**
 * Draw order of a wielded weapon relative to its wielder, from the old
 * `CombatController` (`getDepth: () => player.depth + 0.01`). Layer order and
 * authored `depthOffset` are added on top by `animationLayerRelativeDepth`.
 */
const WIELDED_WEAPON_DEPTH_OFFSET = 0.01;

function layerKey(layer) {
  const origin = layer.transform?.origin ?? [0.5, 0.5];
  return `${layer.layerId}:${layer.assetId}:${origin[0]},${origin[1]}`;
}

function collectLayers(clips) {
  const layers = new Map();
  for (const { animation } of clips) {
    for (const layer of animation.layers ?? []) if (!layers.has(layerKey(layer))) layers.set(layerKey(layer), layer);
  }
  return layers;
}

function layerNodeName(layer, index) { return `${title(layer.layerId)}${index + 1}`; }

function restingLayerState(layer, baseDepthOffset) {
  const transform = layer.transform ?? {};
  return {
    sourceFrame: 0,
    x: transform.offset?.[0] ?? 0,
    y: transform.offset?.[1] ?? 0,
    scaleX: transform.scale?.[0] ?? 1,
    scaleY: transform.scale?.[1] ?? 1,
    rotationRad: (transform.rotationDeg ?? 0) * Math.PI / 180,
    flipX: transform.flipX ?? false,
    flipY: transform.flipY ?? false,
    depth: 0,
    baseDepthOffset,
  };
}

/**
 * Samples every clip through the shared layered-animation composition (the
 * exact functions the old runtime rendered with, including directional
 * mirroring and the host presentation offset) and writes one step-accurate
 * key per timeline frame for every animated Sprite2D property.
 */
function animationLibrary(resourceId, clips, layers, layerNames, sampling, baseDepthOffset) {
  const animations = {};
  for (const { animationId, animation, host } of clips) {
    const samples = sampling.sampleLayeredAnimation(animation, host);
    const tracks = [];
    for (const [key, knownLayer] of layers) {
      const resting = restingLayerState(knownLayer, baseDepthOffset);
      const perFrame = samples.map(({ layers: active }) => active.find((candidate) => {
        const source = animation.layers[candidate.layerIndex];
        return layerKey(source) === key;
      }));
      const firstActive = perFrame.find(Boolean);
      let held = firstActive ?? resting;
      const states = perFrame.map((active) => {
        if (active) held = active;
        return { visible: Boolean(active), value: active ?? held };
      });
      const binding = `../${layerNames.get(key)}`;
      const keys = (read) => states.map((state, at) => ({ at, value: read(state) }));
      tracks.push({ binding, property: 'frame', keys: keys(({ value }) => value.sourceFrame) });
      tracks.push({ binding, property: 'alpha', keys: keys(({ visible }) => (visible ? 1 : 0)) });
      tracks.push({ binding, property: 'position', keys: keys(({ value }) => [value.x, value.y]) });
      tracks.push({ binding, property: 'scale', keys: keys(({ value }) => [value.scaleX, value.scaleY]) });
      tracks.push({ binding, property: 'rotation', keys: keys(({ value }) => value.rotationRad) });
      tracks.push({ binding, property: 'flipX', keys: keys(({ value }) => value.flipX) });
      tracks.push({ binding, property: 'flipY', keys: keys(({ value }) => value.flipY) });
      tracks.push({ binding, property: 'depthOffset', keys: keys(({ value }) => baseDepthOffset + value.depth) });
    }
    animations[animationId] = {
      durationSeconds: animation.durationSeconds,
      framesPerSecond: animation.framesPerSecond,
      loop: animation.loop,
      ...(animation.loopMode ? { loopMode: animation.loopMode } : {}),
      tracks,
    };
  }
  return { version: 1, resourceId, kind: 'animation-library', animations };
}

function visualContent(rootId, clips, manifest, baseDepthOffset) {
  const layers = collectLayers(clips);
  const layerNames = new Map([...layers].map(([key, layer], index) => [key, layerNodeName(layer, index)]));
  const resourceByAsset = new Map();
  for (const layer of layers.values()) {
    if (!resourceByAsset.has(layer.assetId)) resourceByAsset.set(layer.assetId, `${rootId}.visual.${resourceByAsset.size + 1}`);
  }
  const resources = [...resourceByAsset].map(([assetId, resourceId]) => assetResource(resourceId, assetId, manifest));
  const nodes = [...layers].map(([key, layer], index) => ({
    id: `visual-${index + 1}`,
    name: layerNames.get(key),
    type: 'Sprite2D',
    parentId: 'root',
    order: index,
    properties: {
      texture: { resourceId: resourceByAsset.get(layer.assetId) }, frame: 0,
      origin: layer.transform?.origin ?? [0.5, 0.5],
      position: layer.transform?.offset ?? [0, 0],
      scale: layer.transform?.scale ?? [1, 1],
      rotation: (layer.transform?.rotationDeg ?? 0) * Math.PI / 180,
      alpha: 0,
      // Layers draw relative to the nearest depth source: the wielder's body
      // for weapons, the effect root (or its requested depth) for effects.
      depthMode: 'relative', depthOffset: baseDepthOffset, depthBand: 'world-entities',
    },
  }));
  return { layers, layerNames, resources, nodes };
}

function orientation(direction) {
  if (direction === 'left') return { angle: Math.PI, x: -1, y: 1, swap: false };
  if (direction === 'down') return { angle: Math.PI / 2, x: -1, y: 1, swap: true };
  if (direction === 'up') return { angle: -Math.PI / 2, x: 1, y: -1, swap: true };
  return { angle: 0, x: 1, y: 1, swap: false };
}

/** Old `Weapon.toHitboxConfig`: directional offset plus the attack's presentation offset. */
function orientedPosition(shape, direction, presentationOffsetY) {
  const value = orientation(direction);
  const x = shape.offsetX ?? 0;
  const y = shape.offsetY ?? 0;
  const [px, py] = value.swap ? [y * value.x, x * value.y] : [x * value.x, y * value.y];
  return [px, py + presentationOffsetY];
}

function weaponScene(source, manifest, sampling) {
  const weapon = sampling.normalizeWeaponDefinition(source);
  const attacks = DIRECTIONS.map((direction) => [direction, weapon.directionalAttacks[direction]]);
  const clips = [
    { animationId: 'idle', animation: weapon.animations.idle, host: {} },
    ...attacks.map(([direction, attack]) => ({
      animationId: `attack-${direction}`,
      animation: attack.animation,
      host: { offsetY: attack.presentationOffsetY, mirrorX: attack.mirrorX, mirrorY: attack.mirrorY },
    })),
  ];
  const visual = visualContent(`weapon.${weapon.weaponId}`, clips, manifest, WIELDED_WEAPON_DEPTH_OFFSET);
  const animationId = `weapon.${weapon.weaponId}.animations`;
  const shapeResources = [];
  const shapeNodes = [];
  const attackPlans = {};
  for (const [direction, attack] of attacks) {
    const spans = (attack.attackTrack?.hitboxSpans ?? []).map((span) => {
      const hitbox = attack.hitboxes?.[span.hitboxId];
      return {
        ...span,
        damageMultiplier: hitbox?.damageMultiplier ?? 1,
        knockbackMultiplier: hitbox?.knockbackMultiplier ?? 1,
      };
    });
    attackPlans[direction] = {
      animationId: `attack-${direction}`,
      durationMs: attack.animation.durationSeconds * 1000,
      framesPerSecond: attack.animation.framesPerSecond,
      hitboxSpans: spans,
      events: attack.attackTrack?.events ?? [],
      mirrored: { x: attack.mirrorX, y: attack.mirrorY },
    };
    for (const [hitboxId, hitbox] of Object.entries(attack.hitboxes ?? {})) {
      const resourceId = `weapon.${weapon.weaponId}.${direction}.${hitboxId}.shape`;
      shapeResources.push({ version: 1, resourceId, kind: 'collision-shape', value: collisionShape(hitbox, orientation(direction).angle) });
      shapeNodes.push({
        id: `shape-${direction}-${hitboxId}`,
        name: `${direction}--${hitboxId}`,
        type: 'CollisionShape2D',
        parentId: 'attack-area',
        order: shapeNodes.length,
        properties: {
          shape: { resourceId }, position: orientedPosition(hitbox, direction, attack.presentationOffsetY),
          // Legacy weapon rectangles, circles, and ellipses remain axis-aligned;
          // only their directional offsets rotate. Sectors encode direction in
          // the shape resource's angleRad instead of a node transform.
          rotation: 0,
          disabled: true,
        },
      });
    }
  }
  const visualCount = visual.nodes.length;
  return {
    version: 1,
    sceneId: `weapon.${weapon.weaponId}`,
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: title(weapon.weaponId), type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } },
      ...visual.nodes,
      { id: 'attack-area', name: 'AttackArea', type: 'Area2D', parentId: 'root', order: visualCount, properties: { ...collision(['hitbox'], ['hurtbox']), monitoring: false, monitorable: false } },
      ...shapeNodes,
      { id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'root', order: visualCount + 1, properties: { library: { resourceId: animationId }, domain: 'physics', autoplay: 'idle' } },
      {
        id: 'script', name: 'WeaponScript', type: 'ScriptNode', scriptId: 'game.weapon', parentId: 'root', order: visualCount + 2,
        properties: {
          weaponId: weapon.weaponId, category: weapon.category,
          attackArea: { nodeId: 'attack-area' }, animation: { nodeId: 'animation' },
          baseDamage: weapon.baseDamage, cooldownMs: weapon.cooldownMs, knockStrength: weapon.knockStrength,
          damageModifiers: weapon.damageModifiers ?? [], harvestCapabilities: weapon.harvestCapabilities ?? {}, scaling: weapon.scaling ?? {},
          ...(weapon.onHitEffectId ? { onHitEffectId: weapon.onHitEffectId } : {}),
          attackPlans,
        },
      },
    ],
    instances: [],
    connections: [{ source: { nodeId: 'attack-area' }, signal: 'area_entered', target: { nodeId: 'script' }, handler: 'on_area_entered' }],
    subresources: [...visual.resources, ...shapeResources, animationLibrary(animationId, clips, visual.layers, visual.layerNames, sampling, WIELDED_WEAPON_DEPTH_OFFSET)],
  };
}

/**
 * Old `Projectile.syncVisual`: the per-frame `frameOffsets` (else the source
 * offset) is a visual offset rotated by the projectile's rotation, so it is
 * written to Sprite2D.visualOffset, which Sprite2D rotates with the node.
 */
function projectileFrameOffsetTracks(projectile, animation) {
  const frameOffsets = projectile.visual?.frameOffsets ?? {};
  if (Object.keys(frameOffsets).length === 0) return [];
  const fallback = projectile.visual?.sourceOffset ?? [0, 0];
  return [{ binding: '../Visual', property: 'visualOffset', keys: animation.frames.map((frame, at) => ({ at, value: frameOffsets[String(frame)] ?? fallback })) }];
}

function projectileAnimationLibrary(projectile) {
  const animations = {};
  for (const [id, animation] of Object.entries(projectile.animations ?? (projectile.animation ? { move: projectile.animation } : {}))) {
    animations[id] = {
      durationSeconds: animation.frames.length / animation.framesPerSecond,
      framesPerSecond: animation.framesPerSecond,
      loop: animation.loop,
      ...(animation.loopMode ? { loopMode: animation.loopMode } : {}),
      tracks: [
        { binding: '../Visual', property: 'frame', keys: animation.frames.map((value, at) => ({ at, value })) },
        ...projectileFrameOffsetTracks(projectile, animation),
      ],
    };
  }
  return { version: 1, resourceId: `projectile.${projectile.projectileId}.animations`, kind: 'animation-library', animations };
}

function projectileScene(projectile, manifest) {
  const prefix = `projectile.${projectile.projectileId}`;
  const texture = assetResource(`${prefix}.visual`, projectile.assetId, manifest);
  const shape = { version: 1, resourceId: `${prefix}.body-shape`, kind: 'collision-shape', value: shapeValue(projectile.body) };
  const animations = projectileAnimationLibrary(projectile);
  return {
    version: 1, sceneId: prefix, rootNodeId: 'body',
    nodes: [
      { id: 'body', name: title(projectile.projectileId), type: 'CharacterBody2D', parentId: null, order: 0, properties: { ...collision(['projectile'], ['world']), collideWorldBounds: false, position: [0, 0], velocity: [0, 0] } },
      { id: 'body-shape', name: 'BodyShape', type: 'CollisionShape2D', parentId: 'body', order: 0, properties: { shape: { resourceId: shape.resourceId }, position: [projectile.body.centerOffsetX, projectile.body.centerOffsetY] } },
      { id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'body', order: 1, properties: { texture: { resourceId: texture.resourceId }, frame: 0, visualOffset: projectile.visual?.sourceOffset ?? [0, 0], depthMode: 'world-sorted', depthBand: 'world-entities' } },
      { id: 'attack-area', name: 'AttackArea', type: 'Area2D', parentId: 'body', order: 2, properties: { ...collision(['hitbox'], ['hurtbox']), monitoring: true, monitorable: false } },
      { id: 'attack-shape', name: 'AttackShape', type: 'CollisionShape2D', parentId: 'attack-area', order: 0, properties: { shape: { resourceId: shape.resourceId }, position: [projectile.body.centerOffsetX, projectile.body.centerOffsetY] } },
      { id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'body', order: 3, properties: { library: { resourceId: animations.resourceId }, domain: 'physics', autoplay: 'move' } },
      { id: 'script', name: 'ProjectileScript', type: 'ScriptNode', scriptId: 'game.projectile', parentId: 'body', order: 4, properties: {
        projectileId: projectile.projectileId, body: { nodeId: 'body' }, visual: { nodeId: 'visual' }, animation: { nodeId: 'animation' }, attackArea: { nodeId: 'attack-area' },
        defaultSpeed: projectile.movement.defaultSpeed, lifetimeMs: projectile.movement.lifetimeMs, rotateToVelocity: projectile.movement.rotateToVelocity,
      } },
    ],
    instances: [],
    connections: [{ source: { nodeId: 'attack-area' }, signal: 'area_entered', target: { nodeId: 'script' }, handler: 'on_area_entered' }],
    subresources: [texture, shape, animations],
  };
}

function effectScene(effect, manifest, sampling) {
  const clips = sampling.EFFECT_DIRECTIONS.map((direction) => {
    const variant = sampling.resolveEffectVariant(effect, direction);
    if (!variant) throw new Error(`Effect '${effect.effectId}' does not resolve direction '${direction}'`);
    return { animationId: direction, animation: variant.animation, host: { mirrorX: variant.mirrorX, mirrorY: variant.mirrorY } };
  });
  const visual = visualContent(`effect.${effect.effectId}`, clips, manifest, 0);
  const animationId = `effect.${effect.effectId}.animations`;
  const lifetimeMs = Math.max(...clips.map(({ animation }) => animation.durationSeconds * 1000), 0);
  const visualCount = visual.nodes.length;
  return {
    version: 1, sceneId: `effect.${effect.effectId}`, rootNodeId: 'root',
    nodes: [
      // The root's depth anchor makes it the depth source of its layers; a
      // spawn request's explicit depth overrides it at runtime.
      { id: 'root', name: title(effect.effectId), type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0], depthAnchor: [0, 0] } },
      ...visual.nodes,
      { id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'root', order: visualCount, properties: { library: { resourceId: animationId }, domain: 'physics', autoplay: 'right' } },
      { id: 'script', name: 'EffectScript', type: 'ScriptNode', scriptId: 'game.effect', parentId: 'root', order: visualCount + 1, properties: { effectId: effect.effectId, animation: { nodeId: 'animation' }, lifetimeMs } },
    ],
    instances: [], subresources: [...visual.resources, animationLibrary(animationId, clips, visual.layers, visual.layerNames, sampling, 0)],
  };
}

async function manifest(readSource) { return readJson(readSource, 'asset/assets.json'); }

export const weaponSceneAdapter = {
  async convert({ units, readSource }) {
    const assets = await manifest(readSource);
    const sampling = await loadAnimationSampling();
    const outputs = [];
    for (const unit of units) {
      requireUnit(unit, WEAPON_KEYS);
      const weapon = await readJson(readSource, unit.oldSourcePath);
      outputs.push(convertedOutput(unit, `weapons/${weapon.weaponId}.scene.json`, weaponScene(weapon, assets, sampling), ['$']));
    }
    return outputs;
  },
};

export const projectileSceneAdapter = {
  async convert({ units, readSource }) {
    const assets = await manifest(readSource);
    const outputs = [];
    for (const unit of units) {
      requireUnit(unit, PROJECTILE_KEYS);
      const projectile = await readJson(readSource, unit.oldSourcePath);
      outputs.push(convertedOutput(unit, `projectiles/${projectile.projectileId}.scene.json`, projectileScene(projectile, assets), ['$']));
    }
    return outputs;
  },
};

export const effectSceneAdapter = {
  async convert({ units, readSource }) {
    const assets = await manifest(readSource);
    const sampling = await loadAnimationSampling();
    const outputs = [];
    for (const unit of units) {
      requireUnit(unit, EFFECT_KEYS);
      const effect = await readJson(readSource, unit.oldSourcePath);
      outputs.push(convertedOutput(unit, `effects/${effect.effectId}.scene.json`, effectScene(effect, assets, sampling), ['$']));
    }
    return outputs;
  },
};
