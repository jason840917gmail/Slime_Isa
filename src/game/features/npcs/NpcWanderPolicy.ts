import type { CollisionShapeDocument } from '../../shared/collisionShapes';
import type { MapAgentAreaPerimeter, MapPoint } from '../../content/maps/mapFormat';
import { npcAnchorDomain } from '../../content/npcs/npcWanderGeometry';
import { randomPointInPerimeter } from '../../content/maps/agentAreaGeometry';

export const NPC_AREA_MARGIN = 8;
export const NPC_TARGET_ARRIVAL_DISTANCE = 6;
export const NPC_STUCK_PROGRESS_DISTANCE = 2;
export const NPC_STUCK_SAMPLE_MS = 750;

export type NpcFacing = 'down' | 'up' | 'left' | 'right';
export type NpcWanderPhase = 'pause' | 'move';

export interface NpcWanderState {
  readonly phase: NpcWanderPhase;
  readonly pauseRemainingMs: number;
  readonly target?: MapPoint;
  readonly facing: NpcFacing;
  readonly stuckSampleRemainingMs: number;
  readonly previousDistance?: number;
}

export interface NpcWanderStepInput {
  readonly position: MapPoint;
  readonly deltaMs: number;
  readonly speed: number;
  readonly body: CollisionShapeDocument;
  readonly perimeter: MapAgentAreaPerimeter;
  readonly random?: () => number;
}

export interface NpcWanderStepResult {
  readonly state: NpcWanderState;
  readonly velocity: MapPoint;
  readonly animation: `walk-${NpcFacing}` | 'idle';
}

export function createNpcWanderState(pauseRemainingMs = 0, facing: NpcFacing = 'down'): NpcWanderState {
  return {
    phase: pauseRemainingMs > 0 ? 'pause' : 'move',
    pauseRemainingMs: Math.max(0, pauseRemainingMs),
    facing,
    stuckSampleRemainingMs: NPC_STUCK_SAMPLE_MS,
  };
}

export function sampleNpcWanderTarget(
  perimeter: MapAgentAreaPerimeter,
  body: CollisionShapeDocument,
  random: () => number = Math.random,
): MapPoint | undefined {
  const domain = npcAnchorDomain(perimeter, body, NPC_AREA_MARGIN);
  return domain ? randomPointInPerimeter(domain, random) : undefined;
}

export function stepNpcWander(
  state: NpcWanderState,
  input: NpcWanderStepInput,
): NpcWanderStepResult {
  const deltaMs = Number.isFinite(input.deltaMs) ? Math.max(0, input.deltaMs) : 0;
  const speed = Number.isFinite(input.speed) ? Math.max(0, input.speed) : 0;
  const random = input.random ?? Math.random;
  if (speed <= 0) return { state: createNpcWanderState(0, state.facing), velocity: { x: 0, y: 0 }, animation: 'idle' };

  let next = state;
  if (next.phase === 'pause') {
    const remaining = Math.max(0, next.pauseRemainingMs - deltaMs);
    next = { ...next, pauseRemainingMs: remaining, phase: remaining > 0 ? 'pause' : 'move', target: undefined, stuckSampleRemainingMs: NPC_STUCK_SAMPLE_MS, previousDistance: undefined };
    if (next.phase === 'pause') return { state: next, velocity: { x: 0, y: 0 }, animation: 'idle' };
  }

  const target = next.target ?? sampleNpcWanderTarget(input.perimeter, input.body, random);
  if (!target) return { state: { ...next, phase: 'pause', pauseRemainingMs: 0, target: undefined }, velocity: { x: 0, y: 0 }, animation: 'idle' };
  const dx = target.x - input.position.x;
  const dy = target.y - input.position.y;
  const distance = Math.hypot(dx, dy);
  if (distance <= NPC_TARGET_ARRIVAL_DISTANCE) {
    return {
      state: { ...next, phase: 'pause', pauseRemainingMs: 0, target: undefined, stuckSampleRemainingMs: NPC_STUCK_SAMPLE_MS, previousDistance: undefined },
      velocity: { x: 0, y: 0 },
      animation: 'idle',
    };
  }

  const facing: NpcFacing = Math.abs(dx) >= Math.abs(dy) ? (dx < 0 ? 'left' : 'right') : (dy < 0 ? 'up' : 'down');
  const sampleRemaining = next.stuckSampleRemainingMs - deltaMs;
  const madeProgress = next.previousDistance === undefined || next.previousDistance - distance >= NPC_STUCK_PROGRESS_DISTANCE;
  if (sampleRemaining <= 0 && !madeProgress) {
    return {
      state: { ...next, phase: 'pause', pauseRemainingMs: 0, target: undefined, stuckSampleRemainingMs: NPC_STUCK_SAMPLE_MS, previousDistance: undefined },
      velocity: { x: 0, y: 0 },
      animation: 'idle',
    };
  }
  // Cap the final step so a large frame cannot carry the Arcade body past its
  // sampled anchor. Physics collisions may still stop the actor earlier; the
  // next policy tick will then use the stuck-recovery path.
  const deltaSeconds = deltaMs / 1000;
  const velocityMagnitude = deltaSeconds > 0 ? Math.min(speed, distance / deltaSeconds) : speed;
  return {
    state: { ...next, phase: 'move', target, facing, stuckSampleRemainingMs: sampleRemaining > 0 ? sampleRemaining : NPC_STUCK_SAMPLE_MS, previousDistance: sampleRemaining > 0 ? next.previousDistance ?? distance : distance },
    velocity: { x: (dx / distance) * velocityMagnitude, y: (dy / distance) * velocityMagnitude },
    animation: `walk-${facing}`,
  };
}
