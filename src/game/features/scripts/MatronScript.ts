import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { DamageCommit } from '../combat/DamageReceiver';
import { clampToBossArena } from '../bosses/BossCampBehavior';
import type { CircleSensorShape } from '../../runtime/scene/physics/SensorGeometry';
import { EnemyScript } from './EnemyScript';

type MatronPhase = 'fight' | 'volley-telegraph' | 'volley-rest' | 'dead';

interface VolleyPoint {
  readonly x: number;
  readonly y: number;
}

/**
 * The Orb-Weaver Matron (roadmap 8.7, spec docs/superpowers/specs/2026-10-01-orb-weaver-matron.md).
 * Between volleys she fights like an orb-weaver (keeps her distance and spits
 * webs: the common ranged attack with its wind-up). Every `volleyCadenceMs` she
 * stops, marks `volleyPoints` circles on the ground (one under the slime) for
 * `volleyTelegraphMs`, then webs land: a slime inside a circle is hit, and each
 * circle becomes a web patch effect (`patchEffectId`) that catches a normal
 * slime and lets the Sticky form through. She rests `volleyRestMs` afterwards.
 */
export class MatronScript extends EnemyScript {
  private phaseValue: MatronPhase = 'fight';
  private phaseStartedAt = 0;
  private nextVolleyAt = 0;
  private volley: readonly VolleyPoint[] = [];
  private volleySequence = 0;

  get phase(): MatronPhase { return this.phaseValue; }

  override _enter_tree(): void {
    super._enter_tree();
    this.nextVolleyAt = this.simulationTime + Math.max(1, this.numberProperty('firstVolleyDelayMs', 3500));
  }

  override _physics_process(deltaSeconds: number): void {
    super._physics_process(deltaSeconds);
    if (this.defeated || this.phaseValue === 'dead') return;
    const time = this.simulationTime;

    if (this.phaseValue === 'fight') {
      // Never mid-spit; while walking back into her arena she waits.
      if (this.returningToArena || time < this.nextVolleyAt || this.attacking) return;
      const target = this.currentTarget();
      if (!target?.active || !target.hostile) return;
      this.beginVolley(time, target.position);
      return;
    }

    this.body().velocity = { x: 0, y: 0 };
    if (this.phaseValue === 'volley-telegraph') {
      if (time - this.phaseStartedAt >= Math.max(500, this.numberProperty('volleyTelegraphMs', 900))) this.landVolley(time);
      return;
    }
    if (this.phaseValue === 'volley-rest' && time - this.phaseStartedAt >= Math.max(1, this.numberProperty('volleyRestMs', 1300))) {
      this.nextVolleyAt = time + Math.max(1, this.numberProperty('volleyCadenceMs', 6500));
      this.transitionTo('fight', time);
    }
  }

  /** Marks the circles: one on the slime, the rest around it, inside the arena. */
  beginVolley(time: number, at: Readonly<{ x: number; y: number }>): boolean {
    if (this.defeated || this.phaseValue !== 'fight') return false;
    this.cancelAttack();
    const count = Math.max(1, Math.round(this.numberProperty('volleyPoints', 4)));
    const spread = Math.max(0, this.numberProperty('volleySpread', 170));
    const arena = this.arena();
    const turn = (this.volleySequence * 0.9) % (Math.PI * 2);
    const points: VolleyPoint[] = [{ x: at.x, y: at.y }];
    for (let index = 1; index < count; index += 1) {
      const angle = turn + ((index - 1) / Math.max(1, count - 1)) * Math.PI * 2;
      points.push({ x: at.x + Math.cos(angle) * spread, y: at.y + Math.sin(angle) * spread });
    }
    this.volley = points.map((point) => (arena ? clampToBossArena(arena, point) : point));
    this.volleySequence += 1;
    this.showTelegraph(this.volleyShapes(), at);
    this.playAnimation('attack-side', true);
    this.transitionTo('volley-telegraph', time);
    return true;
  }

  private landVolley(time: number): void {
    this.clearTelegraph();
    const shapes = this.volleyShapes();
    const target = this.currentTarget();
    if (target?.active && this.targetOverlapsShapes(shapes, target)) {
      this.routeImmediateAttack(target, {
        baseDamage: this.numberProperty('volleyDamage', 20),
        knockbackStrength: this.numberProperty('volleyKnockbackStrength', 120),
        impactEffect: false,
      });
    }
    const patch = this.stringProperty('patchEffectId', '');
    for (const point of this.volley) this.spawnEffectAt(patch, point);
    this.shakeCamera(80, 0.002);
    this.transitionTo('volley-rest', time);
  }

  private volleyShapes(): readonly CircleSensorShape[] {
    const radius = Math.max(8, this.numberProperty('volleyRadius', 56));
    return this.volley.map((point, index) => ({
      shapeId: `${this.runtimeId}/volley-${index}` as RuntimeNodeId,
      shape: 'circle' as const,
      centerX: point.x,
      centerY: point.y,
      radius,
    }));
  }

  /** A boss keeps her pattern: hits flash and show their damage but never cancel a volley or stagger her. */
  protected override reactToDamage(commit: DamageCommit, _defeated: boolean): void {
    this.showHitFeedback(commit);
  }

  protected override canRunCommonAttack(): boolean { return this.phaseValue === 'fight'; }

  protected override defeat(): void {
    if (this.defeated) return;
    this.clearTelegraph();
    super.defeat();
    this.transitionTo('dead', this.simulationTime);
  }

  override _exit_tree(): void {
    this.clearTelegraph();
    super._exit_tree();
  }

  private transitionTo(phase: MatronPhase, time: number): void {
    this.phaseValue = phase;
    this.phaseStartedAt = time;
    this.getSignal<{ phase: MatronPhase; time: number }>('phase_changed')?.emit({ phase, time });
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): MatronScript {
    return new MatronScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
