import type Phaser from 'phaser';

import { authoredNodeId, runtimeNodeId, type PersistenceKey, type SceneId } from '../../content/scenes/identifiers';
import { descriptorMap, propertiesForNode, type DescriptorRegistry } from '../../content/scenes/propertyDescriptors';
import { AnimationBinding } from '../../runtime/scene/animation/AnimationBinding';
import { Node } from '../../runtime/scene/Node';
import { Node2D, type Vector2 } from '../../runtime/scene/Node2D';
import { SceneTree, type SceneTreeInputEvent } from '../../runtime/scene/SceneTree';
import { SceneInstantiator } from '../../runtime/scene/resolution/SceneInstantiator';
import type { SceneInstantiationPropertyOverride } from '../../runtime/scene/resolution/SceneInstantiator';
import type { ScriptRegistry } from '../../runtime/scene/registries/ScriptRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import { createPhaserNodeRegistry, type PhaserNodeRegistryServices } from '../phaser-nodes/PhaserNodeRegistry';
import { PhaserNodeContext } from './PhaserNodeContext';
import { PhaserSceneTreeHost, type PhaserSceneTreeHostOptions, type SceneHostDiagnostic } from './PhaserSceneTreeHost';
import type { LegacyWorldAdapter } from './compatibility/LegacyWorldAdapter';
import type { PreparedSceneContent } from './PreparedSceneContent';

export interface PhaserUniversalSceneRuntimeOptions {
  readonly scene: Phaser.Scene;
  readonly content: PreparedSceneContent;
  readonly descriptors: DescriptorRegistry;
  readonly scripts?: ScriptRegistry;
  readonly nodeServices?: Omit<PhaserNodeRegistryServices, 'resolveAnimationBinding'>;
  readonly legacy?: LegacyWorldAdapter;
  readonly resolveAssetKey?: (assetId: string) => string;
  readonly fixedDeltaSeconds?: number;
  readonly diagnosticSink?: (diagnostic: SceneHostDiagnostic) => void;
}

export interface MountSceneOptions {
  readonly runtimeNamespace?: string;
  readonly persistenceKey?: PersistenceKey | string;
  readonly position?: Vector2;
  readonly propertyOverrides?: readonly SceneInstantiationPropertyOverride[];
}

export interface MountedScene {
  readonly sceneId: SceneId;
  readonly runtimeNamespace: string;
  readonly root: Node;
  readonly mount: Node2D;
  readonly disposed: boolean;
  dispose(): void;
}

let nextRuntime = 1;

export class PhaserUniversalSceneRuntime {
  readonly tree: SceneTree;
  readonly context: PhaserNodeContext;
  readonly host: PhaserSceneTreeHost;
  private readonly treeRoot: Node;
  private readonly instantiator: SceneInstantiator;
  private readonly mounts = new Map<string, MountedScene>();
  private nextMount = 1;
  private stopped = false;

  constructor(private readonly options: PhaserUniversalSceneRuntimeOptions) {
    const runtimeNumber = nextRuntime++;
    this.tree = new SceneTree({ diagnosticSink: (diagnostic) => {
      options.diagnosticSink?.({ phase: 'frame', message: diagnostic.message, ...(diagnostic.error === undefined ? {} : { error: diagnostic.error }) });
    } });
    this.context = new PhaserNodeContext(options.scene, options.content.resources, options.resolveAssetKey);
    this.treeRoot = new Node({ runtimeId: runtimeNodeId(`universal-runtime-${runtimeNumber}`, [], authoredNodeId('root')), name: 'UniversalRuntime' });
    this.tree.setRoot(this.treeRoot);
    const nodeTypes = createPhaserNodeRegistry(this.context, {
      ...options.nodeServices,
      resolveAnimationBinding: (player, binding, property) => this.resolveAnimationBinding(player, binding, property),
    });
    this.instantiator = new SceneInstantiator({ nodeTypes, scripts: options.scripts, descriptors: options.descriptors });
    try {
      const hostOptions: PhaserSceneTreeHostOptions = {
        tree: this.tree,
        backend: this.context,
        ...(options.legacy ? { legacy: options.legacy } : {}),
        ...(options.fixedDeltaSeconds === undefined ? {} : { fixedDeltaSeconds: options.fixedDeltaSeconds }),
        ...(options.diagnosticSink ? { diagnosticSink: options.diagnosticSink } : {}),
      };
      this.host = new PhaserSceneTreeHost(hostOptions);
    } catch (error) {
      this.tree.shutdown();
      this.context.shutdown();
      throw error;
    }
  }

  get mountedSceneCount(): number { return this.mounts.size; }

  mountScene(sceneId: SceneId, options: MountSceneOptions = {}): MountedScene {
    this.assertRunning();
    const packed = this.options.content.get(sceneId);
    const mountNumber = this.nextMount++;
    const runtimeNamespace = options.runtimeNamespace ?? `scene-mount-${mountNumber}`;
    if (this.mounts.has(runtimeNamespace)) throw new Error(`Runtime namespace '${runtimeNamespace}' is already mounted`);
    const releaseResources = this.context.acquireResources(packed.definition.resources);
    let mount: Node2D | undefined;
    try {
      const root = this.instantiator.instantiate_scene(packed, {
        runtimeNamespace,
        ...(options.persistenceKey === undefined ? {} : { persistenceKey: options.persistenceKey }),
        ...(options.propertyOverrides === undefined ? {} : { propertyOverrides: options.propertyOverrides }),
      });
      mount = new Node2D({
        runtimeId: runtimeNodeId(runtimeNamespace, [], authoredNodeId('mount')),
        name: `SceneMount${mountNumber}`,
        position: options.position ?? { x: 0, y: 0 },
      });
      mount.lifetimeDisposables.add(releaseResources);
      mount.add_child(root);
      const record = new MountedSceneRecord(sceneId, runtimeNamespace, root, mount, () => this.releaseMount(runtimeNamespace, mount!));
      mount.lifetimeDisposables.add(() => {
        this.mounts.delete(runtimeNamespace);
        record.markDisposed();
      });
      this.treeRoot.add_child(mount);
      this.tree.flushMutations();
      if (!mount.is_inside_tree()) {
        mount.queue_free();
        throw new Error(`Scene '${sceneId}' could not enter the universal runtime tree`);
      }
      this.mounts.set(runtimeNamespace, record);
      return record;
    } catch (error) {
      if (mount && !mount.is_freed()) mount.queue_free();
      else releaseResources();
      this.tree.flushMutations();
      throw error;
    }
  }

  advanceFrame(deltaSeconds: number): number { this.assertRunning(); return this.host.advanceFrame(deltaSeconds); }
  enqueueInput(event: SceneTreeInputEvent): void { this.assertRunning(); this.host.enqueueInput(event); }
  setPaused(paused: boolean): void { this.assertRunning(); this.host.setPaused(paused); }

  shutdown(): void {
    if (this.stopped) return;
    this.stopped = true;
    this.host.shutdown();
    this.mounts.clear();
  }

  private resolveAnimationBinding(player: Node, binding: string, property: string): AnimationBinding {
    const target = player.get_node(binding);
    const scriptId = target instanceof ScriptNode ? target.scriptId : undefined;
    const descriptor = descriptorMap(propertiesForNode(target.runtimeType, scriptId, this.options.descriptors) ?? []).get(property);
    if (!descriptor) throw new Error(`Animation binding '${binding}.${property}' is not declared on '${target.runtimeType}'`);
    return new AnimationBinding(target, property, descriptor);
  }

  private releaseMount(runtimeNamespace: string, mount: Node2D): void {
    if (mount.is_freed()) return;
    mount.queue_free();
    this.tree.flushMutations();
    this.mounts.delete(runtimeNamespace);
  }

  private assertRunning(): void { if (this.stopped) throw new Error('Universal scene runtime has shut down'); }
}

class MountedSceneRecord implements MountedScene {
  private stopped = false;

  constructor(
    readonly sceneId: SceneId,
    readonly runtimeNamespace: string,
    readonly root: Node,
    readonly mount: Node2D,
    private readonly release: () => void,
  ) {}

  get disposed(): boolean { return this.stopped; }
  dispose(): void { if (!this.stopped) this.release(); }
  markDisposed(): void { this.stopped = true; }
}
