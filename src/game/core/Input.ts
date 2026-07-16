import Phaser from 'phaser';

/**
 * Centralized input setup. Extracted from WorldScene.createControls so the
 * control scheme is reusable across scenes (areas) and later supports
 * rebinding + gamepad without touching scene code.
 *
 * Behavior preserved exactly from the original implementation.
 */

export type Controls = Phaser.Types.Input.Keyboard.CursorKeys & {
  upAlt: Phaser.Input.Keyboard.Key;
  downAlt: Phaser.Input.Keyboard.Key;
  leftAlt: Phaser.Input.Keyboard.Key;
  rightAlt: Phaser.Input.Keyboard.Key;
  boost: Phaser.Input.Keyboard.Key;
  jump: Phaser.Input.Keyboard.Key;
  trick: Phaser.Input.Keyboard.Key;
  stretch: Phaser.Input.Keyboard.Key;
  squash: Phaser.Input.Keyboard.Key;
  teleport: Phaser.Input.Keyboard.Key;
  interact: Phaser.Input.Keyboard.Key;
};

/** Fake controls used before the real keyboard is wired (e.g. in constructor). */
export function createFakeControls(): Controls {
  return {
    left: { isDown: false } as Phaser.Input.Keyboard.Key,
    right: { isDown: false } as Phaser.Input.Keyboard.Key,
    up: { isDown: false } as Phaser.Input.Keyboard.Key,
    down: { isDown: false } as Phaser.Input.Keyboard.Key,
    space: { isDown: false } as Phaser.Input.Keyboard.Key,
    shift: { isDown: false } as Phaser.Input.Keyboard.Key,
    upAlt: { isDown: false } as Phaser.Input.Keyboard.Key,
    downAlt: { isDown: false } as Phaser.Input.Keyboard.Key,
    leftAlt: { isDown: false } as Phaser.Input.Keyboard.Key,
    rightAlt: { isDown: false } as Phaser.Input.Keyboard.Key,
    boost: { isDown: false } as Phaser.Input.Keyboard.Key,
    jump: { isDown: false } as Phaser.Input.Keyboard.Key,
    trick: { isDown: false } as Phaser.Input.Keyboard.Key,
    stretch: { isDown: false } as Phaser.Input.Keyboard.Key,
    squash: { isDown: false } as Phaser.Input.Keyboard.Key,
    teleport: { isDown: false } as Phaser.Input.Keyboard.Key,
    interact: { isDown: false } as Phaser.Input.Keyboard.Key,
  };
}

export interface InputBindings {
  controls: Controls;
  dispose: () => void;
}

export function createControls(
  scene: Phaser.Scene,
  onEatKey: () => void,
): InputBindings {
  const keyboard = scene.input.keyboard;
  if (!keyboard) {
    throw new Error('Keyboard input is not available.');
  }

  const cursorKeys = keyboard.createCursorKeys();
  const extraKeys = keyboard.addKeys({
    upAlt: Phaser.Input.Keyboard.KeyCodes.I,
    downAlt: Phaser.Input.Keyboard.KeyCodes.K,
    leftAlt: Phaser.Input.Keyboard.KeyCodes.J,
    rightAlt: Phaser.Input.Keyboard.KeyCodes.L,
    boost: Phaser.Input.Keyboard.KeyCodes.Q,
    jump: Phaser.Input.Keyboard.KeyCodes.SPACE,
    trick: Phaser.Input.Keyboard.KeyCodes.E,
    stretch: Phaser.Input.Keyboard.KeyCodes.R,
    squash: Phaser.Input.Keyboard.KeyCodes.T,
    teleport: Phaser.Input.Keyboard.KeyCodes.Y,
    interact: Phaser.Input.Keyboard.KeyCodes.F,
  }) as Omit<Controls, keyof Phaser.Types.Input.Keyboard.CursorKeys>;

  const controls: Controls = { ...cursorKeys, ...extraKeys };

  const wKey = keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.W);
  const eatHandler = () => onEatKey();
  wKey.on('down', eatHandler, scene);

  return {
    controls,
    dispose: () => {
      wKey.off('down', eatHandler, scene);
    },
  };
}
