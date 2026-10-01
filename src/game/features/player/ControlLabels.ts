import { controlCodes, type ControlAction } from './PlayerInputActions';

/** Names for codes that are not a single printed character. */
const CODE_NAMES: Readonly<Record<string, string>> = {
  Space: 'Space',
  ShiftLeft: 'Shift',
  ShiftRight: 'Shift',
  Escape: 'Esc',
  Enter: 'Enter',
  Tab: 'Tab',
  ArrowUp: '↑',
  ArrowDown: '↓',
  ArrowLeft: '←',
  ArrowRight: '→',
  Equal: '+',
  Minus: '−',
  NumpadAdd: '+',
  NumpadSubtract: '−',
  Mouse0: 'Left click',
  Mouse1: 'Middle click',
  Mouse2: 'Right click',
  WheelUp: 'Mouse wheel',
  WheelDown: 'Mouse wheel',
};

/** What the player's keyboard prints on each physical key, when the browser says (Chromium only). */
let layout: ReadonlyMap<string, string> | undefined;

interface KeyboardLayoutApi { getLayoutMap(): Promise<ReadonlyMap<string, string>> }

/**
 * Reads the player's keyboard layout once, so an AZERTY player sees "Z Q S D"
 * for the movement keys. Without it, labels use QWERTY names.
 */
export async function loadKeyboardLayoutLabels(): Promise<void> {
  const keyboard = (globalThis.navigator as (Navigator & { keyboard?: KeyboardLayoutApi }) | undefined)?.keyboard;
  if (!keyboard?.getLayoutMap) return;
  try {
    layout = await keyboard.getLayoutMap();
  } catch {
    // Not allowed here (an iframe, a permission policy): keep QWERTY names.
  }
}

/** The label for one input code: "W", "1", "Space", "Right click". */
export function codeLabel(code: string): string {
  const named = CODE_NAMES[code];
  if (named) return named;
  const printed = layout?.get(code);
  if (printed && printed.trim()) return printed.toUpperCase();
  if (code.startsWith('Key')) return code.slice(3);
  if (code.startsWith('Digit')) return code.slice(5);
  if (code.startsWith('Numpad')) return `Num ${code.slice(6)}`;
  return code;
}

/** The label for an action's main binding, e.g. `controlLabel('jump')` is "Space". */
export function controlLabel(action: ControlAction): string {
  return codeLabel(controlCodes(action)[0]);
}

/** Every distinct label of an action's bindings, e.g. "+ / −" style lists; joined with " / ". */
export function controlLabels(action: ControlAction): string {
  return [...new Set(controlCodes(action).map(codeLabel))].join(' / ');
}

/** The four movement keys as one label: "WASD" (or "ZQSD" on AZERTY). */
export function movementLabel(): string {
  return (['move-up', 'move-left', 'move-down', 'move-right'] as const).map(controlLabel).join('');
}

/** "Right click" -> "Right-click", for prompts that read as a verb ("Right-click: Open chest"). */
export function controlVerb(action: ControlAction): string {
  return controlLabel(action).replace(/ click$/, '-click');
}
