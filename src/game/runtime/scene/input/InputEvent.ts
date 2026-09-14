import type { SceneTreeInputEvent } from '../SceneTree';

export type InputEventType = 'key-down' | 'key-up' | 'pointer-down' | 'pointer-up' | 'pointer-move';

export interface InputEvent extends SceneTreeInputEvent {
  readonly type: InputEventType;
  readonly timestamp: number;
  readonly key?: string;
  readonly code?: string;
  readonly action?: string;
  readonly pointer?: Readonly<{ x: number; y: number; button: number }>;
  readonly pressed: boolean;
  readonly released: boolean;
  readonly nativeEvent?: Event;
  controlRouted?: boolean;
}

export interface InputActionMap { readonly [code: string]: string }

export function inputEventFromDom(event: Event, actions: InputActionMap = {}): InputEvent | undefined {
  const timestamp = Number.isFinite(event.timeStamp) ? event.timeStamp : 0;
  if (typeof KeyboardEvent !== 'undefined' && event instanceof KeyboardEvent) {
    const pressed = event.type === 'keydown';
    if (!pressed && event.type !== 'keyup') return undefined;
    return { handled: false, type: pressed ? 'key-down' : 'key-up', timestamp, key: event.key, code: event.code, action: actions[event.code], pressed, released: !pressed, nativeEvent: event };
  }
  if (typeof PointerEvent !== 'undefined' && event instanceof PointerEvent) {
    const type = event.type === 'pointerdown' ? 'pointer-down' : event.type === 'pointerup' ? 'pointer-up' : event.type === 'pointermove' ? 'pointer-move' : undefined;
    if (!type) return undefined;
    return { handled: false, type, timestamp, pointer: { x: event.clientX, y: event.clientY, button: event.button }, pressed: type === 'pointer-down', released: type === 'pointer-up', nativeEvent: event };
  }
  return undefined;
}
