import { inputEventFromDom, type InputActionMap, type InputEvent } from './InputEvent';

export interface InputEventSink { enqueueInput(event: InputEvent): void }

export interface InputControl {
  readonly routedInputPriority: number;
  readonly inputVisible: boolean;
  readonly processInputWhenPaused: boolean;
  readonly inputFocused: boolean;
  readonly inputModal: boolean;
  readonly inputModalDepth: number;
  handleRoutedInput(event: InputEvent): void;
}

export interface InputRouterOptions {
  readonly sink: InputEventSink;
  readonly eventTarget?: EventTarget;
  readonly actions?: InputActionMap;
  readonly isPaused?: () => boolean;
}

const DOM_INPUT_TYPES = ['keydown', 'keyup', 'pointerdown', 'pointerup', 'pointermove'] as const;

/** Form fields and draggable entries (a weapon dragged onto the belt) need the browser's own pointer handling. */
function needsNativePointer(target: EventTarget | null): boolean {
  const element = target as { closest?: (selector: string) => unknown } | null;
  return typeof element?.closest === 'function' && element.closest('input, select, textarea, [draggable="true"]') !== null;
}

export class InputRouter {
  private readonly controls = new Set<InputControl>();
  private readonly eventTarget: EventTarget;
  private readonly handleDomEvent = (nativeEvent: Event): void => {
    const event = inputEventFromDom(nativeEvent, this.options.actions);
    if (!event) return;
    this.route(event);
    if (event.handled) {
      // A consumed pointer press on a native form field (range slider, text box) or a draggable
      // entry still needs its browser default, or it never receives mousedown/drag/input.
      if (!(event.type.startsWith('pointer') && needsNativePointer(nativeEvent.target))) nativeEvent.preventDefault();
      nativeEvent.stopPropagation();
    }
    this.options.sink.enqueueInput(event);
  };
  private destroyed = false;

  /** The wheel only feeds gameplay (weapon switching); it never blocks page scrolling. */
  private readonly handleWheel = (nativeEvent: Event): void => {
    const event = inputEventFromDom(nativeEvent, this.options.actions);
    if (event) this.options.sink.enqueueInput(event);
  };

  constructor(private readonly options: InputRouterOptions) {
    this.eventTarget = options.eventTarget ?? document;
    for (const type of DOM_INPUT_TYPES) this.eventTarget.addEventListener(type, this.handleDomEvent);
    this.eventTarget.addEventListener('wheel', this.handleWheel, { passive: true });
  }

  registerControl(control: InputControl): () => void {
    if (this.destroyed) throw new Error('InputRouter has been destroyed');
    this.controls.add(control);
    let active = true;
    return () => { if (!active) return; active = false; this.controls.delete(control); };
  }

  route(event: InputEvent): InputEvent {
    const paused = this.options.isPaused?.() ?? false;
    const eligible = [...this.controls]
      .filter((control) => control.inputVisible && (control.inputFocused || control.inputModal) && (!paused || control.processInputWhenPaused));
    const modalDepth = eligible.reduce((depth, control) => Math.max(depth, control.inputModalDepth), 0);
    const controls = eligible
      .filter((control) => modalDepth === 0 || control.inputModalDepth === modalDepth)
      .sort((left, right) => Number(right.inputFocused) - Number(left.inputFocused)
        || right.routedInputPriority - left.routedInputPriority
        || Number(right.inputModal) - Number(left.inputModal));
    for (const control of controls) {
      control.handleRoutedInput(event);
      if (event.handled) break;
    }
    event.controlRouted = true;
    return event;
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    for (const type of DOM_INPUT_TYPES) this.eventTarget.removeEventListener(type, this.handleDomEvent);
    this.eventTarget.removeEventListener('wheel', this.handleWheel);
    this.controls.clear();
  }
}
