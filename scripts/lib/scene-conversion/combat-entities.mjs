import { convertedOutput, readJson, shapeValue } from './adapter-utils.mjs';

const DIRECTIONS = ['right', 'left', 'up', 'down'];
const WEAPON_KEYS = new Set([
  'weapon:basic-spear', 'weapon:basic-sword', 'weapon:goo-gauntlet', 'weapon:pickaxe', 'weapon:slam-hammer',
  'weapon:stone-axe', 'weapon:stone-pickaxe', 'weapon:stone-spear', 'weapon:wooden-axe', 'weapon:wooden-spear',
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

function layeredClips(entries) {
  const clips = [];
  for (const [animationId, animation] of entries) {
    if (!animation) continue;
    clips.push({ animationId, animation });
  }
  return clips;
}

function layerKey(layer) { return `${layer.layerId}:${layer.assetId}`; }

function collectLayers(clips) {
  const layers = new Map();
  for (const { animation } of clips) {
    for (const layer of animation.layers ?? []) if (!layers.has(layerKey(layer))) layers.set(layerKey(layer), layer);
  }
  return layers;
}

function layerNodeName(layer, index) { return `${title(layer.layerId)}${index + 1}`; }

function animationLibrary(resourceId, clips, layers, layerNames) {
  const animations = {};
  for (const { animationId, animation } of clips) {
    const frameCount = Math.max(1, Math.ceil(animation.durationSeconds * animation.framesPerSecond));
    const tracks = [];
    for (const [key, knownLayer] of layers) {
      const layer = (animation.layers ?? []).find((candidate) => layerKey(candidate) === key);
      const base = layer?.transform ?? knownLayer.transform ?? {};
      const samples = [];
      for (let frame = 0; frame < frameCount; frame += 1) {
        const block = layer?.blocks?.find((candidate) => frame >= candidate.from && frame <= candidate.through);
        const transform = { ...base, ...(block?.transform ?? {}) };
        samples.push({ frame, block, transform });
      }
      const binding = `../${layerNames.get(key)}`;
      tracks.push({ binding, property: 'frame', keys: samples.map(({ frame, block }) => ({ at: frame, value: block?.sourceFrame ?? 0 })) });
      tracks.push({ binding, property: 'alpha', keys: samples.map(({ frame, block }) => ({ at: frame, value: block ? 1 : 0 })) });
      tracks.push({ binding, property: 'position', keys: samples.map(({ frame, transform }) => ({ at: frame, value: transform.offset ?? [0, 0] })) });
      tracks.push({ binding, property: 'scale', keys: samples.map(({ frame, transform }) => ({ at: frame, value: transform.scale ?? [1, 1] })) });
      tracks.push({ binding, property: 'rotation', keys: samples.map(({ frame, transform }) => ({ at: frame, value: (transform.rotationDeg ?? 0) * Math.PI / 180 })) });
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

function visualContent(rootId, clips, manifest) {
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
      depthMode: 'world-sorted', depthBand: 'world-entities',
    },
  }));
  return { layers, layerNames, resources, nodes };
}

function sourceAttack(weapon, direction) {
  const direct = weapon.directionalAttacks?.[direction];
  if (direct) return { attack: direct, mirrorX: false, mirrorY: false };
  if (direction === 'left' && weapon.directionalAttacks?.right) return { attack: weapon.directionalAttacks.right, mirrorX: true, mirrorY: false };
  if (direction === 'up' && weapon.directionalAttacks?.down) return { attack: weapon.directionalAttacks.down, mirrorX: false, mirrorY: true };
  return undefined;
}

function orientation(direction) {
  if (direction === 'left') return { angle: Math.PI, rotation: 180, x: -1, y: 1, swap: false };
  if (direction === 'down') return { angle: Math.PI / 2, rotation: 90, x: -1, y: 1, swap: true };
  if (direction === 'up') return { angle: -Math.PI / 2, rotation: -90, x: 1, y: -1, swap: true };
  return { angle: 0, rotation: 0, x: 1, y: 1, swap: false };
}

function orientedPosition(shape, direction) {
  const value = orientation(direction);
  const x = shape.offsetX ?? 0;
  const y = shape.offsetY ?? 0;
  return value.swap ? [y * value.x, x * value.y] : [x * value.x, y * value.y];
}

function weaponScene(weapon, manifest) {
  const attacks = DIRECTIONS.map((direction) => [direction, sourceAttack(weapon, direction)]).filter(([, value]) => value);
  const clips = layeredClips([
    ['idle', weapon.animations?.idle],
    ...attacks.map(([direction, value]) => [`attack-${direction}`, value.attack.animation]),
  ]);
  const visual = visualContent(`weapon.${weapon.weaponId}`, clips, manifest);
  const animationId = `weapon.${weapon.weaponId}.animations`;
  const shapeResources = [];
  const shapeNodes = [];
  const attackPlans = {};
  for (const [direction, value] of attacks) {
    const attack = value.attack;
    const spans = attack.attackTrack?.hitboxSpans ?? [];
    attackPlans[direction] = {
      animationId: `attack-${direction}`,
      durationMs: attack.animation.durationSeconds * 1000,
      framesPerSecond: attack.animation.framesPerSecond,
      hitboxSpans: spans,
      events: attack.attackTrack?.events ?? [],
      mirrored: { x: value.mirrorX, y: value.mirrorY },
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
          shape: { resourceId }, position: orientedPosition(hitbox, direction),
          rotation: hitbox.shape === 'sector' ? 0 : orientation(direction).rotation,
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
      { id: 'attack-area', name: 'AttackArea', type: 'Area2D', parentId: 'root', order: visualCount, properties: { collisionLayer: 16, collisionMask: 8, monitoring: false, monitorable: false } },
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
    subresources: [...visual.resources, ...shapeResources, animationLibrary(animationId, clips, visual.layers, visual.layerNames)],
  };
}

function projectileAnimationLibrary(projectile) {
  const animations = {};
  for (const [id, animation] of Object.entries(projectile.animations ?? (projectile.animation ? { move: projectile.animation } : {}))) {
    animations[id] = {
      durationSeconds: animation.frames.length / animation.framesPerSecond,
      framesPerSecond: animation.framesPerSecond,
      loop: animation.loop,
      ...(animation.loopMode ? { loopMode: animation.loopMode } : {}),
      tracks: [{ binding: '../Visual', property: 'frame', keys: animation.frames.map((value, at) => ({ at, value })) }],
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
      { id: 'body', name: title(projectile.projectileId), type: 'CharacterBody2D', parentId: null, order: 0, properties: { collisionLayer: 16, collisionMask: 8, position: [0, 0], velocity: [0, 0] } },
      { id: 'body-shape', name: 'BodyShape', type: 'CollisionShape2D', parentId: 'body', order: 0, properties: { shape: { resourceId: shape.resourceId }, position: [projectile.body.centerOffsetX, projectile.body.centerOffsetY] } },
      { id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'body', order: 1, properties: { texture: { resourceId: texture.resourceId }, frame: 0, position: projectile.visual?.sourceOffset ?? [0, 0], depthMode: 'world-sorted', depthBand: 'world-entities' } },
      { id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'body', order: 2, properties: { library: { resourceId: animations.resourceId }, domain: 'physics', autoplay: 'move' } },
      { id: 'script', name: 'ProjectileScript', type: 'ScriptNode', scriptId: 'game.projectile', parentId: 'body', order: 3, properties: {
        projectileId: projectile.projectileId, body: { nodeId: 'body' }, visual: { nodeId: 'visual' }, animation: { nodeId: 'animation' },
        defaultSpeed: projectile.movement.defaultSpeed, lifetimeMs: projectile.movement.lifetimeMs, rotateToVelocity: projectile.movement.rotateToVelocity,
      } },
    ],
    instances: [], subresources: [texture, shape, animations],
  };
}

function sourceEffect(effect, direction) {
  if (effect.directions?.[direction]) return effect.directions[direction];
  if (direction === 'left' && effect.mirrorLeftFromRight && effect.directions?.right) return effect.directions.right;
  if (direction === 'up' && effect.mirrorUpFromDown && effect.directions?.down) return effect.directions.down;
  return effect.default ?? effect.directions?.right ?? effect.directions?.down;
}

function effectScene(effect, manifest) {
  const clips = layeredClips(DIRECTIONS.map((direction) => [direction, sourceEffect(effect, direction)]));
  const visual = visualContent(`effect.${effect.effectId}`, clips, manifest);
  const animationId = `effect.${effect.effectId}.animations`;
  const lifetimeMs = Math.max(...clips.map(({ animation }) => animation.durationSeconds * 1000), 0);
  const visualCount = visual.nodes.length;
  return {
    version: 1, sceneId: `effect.${effect.effectId}`, rootNodeId: 'root',
    nodes: [
      { id: 'root', name: title(effect.effectId), type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } },
      ...visual.nodes,
      { id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'root', order: visualCount, properties: { library: { resourceId: animationId }, domain: 'physics', autoplay: 'right' } },
      { id: 'script', name: 'EffectScript', type: 'ScriptNode', scriptId: 'game.effect', parentId: 'root', order: visualCount + 1, properties: { effectId: effect.effectId, animation: { nodeId: 'animation' }, lifetimeMs } },
    ],
    instances: [], subresources: [...visual.resources, animationLibrary(animationId, clips, visual.layers, visual.layerNames)],
  };
}

async function manifest(readSource) { return readJson(readSource, 'asset/assets.json'); }

export const weaponSceneAdapter = {
  async convert({ units, readSource }) {
    const assets = await manifest(readSource);
    const outputs = [];
    for (const unit of units) {
      requireUnit(unit, WEAPON_KEYS);
      const weapon = await readJson(readSource, unit.oldSourcePath);
      outputs.push(convertedOutput(unit, `weapons/${weapon.weaponId}.scene.json`, weaponScene(weapon, assets), ['$']));
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
    const outputs = [];
    for (const unit of units) {
      requireUnit(unit, EFFECT_KEYS);
      const effect = await readJson(readSource, unit.oldSourcePath);
      outputs.push(convertedOutput(unit, `effects/${effect.effectId}.scene.json`, effectScene(effect, assets), ['$']));
    }
    return outputs;
  },
};
