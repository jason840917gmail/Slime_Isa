import Phaser from 'phaser';

type FixtureSnapshot = {
  readonly mode: 'harness' | 'baseline';
  readonly stepCount: number;
  readonly controlCount: number;
  readonly gameObjectCount: number;
  readonly bodyCount: number;
  readonly canvasCount: number;
  readonly destroyed: boolean;
  readonly loadedAtMs?: number;
  readonly initializationError?: string;
};

type FixtureApi = {
  ready(): boolean;
  step(deltaSeconds?: number): void;
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

if (mode === 'harness') {
  class BrowserHarnessScene extends Phaser.Scene {
    private body?: Phaser.Physics.Arcade.Image;

    constructor() {
      super('browser-harness');
    }

    create(): void {
      const texture = this.textures.createCanvas('browser-harness-dot', 8, 8);
      texture?.context.fillRect(0, 0, 8, 8);
      texture?.refresh();
      this.body = this.physics.add.image(16, 16, 'browser-harness-dot');
      this.body.setVelocityX(60);
      this.game.loop.sleep();
    }

    advance(deltaSeconds: number): void {
      this.physics.world.step(deltaSeconds);
      stepCount += 1;
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
  snapshot() {
    return {
      mode,
      stepCount,
      controlCount,
      gameObjectCount: destroyed ? 0 : countGameObjects(game),
      bodyCount: destroyed ? 0 : countBodies(game),
      canvasCount: document.querySelectorAll('canvas').length,
      destroyed,
      ...(loadedAtMs === undefined ? {} : { loadedAtMs }),
      ...(initializationError === undefined ? {} : { initializationError }),
    };
  },
  destroy() {
    if (destroyed) return;
    destroyed = true;
    control.removeEventListener('click', consumeControl);
    game?.destroy(true);
    game = undefined;
  },
};

window.sceneFixture = api;
