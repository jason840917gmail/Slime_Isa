import { ControlNode, type ControlPresentation } from '../../runtime/scene/ui/ControlNode';

export interface ControlPresentationAdapterOptions {
  readonly root: HTMLElement;
  readonly createElement?: (control: ControlNode) => HTMLElement;
  readonly viewport?: () => Readonly<{ width: number; height: number }>;
}

export class ControlPresentationAdapter implements ControlPresentation {
  private readonly elements = new Map<ControlNode, HTMLElement>();

  constructor(private readonly options: ControlPresentationAdapterOptions) {}

  get size(): number { return this.elements.size; }

  elementFor(control: ControlNode): HTMLElement | undefined { return this.elements.get(control); }

  enter(control: ControlNode): () => void {
    if (this.elements.has(control)) throw new Error(`Control '${control.name}' already owns a presentation element`);
    const element = this.options.createElement?.(control) ?? document.createElement('div');
    element.dataset.sceneControlId = control.runtimeId;
    const parent = control.get_parent();
    const parentElement = parent instanceof ControlNode ? this.elements.get(parent) : undefined;
    (parentElement ?? this.options.root).append(element);
    this.elements.set(control, element);
    this.synchronize(control);
    return () => { this.elements.delete(control); element.remove(); };
  }

  synchronize(control: ControlNode): void {
    const element = this.elements.get(control);
    if (!element) return;
    const parent = control.get_parent();
    const parentElement = parent instanceof ControlNode ? this.elements.get(parent) : undefined;
    const viewport = parentElement
      ? { width: parentElement.clientWidth, height: parentElement.clientHeight }
      : this.options.viewport?.() ?? { width: this.options.root.clientWidth, height: this.options.root.clientHeight };
    const { anchorMin, anchorMax, offsetMin, offsetMax } = control.layout;
    const left = viewport.width * anchorMin.x + offsetMin.x;
    const top = viewport.height * anchorMin.y + offsetMin.y;
    const right = viewport.width * anchorMax.x + offsetMax.x;
    const bottom = viewport.height * anchorMax.y + offsetMax.y;
    element.style.position = 'absolute';
    element.style.left = `${left}px`;
    element.style.top = `${top}px`;
    element.style.width = `${Math.max(0, right - left)}px`;
    element.style.height = `${Math.max(0, bottom - top)}px`;
    element.style.display = control.visible ? '' : 'none';
    element.style.opacity = String(control.opacity);
    element.style.scale = String(control.scale);
    for (const [key, value] of Object.entries(control.theme)) {
      if (value === null || typeof value === 'object') continue;
      element.style.setProperty(`--scene-${key}`, String(value));
    }
  }
}
