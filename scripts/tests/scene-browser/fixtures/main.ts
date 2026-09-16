import Phaser from 'phaser';

import { Camera2DNode } from '../../../../src/game/infrastructure/phaser-nodes/Camera2DNode';
import { Area2DNode } from '../../../../src/game/infrastructure/phaser-nodes/Area2DNode';
import { CharacterBody2DNode } from '../../../../src/game/infrastructure/phaser-nodes/CharacterBody2DNode';
import { CollisionShape2DNode } from '../../../../src/game/infrastructure/phaser-nodes/CollisionShape2DNode';
import { Sprite2DNode } from '../../../../src/game/infrastructure/phaser-nodes/Sprite2DNode';
import { StaticBody2DNode } from '../../../../src/game/infrastructure/phaser-nodes/StaticBody2DNode';
import { AudioStreamPlayerNode, type AudioUnlockService } from '../../../../src/game/infrastructure/phaser-nodes/AudioStreamPlayerNode';
import { PhaserNodeContext } from '../../../../src/game/infrastructure/scenes/PhaserNodeContext';
import { PhaserSceneTreeHost } from '../../../../src/game/infrastructure/scenes/PhaserSceneTreeHost';
import { authoredNodeId, resourceId, runtimeNodeId } from '../../../../src/game/content/scenes/identifiers';
import { Node } from '../../../../src/game/runtime/scene/Node';
import { ControlNode } from '../../../../src/game/runtime/scene/ui/ControlNode';
import { InputRouter } from '../../../../src/game/runtime/scene/input/InputRouter';
import { AnimationBinding } from '../../../../src/game/runtime/scene/animation/AnimationBinding';
import { AnimationPlayerNode } from '../../../../src/game/runtime/scene/animation/AnimationPlayerNode';
import { ScriptNode } from '../../../../src/game/runtime/scene/scripts/ScriptNode';
import type { PhysicsContact } from '../../../../src/game/runtime/scene/physics/PhysicsContact';
import { SceneTree } from '../../../../src/game/runtime/scene/SceneTree';
import { getEnemyConfig } from '../../../../src/game/enemies/library/EnemyTypes';

type FixtureSnapshot = {
  readonly mode: 'harness' | 'baseline';
  readonly stepCount: number;
  readonly controlCount: number;
  readonly gameObjectCount: number;
  readonly bodyCount: number;
  readonly canvasCount: number;
  readonly cameraCount: number;
  readonly managedPresentationCount: number;
  readonly bodyX?: number;
  readonly spriteX?: number;
  readonly spriteY?: number;
  readonly spriteActive?: boolean;
  readonly managedContactParticipantCount?: number;
  readonly managedBlockingColliderCount?: number;
  readonly characterX?: number;
  readonly blockingContactCount?: number;
  readonly sensorContactCount?: number;
  readonly sensorEnterCount?: number;
  readonly sensorExitCount?: number;
  readonly gameplayInputCount?: number;
  readonly audioUnlocked?: boolean;
  readonly audioObjectCount?: number;
  readonly audioIsPlaying?: boolean;
  readonly destroyed: boolean;
  readonly loadedAtMs?: number;
  readonly initializationError?: string;
  readonly managedOrdinaryEnemyCount?: number;
  readonly managedBossCount?: number;
  readonly managedCampCount?: number;
  readonly managedLiveCampCount?: number;
  readonly managedChestCount?: number;
  readonly managedNpcCount?: number;
  readonly managedPlayerCount?: number;
  readonly managedProjectileCount?: number;
  readonly managedProjectileSpawnCount?: number;
  readonly managedEffectCount?: number;
  readonly managedWeaponId?: string | null;
  readonly managedWeaponAttacking?: boolean;
  readonly usingLegacyWeaponVisual?: boolean;
  readonly playerHp?: number;
  readonly legacyEnemyCount?: number;
  readonly legacyBossCount?: number;
  readonly legacyNpcCount?: number;
  readonly legacyPlayerX?: number;
  readonly managedPlayerX?: number;
  readonly hasLegacyChestController?: boolean;
  readonly universalRuntimePaused?: boolean;
};

type FixtureApi = {
  ready(): boolean;
  step(deltaSeconds?: number): void;
  moveSprite(x: number, y: number): void;
  detachSprite(): void;
  attachSprite(): void;
  setWallEnabled(enabled: boolean): void;
  freeWall(): void;
  detachAudio(): void;
  disableProductionEnemySpawning(): void;
  teleportProductionPlayer(x: number, y: number): void;
  spawnManagedEnemy(type: 'slime-spider' | 'worm-archer' | 'worm-brawler' | 'worm-swordsman', x: number, y: number): boolean;
  spawnManagedEffect(effectId: string, direction: 'right' | 'left' | 'up' | 'down', x: number, y: number): boolean;
  equipProductionWeapon(weaponId: string): boolean;
  attackWithProductionWeapon(): boolean;
  snapshot(): FixtureSnapshot;
  destroy(): void;
};

declare global {
  interface Window {
    sceneFixture: FixtureApi;
  }
}

const params = new URLSearchParams(window.location.search);
const mode = params.get('mode') === 'baseline' ? 'baseline' : 'harness';
const control = document.querySelector<HTMLButtonElement>('#fixture-control');
const app = document.querySelector<HTMLDivElement>('#app');
if (!control || !app) throw new Error('Scene browser fixture mount is incomplete');

let controlCount = 0;
let gameplayInputCount = 0;
let stepCount = 0;
let destroyed = false;
let loadedAtMs: number | undefined;
let initializationError: string | undefined;
const navigationStart = performance.now();
const consumeControl = (event: MouseEvent): void => {
  event.preventDefault();
  event.stopPropagation();
  controlCount += 1;
};
if (mode === 'baseline') control.addEventListener('click', consumeControl);

function countBodies(game: Phaser.Game | undefined): number {
  if (!game) return 0;
  return game.scene.getScenes(true).reduce((total, scene) => {
    const world = scene.physics?.world;
    if (!world) return total;
    return total + world.bodies.entries.length + world.staticBodies.entries.length;
  }, 0);
}

function countGameObjects(game: Phaser.Game | undefined): number {
  if (!game) return 0;
  return game.scene.getScenes(true).reduce((total, scene) => total + scene.children.list.length, 0);
}

let game: Phaser.Game | undefined;
let advanceHarness: ((deltaSeconds: number) => void) | undefined;
let moveHarnessSprite: ((x: number, y: number) => void) | undefined;
let detachHarnessSprite: (() => void) | undefined;
let attachHarnessSprite: (() => void) | undefined;
let setHarnessWallEnabled: ((enabled: boolean) => void) | undefined;
let freeHarnessWall: (() => void) | undefined;
let detachHarnessAudio: (() => void) | undefined;
let harnessSnapshot: (() => Partial<FixtureSnapshot>) | undefined;

if (mode === 'harness') {
  class PointerAudioUnlock implements AudioUnlockService {
    private unlocked = false;
    private readonly callbacks = new Set<() => void>();
    private readonly handlePointer = (): void => {
      if (this.unlocked) return;
      this.unlocked = true;
      for (const callback of [...this.callbacks]) callback();
      this.callbacks.clear();
    };

    constructor() { document.addEventListener('pointerdown', this.handlePointer, { capture: true }); }
    isUnlocked(): boolean { return this.unlocked; }
    onUnlocked(callback: () => void): () => void { this.callbacks.add(callback); return () => this.callbacks.delete(callback); }
    destroy(): void { document.removeEventListener('pointerdown', this.handlePointer, { capture: true }); this.callbacks.clear(); }
  }

  class TrackingAreaNode extends Area2DNode {
    enteredCount = 0;
    exitedCount = 0;

    override contactEntered(contact: PhysicsContact): void { super.contactEntered(contact); this.enteredCount += 1; }
    override contactExited(contact: PhysicsContact): void { super.contactExited(contact); this.exitedCount += 1; }
  }

  class BrowserHarnessScene extends Phaser.Scene {
    private body?: Phaser.Physics.Arcade.Image;
    private context?: PhaserNodeContext;
    private tree?: SceneTree;
    private host?: PhaserSceneTreeHost;
    private root?: Node;
    private spriteNode?: Sprite2DNode;
    private character?: CharacterBody2DNode;
    private wall?: StaticBody2DNode;
    private sensor?: TrackingAreaNode;
    private audio?: AudioStreamPlayerNode;
    private audioUnlock?: PointerAudioUnlock;
    private inputRouter?: InputRouter;

    constructor() {
      super('browser-harness');
    }

    create(): void {
      const texture = this.textures.createCanvas('browser-harness-dot', 8, 8);
      texture?.context.fillRect(0, 0, 8, 8);
      texture?.refresh();
      this.body = this.physics.add.image(16, 16, 'browser-harness-dot');
      this.body.setVelocityX(60);
      const textureId = resourceId('texture.browser-dot');
      const bodyShapeId = resourceId('shape.browser-body');
      const sensorShapeId = resourceId('shape.browser-sensor');
      this.context = new PhaserNodeContext(this, new Map([
        [textureId, { version: 1, resourceId: textureId, kind: 'texture', assetId: 'browser-harness-dot' }],
        [bodyShapeId, { version: 1, resourceId: bodyShapeId, kind: 'collision-shape', value: { shape: 'rectangle', width: 12, height: 12 } }],
        [sensorShapeId, { version: 1, resourceId: sensorShapeId, kind: 'collision-shape', value: { shape: 'circle', radius: 10 } }],
      ]));
      const audioContext = (this.sound as unknown as { readonly context?: AudioContext }).context;
      if (audioContext) this.cache.audio.add('browser-silent-loop', audioContext.createBuffer(1, audioContext.sampleRate, audioContext.sampleRate));
      this.tree = new SceneTree();
      this.host = new PhaserSceneTreeHost({ tree: this.tree, backend: this.context });
      this.inputRouter = new InputRouter({ sink: this.host, isPaused: () => this.tree?.paused ?? false });
      this.audioUnlock = new PointerAudioUnlock();
      this.root = new Node({ runtimeId: runtimeNodeId('browser', [], authoredNodeId('root')), name: 'Root' });
      this.root.add_child(new ControlNode({
        runtimeId: runtimeNodeId('browser', [], authoredNodeId('control')), name: 'FixtureControl', inputRouter: this.inputRouter, focused: true,
        onInput: (event) => { if (event.type !== 'pointer-down') return false; controlCount += 1; return true; },
      }));
      class GameplayInputNode extends Node {
        constructor() { super({ runtimeId: runtimeNodeId('browser', [], authoredNodeId('gameplay-input')), name: 'GameplayInput' }); this.set_process_unhandled_input(true); }
        override _unhandled_input(event: { readonly type?: string }): void { if (event.type === 'pointer-down') gameplayInputCount += 1; }
      }
      this.root.add_child(new GameplayInputNode());
      this.spriteNode = new Sprite2DNode({
        runtimeId: runtimeNodeId('browser', [], authoredNodeId('sprite')), name: 'ManagedSprite', context: this.context, texture: textureId,
        position: { x: 40, y: 30 }, depthMode: 'explicit', depth: 10,
      });
      const camera = new Camera2DNode({ runtimeId: runtimeNodeId('browser', [], authoredNodeId('camera')), name: 'ManagedCamera', context: this.context, position: { x: 80, y: 60 } });
      this.root.add_child(this.spriteNode);
      this.root.add_child(new AnimationPlayerNode({
        runtimeId: runtimeNodeId('browser', [], authoredNodeId('animation')), name: 'ManagedAnimation', domain: 'render', advanceSource: this.context, autoplay: 'drift',
        animations: { drift: { durationSeconds: 2, framesPerSecond: 1, loop: true, tracks: [{ binding: 'visual', property: 'position', keys: [{ at: 0, value: [40, 30] }, { at: 1, value: [41, 30] }] }] } },
        resolveBinding: (_player, binding, property) => {
          if (binding !== 'visual' || property !== 'position' || !this.spriteNode) throw new Error(`Unknown browser animation binding '${binding}.${property}'`);
          return new AnimationBinding(this.spriteNode, property, { key: 'position', label: 'Position', value: { kind: 'vector2' }, serialized: true, inspector: 'vector2', animation: { interpolation: 'numeric', domains: ['render'] }, overridable: true });
        },
      }));
      this.root.add_child(new ScriptNode({ runtimeId: runtimeNodeId('browser', [], authoredNodeId('script')), name: 'ManagedScript', scriptId: 'fixture.browser' }));
      this.root.add_child(camera);
      this.character = new CharacterBody2DNode({
        runtimeId: runtimeNodeId('browser', [], authoredNodeId('character')), name: 'ManagedCharacter', context: this.context,
        position: { x: 20, y: 90 }, velocity: { x: 90, y: 0 }, collisionLayer: 1, collisionMask: 2,
      });
      this.character.add_child(new CollisionShape2DNode({
        runtimeId: runtimeNodeId('browser', [], authoredNodeId('character-shape')), name: 'CharacterShape', context: this.context, shape: bodyShapeId,
      }));
      this.sensor = new TrackingAreaNode({
        runtimeId: runtimeNodeId('browser', [], authoredNodeId('sensor')), name: 'ManagedSensor', context: this.context,
        collisionLayer: 4, collisionMask: 2,
      });
      this.sensor.add_child(new CollisionShape2DNode({
        runtimeId: runtimeNodeId('browser', [], authoredNodeId('sensor-shape')), name: 'SensorShape', context: this.context, shape: sensorShapeId,
      }));
      this.character.add_child(this.sensor);
      this.wall = new StaticBody2DNode({
        runtimeId: runtimeNodeId('browser', [], authoredNodeId('wall')), name: 'ManagedWall', context: this.context,
        position: { x: 60, y: 90 }, collisionLayer: 2, collisionMask: 1,
      });
      this.wall.add_child(new CollisionShape2DNode({
        runtimeId: runtimeNodeId('browser', [], authoredNodeId('wall-shape')), name: 'WallShape', context: this.context, shape: bodyShapeId,
      }));
      this.root.add_child(this.character);
      this.root.add_child(this.wall);
      if (audioContext) {
        this.audio = new AudioStreamPlayerNode({
          runtimeId: runtimeNodeId('browser', [], authoredNodeId('audio')), name: 'ManagedAudio', scene: this,
          assetId: 'browser-silent-loop', loop: true, autoplay: true, unlock: this.audioUnlock,
        });
        this.root.add_child(this.audio);
      }
      this.tree.setRoot(this.root);
      const cleanup = (): void => { this.host?.shutdown(); this.inputRouter?.destroy(); this.audioUnlock?.destroy(); };
      this.events.once(Phaser.Scenes.Events.SHUTDOWN, cleanup);
      this.events.once(Phaser.Scenes.Events.DESTROY, cleanup);
      this.game.loop.sleep();
    }

    advance(deltaSeconds: number): void {
      this.host?.advanceFrame(deltaSeconds);
      stepCount = this.context?.physicsStepCount ?? stepCount;
    }

    moveSprite(x: number, y: number): void { if (this.spriteNode) this.spriteNode.position = { x, y }; }
    detachSprite(): void { if (this.root && this.spriteNode?.get_parent() === this.root) { this.root.remove_child(this.spriteNode); this.tree?.flushMutations(); } }
    attachSprite(): void { if (this.root && this.spriteNode && !this.spriteNode.get_parent()) { this.root.add_child(this.spriteNode); this.tree?.flushMutations(); } }
    setWallEnabled(enabled: boolean): void { if (this.wall) this.wall.collisionEnabled = enabled; }
    freeWall(): void { this.wall?.queue_free(); this.tree?.flushMutations(); }
    detachAudio(): void { if (this.root && this.audio?.get_parent() === this.root) { this.root.remove_child(this.audio); this.tree?.flushMutations(); } }
    managedSnapshot(): Partial<FixtureSnapshot> {
      const display = this.children.list.find((entry) => entry instanceof Phaser.GameObjects.Sprite) as Phaser.GameObjects.Sprite | undefined;
      return {
        bodyX: (this.body?.body as Phaser.Physics.Arcade.Body | undefined)?.position.x,
        managedPresentationCount: this.context?.managedPresentationCount ?? 0,
        spriteX: display?.x,
        spriteY: display?.y,
        spriteActive: this.spriteNode?.phaserObjectActive ?? false,
        cameraCount: this.cameras.cameras.length,
        managedContactParticipantCount: this.context?.managedContactParticipantCount ?? 0,
        managedBlockingColliderCount: this.context?.managedBlockingColliderCount ?? 0,
        characterX: this.character?.position.x,
        blockingContactCount: this.character?.blockingContacts.length ?? 0,
        sensorContactCount: this.sensor?.currentContacts.length ?? 0,
        sensorEnterCount: this.sensor?.enteredCount ?? 0,
        sensorExitCount: this.sensor?.exitedCount ?? 0,
        gameplayInputCount,
        audioUnlocked: this.audioUnlock?.isUnlocked() ?? false,
        audioObjectCount: (this.sound as unknown as { readonly sounds?: readonly unknown[] }).sounds?.length ?? 0,
        audioIsPlaying: Boolean((this.sound as unknown as { readonly sounds?: readonly { readonly isPlaying?: boolean }[] }).sounds?.some((sound) => sound.isPlaying)),
      };
    }
  }

  game = new Phaser.Game({
    type: Phaser.CANVAS,
    parent: app,
    width: 160,
    height: 120,
    banner: false,
    audio: { noAudio: false },
    physics: {
      default: 'arcade',
      arcade: { gravity: { x: 0, y: 0 }, fixedStep: false },
    },
    scene: [BrowserHarnessScene],
  });
  advanceHarness = (deltaSeconds) => {
    const scene = game?.scene.getScene('browser-harness') as BrowserHarnessScene | undefined;
    if (!scene) throw new Error('Browser harness scene is unavailable');
    scene.advance(deltaSeconds);
  };
  moveHarnessSprite = (x, y) => (game?.scene.getScene('browser-harness') as BrowserHarnessScene).moveSprite(x, y);
  detachHarnessSprite = () => (game?.scene.getScene('browser-harness') as BrowserHarnessScene).detachSprite();
  attachHarnessSprite = () => (game?.scene.getScene('browser-harness') as BrowserHarnessScene).attachSprite();
  setHarnessWallEnabled = (enabled) => (game?.scene.getScene('browser-harness') as BrowserHarnessScene).setWallEnabled(enabled);
  freeHarnessWall = () => (game?.scene.getScene('browser-harness') as BrowserHarnessScene).freeWall();
  detachHarnessAudio = () => (game?.scene.getScene('browser-harness') as BrowserHarnessScene).detachAudio();
  harnessSnapshot = () => (game?.scene.getScene('browser-harness') as BrowserHarnessScene).managedSnapshot();
} else {
  try {
    const productionConfigPath = '/src/game/' + 'config.ts';
    const { createGame } = await import(/* @vite-ignore */ productionConfigPath) as {
      createGame(container: HTMLDivElement): Promise<Phaser.Game | undefined>;
    };
    game = await createGame(app);
  } catch (error) {
    initializationError = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
  }
}

const api: FixtureApi = {
  ready() {
    if (!game || destroyed) return false;
    const ready = mode === 'harness'
      ? game.scene.isActive('browser-harness')
      : game.scene.isActive('world');
    if (ready && loadedAtMs === undefined) loadedAtMs = performance.now() - navigationStart;
    return ready;
  },
  step(deltaSeconds = 1 / 60) {
    if (!game || destroyed || !advanceHarness) throw new Error('Controlled stepping is only available in harness mode');
    advanceHarness(deltaSeconds);
  },
  moveSprite(x, y) {
    if (!moveHarnessSprite) throw new Error('Managed sprite is only available in harness mode');
    moveHarnessSprite(x, y);
  },
  detachSprite() {
    if (!detachHarnessSprite) throw new Error('Managed sprite is only available in harness mode');
    detachHarnessSprite();
  },
  attachSprite() {
    if (!attachHarnessSprite) throw new Error('Managed sprite is only available in harness mode');
    attachHarnessSprite();
  },
  setWallEnabled(enabled) {
    if (!setHarnessWallEnabled) throw new Error('Managed wall is only available in harness mode');
    setHarnessWallEnabled(enabled);
  },
  freeWall() {
    if (!freeHarnessWall) throw new Error('Managed wall is only available in harness mode');
    freeHarnessWall();
  },
  detachAudio() {
    if (!detachHarnessAudio) throw new Error('Managed audio is only available in harness mode');
    detachHarnessAudio();
  },
  disableProductionEnemySpawning() {
    if (!game || mode !== 'baseline') throw new Error('Production enemy spawning is only available in baseline mode');
    const world = game.scene.getScene('world') as unknown as {
      readonly combatController?: {
        spawner?: { destroy(): void };
      };
    };
    world.combatController?.spawner?.destroy();
    if (world.combatController) world.combatController.spawner = undefined;
  },
  teleportProductionPlayer(x, y) {
    if (!game || mode !== 'baseline') throw new Error('Production player is only available in baseline mode');
    const world = game.scene.getScene('world') as unknown as {
      readonly player?: Phaser.Physics.Arcade.Sprite;
      readonly universalWorld?: { readonly managedPlayer: { teleport(position: Readonly<{ x: number; y: number }>): void } };
    };
    if (!world.player) throw new Error('Production player is unavailable');
    world.universalWorld?.managedPlayer.teleport({ x, y });
    world.player.setPosition(x, y);
    (world.player.body as Phaser.Physics.Arcade.Body).reset(x, y);
    world.player.setVelocity(0, 0);
  },
  spawnManagedEnemy(type, x, y) {
    if (!game || mode !== 'baseline') throw new Error('Production enemy spawning is only available in baseline mode');
    const world = game.scene.getScene('world') as unknown as {
      readonly universalWorld?: {
        createManagedEnemy(request: { x: number; y: number; config: ReturnType<typeof getEnemyConfig> }): unknown;
      };
    };
    return world.universalWorld?.createManagedEnemy({ x, y, config: getEnemyConfig(type) }) !== undefined;
  },
  spawnManagedEffect(effectId, direction, x, y) {
    if (!game || mode !== 'baseline') throw new Error('Production effects are only available in baseline mode');
    const world = game.scene.getScene('world') as unknown as {
      readonly universalWorld?: {
        spawnEffect(request: { effectId: string; direction: 'right' | 'left' | 'up' | 'down'; x: number; y: number; depth: number }): boolean;
      };
    };
    return world.universalWorld?.spawnEffect({ effectId, direction, x, y, depth: 0 }) ?? false;
  },
  equipProductionWeapon(weaponId) {
    if (!game || mode !== 'baseline') throw new Error('Production weapons are only available in baseline mode');
    const world = game.scene.getScene('world') as unknown as {
      readonly combatController?: { equipWeapon(id: string): boolean };
    };
    return world.combatController?.equipWeapon(weaponId) ?? false;
  },
  attackWithProductionWeapon() {
    if (!game || mode !== 'baseline') throw new Error('Production weapons are only available in baseline mode');
    const world = game.scene.getScene('world') as unknown as {
      readonly combatController?: { tryAttack(): boolean };
    };
    return world.combatController?.tryAttack() ?? false;
  },
  snapshot() {
    const world = mode === 'baseline' && game
      ? game.scene.getScene('world') as unknown as {
          readonly universalWorld?: {
            readonly managedOrdinaryEnemyCount: number;
            readonly managedBossCount: number;
            readonly managedCampCount: number;
            readonly managedLiveCampCount: number;
            readonly managedChestCount: number;
            readonly managedNpcCount: number;
            readonly managedPlayerCount: number;
            readonly managedProjectileCount: number;
            readonly managedProjectileSpawnCount: number;
            readonly managedEffectCount: number;
            readonly managedWeaponId: string | null;
            readonly managedWeaponAttacking: boolean;
            readonly managedPlayer: { getPosition(): Readonly<{ x: number; y: number }> };
            readonly runtime: { readonly tree: { readonly paused: boolean } };
          };
          readonly healthSystem?: { getDamageState(): { readonly hp: number } };
          readonly combatController?: {
            readonly targets: Phaser.Physics.Arcade.Group;
            readonly usingLegacyWeaponVisual: boolean;
          };
          readonly bossCampController?: { readonly targets: Phaser.Physics.Arcade.Group };
          readonly chestController?: unknown;
          readonly builtMap?: { readonly npcActors: readonly unknown[] };
          readonly player?: Phaser.Physics.Arcade.Sprite;
        }
      : undefined;
    return {
      mode,
      stepCount,
      controlCount,
      gameObjectCount: destroyed ? 0 : countGameObjects(game),
      bodyCount: destroyed ? 0 : countBodies(game),
      canvasCount: document.querySelectorAll('canvas').length,
      cameraCount: destroyed ? 0 : game?.scene.getScenes(true).reduce((total, scene) => total + scene.cameras.cameras.length, 0) ?? 0,
      managedPresentationCount: destroyed ? 0 : harnessSnapshot?.().managedPresentationCount ?? 0,
      destroyed,
      ...(destroyed ? {} : harnessSnapshot?.()),
      ...(loadedAtMs === undefined ? {} : { loadedAtMs }),
      ...(initializationError === undefined ? {} : { initializationError }),
      ...(world?.universalWorld ? { managedOrdinaryEnemyCount: world.universalWorld.managedOrdinaryEnemyCount } : {}),
      ...(world?.universalWorld ? { managedBossCount: world.universalWorld.managedBossCount } : {}),
      ...(world?.universalWorld ? { managedCampCount: world.universalWorld.managedCampCount } : {}),
      ...(world?.universalWorld ? { managedLiveCampCount: world.universalWorld.managedLiveCampCount } : {}),
      ...(world?.universalWorld ? { managedChestCount: world.universalWorld.managedChestCount } : {}),
      ...(world?.universalWorld ? { managedNpcCount: world.universalWorld.managedNpcCount } : {}),
      ...(world?.universalWorld ? { managedPlayerCount: world.universalWorld.managedPlayerCount } : {}),
      ...(world?.universalWorld ? { managedProjectileCount: world.universalWorld.managedProjectileCount } : {}),
      ...(world?.universalWorld ? { managedProjectileSpawnCount: world.universalWorld.managedProjectileSpawnCount } : {}),
      ...(world?.universalWorld ? { managedEffectCount: world.universalWorld.managedEffectCount } : {}),
      ...(world?.universalWorld ? { managedWeaponId: world.universalWorld.managedWeaponId } : {}),
      ...(world?.universalWorld ? { managedWeaponAttacking: world.universalWorld.managedWeaponAttacking } : {}),
      ...(world?.healthSystem ? { playerHp: world.healthSystem.getDamageState().hp } : {}),
      ...(world?.universalWorld ? { universalRuntimePaused: world.universalWorld.runtime.tree.paused } : {}),
      ...(world?.combatController ? { legacyEnemyCount: world.combatController.targets.countActive(true) } : {}),
      ...(world?.combatController ? { usingLegacyWeaponVisual: world.combatController.usingLegacyWeaponVisual } : {}),
      ...(world?.bossCampController ? { legacyBossCount: world.bossCampController.targets.countActive(true) } : {}),
      ...(world?.builtMap ? { legacyNpcCount: world.builtMap.npcActors.length } : {}),
      ...(world?.player ? { legacyPlayerX: world.player.x } : {}),
      ...(world?.universalWorld ? { managedPlayerX: world.universalWorld.managedPlayer.getPosition().x } : {}),
      ...(world ? { hasLegacyChestController: world.chestController !== undefined } : {}),
    };
  },
  destroy() {
    if (destroyed) return;
    destroyed = true;
    control.removeEventListener('click', consumeControl);
    const destroyingGame = game;
    destroyingGame?.destroy(true);
    // The deterministic fixture sleeps Phaser's RAF loop, so explicitly deliver
    // the pending destroy boundary that would normally arrive on the next frame.
    destroyingGame?.step(performance.now(), 0);
    game = undefined;
  },
};

window.sceneFixture = api;
