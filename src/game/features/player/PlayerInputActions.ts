import type { InputActionMap } from '../../runtime/scene/input/InputEvent';

/**
 * The one table of controls (roadmap 4.10): every action and what it is bound
 * to. Codes are `KeyboardEvent.code` values (physical key positions, so WASD
 * stays under the left hand on any layout), `Mouse0` / `Mouse2` for the left
 * and right button over the game, and `WheelUp` / `WheelDown` for the wheel.
 * The router's action map and every key label are derived from it.
 */
export const PLAYER_ACTION_BINDINGS = {
  'move-up': ['KeyW', 'ArrowUp'],
  'move-down': ['KeyS', 'ArrowDown'],
  'move-left': ['KeyA', 'ArrowLeft'],
  'move-right': ['KeyD', 'ArrowRight'],
  attack: ['Mouse0'],
  interact: ['Mouse2'],
  sprint: ['ShiftLeft', 'ShiftRight'],
  jump: ['Space'],
  dodge: ['Digit1'],
  'stretch-lash': ['Digit2'],
  'squash-slam': ['Digit3'],
  teleport: ['Digit4'],
  eat: ['KeyQ'],
  'weapon-next': ['WheelDown'],
  'weapon-previous': ['WheelUp'],
} as const satisfies Readonly<Record<string, readonly string[]>>;

/**
 * Controls that also work while a window is open or the game is paused, so
 * they are handled by the world scene and the windows rather than the player.
 * Esc is listed for its label only: the modal stack owns it.
 */
export const SHELL_ACTION_BINDINGS = {
  menu: ['KeyE'],
  map: ['KeyM'],
  'zoom-in': ['Equal', 'NumpadAdd'],
  'zoom-out': ['Minus', 'NumpadSubtract'],
  pause: ['Escape'],
} as const satisfies Readonly<Record<string, readonly string[]>>;

export type PlayerInputAction = keyof typeof PLAYER_ACTION_BINDINGS;
export type ShellInputAction = keyof typeof SHELL_ACTION_BINDINGS;
export type ControlAction = PlayerInputAction | ShellInputAction;

const CONTROL_BINDINGS: Readonly<Record<ControlAction, readonly string[]>> = {
  ...PLAYER_ACTION_BINDINGS,
  ...SHELL_ACTION_BINDINGS,
};

/** Input code -> player action, for the input router. */
export const PLAYER_INPUT_ACTIONS: InputActionMap = Object.freeze(Object.fromEntries(
  Object.entries(PLAYER_ACTION_BINDINGS).flatMap(([action, codes]) => codes.map((code) => [code, action])),
));

export function isPlayerInputAction(value: string | undefined): value is PlayerInputAction {
  return value !== undefined && Object.hasOwn(PLAYER_ACTION_BINDINGS, value);
}

/** Every input code bound to `action`, primary first. */
export function controlCodes(action: ControlAction): readonly string[] {
  return CONTROL_BINDINGS[action];
}

/** Whether `code` (a `KeyboardEvent.code`) is bound to `action`. */
export function isControlCode(action: ControlAction, code: string): boolean {
  return CONTROL_BINDINGS[action].includes(code);
}
