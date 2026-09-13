import Phaser from 'phaser';

import { Camera2DNode } from '../../../../src/game/infrastructure/phaser-nodes/Camera2DNode';
import { Sprite2DNode } from '../../../../src/game/infrastructure/phaser-nodes/Sprite2DNode';
import { PhaserNodeContext } from '../../../../src/game/infrastructure/scenes/PhaserNodeContext';
import { PhaserSceneTreeHost } from '../../../../src/game/infrastructure/scenes/PhaserSceneTreeHost';
import { authoredNodeId, resourceId, runtimeNodeId } from '../../../../src/game/content/scenes/identifiers';
import { Node } from '../../../../src/game/runtime/scene/Node';
import { SceneTree } from '../../../../src/game/runtime/scene/SceneTree';

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
  readonly destroyed: boolean;
  readonly loadedAtMs?: number;
  readonly initializationError?: string;
};

type FixtureApi = {
  ready(): boolean;
  step(deltaSeconds?: number): void;
  moveSprite(x: number, y: number): void;
  detachSprite(): void;
  attachSprite(): void;
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
control.addEventListener('click', consumeControl);

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
let harnessSnapshot: (() => Partial<FixtureSnapshot>) | undefined;

if (mode === 'harness') {
  class BrowserHarnessScene extends Phaser.Scene {
    private body?: Phaser.Physics.Arcade.Image;
    private context?: PhaserNodeContext;
    private tree?: SceneTree;
    private host?: PhaserSceneTreeHost;
    private root?: Node;
    private spriteNode?: Sprite2DNode;

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
      this.context = new PhaserNodeContext(this, new Map([
        [textureId, { version: 1, resourceId: textureId, kind: 'texture', assetId: 'browser-harness-dot' }],
      ]));
      this.root = new Node({ runtimeId: runtimeNodeId('browser', [], authoredNodeId('root')), name: 'Root' });
      this.spriteNode = new Sprite2DNode({
        runtimeId: runtimeNodeId('browser', [], authoredNodeId('sprite')), name: 'ManagedSprite', context: this.context, texture: textureId,
        position: { x: 40, y: 30 }, depthMode: 'explicit', depth: 10,
      });
      const camera = new Camera2DNode({ runtimeId: runtimeNodeId('browser', [], authoredNodeId('camera')), name: 'ManagedCamera', context: this.context, position: { x: 80, y: 60 } });
      this.root.add_child(this.spriteNode);
      this.root.add_child(camera);
      this.tree = new SceneTree();
      this.tree.setRoot(this.root);
      this.host = new PhaserSceneTreeHost({ tree: this.tree, backend: this.context });
      this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => this.host?.shutdown());
      this.events.once(Phaser.Scenes.Events.DESTROY, () => this.host?.shutdown());
      this.game.loop.sleep();
    }

    advance(deltaSeconds: number): void {
      this.host?.advanceFrame(deltaSeconds);
      stepCount = this.context?.physicsStepCount ?? stepCount;
    }

    moveSprite(x: number, y: number): void { if (this.spriteNode) this.spriteNode.position = { x, y }; }
    detachSprite(): void { if (this.root && this.spriteNode?.get_parent() === this.root) { this.root.remove_child(this.spriteNode); this.tree?.flushMutations(); } }
    attachSprite(): void { if (this.root && this.spriteNode && !this.spriteNode.get_parent()) { this.root.add_child(this.spriteNode); this.tree?.flushMutations(); } }
    managedSnapshot(): Partial<FixtureSnapshot> {
      const display = this.children.list.find((entry) => entry instanceof Phaser.GameObjects.Sprite) as Phaser.GameObjects.Sprite | undefined;
      return {
        bodyX: (this.body?.body as Phaser.Physics.Arcade.Body | undefined)?.position.x,
        managedPresentationCount: this.context?.managedPresentationCount ?? 0,
        spriteX: display?.x,
        spriteY: display?.y,
        spriteActive: this.spriteNode?.phaserObjectActive ?? false,
        cameraCount: this.cameras.cameras.length,
      };
    }
  }

  game = new Phaser.Game({
    type: Phaser.CANVAS,
    parent: app,
    width: 160,
    height: 120,
    banner: false,
    audio: { noAudio: true },
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
  snapshot() {
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
