import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { Node } from '../../runtime/scene/Node';
import type { Node2D } from '../../runtime/scene/Node2D';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import type { NpcWanderState, NpcWanderStepResult } from '../npcs/NpcWanderPolicy';
import { createNpcWanderState } from '../npcs/NpcWanderPolicy';
import { CharacterScript, type CharacterPoint } from './CharacterScript';

export const NPC_RUNTIME_SERVICE = 'world.npc-runtime';

interface NpcVelocityBody extends Node2D {
  velocity: CharacterPoint;
}

interface NpcAnimationNode extends Node {
  readonly currentAnimation?: string;
  hasAnimation(animationId: string): boolean;
  play(animationId: string): void;
}

export interface NpcRuntimeRequest {
  readonly sourceNodeId: string;
  readonly characterId: string;
  readonly npcDefinitionId: string;
  readonly wanderSpeed: number;
  readonly pauseMinMs: number;
  readonly pauseMaxMs: number;
}

export interface NpcWanderAgent {
  readonly initialState?: NpcWanderState;
  step(
    state: NpcWanderState,
    input: Readonly<{ position: CharacterPoint; deltaMs: number; speed: number }>,
  ): NpcWanderStepResult;
  dispose(): void;
}

export interface NpcRuntimeService {
  acquire(request: NpcRuntimeRequest): NpcWanderAgent | undefined;
}

export interface NpcLockChanged {
  readonly locked: boolean;
  readonly lockCount: number;
}

/** Node-owned NPC movement and interaction-lock orchestration. */
export class NpcScript extends CharacterScript {
  readonly characterId: string;
  readonly npcDefinitionId: string;
  readonly wanderSpeed: number;
  readonly pauseMinMs: number;
  readonly pauseMaxMs: number;
  private bodyNode?: NpcVelocityBody;
  private animationNode?: NpcAnimationNode;
  private agent?: NpcWanderAgent;
  private wanderState: NpcWanderState = createNpcWanderState();
  private simulationPaused = false;
  private interactionLocks = 0;
  private activeAnimation = 'idle';

  constructor(context: NodeConstructionContext) {
    super(context);
    this.characterId = this.stringProperty('characterId', 'npc');
    this.npcDefinitionId = typeof context.properties.npcDefinitionId === 'string'
      ? context.properties.npcDefinitionId : this.characterId;
    this.wanderSpeed = Math.max(0, this.numberProperty('wanderSpeed', 0));
    this.pauseMinMs = Math.max(0, this.numberProperty('pauseMinMs', 0));
    this.pauseMaxMs = Math.max(this.pauseMinMs, this.numberProperty('pauseMaxMs', this.pauseMinMs));
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.bodyNode = requireNpcBody(this.getReference<Node>('body')?.configuredTarget, this.runtimeId);
    this.animationNode = requireNpcAnimation(this.getReference<Node>('animation')?.configuredTarget, this.runtimeId);
    const agent = this.service<NpcRuntimeService>(NPC_RUNTIME_SERVICE).acquire({
      sourceNodeId: this.runtimeId,
      characterId: this.characterId,
      npcDefinitionId: this.npcDefinitionId,
      wanderSpeed: this.wanderSpeed,
      pauseMinMs: this.pauseMinMs,
      pauseMaxMs: this.pauseMaxMs,
    });
    this.agent = agent;
    if (agent) {
      this.wanderState = agent.initialState ?? createNpcWanderState();
      this.entryDisposables.add(() => agent.dispose());
    }
    this.add_to_group('npc');
    this.add_to_group('interactable');
    this.set_physics_process(true);
    this.playAnimation('idle');
  }

  override _physics_process(deltaSeconds: number): void {
    const body = this.requireBody();
    if (this.isPaused() || !this.agent) {
      body.velocity = { x: 0, y: 0 };
      this.playAnimation('idle');
      return;
    }
    const result = this.agent.step(this.wanderState, {
      position: body.get_global_transform().position,
      deltaMs: deltaSeconds * 1000,
      speed: this.wanderSpeed,
    });
    this.wanderState = result.state;
    body.velocity = { ...result.velocity };
    this.playAnimation(result.animation);
  }

  override _exit_tree(): void {
    this.set_physics_process(false);
    if (this.bodyNode) this.bodyNode.velocity = { x: 0, y: 0 };
    this.agent = undefined;
    this.animationNode = undefined;
    this.bodyNode = undefined;
  }

  getPosition(): CharacterPoint {
    return { ...this.requireBody().get_global_transform().position };
  }

  isActive(): boolean {
    return this.is_inside_tree() && !this.is_freed();
  }

  setSimulationPaused(paused: boolean): void {
    this.simulationPaused = paused;
    if (this.isPaused() && this.bodyNode) this.bodyNode.velocity = { x: 0, y: 0 };
  }

  acquireInteractionLock(): () => void {
    if (!this.isActive()) return () => undefined;
    this.interactionLocks += 1;
    this.bodyNode!.velocity = { x: 0, y: 0 };
    this.playAnimation('idle');
    this.emitLockChanged();
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.interactionLocks = Math.max(0, this.interactionLocks - 1);
      if (this.isActive()) this.emitLockChanged();
    };
  }

  get interactionLocked(): boolean {
    return this.interactionLocks > 0;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): NpcScript {
    return new NpcScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }

  private isPaused(): boolean {
    return this.simulationPaused || this.interactionLocks > 0;
  }

  private requireBody(): NpcVelocityBody {
    if (!this.bodyNode) throw new Error(`NpcScript '${this.runtimeId}' is outside the scene tree.`);
    return this.bodyNode;
  }

  private playAnimation(animationId: string): void {
    const animation = this.animationNode;
    if (!animation || this.activeAnimation === animationId && animation.currentAnimation === animationId) return;
    if (!animation.hasAnimation(animationId)) return;
    animation.play(animationId);
    this.activeAnimation = animationId;
  }

  private emitLockChanged(): void {
    this.getSignal<NpcLockChanged>('interaction_lock_changed')?.emit({
      locked: this.interactionLocked,
      lockCount: this.interactionLocks,
    });
  }
}

function requireNpcBody(node: Node | undefined, ownerId: string): NpcVelocityBody {
  if (!node || !node.has_runtime_capability('character-body') || !('velocity' in node) || !('get_global_transform' in node)) {
    throw new Error(`NpcScript '${ownerId}' requires a CharacterBody2D body reference.`);
  }
  return node as NpcVelocityBody;
}

function requireNpcAnimation(node: Node | undefined, ownerId: string): NpcAnimationNode {
  if (!node || !('hasAnimation' in node) || !('play' in node)) {
    throw new Error(`NpcScript '${ownerId}' requires an AnimationPlayer reference.`);
  }
  return node as NpcAnimationNode;
}
