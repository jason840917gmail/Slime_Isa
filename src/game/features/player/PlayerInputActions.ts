import type { InputActionMap } from '../../runtime/scene/input/InputEvent';

export const PLAYER_INPUT_ACTIONS: InputActionMap = Object.freeze({
  ArrowUp: 'move-up',
  ArrowDown: 'move-down',
  ArrowLeft: 'move-left',
  ArrowRight: 'move-right',
  KeyI: 'move-up',
  KeyK: 'move-down',
  KeyJ: 'move-left',
  KeyL: 'move-right',
  KeyQ: 'dodge-boost',
  Space: 'jump',
  KeyE: 'attack',
  KeyR: 'stretch-lash',
  KeyT: 'squash-slam',
  KeyY: 'teleport',
  KeyF: 'interact',
  KeyW: 'eat',
});

export type PlayerInputAction =
  | 'move-up'
  | 'move-down'
  | 'move-left'
  | 'move-right'
  | 'dodge-boost'
  | 'jump'
  | 'attack'
  | 'stretch-lash'
  | 'squash-slam'
  | 'teleport'
  | 'interact'
  | 'eat';

export function isPlayerInputAction(value: string | undefined): value is PlayerInputAction {
  return value === 'move-up' || value === 'move-down' || value === 'move-left'
    || value === 'move-right' || value === 'dodge-boost' || value === 'jump'
    || value === 'attack' || value === 'stretch-lash' || value === 'squash-slam'
    || value === 'teleport' || value === 'interact' || value === 'eat';
}
