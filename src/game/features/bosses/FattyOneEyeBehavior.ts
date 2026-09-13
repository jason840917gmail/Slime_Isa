import type { MapEnemyAreaPerimeter } from '../../content/maps/mapFormat';

export type FattyOneEyePhase = 'chase' | 'return-to-center' | 'contact-hop' | 'small-hop' | 'airborne' | 'landing' | 'recovery' | 'dead';

export interface ContactHopEligibility {
  readonly alive: boolean;
  readonly destroyed: boolean;
  readonly phase: FattyOneEyePhase;
  readonly time: number;
  readonly nextContactHopAt: number;
}

export function canRequestContactHop(state: ContactHopEligibility): boolean {
  return state.alive
    && !state.destroyed
    && state.phase === 'chase'
    && Number.isFinite(state.time)
    && state.time >= state.nextContactHopAt;
}

export function bossArenaCenter(perimeter: MapEnemyAreaPerimeter): Readonly<{ x: number; y: number }> {
  return perimeter.shape === 'circle'
    ? { x: perimeter.x, y: perimeter.y }
    : { x: perimeter.x + perimeter.w / 2, y: perimeter.y + perimeter.h / 2 };
}

export function bossAnchorOutsideArena(
  perimeter: MapEnemyAreaPerimeter,
  point: Readonly<{ x: number; y: number }>,
): boolean {
  if (![point.x, point.y, perimeter.x, perimeter.y].every(Number.isFinite)) return true;
  if (perimeter.shape === 'circle') {
    const dx = point.x - perimeter.x;
    const dy = point.y - perimeter.y;
    return dx * dx + dy * dy > perimeter.radius * perimeter.radius;
  }
  return point.x < perimeter.x || point.x > perimeter.x + perimeter.w
    || point.y < perimeter.y || point.y > perimeter.y + perimeter.h;
}

export function shouldBossReturnToArenaCenter(
  perimeter: MapEnemyAreaPerimeter,
  player: Readonly<{ x: number; y: number }>,
): boolean {
  return !canBossBeginAttack(perimeter, player);
}

export function canBossBeginAttack(
  perimeter: MapEnemyAreaPerimeter,
  player: Readonly<{ x: number; y: number }>,
): boolean {
  return !bossAnchorOutsideArena(perimeter, player);
}

export function shouldResumePursuitFromReturn(
  perimeter: MapEnemyAreaPerimeter,
  player: Readonly<{ x: number; y: number }>,
): boolean {
  return canBossBeginAttack(perimeter, player);
}

export function contactHopProgress(time: number, startedAt: number, durationMs: number): number {
  if (!Number.isFinite(time) || !Number.isFinite(startedAt) || !Number.isFinite(durationMs) || durationMs <= 0) return 0;
  return Math.max(0, Math.min(1, (time - startedAt) / durationMs));
}

export function contactHopVisualHeight(progress: number, maximumHeight = 48): number {
  const normalized = Math.max(0, Math.min(1, Number.isFinite(progress) ? progress : 0));
  if (normalized === 0 || normalized === 1) return 0;
  return Math.sin(normalized * Math.PI) * Math.max(0, maximumHeight);
}

export function landingRadiusContains(
  center: Readonly<{ x: number; y: number }>,
  point: Readonly<{ x: number; y: number }>,
  radius: number,
): boolean {
  if (![center.x, center.y, point.x, point.y, radius].every(Number.isFinite) || radius <= 0) return false;
  const dx = point.x - center.x;
  const dy = point.y - center.y;
  return dx * dx + dy * dy <= radius * radius;
}

export function shouldApplyContactHopLandingHit(input: {
  readonly center: Readonly<{ x: number; y: number }>;
  readonly player: Readonly<{ x: number; y: number; active: boolean }>;
  readonly radius: number;
  readonly dodging: boolean;
}): boolean {
  return input.player.active && !input.dodging && landingRadiusContains(input.center, input.player, input.radius);
}

export function contactHopCompletion(nextLeapAt: number): { readonly phase: 'chase'; readonly nextLeapAt: number } {
  return { phase: 'chase', nextLeapAt };
}
