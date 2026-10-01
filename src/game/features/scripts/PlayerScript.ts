import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import type { Node } from '../../runtime/scene/Node';
import type { SceneTreeInputEvent } from '../../runtime/scene/SceneTree';
import type { InputEvent } from '../../runtime/scene/input/InputEvent';
import type { PhysicsContact } from '../../runtime/scene/physics/PhysicsContact';
import type { SensorShape } from '../../runtime/scene/physics/SensorGeometry';
import type {
  DamageCommit,
  DamageMitigationInput,
  DamageReceiver,
  DamageStateDecision,
} from '../combat/DamageReceiver';
import type { DamageRouter } from '../combat/DamageRouter';
import type { PlayerActorPort } from '../player/PlayerServicePorts';
import { isPlayerInputAction, type PlayerInputAction } from '../player/PlayerInputActions';
import { WheelStepper } from '../player/WheelStepper';
import { GAME_CONSTANTS } from '../../Constant';
import {
  PlayerNodePorts,
  requirePlayerAnimationNode,
  requirePlayerBoundsNode,
  requirePlayerVelocityBody,
} from '../player/PlayerNodePorts';
import { CharacterScript, type CharacterPoint } from './CharacterScript';
import { DAMAGE_ROUTER_SERVICE } from './EnemyScript';
import { CollectibleScript } from './CollectibleScript';

export const PLAYER_HEALTH_SERVICE = 'player.health-receiver';

export interface PlayerHealthChanged {
  readonly hp: number;
  readonly maxHp: number;
}

export class PlayerScript extends CharacterScript implements DamageReceiver, PlayerActorPort {
  readonly playerName: string;
  private health?: DamageReceiver;
  private ports?: PlayerNodePorts;
  private simulationTimeMs = 0;
  private dodgeUntilMs = 0;
  private rollUntilMs = 0;
  private movementSuppressedUntilMs = 0;
  private readonly heldInput = new Set<PlayerInputAction>();
  /** Presses not yet used, with the simulation time they were made. */
  private readonly pressedInput = new Map<PlayerInputAction, number>();
  private readonly wheel = new WheelStepper(() => GAME_CONSTANTS.input.weaponWheelStepLockMs);

  constructor(context: NodeConstructionContext) {
    super(context);
    this.playerName = this.stringProperty('playerName', 'Player');
    this.registerSignalHandler<PhysicsContact>('on_pickup_area_entered', (contact) => {
      const collectible = contact.other?.get_parent()?.get_children()
        .find((node) => node instanceof CollectibleScript);
      if (collectible instanceof CollectibleScript) collectible.requestPickup(contact.observerId);
    });
  }

  get runtimeNodeId(): string { return this.runtimeId; }
  get simulationTime(): number { return this.simulationTimeMs; }
  get damageAreaNodeId(): string {
    const target = this.getReference<Node>('damageArea')?.configuredTarget;
    if (!target) throw new Error(`PlayerScript '${this.runtimeId}' requires its damageArea reference.`);
    return target.runtimeId;
  }

  /** World-space hurtbox shapes (the damage area's enabled collision shapes). */
  get damageShapes(): readonly SensorShape[] {
    const target = this.getReference<Node>('damageArea')?.configuredTarget as (Node & { contactShapes?: () => readonly SensorShape[] }) | undefined;
    return typeof target?.contactShapes === 'function' ? target.contactShapes() : [];
  }

  override _enter_tree(): void {
    super._enter_tree();
    const damageRouter = this.service<DamageRouter>(DAMAGE_ROUTER_SERVICE);
    this.health = this.service<DamageReceiver>(PLAYER_HEALTH_SERVICE);
    const body = requirePlayerVelocityBody(this.getReference<Node>('body')?.configuredTarget, this.runtimeId);
    const damageArea = requirePlayerBoundsNode(this.getReference<Node>('damageArea')?.configuredTarget, this.runtimeId);
    const animation = requirePlayerAnimationNode(this.getReference<Node>('animation')?.configuredTarget, this.runtimeId);
    this.ports = new PlayerNodePorts(body, damageArea, animation, () => this.isDodging());
    damageRouter.registerArea(this, {
      areaNodeId: damageArea.runtimeId,
      priority: 0,
      damageMultiplier: 1,
    });
    this.entryDisposables.add(() => damageRouter.unregisterArea(this, damageArea.runtimeId));
    this.add_to_group('player');
    this.add_to_group('damage-target');
    this.set_physics_process(true);
    this.set_process_unhandled_input(true);
  }

  override _physics_process(deltaSeconds: number): void {
    this.simulationTimeMs += deltaSeconds * 1000;
  }

  override _unhandled_input(event: SceneTreeInputEvent): void {
    const input = event as InputEvent;
    if (!isPlayerInputAction(input.action)) return;
    if (input.type === 'wheel') {
      if (this.wheel.step(input.action, input.wheelDelta ?? 0, input.timestamp)) this.pressedInput.set(input.action, this.simulationTimeMs);
      event.handled = true;
      return;
    }
    if (input.pressed) {
      if (!this.heldInput.has(input.action)) this.pressedInput.set(input.action, this.simulationTimeMs);
      this.heldInput.add(input.action);
    }
    if (input.released) this.heldInput.delete(input.action);
    event.handled = true;
  }

  override _exit_tree(): void {
    this.set_physics_process(false);
    this.set_process_unhandled_input(false);
    this.clearInput();
    this.ports?.stop();
    this.ports = undefined;
    this.health = undefined;
  }

  getPosition(): CharacterPoint {
    return this.requirePorts().getPosition();
  }

  getBodyBounds(): Readonly<{ x: number; y: number; width: number; height: number }> {
    return this.requirePorts().getBodyBounds();
  }

  isDodging(): boolean {
    return this.simulationTimeMs < this.dodgeUntilMs;
  }

  /** Knockback or a dodge roll owns the body: movement keys and actions wait. */
  isMovementSuppressed(): boolean {
    return this.simulationTimeMs < this.movementSuppressedUntilMs || this.isRolling();
  }

  move(direction: CharacterPoint, speed: number): boolean {
    if (this.isMovementSuppressed()) return false;
    this.requirePorts().setVelocity(direction, speed);
    if (direction.x !== 0 || direction.y !== 0) this.requirePorts().play('walk');
    else this.requirePorts().play('idle');
    return true;
  }

  stopMovement(): void {
    this.requirePorts().stop();
  }

  playAnimation(animationId: string, forceRestart = false): boolean {
    return this.requirePorts().play(animationId, forceRestart);
  }

  getMovementInput(): CharacterPoint {
    return {
      x: Number(this.heldInput.has('move-right')) - Number(this.heldInput.has('move-left')),
      y: Number(this.heldInput.has('move-down')) - Number(this.heldInput.has('move-up')),
    };
  }

  isActionPressed(action: string): boolean {
    return isPlayerInputAction(action) && this.heldInput.has(action);
  }

  /**
   * Uses a press of `action`. A press older than `input.bufferMs` (made during
   * knockback, an action lock or the Gulp wheel) is dropped instead of firing late.
   */
  consumeActionPress(action: string): boolean {
    if (!isPlayerInputAction(action)) return false;
    const pressedAt = this.pressedInput.get(action);
    if (pressedAt === undefined) return false;
    this.pressedInput.delete(action);
    return this.simulationTimeMs - pressedAt <= GAME_CONSTANTS.input.bufferMs;
  }

  clearInput(): void {
    this.heldInput.clear();
    this.pressedInput.clear();
    this.wheel.reset();
  }

  teleport(position: CharacterPoint): void {
    this.requirePorts().stop();
    this.requirePorts().teleport(position);
  }

  /**
   * Rolls along `direction` for `durationMs`: movement keys are ignored for the
   * whole roll, and damage only for its first `invulnerabilityMs`.
   */
  beginDodge(direction: CharacterPoint, speed: number, durationMs: number, invulnerabilityMs: number): boolean {
    if (this.isMovementSuppressed() || !Number.isFinite(durationMs) || durationMs <= 0
      || !Number.isFinite(invulnerabilityMs) || invulnerabilityMs < 0) return false;
    this.dodgeUntilMs = Math.max(this.dodgeUntilMs, this.simulationTimeMs + Math.min(invulnerabilityMs, durationMs));
    this.rollUntilMs = Math.max(this.rollUntilMs, this.simulationTimeMs + durationMs);
    this.requirePorts().setVelocity(direction, speed);
    this.requirePorts().play('roll');
    return true;
  }

  /** True for the whole roll, including the recovery after the invulnerable part. */
  isRolling(): boolean {
    return this.simulationTimeMs < this.rollUntilMs;
  }

  applyKnockback(direction: CharacterPoint, strength: number, durationMs: number): void {
    if (!Number.isFinite(durationMs) || durationMs < 0) throw new Error('Player knockback duration must be a finite non-negative number.');
    this.movementSuppressedUntilMs = Math.max(this.movementSuppressedUntilMs, this.simulationTimeMs + durationMs);
    this.requirePorts().applyKnockback(direction, strength, durationMs);
  }

  getDamageState() {
    return this.requireHealth().getDamageState();
  }

  canReceiveDamage(input: DamageMitigationInput): DamageStateDecision {
    if (this.isDodging()) return { accepted: false, reason: 'state-blocked' };
    return this.requireHealth().canReceiveDamage?.(input) ?? { accepted: true };
  }

  mitigateDamage(input: DamageMitigationInput): number {
    return this.requireHealth().mitigateDamage?.(input) ?? input.scaledDamage;
  }

  commitDamage(commit: DamageCommit): void {
    this.requireHealth().commitDamage(commit);
    const state = this.getDamageState();
    this.getSignal<PlayerHealthChanged>('health_changed')?.emit({ hp: state.hp, maxHp: state.maxHp });
    this.getSignal<DamageCommit>('damaged')?.emit(commit);
    if (state.dead) this.getSignal<{ receiverNodeId: string }>('defeated')?.emit({ receiverNodeId: this.runtimeId });
  }

  publishDamageFeedback(commit: DamageCommit): void {
    this.requireHealth().publishDamageFeedback?.(commit);
    this.getSignal<DamageCommit>('damage_feedback')?.emit(commit);
  }

  private requirePorts(): PlayerNodePorts {
    if (!this.ports) throw new Error(`PlayerScript '${this.runtimeId}' is outside the scene tree.`);
    return this.ports;
  }

  private requireHealth(): DamageReceiver {
    if (!this.health) throw new Error(`PlayerScript '${this.runtimeId}' has no health service.`);
    return this.health;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): PlayerScript {
    return new PlayerScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
