import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';
import { controlLabel, controlVerb, movementLabel } from '../player/ControlLabels';

export type ControlHintId = 'move' | 'interact' | 'attack' | 'dodge' | 'inventory' | 'crafting';

export interface ControlHintDefinition {
  readonly id: ControlHintId;
  /** Read when shown, so the key names always match the binding table. */
  readonly text: string;
}

function hint(id: ControlHintId, text: () => string): ControlHintDefinition {
  return Object.freeze({ id, get text() { return text(); } });
}

/** In priority order: when several are useful at once, the first unlearned one shows. */
export const CONTROL_HINTS: readonly ControlHintDefinition[] = Object.freeze([
  hint('move', () => `Move with ${movementLabel()}`),
  hint('interact', () => `${controlVerb('interact')} to talk, open or use`),
  hint('attack', () => `${controlVerb('attack')} to attack`),
  hint('dodge', () => `Press ${controlLabel('dodge')} to roll out of danger`),
  hint('inventory', () => `Press ${controlLabel('menu')} to open your bag`),
  hint('crafting', () => `Press ${controlLabel('menu')}, then Crafting, to craft`),
]);

export interface ControlHintState {
  /** True once the player has used this control in this run (saved with the run). */
  isLearned(id: ControlHintId): boolean;
  learn(id: ControlHintId): void;
  /** True while the hint would help right now (an F prompt shows, an enemy is near, …). */
  isRelevant(id: ControlHintId): boolean;
}

export const CONTROL_HINT_SURFACE_ID = 'control-hint';

/**
 * First-time control hints. Each hint shows while it is relevant and the
 * player has not used that control yet; using it (`learn`) hides it for good
 * in this run. One hint shows at a time. The presentation fades through the
 * `control-hint` UI scene.
 */
export class ControlHintsController implements UiSurfacePort {
  private current?: ControlHintDefinition;
  private lastText = '';
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();

  constructor(private readonly state: ControlHintState) {}

  get showing(): ControlHintId | undefined { return this.current?.id; }

  /** Picks the hint to show now; call once per frame while the player can act. */
  update(): void {
    const next = CONTROL_HINTS.find((hint) => !this.state.isLearned(hint.id) && this.state.isRelevant(hint.id));
    if (next === this.current) return;
    this.current = next;
    if (next) this.lastText = next.text;
    this.publish();
  }

  /** The player used a control: its hint never returns in this run. */
  learn(id: ControlHintId): void {
    if (this.state.isLearned(id)) return;
    this.state.learn(id);
    if (this.current?.id === id) {
      this.current = undefined;
      this.publish();
    }
  }

  /** Hides any hint (menus, title, defeat) until the next update. */
  hide(): void {
    if (!this.current) return;
    this.current = undefined;
    this.publish();
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== CONTROL_HINT_SURFACE_ID) return {};
    // Keep the last text while fading out, so the words do not vanish before the panel.
    return { text: this.current?.text ?? this.lastText, opacity: this.current ? 1 : 0 };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== CONTROL_HINT_SURFACE_ID) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(): void {}

  private publish(): void {
    const model = this.snapshot(CONTROL_HINT_SURFACE_ID);
    for (const listener of this.listeners) listener(model);
  }
}
