/**
 * Enemy AI states. Composable behaviors — the Enemy class delegates per-state
 * logic to functions in EnemyAI.ts. States transition via return values.
 */
export type EnemyState = 'idle' | 'wander' | 'chase' | 'attack' | 'flee' | 'dead';

export interface EnemyDirection {
  readonly x: number;
  readonly y: number;
  clone(): EnemyDirection;
}

export interface EnemyVelocityBody {
  setVelocity(x: number, y: number): void;
  velocity: { scale(amount: number): void };
}

export interface EnemyStateEntity {
  readonly x: number;
  readonly y: number;
  readonly body: unknown;
}

export interface EnemySafeZone {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface EnemyStateContext {
  enemy: EnemyStateEntity;
  player: { readonly x: number; readonly y: number };
  time: number;
  delta: number;
  /** Distance to player. */
  distToPlayer: number;
  /** Normalized direction to player. */
  dirToPlayer: EnemyDirection;
  /** Config-driven behavior parameters. */
  config: EnemyAIConfig;
  /** Requests one typed attack sequence; Enemy owns timing and effects. */
  requestAttack?: (direction: EnemyDirection) => void;
  /** Areas enemies should not enter, such as the player's house. */
  safeZones?: EnemySafeZone[];
}

export interface EnemyAIConfig {
  /** Detection range — switch from wander to chase. */
  aggroRange: number;
  /** Attack range — switch from chase to attack. */
  attackRange: number;
  /** Optional leap/charge attack range. */
  leapRange?: number;
  /** Distance a ranged or evasive enemy tries to maintain. */
  fleeRange?: number;
  /** Move speed while wandering. */
  wanderSpeed: number;
  /** Move speed while chasing. */
  chaseSpeed: number;
  /** Attack cooldown in ms. */
  attackCooldownMs: number;
  /** Attack windup (telegraph) in ms. */
  attackWindupMs: number;
  /** Recovery after the impact/fire moment in ms. */
  attackRecoveryMs: number;
  /** Contact damage dealt to the player on touch. */
  contactDamage: number;
  /** Player knockback speed applied by an accepted attack. */
  knockbackStrength: number;
  /** Whether the enemy uses ranged attacks. */
  isRanged: boolean;
  /** Projectile speed (if ranged). */
  projectileSpeed?: number;
  /** Whether the enemy uses a leap/charge attack. */
  isLeaper?: boolean;
  /** Knockback resistance (0 = full knockback, 1 = immune). */
  knockbackResist: number;
}

export type StateResult = EnemyState | 'continue';

/** Run the current state; returns the next state or 'continue'. */
export function runState(state: EnemyState, ctx: EnemyStateContext): StateResult {
  if (state !== 'dead') {
    const safeZoneResult = avoidSafeZones(ctx);
    if (safeZoneResult) return safeZoneResult;
  }

  switch (state) {
    case 'idle':
      return stateIdle(ctx);
    case 'wander':
      return stateWander(ctx);
    case 'chase':
      return stateChase(ctx);
    case 'attack':
      return stateAttack(ctx);
    case 'flee':
      return stateFlee(ctx);
    case 'dead':
      return 'continue';
  }
  return 'continue';
}

function avoidSafeZones(ctx: EnemyStateContext): StateResult | null {
  const zones = ctx.safeZones;
  if (!zones || zones.length === 0) return null;

  for (const zone of zones) {
    if (ctx.enemy.x < zone.x || ctx.enemy.x > zone.x + zone.w
      || ctx.enemy.y < zone.y || ctx.enemy.y > zone.y + zone.h) continue;

    const body = ctx.enemy.body as EnemyVelocityBody;
    const distances = [
      { distance: ctx.enemy.x - zone.x, x: -1, y: 0 },
      { distance: zone.x + zone.w - ctx.enemy.x, x: 1, y: 0 },
      { distance: ctx.enemy.y - zone.y, x: 0, y: -1 },
      { distance: zone.y + zone.h - ctx.enemy.y, x: 0, y: 1 },
    ];
    let nearest = distances[0];
    for (const candidate of distances.slice(1)) {
      if (candidate.distance < nearest.distance) nearest = candidate;
    }
    const length = Math.hypot(nearest.x, nearest.y) || 1;
    const speed = ctx.config.chaseSpeed * 1.25;
    body.setVelocity((nearest.x / length) * speed, (nearest.y / length) * speed);
    return 'flee';
  }

  return null;
}

function stateIdle(ctx: EnemyStateContext): StateResult {
  const { enemy, distToPlayer, config } = ctx;
  const body = enemy.body as EnemyVelocityBody;
  body.setVelocity(0, 0);

  if (distToPlayer <= config.aggroRange) {
    return 'chase';
  }
  // Short idle → wander.
  if (Math.random() < 0.01) return 'wander';
  return 'continue';
}

function stateWander(ctx: EnemyStateContext): StateResult {
  const { enemy, distToPlayer, config } = ctx;
  const body = enemy.body as EnemyVelocityBody;

  if (distToPlayer <= config.aggroRange) {
    body.setVelocity(0, 0);
    return 'chase';
  }

  // Random wander: pick a direction every ~1s.
  if (Math.random() < 0.02) {
    const angle = Math.random() * Math.PI * 2;
    body.setVelocity(Math.cos(angle) * config.wanderSpeed, Math.sin(angle) * config.wanderSpeed);
  }
  // Occasionally idle.
  if (Math.random() < 0.005) {
    body.setVelocity(0, 0);
    return 'idle';
  }
  return 'continue';
}

function stateChase(ctx: EnemyStateContext): StateResult {
  const { enemy, dirToPlayer, distToPlayer, config } = ctx;
  const body = enemy.body as EnemyVelocityBody;

  if (distToPlayer > config.aggroRange * 1.5) {
    return 'wander';
  }

  // Ranged or evasive enemies flee to maintain distance instead of closing in.
  if (config.fleeRange && distToPlayer < config.fleeRange) {
    return 'flee';
  }

  if (distToPlayer <= config.attackRange) {
    body.setVelocity(0, 0);
    return 'attack';
  }

  // Optional leap/charge check.
  if (config.isLeaper && config.leapRange && distToPlayer <= config.leapRange) {
    body.setVelocity(0, 0);
    return 'attack';
  }

  body.setVelocity(dirToPlayer.x * config.chaseSpeed, dirToPlayer.y * config.chaseSpeed);
  return 'continue';
}

function stateAttack(ctx: EnemyStateContext): StateResult {
  const { enemy, dirToPlayer, distToPlayer, config, requestAttack } = ctx;
  const body = enemy.body as EnemyVelocityBody;

  // If the player moved away, resume chasing.
  if (distToPlayer > config.attackRange * 1.3) {
    return 'chase';
  }

  body.setVelocity(0, 0);
  requestAttack?.(dirToPlayer.clone());
  return 'continue';
}

function stateFlee(ctx: EnemyStateContext): StateResult {
  const { enemy, dirToPlayer, distToPlayer, config } = ctx;
  const body = enemy.body as EnemyVelocityBody;

  // If far enough, stop fleeing and attack.
  if (config.fleeRange && distToPlayer >= config.fleeRange) {
    body.setVelocity(0, 0);
    return 'attack';
  }

  // If player is far beyond aggro, go back to wander.
  if (distToPlayer > config.aggroRange * 1.5) {
    return 'wander';
  }

  // Run away from the player.
  body.setVelocity(-dirToPlayer.x * config.chaseSpeed, -dirToPlayer.y * config.chaseSpeed);
  return 'continue';
}
