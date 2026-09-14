import { inputEventFromDom, type InputActionMap, type InputEvent } from './InputEvent';

export interface InputEventSink { enqueueInput(event: InputEvent): void }

export interface InputControl {
  readonly routedInputPriority: number;
  readonly inputVisible: boolean;
  readonly processInputWhenPaused: boolean;
  readonly inputFocused: boolean;
  readonly inputModal: boolean;
  handleRoutedInput(event: InputEvent): void;
}

export interface InputRouterOptions {
  readonly sink: InputEventSink;
  readonly eventTarget?: EventTarget;
  readonly actions?: InputActionMap;
  readonly isPaused?: () => boolean;
}

const DOM_INPUT_TYPES = ['keydown', 'keyup', 'pointerdown', 'pointerup', 'pointermove'] as const;

export class InputRouter {
  private readonly controls = new Set<InputControl>();
  private readonly eventTarget: EventTarget;
  private readonly handleDomEvent = (nativeEvent: Event): void => {
    const event = inputEventFromDom(nativeEvent, this.options.actions);
    if (!event) return;
    this.route(event);
    if (event.handled) {
      nativeEvent.preventDefault();
      nativeEvent.stopPropagation();
    }
    this.options.sink.enqueueInput(event);
  };
  private destroyed = false;

  constructor(private readonly options: InputRouterOptions) {
    this.eventTarget = options.eventTarget ?? document;
    for (const type of DOM_INPUT_TYPES) this.eventTarget.addEventListener(type, this.handleDomEvent);
  }

  registerControl(control: InputControl): () => void {
    if (this.destroyed) throw new Error('InputRouter has been destroyed');
    this.controls.add(control);
    let active = true;
    return () => { if (!active) return; active = false; this.controls.delete(control); };
  }

  route(event: InputEvent): InputEvent {
    const paused = this.options.isPaused?.() ?? false;
    const controls = [...this.controls]
      .filter((control) => control.inputVisible && (control.inputFocused || control.inputModal) && (!paused || control.processInputWhenPaused))
      .sort((left, right) => Number(right.inputModal) - Number(left.inputModal) || right.routedInputPriority - left.routedInputPriority);
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
    this.controls.clear();
  }
}
