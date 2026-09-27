import Phaser from 'phaser';

import { runtimeNodeId, type ResourceId, type SceneId } from '../../../content/scenes/identifiers';
import type { DescriptorRegistry } from '../../../content/scenes/propertyDescriptors';
import type { SceneDocument, SceneResourceDocument } from '../../../content/scenes/types';
import { createUiAssetUrlResolver } from '../../../features/world/UniversalSceneWorldController';
import { ASSET_MANIFEST, type AssetId } from '../../../infrastructure/assets/manifest';
import { ProceduralAssetScene } from '../../../infrastructure/assets/ProceduralAssetScene';
import { HtmlControlPresentationAdapter } from '../../../infrastructure/phaser-nodes/ui/HtmlControlPresentationAdapter';
import { PhaserUniversalSceneRuntime, type MountedScene } from '../../../infrastructure/scenes/PhaserUniversalSceneRuntime';
import { Sprite2DNode, type SpriteBoundsGeometry } from '../../../infrastructure/phaser-nodes/Sprite2DNode';
import { PreparedSceneContent } from '../../../infrastructure/scenes/PreparedSceneContent';
import { AnimationPlayerNode } from '../../../runtime/scene/animation/AnimationPlayerNode';
import type { Node } from '../../../runtime/scene/Node';
import { Node2D } from '../../../runtime/scene/Node2D';
import { ScriptRegistry } from '../../../runtime/scene/registries/ScriptRegistry';
import { ScriptNode } from '../../../runtime/scene/scripts/ScriptNode';
import type { ScenePreviewFactory, ScenePreviewHost } from '../ScenePreview';
import { UI_PREVIEW_SIZE, type ViewportCamera, type WorldRect } from '../SceneViewport';

export const STUDIO_PREVIEW_NAMESPACE = 'studio-preview';
const PREVIEW_SCENE_KEY = 'scene-studio-preview';
const UI_ROOT_TYPES = new Set(['Control', 'Container', 'TextureRect', 'Label', 'ProgressBar', 'Button', 'ItemList', 'GridContainer', 'ScrollContainer', 'ModalRoot']);

export type StudioPreviewStatus = 'booting' | 'loading' | 'ready' | 'error' | 'idle';

export interface StudioPreviewState {
  readonly status: StudioPreviewStatus;
  readonly kind: 'world' | 'ui';
  readonly error?: string;
  readonly sceneId?: SceneId;
  /** Union of every rendered display object, in world coordinates. */
  readonly contentBounds?: WorldRect;
  /** Wall-clock milliseconds the last prepare + mount took. */
  readonly mountMs?: number;
  readonly prepareMs?: number;
}

export interface StudioPreviewContentSource {
  /** Every scene document known to the studio (disk truth); the draft replaces its own entry. */
  scenes(): readonly SceneDocument[];
  resources(): readonly SceneResourceDocument[];
}

export interface StudioPreviewOptions {
  readonly registry: DescriptorRegistry;
  readonly content: StudioPreviewContentSource;
  readonly onChange?: (state: StudioPreviewState) => void;
}

/**
 * Editor-safe script host: every registered script resolves to an inert
 * ScriptNode that keeps its identity, exported properties, references and
 * signal handlers but runs no behavior and requires no gameplay services.
 */
export function createInertScriptRegistry(registry: DescriptorRegistry): ScriptRegistry {
  const scripts = new ScriptRegistry();
  for (const descriptor of registry.scripts.values()) {
    scripts.registerDefinition({
      descriptor,
      factory: (context) => {
        const node = new ScriptNode({ runtimeId: context.runtimeId, name: context.name, scriptId: context.scriptId ?? descriptor.scriptId, exportedProperties: context.properties });
        for (const handler of scripts.metadata(descriptor.scriptId).handlers) node.registerSignalHandler(handler.id, () => undefined);
        return node;
      },
    });
  }
  return scripts;
}

/**
 * Collects the target scene plus every scene it (transitively) instances or
 * names in a property value (e.g. scene-reference properties such as a boss
 * scene), so the catalog validates exactly what the runtime would load.
 */
export function previewSceneClosure(document: SceneDocument, resolve: (sceneId: SceneId) => SceneDocument | undefined): readonly SceneDocument[] {
  const output = new Map<SceneId, SceneDocument>([[document.sceneId, document]]);
  const pending = [document];
  const include = (candidate: string): void => {
    if (output.has(candidate as SceneId)) return;
    const source = resolve(candidate as SceneId);
    if (!source) return;
    output.set(source.sceneId, source);
    pending.push(source);
  };
  const scan = (value: unknown): void => {
    if (typeof value === 'string') { if (value.includes('.')) include(value); return; }
    if (Array.isArray(value)) { for (const entry of value) scan(entry); return; }
    if (value && typeof value === 'object') for (const entry of Object.values(value)) scan(entry);
  };
  while (pending.length > 0) {
    const current = pending.pop()!;
    for (const instance of current.instances) {
      include(instance.sceneId);
      for (const override of instance.overrides) scan(override.value);
    }
    for (const node of current.nodes) scan(node.properties);
  }
  return [...output.values()];
}

const NEVER_UNLOCKED = { isUnlocked: () => false, onUnlocked: () => () => undefined };
const MUTED = { volume: () => 0, muted: () => true };

class PreviewPhaserScene extends Phaser.Scene {
  onFrame?: (deltaMs: number) => void;
  private readyCallback?: (scene: PreviewPhaserScene) => void;

  constructor(ready: (scene: PreviewPhaserScene) => void) {
    super(PREVIEW_SCENE_KEY);
    this.readyCallback = ready;
  }

  create(): void {
    this.cameras.main.setBackgroundColor('#0b1411');
    this.readyCallback?.(this);
    this.readyCallback = undefined;
  }

  update(_time: number, delta: number): void { this.onFrame?.(delta); }
}

/**
 * Embedded Phaser host that mounts authored scenes through the same
 * PreparedSceneContent → PhaserUniversalSceneRuntime → PhaserNodeRegistry
 * path as the game, with the tree paused, physics never stepped and every
 * script replaced by an inert node. Rendering is therefore identical to the
 * game for sprites, tile maps, instanced scenes and UI controls.
 */
export class StudioScenePreview implements ScenePreviewFactory {
  readonly element: HTMLDivElement;
  private readonly canvasHost: HTMLDivElement;
  private readonly uiRoot: HTMLDivElement;
  private game?: Phaser.Game;
  private scene?: PreviewPhaserScene;
  private readonly booted: Promise<PreviewPhaserScene>;
  private runtime?: PhaserUniversalSceneRuntime;
  private content?: PreparedSceneContent;
  private mounted?: MountedScene;
  private generation = 0;
  private dirty = false;
  private camera: ViewportCamera = { centerX: 0, centerY: 0, zoom: 1 };
  private animationPlayer?: AnimationPlayerNode;
  private onionGhosts: Phaser.GameObjects.Image[] = [];
  private thumbnailResolver?: (key: string, frame: number) => string | undefined;
  private resourceOverrides: readonly SceneResourceDocument[] = [];
  private stateValue: StudioPreviewState = { status: 'booting', kind: 'world' };
  private uiAdapter?: HtmlControlPresentationAdapter;

  constructor(private readonly options: StudioPreviewOptions) {
    this.element = document.createElement('div');
    this.element.className = 'scene-preview-stage';
    this.canvasHost = document.createElement('div');
    this.canvasHost.className = 'scene-preview-canvas';
    this.uiRoot = document.createElement('div');
    this.uiRoot.className = 'scene-ui-root scene-preview-ui-root';
    this.uiRoot.style.width = `${UI_PREVIEW_SIZE.width}px`;
    this.uiRoot.style.height = `${UI_PREVIEW_SIZE.height}px`;
    // The preview is a picture of the UI: never focusable or interactive.
    this.uiRoot.inert = true;
    this.element.append(this.canvasHost, this.uiRoot);
    this.booted = new Promise<PreviewPhaserScene>((resolve, reject) => { this.resolveBoot = resolve; this.rejectBoot = reject; });
    this.booted.then((scene) => {
      this.scene = scene;
      scene.onFrame = (delta) => this.frame(delta);
      scene.scale.on('resize', () => this.applyCamera());
      if (this.stateValue.status === 'booting') this.setState({ status: 'idle', kind: 'world' });
      this.applyCamera();
    }, (error: unknown) => this.setState({ status: 'error', kind: 'world', error: message(error) }));
  }

  private resolveBoot?: (scene: PreviewPhaserScene) => void;
  private rejectBoot?: (error: unknown) => void;

  /**
   * Starts the embedded Phaser game once the stage is attached and has a size
   * (a zero-sized canvas cannot allocate WebGL framebuffers).
   */
  ensureBooted(): void {
    if (this.game || !this.element.isConnected || this.element.clientWidth === 0 || this.element.clientHeight === 0) return;
    try {
      this.game = new Phaser.Game({
        type: Phaser.AUTO,
        parent: this.canvasHost,
        backgroundColor: '#0b1411',
        scale: { mode: Phaser.Scale.RESIZE, width: this.element.clientWidth, height: this.element.clientHeight, autoRound: false },
        pixelArt: false,
        roundPixels: true,
        audio: { noAudio: true },
        input: { keyboard: false, mouse: false, touch: false, gamepad: false },
        banner: false,
        physics: { default: 'arcade', arcade: { gravity: { x: 0, y: 0 }, debug: false, fps: 60, fixedStep: true } },
        scene: [new ProceduralAssetScene(PREVIEW_SCENE_KEY), new PreviewPhaserScene((scene) => this.resolveBoot?.(scene))],
      });
    } catch (error) { this.rejectBoot?.(error); }
  }

  get state(): StudioPreviewState { return this.stateValue; }
  get phaserGame(): Phaser.Game | undefined { return this.game; }
  get runtimeTree(): Node | undefined { return this.mounted?.root; }

  /** Draft external resources (tile data, tile sets…) that shadow disk versions. */
  setResourceOverrides(resources: readonly SceneResourceDocument[]): void { this.resourceOverrides = resources; }

  create(document: SceneDocument): ScenePreviewHost {
    const generation = ++this.generation;
    void this.mount(document, generation);
    return {
      // Deferred so ScenePreview.open (close + create) keeps the previous frame
      // on screen until the replacement is prepared.
      dispose: () => {
        if (this.generation !== generation) return;
        this.generation += 1;
        const closed = this.generation;
        queueMicrotask(() => { if (this.generation === closed) this.unmount(); });
      },
      resourceCount: () => this.mounted ? this.content?.resources.size ?? 0 : 0,
    };
  }

  setCamera(camera: ViewportCamera): void {
    this.camera = camera;
    this.applyCamera();
  }

  /** Runtime IDs of mounted nodes mapped to world-space display bounds. */
  nodeBounds(): ReadonlyMap<string, WorldRect> {
    const output = new Map<string, WorldRect>();
    const visit = (node: Node): void => {
      const presentation = (node as unknown as { presentationObject?: Phaser.GameObjects.Sprite; phaserObjectActive?: boolean });
      if (presentation.phaserObjectActive) {
        try {
          const object = presentation.presentationObject;
          if (object?.visible) {
            const bounds = object.getBounds();
            output.set(node.runtimeId, { x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height });
          }
        } catch { /* presentation not mounted */ }
      }
      for (const child of node.get_children()) visit(child);
    };
    if (this.mounted) visit(this.mounted.root);
    return output;
  }

  /** Runtime IDs of rendered sprites mapped to their frame geometry, for occlusion/depth guides. */
  spriteGeometry(): ReadonlyMap<string, SpriteBoundsGeometry> {
    const output = new Map<string, SpriteBoundsGeometry>();
    const visit = (node: Node): void => {
      if (node instanceof Sprite2DNode) {
        const geometry = node.boundsGeometry();
        if (geometry) output.set(node.runtimeId, geometry);
      }
      for (const child of node.get_children()) visit(child);
    };
    if (this.mounted) visit(this.mounted.root);
    return output;
  }

  /**
   * Applies a local position to a mounted Node2D immediately, so drags feel
   * instant while the authoritative rebuild is prepared in the background.
   */
  patchPosition(runtimeId: string, position: readonly [number, number]): boolean {
    let found: Node | undefined;
    const visit = (node: Node): void => {
      if (found) return;
      if (node.runtimeId === runtimeId) { found = node; return; }
      for (const child of node.get_children()) visit(child);
    };
    if (this.mounted) visit(this.mounted.root);
    if (!(found instanceof Node2D)) return false;
    found.position = { x: position[0], y: position[1] };
    this.dirty = true;
    return true;
  }

  animationPlayers(): readonly AnimationPlayerNode[] {
    const output: AnimationPlayerNode[] = [];
    const visit = (node: Node): void => {
      if (node instanceof AnimationPlayerNode) output.push(node);
      for (const child of node.get_children()) visit(child);
    };
    if (this.mounted) visit(this.mounted.root);
    return output;
  }

  private playerFor(playerRuntimeId: string, clip: string): AnimationPlayerNode | undefined {
    const player = this.animationPlayers().find((candidate) => candidate.runtimeId === playerRuntimeId);
    return player?.hasAnimation(clip) ? player : undefined;
  }

  /** Shows one frame of a clip, paused — the timeline's scrub and edit preview. */
  poseAnimation(playerRuntimeId: string, clip: string, frame: number): boolean {
    const player = this.playerFor(playerRuntimeId, clip);
    if (!player) return false;
    this.clearOnionSkin();
    if (this.animationPlayer !== player || player.currentAnimation !== clip) {
      this.animationPlayer?.stop();
      player.play(clip);
    }
    player.pause();
    player.seek(frame);
    this.animationPlayer = player;
    this.dirty = true;
    return true;
  }

  /** Plays a clip from a frame at its authored speed. */
  playAnimationFrom(playerRuntimeId: string, clip: string, frame: number): boolean {
    if (!this.poseAnimation(playerRuntimeId, clip, frame)) return false;
    this.animationPlayer?.resume();
    return true;
  }

  pauseAnimation(): void {
    this.animationPlayer?.pause();
    this.dirty = true;
  }

  stopAnimation(): void {
    this.clearOnionSkin();
    this.animationPlayer?.stop();
    this.animationPlayer = undefined;
    this.dirty = true;
  }

  /** The posed or playing clip; `clip` is undefined once a one-shot clip has finished. */
  get animationState(): { readonly clip?: string; readonly frame: number; readonly playing: boolean } | undefined {
    const player = this.animationPlayer;
    if (!player) return undefined;
    const state = player.playbackState;
    return { ...(player.currentAnimation ? { clip: player.currentAnimation } : {}), frame: state.timelineFrame, playing: Boolean(player.currentAnimation) && !state.paused };
  }

  /**
   * Draws translucent copies of every sprite at the given frames of the posed
   * clip (onion skinning), then restores the current pose.
   */
  showOnionSkin(frames: readonly { readonly frame: number; readonly tint: number }[]): void {
    this.clearOnionSkin();
    const player = this.animationPlayer;
    const scene = this.scene;
    if (!player?.currentAnimation || !scene || !this.mounted) return;
    const current = player.playbackState.timelineFrame;
    for (const { frame, tint } of frames) {
      player.seek(frame);
      this.synchronize();
      for (const sprite of this.visibleSprites()) {
        const ghost = scene.add.image(sprite.x, sprite.y, sprite.texture.key, sprite.frame.name)
          .setOrigin(sprite.originX, sprite.originY)
          .setScale(sprite.scaleX, sprite.scaleY)
          .setRotation(sprite.rotation)
          .setFlip(sprite.flipX, sprite.flipY)
          .setAlpha(sprite.alpha * 0.35)
          .setTintFill(tint)
          .setDepth(sprite.depth - 0.001);
        this.onionGhosts.push(ghost);
      }
    }
    player.seek(current);
    this.dirty = true;
  }

  clearOnionSkin(): void {
    for (const ghost of this.onionGhosts) ghost.destroy();
    this.onionGhosts = [];
  }

  /** A data URL of one sprite-sheet frame, rendered from the loaded texture. */
  frameThumbnail(assetId: string, frame: number): string | undefined {
    const scene = this.scene;
    const textureKey = (ASSET_MANIFEST.assets as Record<string, { runtime: { textureKey: string } } | undefined>)[assetId]?.runtime.textureKey;
    if (!scene || !textureKey) return undefined;
    this.thumbnailResolver ??= createUiAssetUrlResolver(scene);
    return this.thumbnailResolver(textureKey, frame);
  }

  private visibleSprites(): Phaser.GameObjects.Sprite[] {
    const output: Phaser.GameObjects.Sprite[] = [];
    const visit = (node: Node): void => {
      if (node instanceof Sprite2DNode && node.phaserObjectActive && node.presentationObject.visible && node.presentationObject.alpha > 0) output.push(node.presentationObject);
      for (const child of node.get_children()) visit(child);
    };
    if (this.mounted) visit(this.mounted.root);
    return output;
  }

  destroy(): void {
    this.generation += 1;
    this.unmount();
    this.game?.destroy(true);
    this.game = undefined;
  }

  private async mount(authored: SceneDocument, generation: number): Promise<void> {
    // Closed modal roots are hidden at runtime; the editor previews them open
    // (the UI layer is inert, so opening never moves focus).
    const document: SceneDocument = authored.nodes.some((node) => node.type === 'ModalRoot' && node.properties.open !== true)
      ? { ...authored, nodes: authored.nodes.map((node) => node.type === 'ModalRoot' ? { ...node, properties: { ...node.properties, open: true } } : node) }
      : authored;
    const kind = UI_ROOT_TYPES.has(document.nodes.find((node) => node.id === document.rootNodeId)?.type ?? '') ? 'ui' : 'world';
    this.setState({ status: 'loading', kind, sceneId: document.sceneId });
    const started = performance.now();
    let content: PreparedSceneContent | undefined;
    try {
      const scene = await this.booted;
      const known = new Map(this.options.content.scenes().map((candidate) => [candidate.sceneId, candidate]));
      known.set(document.sceneId, document);
      const scenes = previewSceneClosure(document, (sceneId) => known.get(sceneId));
      const resources = new Map<ResourceId, SceneResourceDocument>(this.options.content.resources().map((resource) => [resource.resourceId, resource]));
      for (const resource of this.resourceOverrides) resources.set(resource.resourceId, resource);
      content = await PreparedSceneContent.prepare({
        scenes,
        resources: [...resources.values()],
        registry: this.options.registry,
        sceneIds: [document.sceneId],
        hasAsset: (assetId) => Object.hasOwn(ASSET_MANIFEST.assets, assetId),
      });
      if (generation !== this.generation) { content.dispose(); return; }
      const prepared = performance.now();
      this.unmount();
      this.uiRoot.replaceChildren();
      this.uiAdapter = new HtmlControlPresentationAdapter({
        root: this.uiRoot,
        viewport: () => ({ width: UI_PREVIEW_SIZE.width, height: UI_PREVIEW_SIZE.height }),
        resolveAssetUrl: createUiAssetUrlResolver(scene),
      });
      const diagnostics: string[] = [];
      const runtime = new PhaserUniversalSceneRuntime({
        scene,
        content,
        descriptors: this.options.registry,
        scripts: createInertScriptRegistry(this.options.registry),
        nodeServices: { controlPresentation: this.uiAdapter, audioPreferences: MUTED, audioUnlock: NEVER_UNLOCKED },
        resolveAssetKey: (assetId) => (ASSET_MANIFEST.assets as Record<string, { runtime: { textureKey: string } } | undefined>)[assetId as AssetId]?.runtime.textureKey ?? assetId,
        diagnosticSink: (diagnostic) => diagnostics.push(diagnostic.message),
      });
      this.runtime = runtime;
      this.content = content;
      runtime.setPaused(true);
      this.mounted = runtime.mountScene(document.sceneId, { runtimeNamespace: STUDIO_PREVIEW_NAMESPACE });
      this.synchronize();
      this.setState({
        status: 'ready', kind, sceneId: document.sceneId, mountMs: Math.round(performance.now() - started), prepareMs: Math.round(prepared - started),
        ...(diagnostics.length > 0 ? { error: diagnostics.join('\n') } : {}),
        ...(this.contentBounds(kind) ? { contentBounds: this.contentBounds(kind) } : {}),
      });
    } catch (error) {
      if (generation !== this.generation) { content?.dispose(); return; }
      this.unmount();
      content?.dispose();
      this.setState({ status: 'error', kind, sceneId: document.sceneId, error: message(error) });
    }
  }

  private unmount(): void {
    this.clearOnionSkin();
    this.animationPlayer = undefined;
    const runtime = this.runtime;
    this.runtime = undefined;
    this.mounted = undefined;
    try { runtime?.shutdown(); } catch (error) { console.error('[SceneStudioPreview] shutdown', error); }
    this.content?.dispose();
    this.content = undefined;
    this.uiAdapter = undefined;
    this.uiRoot.replaceChildren();
  }

  private frame(deltaMs: number): void {
    if (!this.runtime) return;
    if (this.animationPlayer?.currentAnimation && !this.animationPlayer.playbackState.paused) {
      try { this.animationPlayer.advance(deltaMs / 1000); } catch (error) { console.error(error); this.animationPlayer = undefined; }
      this.dirty = true;
    }
    if (this.dirty) this.synchronize();
  }

  private synchronize(): void {
    this.dirty = false;
    try { this.runtime?.advanceFrame(0); } catch (error) { this.setState({ ...this.stateValue, status: 'error', error: message(error) }); }
    // Authored Camera2D nodes add their own cameras; the studio camera owns the view.
    const scene = this.scene;
    if (scene) for (const camera of scene.cameras.cameras) if (camera !== scene.cameras.main) camera.setVisible(false);
  }

  private contentBounds(kind: 'world' | 'ui'): WorldRect | undefined {
    if (kind === 'ui') return { x: 0, y: 0, width: UI_PREVIEW_SIZE.width, height: UI_PREVIEW_SIZE.height };
    const scene = this.scene;
    if (!scene) return undefined;
    let minX = Infinity; let minY = Infinity; let maxX = -Infinity; let maxY = -Infinity;
    for (const object of scene.children.list) {
      const candidate = object as unknown as { visible?: boolean; getBounds?: () => Phaser.Geom.Rectangle };
      if (!candidate.visible || typeof candidate.getBounds !== 'function') continue;
      const bounds = candidate.getBounds();
      if (![bounds.x, bounds.y, bounds.width, bounds.height].every(Number.isFinite)) continue;
      minX = Math.min(minX, bounds.x); minY = Math.min(minY, bounds.y);
      maxX = Math.max(maxX, bounds.right); maxY = Math.max(maxY, bounds.bottom);
    }
    return Number.isFinite(minX) ? { x: minX, y: minY, width: maxX - minX, height: maxY - minY } : undefined;
  }

  private applyCamera(): void {
    const scene = this.scene;
    if (scene) {
      const main = scene.cameras.main;
      main.setZoom(this.camera.zoom);
      main.centerOn(this.camera.centerX, this.camera.centerY);
    }
    const width = this.element.clientWidth;
    const height = this.element.clientHeight;
    const left = width / 2 - this.camera.centerX * this.camera.zoom;
    const top = height / 2 - this.camera.centerY * this.camera.zoom;
    this.uiRoot.style.transform = `translate(${left}px, ${top}px) scale(${this.camera.zoom})`;
  }

  private setState(state: StudioPreviewState): void {
    this.stateValue = state;
    this.options.onChange?.(state);
  }
}

export function previewRuntimeId(instancePath: readonly string[], nodeId: string): string {
  return runtimeNodeId(STUDIO_PREVIEW_NAMESPACE, instancePath as never, nodeId as never);
}

function message(error: unknown): string { return error instanceof Error ? error.message : String(error); }
