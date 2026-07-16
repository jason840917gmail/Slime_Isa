import Phaser from 'phaser';
import { floatingText } from '../ui/FloatingText';

/**
 * Enemy AI states. Composable behaviors — the Enemy class delegates per-state
 * logic to functions in EnemyAI.ts. States transition via return values.
 */
export type EnemyState = 'idle' | 'wander' | 'chase' | 'attack' | 'flee' | 'dead';

export interface EnemySafeZone {
  x: number;
  y: number;
  radius: number;
}

export interface EnemyStateContext {
  enemy: Phaser.Physics.Arcade.Sprite;
  player: Phaser.Physics.Arcade.Sprite;
  time: number;
  delta: number;
  /** Distance to player. */
  distToPlayer: number;
  /** Normalized direction to player. */
  dirToPlayer: Phaser.Math.Vector2;
  /** Config-driven behavior parameters. */
  config: EnemyAIConfig;
  /** Fire a projectile (for ranged enemies). */
  fireProjectile?: (x: number, y: number, dx: number, dy: number) => void;
  /** Apply a telegraph flash before attacking. */
  telegraph?: (durationMs: number) => void;
  /** Areas enemies should not enter, such as the player's house. */
  safeZones?: EnemySafeZone[];
}

export interface EnemyAIConfig {
  /** Detection range — switch from wander to chase. */
  aggroRange: number;
  /** Attack range — switch from chase to attack. */
  attackRange: number;
  /** Leap/charge attack range (for bouncers). */
  leapRange?: number;
  /** Flee range — caster keeps this distance. */
  fleeRange?: number;
  /** Move speed while wandering. */
  wanderSpeed: number;
  /** Move speed while chasing. */
  chaseSpeed: number;
  /** Attack cooldown in ms. */
  attackCooldownMs: number;
  /** Attack windup (telegraph) in ms. */
  attackWindupMs: number;
  /** Contact damage dealt to the player on touch. */
  contactDamage: number;
  /** Whether the enemy uses ranged attacks. */
  isRanged: boolean;
  /** Projectile speed (if ranged). */
  projectileSpeed?: number;
  /** Whether the enemy leaps (bouncer). */
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
    const dx = ctx.enemy.x - zone.x;
    const dy = ctx.enemy.y - zone.y;
    const dist = Math.hypot(dx, dy);
    if (dist > zone.radius) continue;

    const body = ctx.enemy.body as Phaser.Physics.Arcade.Body;
    const away = new Phaser.Math.Vector2(dx, dy);
    if (away.lengthSq() === 0) {
      away.set(ctx.enemy.x - ctx.player.x, ctx.enemy.y - ctx.player.y);
    }
    if (away.lengthSq() === 0) away.set(1, 0);
    away.normalize().scale(ctx.config.chaseSpeed * 1.25);
    body.setVelocity(away.x, away.y);
    return 'flee';
  }

  return null;
}

function stateIdle(ctx: EnemyStateContext): StateResult {
  const { enemy, distToPlayer, config } = ctx;
  const body = enemy.body as Phaser.Physics.Arcade.Body;
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
  const body = enemy.body as Phaser.Physics.Arcade.Body;

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
  const body = enemy.body as Phaser.Physics.Arcade.Body;

  if (distToPlayer > config.aggroRange * 1.5) {
    return 'wander';
  }

  // Caster types flee to maintain distance instead of closing in.
  if (config.fleeRange && distToPlayer < config.fleeRange) {
    return 'flee';
  }

  if (distToPlayer <= config.attackRange) {
    body.setVelocity(0, 0);
    return 'attack';
  }

  // Leap check for bouncers.
  if (config.isLeaper && config.leapRange && distToPlayer <= config.leapRange) {
    body.setVelocity(0, 0);
    return 'attack';
  }

  body.setVelocity(dirToPlayer.x * config.chaseSpeed, dirToPlayer.y * config.chaseSpeed);
  return 'continue';
}

function stateAttack(ctx: EnemyStateContext): StateResult {
  const { enemy, player, dirToPlayer, distToPlayer, config, time, fireProjectile, telegraph } = ctx;
  const body = enemy.body as Phaser.Physics.Arcade.Body;

  // If the player moved away, resume chasing.
  if (distToPlayer > config.attackRange * 1.3) {
    return 'chase';
  }

  // Ranged: fire projectile.
  if (config.isRanged && fireProjectile) {
    const cooldown = (enemy as any)._lastAttackAt as number;
    if (!cooldown || time >= cooldown + config.attackCooldownMs) {
      telegraph?.(config.attackWindupMs);
      enemy.scene.time.delayedCall(config.attackWindupMs, () => {
        if (!enemy.active) return;
        fireProjectile(enemy.x, enemy.y, dirToPlayer.x, dirToPlayer.y);
      });
      (enemy as any)._lastAttackAt = time;
    }
    // After firing, reposition.
    body.setVelocity(0, 0);
    return 'continue';
  }

  // Melee / leaper: telegraph then lunge.
  const cooldown = (enemy as any)._lastAttackAt as number;
  if (!cooldown || time >= cooldown + config.attackCooldownMs) {
    telegraph?.(config.attackWindupMs);
    enemy.scene.time.delayedCall(config.attackWindupMs, () => {
      if (!enemy.active) return;
      const lungeSpeed = config.isLeaper ? config.chaseSpeed * 2.2 : config.chaseSpeed * 1.4;
      body.setVelocity(dirToPlayer.x * lungeSpeed, dirToPlayer.y * lungeSpeed);
    });
    (enemy as any)._lastAttackAt = time;
  }

  // Stop between attacks.
  if (time > (cooldown ?? 0) + config.attackWindupMs + 200) {
    body.setVelocity(0, 0);
  }
  return 'continue';
}

function stateFlee(ctx: EnemyStateContext): StateResult {
  const { enemy, dirToPlayer, distToPlayer, config } = ctx;
  const body = enemy.body as Phaser.Physics.Arcade.Body;

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
