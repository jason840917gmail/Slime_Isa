import { ControlPresentationAdapter, type ControlPresentationAdapterOptions } from '../ControlPresentationAdapter';
import type { ControlNode } from '../../../runtime/scene/ui/ControlNode';
import type { InputEvent } from '../../../runtime/scene/input/InputEvent';
import {
  ButtonControlNode,
  ContainerControlNode,
  GridContainerControlNode,
  ItemListControlNode,
  LabelControlNode,
  ModalRootControlNode,
  ProgressBarControlNode,
  ScrollContainerControlNode,
  StyledControlNode,
  TextureRectControlNode,
  type UiTone,
} from './ControlNodes';

export interface HtmlControlPresentationOptions extends Omit<ControlPresentationAdapterOptions, 'createElement'> {
  readonly resolveAssetUrl?: (assetKey: string, frame: number) => string | undefined;
}

const TONE_VARIABLE: Readonly<Record<UiTone, string>> = {
  default: 'var(--scene-text-primary, #f5f7ff)',
  muted: 'var(--scene-text-muted, #8fbba3)',
  accent: 'var(--scene-accent, #86f0c3)',
  info: 'var(--scene-info, #72d8ff)',
  warning: 'var(--scene-warning, #ffd277)',
  danger: 'var(--scene-danger, #ff6f88)',
  special: 'var(--scene-special, #a78bfa)',
};

export class HtmlControlPresentationAdapter extends ControlPresentationAdapter {
  constructor(private readonly htmlOptions: HtmlControlPresentationOptions) {
    super({ ...htmlOptions, createElement: (control) => createElement(control) });
  }

  override synchronize(control: ControlNode): void {
    super.synchronize(control);
    const element = this.elementFor(control);
    if (!element) return;
    synchronizeElement(element, control, this.htmlOptions.resolveAssetUrl);
  }
}

function createElement(control: ControlNode): HTMLElement {
  if (control instanceof ButtonControlNode) return document.createElement('button');
  if (control instanceof TextureRectControlNode) return document.createElement('img');
  if (control instanceof LabelControlNode) return document.createElement('span');
  if (control instanceof ProgressBarControlNode) return document.createElement('div');
  if (control instanceof ItemListControlNode) return document.createElement('div');
  if (control instanceof ModalRootControlNode) return document.createElement('section');
  if (control instanceof ScrollContainerControlNode) return document.createElement('div');
  if (control instanceof GridContainerControlNode) return document.createElement('div');
  if (control instanceof ContainerControlNode) return document.createElement('div');
  return document.createElement('div');
}

function synchronizeElement(
  element: HTMLElement,
  control: ControlNode,
  resolveAssetUrl: HtmlControlPresentationOptions['resolveAssetUrl'],
): void {
  element.className = `scene-control scene-control--${control.runtimeType.toLowerCase()}${control instanceof StyledControlNode && control.styleClass ? ` ${control.styleClass}` : ''}`;
  if (control instanceof StyledControlNode) {
    element.setAttribute('aria-label', control.ariaLabel || control.name);
    element.title = control.tooltip;
    element.style.zIndex = String(control.zIndex);
  }
  if (control instanceof ContainerControlNode) synchronizeContainer(element, control);
  if (control instanceof LabelControlNode) synchronizeLabel(element, control);
  if (control instanceof ButtonControlNode && element instanceof HTMLButtonElement) {
    element.type = 'button';
    element.disabled = control.disabled;
    element.onclick = (event) => { if (control.activate()) { event.preventDefault(); event.stopPropagation(); } };
    synchronizeFocusable(element, control);
  }
  if (control instanceof ProgressBarControlNode) synchronizeProgress(element, control);
  if (control instanceof TextureRectControlNode && element instanceof HTMLImageElement) {
    element.alt = control.alt;
    element.style.objectFit = control.fit;
    const url = control.assetKey ? resolveAssetUrl?.(control.assetKey, control.frame) : undefined;
    if (url) element.src = url;
    else element.removeAttribute('src');
  }
  if (control instanceof ItemListControlNode) {
    synchronizeFocusable(element, control);
    synchronizeList(element, control, resolveAssetUrl);
  }
  if (control instanceof ScrollContainerControlNode) {
    element.style.overflowX = control.scrollAxis === 'horizontal' ? 'auto' : 'hidden';
    element.style.overflowY = control.scrollAxis === 'vertical' ? 'auto' : 'hidden';
  }
  if (control instanceof ModalRootControlNode) {
    element.setAttribute('role', 'dialog');
    element.setAttribute('aria-modal', 'true');
    element.setAttribute('aria-hidden', String(!control.open));
  }
}

function synchronizeFocusable(element: HTMLElement, control: ButtonControlNode | ItemListControlNode): void {
  element.tabIndex = control instanceof ButtonControlNode && control.disabled ? -1 : 0;
  element.onfocus = () => { control.focused = true; };
  element.onblur = () => { control.focused = false; };
  element.onkeydown = (nativeEvent) => {
    const event: InputEvent = {
      handled: false,
      type: 'key-down',
      timestamp: nativeEvent.timeStamp,
      key: nativeEvent.key,
      code: nativeEvent.code,
      pressed: true,
      released: false,
      nativeEvent,
    };
    control.handleRoutedInput(event);
    if (event.handled) {
      nativeEvent.preventDefault();
      nativeEvent.stopPropagation();
    }
  };
}

function synchronizeContainer(element: HTMLElement, control: ContainerControlNode): void {
  element.style.display = control.visible ? (control instanceof GridContainerControlNode ? 'grid' : control.direction === 'none' ? 'block' : 'flex') : 'none';
  if (control.direction !== 'none') element.style.flexDirection = control.direction === 'horizontal' ? 'row' : 'column';
  element.style.gap = `${control.gap}px`;
  element.style.padding = control.padding.map((value) => `${value}px`).join(' ');
  element.style.alignItems = control.align === 'start' ? 'flex-start' : control.align === 'end' ? 'flex-end' : control.align;
  element.style.justifyContent = control.justify === 'start' ? 'flex-start' : control.justify === 'end' ? 'flex-end' : control.justify;
  if (control instanceof GridContainerControlNode) element.style.gridTemplateColumns = `repeat(${control.columns}, minmax(0, 1fr))`;
}

function synchronizeLabel(element: HTMLElement, control: LabelControlNode): void {
  element.textContent = control.text;
  element.style.color = control.color ?? TONE_VARIABLE[control.tone];
  element.style.fontSize = `${control.fontSize}px`;
  element.style.fontWeight = String(control.fontWeight);
  element.style.textAlign = control.textAlign;
  element.style.whiteSpace = control.wrap ? 'pre-line' : 'nowrap';
}

function synchronizeProgress(element: HTMLElement, control: ProgressBarControlNode): void {
  element.setAttribute('role', 'progressbar');
  element.setAttribute('aria-valuemin', '0');
  element.setAttribute('aria-valuemax', String(control.max));
  element.setAttribute('aria-valuenow', String(control.value));
  element.setAttribute('aria-label', control.label || control.name);
  element.style.setProperty('--scene-progress', String(control.ratio));
  element.style.setProperty('--scene-progress-color', TONE_VARIABLE[control.tone]);
  element.textContent = control.showValue ? `${control.label} ${Math.ceil(control.value)} / ${Math.ceil(control.max)}`.trim() : control.label;
}

function synchronizeList(
  element: HTMLElement,
  control: ItemListControlNode,
  resolveAssetUrl: HtmlControlPresentationOptions['resolveAssetUrl'],
): void {
  const signature = JSON.stringify([control.items, control.selectedIndex, control.columns, control.gap]);
  if (element.dataset.sceneListSignature === signature) return;
  element.dataset.sceneListSignature = signature;
  element.replaceChildren();
  element.setAttribute('role', 'listbox');
  element.style.display = 'grid';
  element.style.gridTemplateColumns = `repeat(${control.columns}, minmax(0, 1fr))`;
  element.style.gap = `${control.gap}px`;
  control.items.forEach((item, index) => {
    const option = document.createElement('button');
    option.type = 'button';
    option.textContent = item.label;
    const icon = itemIcon(item.metadata);
    const iconUrl = icon ? resolveAssetUrl?.(icon.key, icon.frame) : undefined;
    if (iconUrl) {
      const image = document.createElement('img');
      image.src = iconUrl;
      image.alt = '';
      image.setAttribute('aria-hidden', 'true');
      const shortcut = document.createElement('span');
      shortcut.textContent = icon?.shortcut ?? '';
      option.replaceChildren(image, shortcut);
      option.classList.add('scene-item--illustrated');
      option.setAttribute('aria-label', item.label.replace(/\s+/g, ' '));
      option.title = item.label.replace(/\s+/g, ' ');
    }
    option.disabled = item.disabled ?? false;
    option.dataset.itemId = item.id;
    option.setAttribute('role', 'option');
    option.setAttribute('aria-selected', String(index === control.selectedIndex));
    option.onclick = (event) => { if (control.select(index)) { event.preventDefault(); event.stopPropagation(); } };
    element.append(option);
  });
}

function itemIcon(metadata: unknown): { readonly key: string; readonly frame: number; readonly shortcut?: string } | undefined {
  if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) return undefined;
  const candidate = metadata as Readonly<Record<string, unknown>>;
  if (typeof candidate.iconKey !== 'string' || typeof candidate.iconFrame !== 'number'
    || !Number.isInteger(candidate.iconFrame) || candidate.iconFrame < 0) return undefined;
  return { key: candidate.iconKey, frame: candidate.iconFrame,
    ...(typeof candidate.shortcut === 'string' ? { shortcut: candidate.shortcut } : {}),
  };
}
