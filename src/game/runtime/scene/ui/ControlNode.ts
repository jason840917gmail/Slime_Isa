import type { RuntimeNodeId } from '../../../content/scenes/identifiers';
import type { JsonValue } from '../../../content/scenes/types';
import { Node, type NodeOptions } from '../Node';
import type { InputControl, InputRouter } from '../input/InputRouter';
import type { InputEvent } from '../input/InputEvent';

export interface ControlLayout {
  readonly anchorMin: Readonly<{ x: number; y: number }>;
  readonly anchorMax: Readonly<{ x: number; y: number }>;
  readonly offsetMin: Readonly<{ x: number; y: number }>;
  readonly offsetMax: Readonly<{ x: number; y: number }>;
}

export interface ControlPresentation {
  enter(control: ControlNode): () => void;
  synchronize(control: ControlNode): void;
}

export interface ControlNodeOptions extends NodeOptions {
  readonly inputRouter?: InputRouter;
  readonly presentation?: ControlPresentation;
  readonly layout?: Partial<ControlLayout>;
  readonly visible?: boolean;
  readonly opacity?: number;
  readonly scale?: number;
  readonly focused?: boolean;
  readonly modal?: boolean;
  readonly consumeInput?: boolean;
  readonly processWhenPaused?: boolean;
  readonly inputPriority?: number;
  readonly onInput?: (event: InputEvent) => boolean | void;
  readonly theme?: Readonly<Record<string, JsonValue>>;
}

const ZERO = { x: 0, y: 0 } as const;

export class ControlNode extends Node implements InputControl {
  layout: ControlLayout;
  visible: boolean;
  opacity: number;
  scale: number;
  focused: boolean;
  modal: boolean;
  consumeInput: boolean;
  readonly theme: Readonly<Record<string, JsonValue>>;
  private readonly priority: number;

  constructor(private readonly controlOptions: ControlNodeOptions) {
    super(controlOptions);
    this.layout = {
      anchorMin: controlOptions.layout?.anchorMin ?? ZERO,
      anchorMax: controlOptions.layout?.anchorMax ?? ZERO,
      offsetMin: controlOptions.layout?.offsetMin ?? ZERO,
      offsetMax: controlOptions.layout?.offsetMax ?? ZERO,
    };
    this.visible = controlOptions.visible ?? true;
    this.opacity = controlOptions.opacity ?? 1;
    if (!Number.isFinite(this.opacity) || this.opacity < 0 || this.opacity > 1) throw new Error('Control opacity must be between 0 and 1');
    this.scale = controlOptions.scale ?? 1;
    if (!Number.isFinite(this.scale) || this.scale <= 0) throw new Error('Control scale must be positive');
    this.focused = controlOptions.focused ?? false;
    this.modal = controlOptions.modal ?? false;
    this.consumeInput = controlOptions.consumeInput ?? false;
    this.theme = Object.freeze(structuredClone(controlOptions.theme ?? {}));
    this.priority = controlOptions.inputPriority ?? 1000;
    for (const point of Object.values(this.layout)) if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) throw new Error('Control layout values must be finite');
    this.set_process_input(true);
    this.set_process(true);
    this.set_process_when_paused(controlOptions.processWhenPaused ?? true);
    this.set_input_priority(this.priority);
  }

  setLayoutOffset(edge: 'offsetMin' | 'offsetMax', value: Readonly<{ x: number; y: number }>): void {
    if (!Number.isFinite(value.x) || !Number.isFinite(value.y)) throw new Error('Control layout offsets must be finite');
    this.layout = { ...this.layout, [edge]: { x: value.x, y: value.y } };
  }

  get routedInputPriority(): number { return this.priority; }
  get inputVisible(): boolean {
    if (!this.is_inside_tree()) return false;
    let current: Node | undefined = this;
    while (current) {
      if (current instanceof ControlNode && !current.visible) return false;
      current = current.get_parent();
    }
    return true;
  }
  get processInputWhenPaused(): boolean { return this.can_process_while_paused(); }
  get inputFocused(): boolean { return this.focused; }
  get inputModal(): boolean { return this.modal; }
  get inputModalDepth(): number {
    let depth = 0;
    let current: Node | undefined = this;
    while (current) {
      if (current instanceof ControlNode && current.modal && current.visible) depth += 1;
      current = current.get_parent();
    }
    return depth;
  }

  override _enter_tree(): void {
    if (this.controlOptions.inputRouter) this.entryDisposables.add(this.controlOptions.inputRouter.registerControl(this));
    if (this.controlOptions.presentation) this.entryDisposables.add(this.controlOptions.presentation.enter(this));
  }

  override _process(): void { this.controlOptions.presentation?.synchronize(this); }

  override _input(event: InputEvent): void {
    if (event.controlRouted || !this.inputVisible || (!this.focused && !this.modal)) return;
    this.handleRoutedInput(event);
  }

  handleRoutedInput(event: InputEvent): void {
    if (!this.inputVisible) return;
    if (this.controlOptions.onInput?.(event) === true || this.consumeInput) event.handled = true;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): ControlNode {
    return new ControlNode({ ...this.controlOptions, runtimeId, name: this.name, layout: this.layout, visible: this.visible, opacity: this.opacity, scale: this.scale, focused: this.focused, modal: this.modal, consumeInput: this.consumeInput, processWhenPaused: this.can_process_while_paused(), inputPriority: this.priority });
  }
}
