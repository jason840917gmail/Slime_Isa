import { normalizeWeaponDefinition } from '../content/weapons/normalize';
import type {
  NormalizedWeaponDirectionalAttack,
  WeaponAttackDirection,
  WeaponAttackTrackDocument,
  WeaponDefinition,
  WeaponHitboxDocument,
  WeaponHitboxShape,
} from '../content/weapons/types';
import { LEGACY_WEAPON_SECTOR_ARC_RAD } from '../content/weapons/types';
import { timelineFrameCount } from '../shared/animation';

export const WEAPON_HITBOX_PREVIEW_SCALE = 2;

export interface ResolvedWeaponHitboxPreview {
  readonly attack: NormalizedWeaponDirectionalAttack;
  readonly direction: WeaponAttackDirection;
  readonly track: WeaponAttackTrackDocument;
  readonly trackMode: 'authored' | 'synthetic';
}

export interface WeaponHitboxPreviewGeometry {
  readonly shape: WeaponHitboxShape;
  readonly centerX: number;
  readonly centerY: number;
  readonly width: number;
  readonly height: number;
  readonly valid: boolean;
  readonly invalidReason?: string;
  readonly sectorAreaPath?: string;
  readonly sectorBoundaryPath?: string;
  readonly sectorViewBox?: string;
}

function finite(value: number): boolean {
  return Number.isFinite(value);
}

function pathNumber(value: number): string {
  const rounded = Math.round(value * 1000) / 1000;
  return String(Object.is(rounded, -0) ? 0 : rounded);
}

function pointAt(center: number, radius: number, angle: number): readonly [number, number] {
  return [center + Math.cos(angle) * radius, center + Math.sin(angle) * radius];
}

function pointCommand(point: readonly [number, number]): string {
  return `${pathNumber(point[0])} ${pathNumber(point[1])}`;
}

function fullCirclePath(center: number, outerRadius: number, innerRadius: number): string {
  const outerRight = `${pathNumber(center + outerRadius)} ${pathNumber(center)}`;
  const outerLeft = `${pathNumber(center - outerRadius)} ${pathNumber(center)}`;
  const outer = `M ${outerRight} A ${pathNumber(outerRadius)} ${pathNumber(outerRadius)} 0 1 1 ${outerLeft} A ${pathNumber(outerRadius)} ${pathNumber(outerRadius)} 0 1 1 ${outerRight} Z`;
  if (innerRadius <= 0) return outer;
  const innerRight = `${pathNumber(center + innerRadius)} ${pathNumber(center)}`;
  const innerLeft = `${pathNumber(center - innerRadius)} ${pathNumber(center)}`;
  return `${outer} M ${innerRight} A ${pathNumber(innerRadius)} ${pathNumber(innerRadius)} 0 1 0 ${innerLeft} A ${pathNumber(innerRadius)} ${pathNumber(innerRadius)} 0 1 0 ${innerRight} Z`;
}

function sectorPaths(
  outerRadius: number,
  innerRadius: number,
  angle: number,
  arcWidth: number,
): Pick<WeaponHitboxPreviewGeometry, 'sectorAreaPath' | 'sectorBoundaryPath' | 'sectorViewBox'> {
  const diameter = outerRadius * 2;
  const center = outerRadius;
  const viewBox = `0 0 ${pathNumber(diameter)} ${pathNumber(diameter)}`;
  if (arcWidth >= Math.PI * 2 - 1e-6) {
    return { sectorAreaPath: fullCirclePath(center, outerRadius, innerRadius), sectorViewBox: viewBox };
  }

  const startAngle = angle - arcWidth / 2;
  const endAngle = angle + arcWidth / 2;
  const outerStart = pointAt(center, outerRadius, startAngle);
  const outerEnd = pointAt(center, outerRadius, endAngle);
  const innerStart = pointAt(center, innerRadius, startAngle);
  const innerEnd = pointAt(center, innerRadius, endAngle);

  if (arcWidth <= 1e-6) {
    const origin = innerRadius > 0 ? innerStart : [center, center] as const;
    const boundary = `M ${pointCommand(origin)} L ${pointCommand(outerStart)} M ${pointCommand(innerRadius > 0 ? innerEnd : [center, center])} L ${pointCommand(outerEnd)}`;
    return { sectorBoundaryPath: boundary, sectorViewBox: viewBox };
  }

  const largeArc = arcWidth > Math.PI ? 1 : 0;
  const outerArc = `A ${pathNumber(outerRadius)} ${pathNumber(outerRadius)} 0 ${largeArc} 1 ${pointCommand(outerEnd)}`;
  if (innerRadius <= 0) {
    return {
      sectorAreaPath: `M ${pathNumber(center)} ${pathNumber(center)} L ${pointCommand(outerStart)} ${outerArc} Z`,
      sectorViewBox: viewBox,
    };
  }

  const innerArc = `A ${pathNumber(innerRadius)} ${pathNumber(innerRadius)} 0 ${largeArc} 0 ${pointCommand(innerStart)}`;
  return {
    sectorAreaPath: `M ${pointCommand(outerStart)} ${outerArc} L ${pointCommand(innerEnd)} ${innerArc} Z`,
    sectorViewBox: viewBox,
  };
}

function invalidGeometry(shape: WeaponHitboxShape, reason: string): WeaponHitboxPreviewGeometry {
  return { shape, centerX: 0, centerY: 0, width: 0, height: 0, valid: false, invalidReason: reason };
}

export function weaponHitboxPreviewOffset(
  direction: WeaponAttackDirection,
  offsetX: number,
  offsetY: number,
): readonly [number, number] {
  if (direction === 'right') return [offsetX, offsetY];
  if (direction === 'left') return [-offsetX, offsetY];
  if (direction === 'up') return [offsetY, -offsetX];
  return [-offsetY, offsetX];
}

export function weaponHitboxPreviewAngle(direction: WeaponAttackDirection): number {
  if (direction === 'left') return Math.PI;
  if (direction === 'up') return -Math.PI / 2;
  if (direction === 'down') return Math.PI / 2;
  return 0;
}

export function resolveWeaponHitboxPreview(
  weapon: WeaponDefinition,
  direction: WeaponAttackDirection,
): ResolvedWeaponHitboxPreview {
  const attack = normalizeWeaponDefinition(weapon).directionalAttacks[direction];
  if (attack.attackTrack) return { attack, direction, track: attack.attackTrack, trackMode: 'authored' };
  const firstHitboxId = Object.keys(attack.hitboxes)[0];
  const timelineFrames = timelineFrameCount(attack.animation);
  return {
    attack,
    direction,
    trackMode: 'synthetic',
    track: {
      hitboxSpans: firstHitboxId
        ? [{ hitboxId: firstHitboxId, from: 0, through: Math.max(0, timelineFrames - 1) }]
        : [],
      events: [],
    },
  };
}

export function weaponHitboxIsActive(
  preview: ResolvedWeaponHitboxPreview,
  hitboxId: string,
  timelineFrame: number,
): boolean {
  return preview.track.hitboxSpans.some((span) => (
    span.hitboxId === hitboxId
    && span.from <= timelineFrame
    && timelineFrame <= span.through
  ));
}

export function weaponAttackTrackScopeLabel(direction: WeaponAttackDirection): string {
  return `ATTACK / ${direction.toUpperCase()}`;
}

export function resolveWeaponHitboxPreviewGeometry(
  hitbox: WeaponHitboxDocument,
  direction: WeaponAttackDirection,
): WeaponHitboxPreviewGeometry {
  if (hitbox.shape === 'sector') {
    const outerRadius = hitbox.outerRadius ?? hitbox.offsetX + hitbox.width / 2;
    const innerRadius = hitbox.innerRadius ?? 0;
    const rawArcWidth = hitbox.arcWidthRad ?? LEGACY_WEAPON_SECTOR_ARC_RAD;
    if (![outerRadius, innerRadius, rawArcWidth, hitbox.offsetX, hitbox.offsetY].every(finite)) return invalidGeometry(hitbox.shape, 'Non-finite sector geometry');
    if (outerRadius <= 0) return invalidGeometry(hitbox.shape, 'Outer radius must be positive');
    if (innerRadius < 0 || innerRadius >= outerRadius) return invalidGeometry(hitbox.shape, 'Inner radius must be smaller than outer radius');
    const arcWidth = Math.max(0, Math.min(Math.PI * 2, rawArcWidth));
    const paths = sectorPaths(outerRadius, innerRadius, weaponHitboxPreviewAngle(direction), arcWidth);
    const [centerX, centerY] = weaponHitboxPreviewOffset(direction, hitbox.offsetX, hitbox.offsetY);
    return {
      shape: hitbox.shape,
      centerX,
      centerY,
      width: outerRadius * 2,
      height: outerRadius * 2,
      valid: true,
      ...paths,
    };
  }

  if (![hitbox.offsetX, hitbox.offsetY].every(finite)) return invalidGeometry(hitbox.shape, 'Offsets must be finite');
  const [centerX, centerY] = weaponHitboxPreviewOffset(direction, hitbox.offsetX, hitbox.offsetY);
  if (hitbox.shape === 'rectangle') {
    if (![hitbox.width, hitbox.height].every(finite) || hitbox.width <= 0 || hitbox.height <= 0) {
      return invalidGeometry(hitbox.shape, 'Dimensions must be positive');
    }
    return { shape: hitbox.shape, centerX, centerY, width: hitbox.width, height: hitbox.height, valid: true };
  }

  const radiusX = hitbox.radiusX ?? hitbox.radius ?? hitbox.width / 2;
  const radiusY = hitbox.radiusY ?? hitbox.radius ?? hitbox.height / 2;
  if (![radiusX, radiusY].every(finite) || radiusX <= 0 || radiusY <= 0) {
    return invalidGeometry(hitbox.shape, 'Radii must be positive');
  }
  return { shape: hitbox.shape, centerX, centerY, width: radiusX * 2, height: radiusY * 2, valid: true };
}
