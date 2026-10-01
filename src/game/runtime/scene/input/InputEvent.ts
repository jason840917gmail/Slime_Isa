import type { SceneTreeInputEvent } from '../SceneTree';

export type InputEventType = 'key-down' | 'key-up' | 'pointer-down' | 'pointer-up' | 'pointer-move' | 'wheel';

export interface InputEvent extends SceneTreeInputEvent {
  readonly type: InputEventType;
  readonly timestamp: number;
  readonly key?: string;
  /** `KeyboardEvent.code`, `Mouse<button>` for a button, or `WheelUp` / `WheelDown`. */
  readonly code?: string;
  readonly action?: string;
  readonly pointer?: Readonly<{ x: number; y: number; button: number }>;
  /** How far one wheel event scrolled, in pixels (always positive; the code says which way). */
  readonly wheelDelta?: number;
  readonly pressed: boolean;
  readonly released: boolean;
  readonly nativeEvent?: Event;
  controlRouted?: boolean;
}

export interface InputActionMap { readonly [code: string]: string }

/** Pixels per wheel line and per page, for browsers that scroll in those units. */
const WHEEL_LINE_PX = 40;
const WHEEL_PAGE_PX = 800;

/**
 * Mouse buttons and the wheel only act in the game when they happen over the
 * game itself (the canvas), not over a window, the HUD or the dev panel.
 */
function isGameSurface(target: EventTarget | null): boolean {
  return typeof HTMLCanvasElement !== 'undefined' && target instanceof HTMLCanvasElement;
}

export function inputEventFromDom(event: Event, actions: InputActionMap = {}): InputEvent | undefined {
  const timestamp = Number.isFinite(event.timeStamp) ? event.timeStamp : 0;
  if (typeof KeyboardEvent !== 'undefined' && event instanceof KeyboardEvent) {
    const pressed = event.type === 'keydown';
    if (!pressed && event.type !== 'keyup') return undefined;
    return { handled: false, type: pressed ? 'key-down' : 'key-up', timestamp, key: event.key, code: event.code, action: actions[event.code], pressed, released: !pressed, nativeEvent: event };
  }
  if (typeof WheelEvent !== 'undefined' && event instanceof WheelEvent) {
    const pixels = event.deltaY * (event.deltaMode === 1 ? WHEEL_LINE_PX : event.deltaMode === 2 ? WHEEL_PAGE_PX : 1);
    if (pixels === 0 || !isGameSurface(event.target)) return undefined;
    const code = pixels > 0 ? 'WheelDown' : 'WheelUp';
    return { handled: false, type: 'wheel', timestamp, code, action: actions[code], wheelDelta: Math.abs(pixels), pressed: false, released: false, nativeEvent: event };
  }
  if (typeof PointerEvent !== 'undefined' && event instanceof PointerEvent) {
    const type = event.type === 'pointerdown' ? 'pointer-down' : event.type === 'pointerup' ? 'pointer-up' : event.type === 'pointermove' ? 'pointer-move' : undefined;
    if (!type) return undefined;
    const code = type === 'pointer-move' ? undefined : `Mouse${event.button}`;
    // A press counts only over the game; a release always does, so a button
    // let go over a window is never left held.
    const action = code && (type === 'pointer-up' || isGameSurface(event.target)) ? actions[code] : undefined;
    return { handled: false, type, timestamp, code, action, pointer: { x: event.clientX, y: event.clientY, button: event.button }, pressed: type === 'pointer-down', released: type === 'pointer-up', nativeEvent: event };
  }
  return undefined;
}
