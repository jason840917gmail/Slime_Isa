import { GULP_FORMS, gulpFormForMaterial, type GulpFormDefinition } from '../../content/gulp/gulpForms';
import { controlLabel } from '../player/ControlLabels';

export interface GulpPoint {
  readonly x: number;
  readonly y: number;
}

/** A world object that can be eaten from any number of times. */
export interface GulpSpot extends GulpPoint {
  readonly materialItemId: string;
  /** Distance from the spot within which the mouth (Q) eats from it. */
  readonly radius: number;
  /** How far above the spot its "[Q] Gulp" hint floats. */
  readonly badgeRise?: number;
}

export type GulpEndReason = 'burp' | 'expired' | 'switched' | 'cleared';

export interface GulpContext {
  /** Gameplay clock in ms; stands still while the simulation is paused. */
  now(): number;
  readonly formDurationMs: number;
  playerPosition(): GulpPoint;
  spots(): Iterable<GulpSpot>;
  inventoryCount(itemId: string): number;
  /** Removes one of `itemId` from the inventory; false if it could not. */
  consume(itemId: string): boolean;
  /** The form started, was refreshed, or ended (`form` undefined). */
  onFormChanged(form: GulpFormDefinition | undefined, reason: GulpEndReason | 'started' | 'refreshed'): void;
  showMessage(text: string): void;
}

/** One carried Gulp material on the quick wheel. */
export interface GulpWheelEntry {
  readonly itemId: string;
  readonly form: GulpFormDefinition;
  readonly count: number;
}

/** What one press of the mouth (Q) did. */
export type GulpEatResult = 'spot' | 'inventory' | 'burp' | 'nothing';

/**
 * The slime's mouth (the `eat` control, Q). Tap near a Gulp spot to eat from the world for free;
 * tap while in a form, away from a spot, to burp the form away; a tap anywhere
 * else only says how to gulp. Carried materials are eaten from the quick wheel
 * (hold Q: `wheelEntries`, `eatMaterial`). A form ends by itself after
 * `formDurationMs`.
 */
export class GulpController {
  private form?: GulpFormDefinition;
  private endsAt = 0;
  private lastMaterialItemId = GULP_FORMS[0]?.materialItemId;

  constructor(private readonly ctx: GulpContext) {}

  get activeForm(): GulpFormDefinition | undefined {
    return this.form;
  }

  /** Milliseconds left in the current form, or 0. */
  remainingMs(): number {
    return this.form ? Math.max(0, this.endsAt - this.ctx.now()) : 0;
  }

  eat(): GulpEatResult {
    const spot = this.nearestSpot();
    if (spot) {
      const form = gulpFormForMaterial(spot.materialItemId);
      if (!form) return 'nothing';
      this.become(form);
      return 'spot';
    }
    if (this.form) {
      this.end('burp');
      return 'burp';
    }
    // Carried materials are only eaten from the quick wheel (hold Q), never by a
    // stray tap: the owner kept turning Heavy far from any rock (2026-09-30).
    this.ctx.showMessage(this.carriedMaterial() ? `No Gulp spot here. Hold ${controlLabel('eat')} to eat what you carry` : 'Nothing to gulp here');
    return 'nothing';
  }

  /**
   * Eats one carried `itemId` (the quick wheel's choice): takes its form, or
   * refreshes it, or switches from another form. Costs one from the inventory.
   */
  eatMaterial(itemId: string): GulpEatResult {
    const form = gulpFormForMaterial(itemId);
    if (!form || this.ctx.inventoryCount(itemId) < 1 || !this.ctx.consume(itemId)) return 'nothing';
    this.become(form);
    return 'inventory';
  }

  /** The carried Gulp materials, one entry per form, for the quick wheel (form order). */
  wheelEntries(): readonly GulpWheelEntry[] {
    return GULP_FORMS
      .map((form) => ({ itemId: form.materialItemId, form, count: this.ctx.inventoryCount(form.materialItemId) }))
      .filter((entry) => entry.count > 0);
  }

  /** The last-used carried Gulp material (the quick wheel's starting choice). */
  get preferredMaterial(): string | undefined {
    return this.carriedMaterial();
  }

  /** Ends an expired form. Call once per frame. */
  update(): void {
    if (this.form && this.ctx.now() >= this.endsAt) this.end('expired');
  }

  /** Drops the form without a burp (defeat, map change). */
  clear(): void {
    if (this.form) this.end('cleared');
  }

  /** The Gulp spot within reach, if any: the one nearest the player. */
  nearestSpot(): GulpSpot | undefined {
    const player = this.ctx.playerPosition();
    let nearest: GulpSpot | undefined;
    let nearestDistance = Number.POSITIVE_INFINITY;
    for (const spot of this.ctx.spots()) {
      const distance = Math.hypot(spot.x - player.x, spot.y - player.y);
      if (distance <= spot.radius && distance < nearestDistance) {
        nearest = spot;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  private become(form: GulpFormDefinition): void {
    const previous = this.form;
    if (previous && previous.id !== form.id) this.ctx.onFormChanged(undefined, 'switched');
    this.form = form;
    this.endsAt = this.ctx.now() + this.ctx.formDurationMs;
    this.lastMaterialItemId = form.materialItemId;
    this.ctx.onFormChanged(form, previous?.id === form.id ? 'refreshed' : 'started');
  }

  private end(reason: GulpEndReason): void {
    this.form = undefined;
    this.endsAt = 0;
    this.ctx.onFormChanged(undefined, reason);
  }

  /** The last-used material if still carried, otherwise any carried Gulp material. */
  private carriedMaterial(): string | undefined {
    const candidates = [this.lastMaterialItemId, ...GULP_FORMS.map((form) => form.materialItemId)];
    return candidates.find((itemId): itemId is string => itemId !== undefined && this.ctx.inventoryCount(itemId) > 0);
  }
}
