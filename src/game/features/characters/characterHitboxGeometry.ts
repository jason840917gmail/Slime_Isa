import type { CharacterHitboxDocument } from '../../content/characters/types';

export interface CharacterHitboxRectangle {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export interface CharacterHitboxAnchor {
  readonly x: number;
  readonly y: number;
}

/** Resolve an authored hitbox into world-space top-left rectangle coordinates. */
export function resolveCharacterHitboxRectangle(
  hitbox: CharacterHitboxDocument,
  anchor: CharacterHitboxAnchor,
  facingX: 1 | -1,
): CharacterHitboxRectangle {
  const centerX = anchor.x + (hitbox.mirrorX ? hitbox.offsetX * facingX : hitbox.offsetX);
  const centerY = anchor.y + hitbox.offsetY;
  return {
    x: centerX - hitbox.width / 2,
    y: centerY - hitbox.height / 2,
    width: hitbox.width,
    height: hitbox.height,
  };
}

/** Match Phaser's rectangle overlap behavior: edge-touching rectangles do not overlap. */
export function characterHitboxesIntersect(
  first: CharacterHitboxRectangle,
  second: CharacterHitboxRectangle,
): boolean {
  return first.x < second.x + second.width
    && first.x + first.width > second.x
    && first.y < second.y + second.height
    && first.y + first.height > second.y;
}
