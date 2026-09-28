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
  private readonly modalFocus = new Map<ModalRootControlNode, { previous: Element | null; open: boolean }>();

  constructor(private readonly htmlOptions: HtmlControlPresentationOptions) {
    super({ ...htmlOptions, createElement: (control) => createElement(control) });
  }

  override enter(control: ControlNode): () => void {
    const dispose = super.enter(control);
    if (!(control instanceof ModalRootControlNode)) return dispose;
    const element = this.elementFor(control)!;
    element.tabIndex = -1;
    element.addEventListener('keydown', trapModalTab);
    return () => {
      const focus = this.modalFocus.get(control);
      if (focus?.open) restoreFocus(focus.previous);
      this.modalFocus.delete(control);
      element.removeEventListener('keydown', trapModalTab);
      dispose();
    };
  }

  override synchronize(control: ControlNode): void {
    super.synchronize(control);
    const element = this.elementFor(control);
    if (!element) return;
    synchronizeElement(element, control, this.htmlOptions.resolveAssetUrl);
    if (control instanceof ModalRootControlNode) {
      const state = this.modalFocus.get(control);
      if (control.open && !state?.open) {
        const previous = document.activeElement;
        this.modalFocus.set(control, { previous, open: true });
        requestAnimationFrame(() => {
          if (!control.open || !element.isConnected) return;
          (element.querySelector<HTMLElement>('button:not(:disabled), [tabindex="0"]') ?? element).focus();
        });
      } else if (!control.open && state?.open) {
        this.modalFocus.set(control, { previous: state.previous, open: false });
        restoreFocus(state.previous);
      }
    }
  }
}

/**
 * Returns focus to the element that opened a modal, except HUD scene controls
 * (weapon belt, ability bar) outside an open dialog: they must not regain
 * keyboard focus, or arrow keys and Space would drive them while the player walks.
 */
function restoreFocus(previous: Element | null): void {
  if (previous instanceof HTMLElement && previous.isConnected
    && (!previous.closest('.scene-control') || previous.closest('[role="dialog"][aria-hidden="false"]'))) {
    previous.focus();
    return;
  }
  const active = document.activeElement;
  if (active instanceof HTMLElement && active !== document.body && active.closest('.scene-control')) active.blur();
}

/** HUD controls outside dialogs stay clickable but never take keyboard focus from a pointer press. */
function keepPointerFocusOutsideHud(event: MouseEvent): void {
  if (!(event.currentTarget as HTMLElement).closest('[role="dialog"]')) event.preventDefault();
}

function trapModalTab(event: KeyboardEvent): void {
  event.stopPropagation();
  if (event.key !== 'Tab') return;
  const root = event.currentTarget as HTMLElement;
  const focusable = [...root.querySelectorAll<HTMLElement>('button:not(:disabled), [tabindex="0"]')]
    .filter((item) => item.getClientRects().length > 0);
  if (!focusable.length) { event.preventDefault(); root.focus(); return; }
  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (event.shiftKey && (document.activeElement === first || document.activeElement === root)) {
    event.preventDefault(); event.stopPropagation(); last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault(); event.stopPropagation(); first.focus();
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

/**
 * Controls synchronize every frame. Each writer below compares against the
 * live DOM first: redundant writes invalidate style/layout, and the base
 * adapter's per-control size reads would then force a reflow every frame.
 */
function setText(element: HTMLElement, text: string): void {
  if (element.textContent !== text) element.textContent = text;
}

function setAttribute(element: Element, name: string, value: string): void {
  if (element.getAttribute(name) !== value) element.setAttribute(name, value);
}

function removeAttribute(element: Element, name: string): void {
  if (element.hasAttribute(name)) element.removeAttribute(name);
}

function setStyle(element: HTMLElement, property: string, value: string): void {
  if (element.style.getPropertyValue(property) !== value) element.style.setProperty(property, value);
}

/** Elements whose DOM event handlers are wired; each element serves one control for its lifetime. */
const wiredElements = new WeakSet<HTMLElement>();

function synchronizeElement(
  element: HTMLElement,
  control: ControlNode,
  resolveAssetUrl: HtmlControlPresentationOptions['resolveAssetUrl'],
): void {
  const className = `scene-control scene-control--${control.runtimeType.toLowerCase()}${control instanceof StyledControlNode && control.styleClass ? ` ${control.styleClass}` : ''}`;
  if (element.className !== className) element.className = className;
  if (control instanceof StyledControlNode) {
    if (control.ariaLabel) setAttribute(element, 'aria-label', control.ariaLabel);
    else removeAttribute(element, 'aria-label');
    if (element.title !== control.tooltip) element.title = control.tooltip;
    setStyle(element, 'z-index', String(control.zIndex));
  }
  if (control instanceof ContainerControlNode) synchronizeContainer(element, control);
  if (control instanceof LabelControlNode) synchronizeLabel(element, control);
  if (control instanceof ButtonControlNode && element instanceof HTMLButtonElement) {
    if (element.type !== 'button') element.type = 'button';
    if (element.disabled !== control.disabled) element.disabled = control.disabled;
    if (!wiredElements.has(element)) {
      element.onclick = (event) => { if (control.activate()) { event.preventDefault(); event.stopPropagation(); } };
    }
    synchronizeFocusable(element, control);
  }
  if (control instanceof ProgressBarControlNode) synchronizeProgress(element, control);
  if (control instanceof TextureRectControlNode && element instanceof HTMLImageElement) {
    if (element.alt !== control.alt) element.alt = control.alt;
    setStyle(element, 'object-fit', control.fit);
    const url = control.assetKey ? resolveAssetUrl?.(control.assetKey, control.frame) : undefined;
    if (url) setAttribute(element, 'src', url);
    else removeAttribute(element, 'src');
  }
  if (control instanceof ItemListControlNode) {
    synchronizeList(element, control, resolveAssetUrl);
    synchronizeFocusable(element, control);
  }
  if (control instanceof ScrollContainerControlNode) {
    setStyle(element, 'overflow-x', control.scrollAxis === 'horizontal' ? 'auto' : 'hidden');
    setStyle(element, 'overflow-y', control.scrollAxis === 'vertical' ? 'auto' : 'hidden');
  }
  if (control instanceof ModalRootControlNode) {
    setAttribute(element, 'role', 'dialog');
    setAttribute(element, 'aria-modal', 'true');
    setAttribute(element, 'aria-hidden', String(!control.open));
  }
  wiredElements.add(element);
}

function synchronizeFocusable(element: HTMLElement, control: ButtonControlNode | ItemListControlNode): void {
  // HUD controls outside dialogs stay out of the Tab order: the game owns Tab,
  // and a focused weapon belt or ability bar would turn walking keys into UI input.
  const inHud = !element.closest('[role="dialog"]');
  const tabIndex = inHud || (control instanceof ButtonControlNode && control.disabled) ? -1 : 0;
  if (element.tabIndex !== tabIndex) element.tabIndex = tabIndex;
  if (control instanceof ItemListControlNode) {
    const optionTabIndex = inHud ? -1 : 0;
    for (const option of element.children) {
      if (option instanceof HTMLElement && option.tabIndex !== optionTabIndex) option.tabIndex = optionTabIndex;
    }
  }
  // Browsers skip `blur` when a focused element is disabled or removed (ItemList
  // rebuilds its options), which would leave `focused` stuck and let the router
  // feed every document key to this control. Re-derive it from the live DOM.
  const hasFocus = element.contains(document.activeElement);
  if (control.focused !== hasFocus) control.focused = hasFocus;
  if (wiredElements.has(element)) return;
  element.onmousedown = keepPointerFocusOutsideHud;
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
  setStyle(element, 'display', control.visible ? (control instanceof GridContainerControlNode ? 'grid' : control.direction === 'none' ? 'block' : 'flex') : 'none');
  if (control.direction !== 'none') setStyle(element, 'flex-direction', control.direction === 'horizontal' ? 'row' : 'column');
  setStyle(element, 'gap', `${control.gap}px`);
  setStyle(element, 'padding', control.padding.map((value) => `${value}px`).join(' '));
  setStyle(element, 'align-items', control.align === 'start' ? 'flex-start' : control.align === 'end' ? 'flex-end' : control.align);
  setStyle(element, 'justify-content', control.justify === 'start' ? 'flex-start' : control.justify === 'end' ? 'flex-end' : control.justify);
  if (control instanceof GridContainerControlNode) setStyle(element, 'grid-template-columns', `repeat(${control.columns}, minmax(0, 1fr))`);
}

function synchronizeLabel(element: HTMLElement, control: LabelControlNode): void {
  setText(element, control.text);
  setStyle(element, 'color', control.color ?? TONE_VARIABLE[control.tone]);
  setStyle(element, 'font-size', `${control.fontSize}px`);
  setStyle(element, 'font-weight', String(control.fontWeight));
  setStyle(element, 'text-align', control.textAlign);
  setStyle(element, 'white-space', control.wrap ? 'pre-line' : 'nowrap');
}

function synchronizeProgress(element: HTMLElement, control: ProgressBarControlNode): void {
  setAttribute(element, 'role', 'progressbar');
  setAttribute(element, 'aria-valuemin', '0');
  setAttribute(element, 'aria-valuemax', String(control.max));
  setAttribute(element, 'aria-valuenow', String(control.value));
  setAttribute(element, 'aria-label', control.label || control.name);
  setStyle(element, '--scene-progress', String(control.ratio));
  setStyle(element, '--scene-progress-color', TONE_VARIABLE[control.tone]);
  setText(element, control.showValue ? `${control.label} ${Math.ceil(control.value)} / ${Math.ceil(control.max)}`.trim() : control.label);
}

function synchronizeList(
  element: HTMLElement,
  control: ItemListControlNode,
  resolveAssetUrl: HtmlControlPresentationOptions['resolveAssetUrl'],
): void {
  const signature = JSON.stringify([control.items, control.columns, control.gap]);
  if (element.dataset.sceneListSignature === signature) {
    [...element.children].forEach((child, index) => setAttribute(child, 'aria-selected', String(index === control.selectedIndex)));
    return;
  }
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
      const caption = document.createElement('span');
      caption.className = 'scene-item-label';
      caption.textContent = item.label;
      const shortcut = document.createElement('span');
      shortcut.className = 'scene-item-shortcut';
      shortcut.textContent = icon?.shortcut ?? '';
      option.replaceChildren(image, ...(icon?.showLabel ? [caption] : []), shortcut);
      option.classList.add('scene-item--illustrated');
      option.setAttribute('aria-label', item.label.replace(/\s+/g, ' '));
      option.title = item.label.replace(/\s+/g, ' ');
    }
    option.disabled = item.disabled ?? false;
    option.dataset.itemId = item.id;
    option.setAttribute('role', 'option');
    option.setAttribute('aria-selected', String(index === control.selectedIndex));
    option.onmousedown = keepPointerFocusOutsideHud;
    option.onfocus = () => { control.focused = true; };
    option.onblur = () => { control.focused = false; };
    option.onclick = (event) => { if (control.select(index)) { event.preventDefault(); event.stopPropagation(); } };
    option.oncontextmenu = (event) => {
      if (control.secondarySelect(index)) { event.preventDefault(); event.stopPropagation(); }
    };
    element.append(option);
  });
}

function itemIcon(metadata: unknown): { readonly key: string; readonly frame: number; readonly shortcut?: string; readonly showLabel: boolean } | undefined {
  if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) return undefined;
  const candidate = metadata as Readonly<Record<string, unknown>>;
  if (typeof candidate.iconKey !== 'string' || typeof candidate.iconFrame !== 'number'
    || !Number.isInteger(candidate.iconFrame) || candidate.iconFrame < 0) return undefined;
  return { key: candidate.iconKey, frame: candidate.iconFrame, showLabel: candidate.showLabel === true,
    ...(typeof candidate.shortcut === 'string' ? { shortcut: candidate.shortcut } : {}),
  };
}
