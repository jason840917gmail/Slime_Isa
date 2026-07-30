import type {
  EnemyAIConfig,
  EnemyDirection,
  EnemyState,
  EnemyStateContext,
  EnemyVelocityBody,
  StateResult,
} from '../EnemyAI';

/**
 * Ranged spider behavior: approach while orbiting, hold a preferred distance,
 * retreat around the player when pressured, and keep firing through the shared
 * Enemy attack lifecycle.
 */
export function runSlimeSpiderState(state: EnemyState, ctx: EnemyStateContext): StateResult {
  switch (state) {
    case 'idle':
      return spiderIdle(ctx);
    case 'wander':
      return spiderWander(ctx);
    case 'chase':
      return spiderChase(ctx);
    case 'flee':
      return spiderFlee(ctx);
    case 'attack':
      return spiderAttack(ctx);
    case 'dead':
      return 'continue';
  }
}

function preferredDistance(config: EnemyAIConfig): number {
  return Math.max(1, config.fleeRange ?? config.attackRange * 0.55);
}

function spiderIdle(ctx: EnemyStateContext): StateResult {
  const body = ctx.enemy.body as EnemyVelocityBody;
  body.setVelocity(0, 0);
  if (ctx.distToPlayer <= ctx.config.aggroRange) return 'chase';
  if (Math.random() < 0.008) return 'wander';
  return 'continue';
}

function spiderWander(ctx: EnemyStateContext): StateResult {
  const body = ctx.enemy.body as EnemyVelocityBody;
  if (ctx.distToPlayer <= ctx.config.aggroRange) {
    body.setVelocity(0, 0);
    return 'chase';
  }
  if (Math.random() < 0.02) {
    const angle = Math.random() * Math.PI * 2;
    body.setVelocity(
      Math.cos(angle) * ctx.config.wanderSpeed,
      Math.sin(angle) * ctx.config.wanderSpeed,
    );
  }
  if (Math.random() < 0.004) {
    body.setVelocity(0, 0);
    return 'idle';
  }
  return 'continue';
}

function spiderChase(ctx: EnemyStateContext): StateResult {
  if (ctx.distToPlayer > ctx.config.aggroRange * 1.5) return 'wander';

  const preferred = preferredDistance(ctx.config);
  if (ctx.distToPlayer <= ctx.config.attackRange) {
    if (ctx.distToPlayer < preferred) return 'flee';
    const body = ctx.enemy.body as EnemyVelocityBody;
    body.setVelocity(0, 0);
    return 'attack';
  }

  setOrbitVelocity(ctx, 0.86, 0.52, ctx.config.chaseSpeed);
  return 'continue';
}

function spiderFlee(ctx: EnemyStateContext): StateResult {
  if (ctx.distToPlayer > ctx.config.aggroRange * 1.5) return 'wander';

  const preferred = preferredDistance(ctx.config);
  if (ctx.distToPlayer >= preferred) {
    if (ctx.distToPlayer <= ctx.config.attackRange) return 'attack';
    return 'chase';
  }

  setOrbitVelocity(ctx, -0.92, 0.44, ctx.config.chaseSpeed * 1.08);
  return 'continue';
}

function spiderAttack(ctx: EnemyStateContext): StateResult {
  const body = ctx.enemy.body as EnemyVelocityBody;
  if (ctx.distToPlayer > ctx.config.attackRange * 1.3) return 'chase';
  if (ctx.distToPlayer < preferredDistance(ctx.config) * 0.72) return 'flee';
  body.setVelocity(0, 0);
  ctx.requestAttack?.(ctx.dirToPlayer.clone());
  return 'continue';
}

function setOrbitVelocity(
  ctx: EnemyStateContext,
  radialWeight: number,
  lateralWeight: number,
  speed: number,
): void {
  const body = ctx.enemy.body as EnemyVelocityBody;
  const direction = ctx.dirToPlayer;
  const orbitSign = Math.sin(ctx.enemy.x * 0.017 + ctx.enemy.y * 0.013) >= 0 ? 1 : -1;
  const tangent: EnemyDirection = {
    x: -direction.y * orbitSign,
    y: direction.x * orbitSign,
    clone: () => tangent,
  };
  const x = direction.x * radialWeight + tangent.x * lateralWeight;
  const y = direction.y * radialWeight + tangent.y * lateralWeight;
  const length = Math.hypot(x, y) || 1;
  body.setVelocity((x / length) * speed, (y / length) * speed);
}
