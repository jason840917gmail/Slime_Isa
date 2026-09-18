import type { RuntimeNodeId } from '../../../content/scenes/identifiers';
import type { JsonValue } from '../../../content/scenes/types';
import { ControlNode, type ControlNodeOptions } from '../../../runtime/scene/ui/ControlNode';
import type { InputEvent } from '../../../runtime/scene/input/InputEvent';

export type UiAxis = 'horizontal' | 'vertical';
export type UiAlignment = 'start' | 'center' | 'end' | 'stretch';
export type UiTextAlignment = 'left' | 'center' | 'right';
export type UiTone = 'default' | 'muted' | 'accent' | 'info' | 'warning' | 'danger' | 'special';

export interface StyledControlOptions extends ControlNodeOptions {
  readonly styleClass?: string;
  readonly ariaLabel?: string;
  readonly tooltip?: string;
  readonly zIndex?: number;
}

export class StyledControlNode extends ControlNode {
  readonly styleClass: string;
  readonly ariaLabel: string;
  readonly tooltip: string;
  readonly zIndex: number;

  constructor(protected readonly styledOptions: StyledControlOptions) {
    super(styledOptions);
    this.styleClass = styledOptions.styleClass ?? '';
    this.ariaLabel = styledOptions.ariaLabel ?? '';
    this.tooltip = styledOptions.tooltip ?? '';
    this.zIndex = styledOptions.zIndex ?? 0;
    if (!Number.isSafeInteger(this.zIndex)) throw new Error('Control zIndex must be an integer');
  }

  protected duplicateOptions(runtimeId: RuntimeNodeId): StyledControlOptions {
    return {
      ...this.styledOptions,
      runtimeId,
      name: this.name,
      layout: this.layout,
      visible: this.visible,
      focused: this.focused,
      modal: this.modal,
      consumeInput: this.consumeInput,
      processWhenPaused: this.can_process_while_paused(),
      inputPriority: this.routedInputPriority,
      styleClass: this.styleClass,
      ariaLabel: this.ariaLabel,
      tooltip: this.tooltip,
      zIndex: this.zIndex,
    };
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): StyledControlNode {
    return new StyledControlNode(this.duplicateOptions(runtimeId));
  }
}

export interface ContainerControlOptions extends StyledControlOptions {
  readonly direction?: UiAxis | 'none';
  readonly gap?: number;
  readonly padding?: readonly [number, number, number, number];
  readonly align?: UiAlignment;
  readonly justify?: UiAlignment | 'space-between';
}

export class ContainerControlNode extends StyledControlNode {
  readonly direction: UiAxis | 'none';
  readonly gap: number;
  readonly padding: readonly [number, number, number, number];
  readonly align: UiAlignment;
  readonly justify: UiAlignment | 'space-between';

  constructor(protected readonly containerOptions: ContainerControlOptions) {
    super(containerOptions);
    this.direction = containerOptions.direction ?? 'none';
    this.gap = finiteNonNegative(containerOptions.gap ?? 0, 'Container gap');
    this.padding = containerOptions.padding ?? [0, 0, 0, 0];
    if (this.padding.length !== 4 || this.padding.some((value) => !Number.isFinite(value) || value < 0)) {
      throw new Error('Container padding requires four finite non-negative values');
    }
    this.align = containerOptions.align ?? 'stretch';
    this.justify = containerOptions.justify ?? 'start';
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): ContainerControlNode {
    return new ContainerControlNode({ ...this.containerOptions, ...this.duplicateOptions(runtimeId), direction: this.direction, gap: this.gap, padding: this.padding, align: this.align, justify: this.justify });
  }
}

export interface LabelControlOptions extends StyledControlOptions {
  readonly text?: string;
  readonly tone?: UiTone;
  readonly fontSize?: number;
  readonly fontWeight?: number;
  readonly textAlign?: UiTextAlignment;
  readonly wrap?: boolean;
}

export class LabelControlNode extends StyledControlNode {
  text: string;
  readonly tone: UiTone;
  readonly fontSize: number;
  readonly fontWeight: number;
  readonly textAlign: UiTextAlignment;
  readonly wrap: boolean;

  constructor(protected readonly labelOptions: LabelControlOptions) {
    super(labelOptions);
    this.text = labelOptions.text ?? '';
    this.tone = labelOptions.tone ?? 'default';
    this.fontSize = finitePositive(labelOptions.fontSize ?? 14, 'Label fontSize');
    this.fontWeight = finitePositive(labelOptions.fontWeight ?? 400, 'Label fontWeight');
    this.textAlign = labelOptions.textAlign ?? 'left';
    this.wrap = labelOptions.wrap ?? false;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): LabelControlNode {
    return new LabelControlNode({ ...this.labelOptions, ...this.duplicateOptions(runtimeId), text: this.text, tone: this.tone, fontSize: this.fontSize, fontWeight: this.fontWeight, textAlign: this.textAlign, wrap: this.wrap });
  }
}

export interface TextureRectControlOptions extends StyledControlOptions {
  readonly assetKey?: string;
  readonly frame?: number;
  readonly fit?: 'contain' | 'cover' | 'fill' | 'none';
  readonly alt?: string;
}

export class TextureRectControlNode extends StyledControlNode {
  readonly assetKey?: string;
  readonly frame: number;
  readonly fit: 'contain' | 'cover' | 'fill' | 'none';
  readonly alt: string;

  constructor(protected readonly textureOptions: TextureRectControlOptions) {
    super(textureOptions);
    this.assetKey = textureOptions.assetKey;
    this.frame = textureOptions.frame ?? 0;
    this.fit = textureOptions.fit ?? 'contain';
    this.alt = textureOptions.alt ?? '';
    if (!Number.isSafeInteger(this.frame) || this.frame < 0) throw new Error('TextureRect frame must be a non-negative integer');
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): TextureRectControlNode {
    return new TextureRectControlNode({ ...this.textureOptions, ...this.duplicateOptions(runtimeId), assetKey: this.assetKey, frame: this.frame, fit: this.fit, alt: this.alt });
  }
}

export interface ProgressBarControlOptions extends StyledControlOptions {
  readonly value?: number;
  readonly max?: number;
  readonly label?: string;
  readonly tone?: UiTone;
  readonly showValue?: boolean;
}

export class ProgressBarControlNode extends StyledControlNode {
  value: number;
  max: number;
  label: string;
  tone: UiTone;
  readonly showValue: boolean;

  constructor(protected readonly progressOptions: ProgressBarControlOptions) {
    super(progressOptions);
    this.value = finiteNonNegative(progressOptions.value ?? 0, 'ProgressBar value');
    this.max = finitePositive(progressOptions.max ?? 1, 'ProgressBar max');
    this.label = progressOptions.label ?? '';
    this.tone = progressOptions.tone ?? 'accent';
    this.showValue = progressOptions.showValue ?? false;
  }

  get ratio(): number { return Math.max(0, Math.min(1, this.value / this.max)); }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): ProgressBarControlNode {
    return new ProgressBarControlNode({ ...this.progressOptions, ...this.duplicateOptions(runtimeId), value: this.value, max: this.max, label: this.label, tone: this.tone, showValue: this.showValue });
  }
}

export interface ButtonControlOptions extends LabelControlOptions { readonly disabled?: boolean }

export class ButtonControlNode extends LabelControlNode {
  disabled: boolean;

  constructor(protected readonly buttonOptions: ButtonControlOptions) {
    super(buttonOptions);
    this.disabled = buttonOptions.disabled ?? false;
  }

  activate(): boolean {
    if (this.disabled || !this.visible) return false;
    this.getSignal<void>('pressed')?.emit();
    return true;
  }

  override handleRoutedInput(event: InputEvent): void {
    if (this.focused && event.type === 'key-down' && (event.key === 'Enter' || event.key === ' ')) {
      if (this.activate()) event.handled = true;
      return;
    }
    super.handleRoutedInput(event);
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): ButtonControlNode {
    return new ButtonControlNode({ ...this.buttonOptions, ...this.duplicateOptions(runtimeId), text: this.text, tone: this.tone, fontSize: this.fontSize, fontWeight: this.fontWeight, textAlign: this.textAlign, wrap: this.wrap, disabled: this.disabled });
  }
}

export interface UiListItem { readonly id: string; readonly label: string; readonly disabled?: boolean; readonly metadata?: JsonValue }

export interface ItemListControlOptions extends StyledControlOptions {
  readonly items?: readonly UiListItem[];
  readonly selectedIndex?: number;
  readonly columns?: number;
  readonly gap?: number;
}

export class ItemListControlNode extends StyledControlNode {
  items: readonly UiListItem[];
  selectedIndex: number;
  readonly columns: number;
  readonly gap: number;

  constructor(protected readonly listOptions: ItemListControlOptions) {
    super(listOptions);
    this.items = Object.freeze(structuredClone(listOptions.items ?? []));
    this.selectedIndex = listOptions.selectedIndex ?? -1;
    this.columns = listOptions.columns ?? 1;
    this.gap = finiteNonNegative(listOptions.gap ?? 8, 'ItemList gap');
    if (!Number.isSafeInteger(this.columns) || this.columns < 1) throw new Error('ItemList columns must be a positive integer');
    if (!Number.isSafeInteger(this.selectedIndex) || this.selectedIndex < -1 || this.selectedIndex >= this.items.length) throw new Error('ItemList selectedIndex is out of range');
  }

  select(index: number): boolean {
    const item = this.items[index];
    if (!item || item.disabled) return false;
    this.selectedIndex = index;
    this.getSignal<Readonly<{ index: number; item: UiListItem }>>('item_selected')?.emit({ index, item });
    return true;
  }

  override handleRoutedInput(event: InputEvent): void {
    if (!this.focused || event.type !== 'key-down') {
      super.handleRoutedInput(event);
      return;
    }
    const direction = event.key === 'ArrowLeft' ? -1
      : event.key === 'ArrowRight' ? 1
        : event.key === 'ArrowUp' ? -this.columns
          : event.key === 'ArrowDown' ? this.columns
            : 0;
    if (direction !== 0) {
      event.handled = this.selectNearest(this.selectedIndex < 0 ? (direction > 0 ? 0 : this.items.length - 1) : this.selectedIndex + direction, direction);
      return;
    }
    if (event.key === 'Home') { event.handled = this.selectNearest(0, 1); return; }
    if (event.key === 'End') { event.handled = this.selectNearest(this.items.length - 1, -1); return; }
    if (event.key === 'Enter' || event.key === ' ') { event.handled = this.select(this.selectedIndex); return; }
    super.handleRoutedInput(event);
  }

  private selectNearest(start: number, direction: number): boolean {
    for (let index = start; index >= 0 && index < this.items.length; index += direction) {
      if (this.select(index)) return true;
    }
    return false;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): ItemListControlNode {
    return new ItemListControlNode({ ...this.listOptions, ...this.duplicateOptions(runtimeId), items: this.items, selectedIndex: this.selectedIndex, columns: this.columns, gap: this.gap });
  }
}

export interface GridContainerControlOptions extends ContainerControlOptions { readonly columns?: number }

export class GridContainerControlNode extends ContainerControlNode {
  readonly columns: number;

  constructor(protected readonly gridOptions: GridContainerControlOptions) {
    super({ ...gridOptions, direction: 'none' });
    this.columns = gridOptions.columns ?? 1;
    if (!Number.isSafeInteger(this.columns) || this.columns < 1) throw new Error('GridContainer columns must be a positive integer');
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): GridContainerControlNode {
    return new GridContainerControlNode({ ...this.gridOptions, ...this.duplicateOptions(runtimeId), columns: this.columns, gap: this.gap, padding: this.padding, align: this.align, justify: this.justify });
  }
}

export interface ScrollContainerControlOptions extends ContainerControlOptions { readonly scrollAxis?: UiAxis }

export class ScrollContainerControlNode extends ContainerControlNode {
  readonly scrollAxis: UiAxis;

  constructor(protected readonly scrollOptions: ScrollContainerControlOptions) {
    super(scrollOptions);
    this.scrollAxis = scrollOptions.scrollAxis ?? 'vertical';
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): ScrollContainerControlNode {
    return new ScrollContainerControlNode({ ...this.scrollOptions, ...this.duplicateOptions(runtimeId), scrollAxis: this.scrollAxis, direction: this.direction, gap: this.gap, padding: this.padding, align: this.align, justify: this.justify });
  }
}

export interface ModalRootControlOptions extends ContainerControlOptions { readonly open?: boolean }

export class ModalRootControlNode extends ContainerControlNode {
  open: boolean;

  constructor(protected readonly modalOptions: ModalRootControlOptions) {
    super({ ...modalOptions, modal: true, consumeInput: true, processWhenPaused: true });
    this.open = modalOptions.open ?? false;
    this.visible = this.open;
  }

  setOpen(open: boolean): void { this.open = open; this.visible = open; }

  override handleRoutedInput(event: InputEvent): void {
    if (this.open && event.type === 'key-down' && event.key === 'Escape') {
      this.getSignal<void>('close_requested')?.emit();
      event.handled = true;
      return;
    }
    super.handleRoutedInput(event);
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): ModalRootControlNode {
    return new ModalRootControlNode({ ...this.modalOptions, ...this.duplicateOptions(runtimeId), open: this.open, direction: this.direction, gap: this.gap, padding: this.padding, align: this.align, justify: this.justify });
  }
}

function finiteNonNegative(value: number, label: string): number {
  if (!Number.isFinite(value) || value < 0) throw new Error(`${label} must be finite and non-negative`);
  return value;
}

function finitePositive(value: number, label: string): number {
  if (!Number.isFinite(value) || value <= 0) throw new Error(`${label} must be finite and positive`);
  return value;
}
