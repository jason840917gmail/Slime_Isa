import type Phaser from 'phaser';

import { sceneId as toSceneId } from '../../../../src/game/content/scenes/identifiers';
import type { PhaserUniversalSceneRuntime } from '../../../../src/game/infrastructure/scenes/PhaserUniversalSceneRuntime';
import { Area2DNode } from '../../../../src/game/infrastructure/phaser-nodes/Area2DNode';
import { CharacterBody2DNode } from '../../../../src/game/infrastructure/phaser-nodes/CharacterBody2DNode';
import { PhysicsBody2DNode } from '../../../../src/game/infrastructure/phaser-nodes/PhysicsBody2DNode';
import { TileMapLayer2DNode } from '../../../../src/game/infrastructure/phaser-nodes/TileMapLayer2DNode';
import type { Node } from '../../../../src/game/runtime/scene/Node';
import { ScriptNode } from '../../../../src/game/runtime/scene/scripts/ScriptNode';

/**
 * Behaviour probe for the REAL production world (baseline mode): mounts real
 * authored scenes into the running universal runtime and reads real Arcade
 * body rectangles, so blocking tests exercise production layer/mask data.
 */
export interface ProbeRect { readonly x: number; readonly y: number; readonly width: number; readonly height: number }

export interface PhysicsProbeApi {
  worldBounds(): ProbeRect;
  playerBodyRect(): ProbeRect;
  /** Queues a player teleport so its body centre lands on (x, y) at the next physics step. */
  placePlayerBody(x: number, y: number): void;
  /** Top-left corners of free regions: no Arcade body overlaps them and they stay `margin` inside the world. */
  findClearRegion(width: number, height: number, margin: number, skip?: number): ProbeRect | null;
  /** Arcade bodies (other than the player and the ignored scene mounts) overlapping `rect`. */
  bodiesIn(rect: ProbeRect, ignoreMounts?: readonly string[]): number;
  mountScene(sceneId: string, x: number, y: number): string;
  mountRootBodyRect(mountId: string): ProbeRect;
  /** Queues a teleport of the mount's root CharacterBody2D so its body centre lands on (x, y). */
  placeMountBody(mountId: string, x: number, y: number): void;
  collidableTileRects(): readonly ProbeRect[];
  /** Stops the mount's scripts' physics processing and drives its root body at a constant velocity every physics step. */
  driveMountBody(mountId: string, velocityX: number, velocityY: number): void;
  mountBodyLayer(mountId: string): { readonly collisionLayer: number; readonly collisionMask: number };
  launchArrow(x: number, y: number, directionX: number, directionY: number, speed: number): void;
  /** Largest projectile body right edge seen after each physics step since the last launch, and whether a projectile is still live. */
  arrowTrace(): { readonly maxRight: number; readonly live: number; readonly steps: number };
}

interface UniversalWorldLike {
  readonly runtime: PhaserUniversalSceneRuntime;
  readonly managedProjectileCount: number;
  readonly managedPlayer: { teleport(position: Readonly<{ x: number; y: number }>): void; getPosition(): Readonly<{ x: number; y: number }> };
  spawnEnemyProjectile(request: {
    sourceNodeId: string; position: { x: number; y: number }; direction: { x: number; y: number };
    speed: number; damage: number; knockbackStrength: number; projectileId: string;
  }): boolean;
}

function rectOf(body: Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody): ProbeRect {
  return { x: body.position.x, y: body.position.y, width: body.width, height: body.height };
}

function descendantsOf<T>(root: Node, type: abstract new (...args: never[]) => T): T[] {
  const found: T[] = [];
  const visit = (node: Node): void => {
    if (node instanceof type) found.push(node);
    for (const child of node.get_children()) visit(child);
  };
  visit(root);
  return found;
}

export function createPhysicsProbe(getGame: () => Phaser.Game | undefined): PhysicsProbeApi {
  const mounts = new Map<string, { readonly root: Node; readonly mount: Node }>();
  let arrow = { maxRight: Number.NEGATIVE_INFINITY, steps: 0 };

  const scene = (): Phaser.Scene & { readonly universalWorld?: UniversalWorldLike } => {
    const game = getGame();
    if (!game) throw new Error('Production game is unavailable');
    return game.scene.getScene('world') as Phaser.Scene & { readonly universalWorld?: UniversalWorldLike };
  };
  const universal = (): UniversalWorldLike => {
    const world = scene().universalWorld;
    if (!world) throw new Error('Managed universal world is unavailable');
    return world;
  };
  const playerBodyNode = (): CharacterBody2DNode => {
    const body = universal().runtime.tree.root ? descendantsOf(universal().runtime.tree.root!, CharacterBody2DNode)
      .find((node) => node.runtimeId.startsWith('managed-player')) : undefined;
    if (!body) throw new Error('Managed player body is unavailable');
    return body;
  };
  const rootBody = (mountId: string): PhysicsBody2DNode => {
    const entry = mounts.get(mountId);
    if (!entry) throw new Error(`Unknown probe mount '${mountId}'`);
    const body = descendantsOf(entry.root, PhysicsBody2DNode)[0];
    if (!body) throw new Error(`Probe mount '${mountId}' has no physics body`);
    return body;
  };
  const bodyOf = (node: PhysicsBody2DNode): Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody => {
    const body = node.physicsObject.body as Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody | null;
    if (!body) throw new Error(`Physics body '${node.runtimeId}' has no Arcade body`);
    return body;
  };
  type AnyBody = Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody;
  // Area2D sensors keep broadphase-only static bodies; they never block, so they are not obstacles.
  const isSolid = (): ((body: AnyBody) => boolean) => {
    const root = universal().runtime.tree.root;
    const areaNames = new Set(root ? descendantsOf(root, Area2DNode).map((area) => area.runtimeId as string) : []);
    return (body) => body.enable && !areaNames.has(body.gameObject?.name ?? '');
  };
  const overlapping = (rect: ProbeRect): readonly AnyBody[] => (
    scene().physics.overlapRect(rect.x, rect.y, rect.width, rect.height, true, true) as AnyBody[]
  ).filter(isSolid());

  return {
    worldBounds() {
      const bounds = scene().physics.world.bounds;
      return { x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height };
    },
    playerBodyRect() { return rectOf(bodyOf(playerBodyNode())); },
    placePlayerBody(x, y) {
      const node = playerBodyNode();
      const rect = rectOf(bodyOf(node));
      const anchor = node.get_global_transform().position;
      const offset = { x: rect.x + rect.width / 2 - anchor.x, y: rect.y + rect.height / 2 - anchor.y };
      // Applied at the next physics step; callers poll playerBodyRect().
      universal().managedPlayer.teleport({ x: x - offset.x, y: y - offset.y });
    },
    findClearRegion(width, height, margin, skip = 0) {
      // One pass over every body into a coarse occupancy grid, then a
      // summed-area scan: cheap enough not to stall the running game loop.
      const world = scene().physics.world;
      const bounds = world.bounds;
      const cell = 32;
      const columns = Math.ceil(bounds.width / cell);
      const rows = Math.ceil(bounds.height / cell);
      const occupied = new Uint8Array(columns * rows);
      const solid = isSolid();
      const bodies = [...world.bodies.entries, ...world.staticBodies.entries] as AnyBody[];
      for (const body of bodies) {
        if (!solid(body)) continue;
        const left = Math.max(0, Math.floor((body.position.x - bounds.x) / cell));
        const right = Math.min(columns - 1, Math.floor((body.position.x + body.width - bounds.x) / cell));
        const top = Math.max(0, Math.floor((body.position.y - bounds.y) / cell));
        const bottom = Math.min(rows - 1, Math.floor((body.position.y + body.height - bounds.y) / cell));
        for (let row = top; row <= bottom; row += 1) for (let column = left; column <= right; column += 1) occupied[row * columns + column] = 1;
      }
      const sums = new Uint32Array((columns + 1) * (rows + 1));
      for (let row = 0; row < rows; row += 1) {
        for (let column = 0; column < columns; column += 1) {
          sums[(row + 1) * (columns + 1) + column + 1] = occupied[row * columns + column]
            + sums[row * (columns + 1) + column + 1] + sums[(row + 1) * (columns + 1) + column] - sums[row * (columns + 1) + column];
        }
      }
      const spanX = Math.ceil(width / cell);
      const spanY = Math.ceil(height / cell);
      const first = Math.ceil(margin / cell);
      let skipped = 0;
      for (let row = first; row + spanY <= rows - first; row += 1) {
        for (let column = first; column + spanX <= columns - first; column += 1) {
          const at = (r: number, c: number): number => sums[r * (columns + 1) + c];
          const count = at(row + spanY, column + spanX) - at(row, column + spanX) - at(row + spanY, column) + at(row, column);
          if (count !== 0) continue;
          if (skipped < skip) { skipped += 1; column += spanX; continue; }
          return { x: bounds.x + column * cell, y: bounds.y + row * cell, width, height };
        }
      }
      return null;
    },
    bodiesIn(rect, ignoreMounts = []) {
      const ignored = new Set<object>([bodyOf(playerBodyNode())]);
      for (const mountId of ignoreMounts) for (const node of descendantsOf(mounts.get(mountId)?.root ?? universal().runtime.tree.root!, PhysicsBody2DNode)) ignored.add(bodyOf(node));
      return overlapping(rect).filter((body) => !ignored.has(body)).length;
    },
    mountScene(id, x, y) {
      const mounted = universal().runtime.mountScene(toSceneId(id), { position: { x, y } });
      mounts.set(mounted.runtimeNamespace, { root: mounted.root, mount: mounted.mount });
      return mounted.runtimeNamespace;
    },
    mountRootBodyRect(mountId) { return rectOf(bodyOf(rootBody(mountId))); },
    placeMountBody(mountId, x, y) {
      const node = rootBody(mountId);
      if (!(node instanceof CharacterBody2DNode)) throw new Error(`Probe mount '${mountId}' is not a CharacterBody2D`);
      const rect = rectOf(bodyOf(node));
      const anchor = node.get_global_transform().position;
      node.queue_teleport({ x: x - (rect.x + rect.width / 2 - anchor.x), y: y - (rect.y + rect.height / 2 - anchor.y) });
    },
    collidableTileRects() {
      const root = universal().runtime.tree.root;
      if (!root) return [];
      return descendantsOf(root, TileMapLayer2DNode).flatMap((layer) => layer.collisionBodyBounds());
    },
    driveMountBody(mountId, velocityX, velocityY) {
      const entry = mounts.get(mountId);
      if (!entry) throw new Error(`Unknown probe mount '${mountId}'`);
      for (const script of descendantsOf(entry.root, ScriptNode)) script.set_physics_process(false);
      const body = rootBody(mountId);
      if (!(body instanceof CharacterBody2DNode)) throw new Error(`Probe mount '${mountId}' is not a CharacterBody2D`);
      const drive = (): void => { if (body.is_inside_tree()) body.velocity = { x: velocityX, y: velocityY }; };
      drive();
      body.lifetimeDisposables.add(universal().runtime.context.registerCallback('physics-animation', drive));
    },
    mountBodyLayer(mountId) {
      const body = rootBody(mountId);
      return { collisionLayer: body.collisionLayer, collisionMask: body.collisionMask };
    },
    launchArrow(x, y, directionX, directionY, speed) {
      arrow = { maxRight: Number.NEGATIVE_INFINITY, steps: 0 };
      const world = universal();
      const launched = world.spawnEnemyProjectile({
        sourceNodeId: 'scene-browser-physics-probe', position: { x, y }, direction: { x: directionX, y: directionY },
        speed, damage: 0, knockbackStrength: 0, projectileId: 'worm-arrow',
      });
      if (!launched) throw new Error('worm-arrow projectile did not launch');
      const projectiles = (world as unknown as { readonly projectiles: ReadonlyMap<number, { readonly mount: { readonly root: Node } }> }).projectiles;
      const newest = [...projectiles.values()].at(-1);
      const body = newest ? descendantsOf(newest.mount.root, CharacterBody2DNode)[0] : undefined;
      if (!body) throw new Error('worm-arrow projectile has no CharacterBody2D');
      const unregister = world.runtime.context.registerCallback('post-physics', () => {
        if (!body.is_inside_tree()) { unregister(); return; }
        const arcade = body.physicsObject.body as Phaser.Physics.Arcade.Body | null;
        if (!arcade) return;
        arrow.steps += 1;
        arrow.maxRight = Math.max(arrow.maxRight, arcade.position.x + arcade.width);
      });
    },
    arrowTrace() { return { maxRight: arrow.maxRight, live: universal().managedProjectileCount, steps: arrow.steps }; },
  };
}

declare global {
  interface Window {
    physicsProbe: PhysicsProbeApi;
  }
}
