import Phaser from 'phaser';
import { Enemy, type EnemyConfig, type EnemyContext } from './Enemy';
import type { EnemySafeZone } from './EnemyAI';
import type { MapEnemySpawnArea } from '../content/maps/mapFormat';
import { getEnemyConfig } from './library/EnemyTypes';
import {
  enemySpawnAreaContainsPlayer,
  randomPointInPerimeter,
} from '../content/maps/enemySpawnAreaGeometry';

/**
 * Area-aware enemy spawner. Manages population caps, despawns enemies that
 * wander too far from the player, and respawns over time to maintain a steady
 * population density for combat.
 */

export interface SpawnEntry {
  config: EnemyConfig;
  weight: number;
  maxAlive?: number;
}

export interface SpawnerContext {
  scene: Phaser.Scene;
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  enemyContext: EnemyContext;
  /** Max concurrent enemies. */
  maxPopulation: number;
  /** Spawn distance from the player (off-screen-ish). */
  spawnRadius: number;
  /** Despawn distance — enemies beyond this are removed. */
  despawnRadius: number;
  /** Min distance from the player to spawn (don't spawn on top). */
  minSpawnDistance: number;
  /** Available enemy types + weights. */
  spawnTable: SpawnEntry[];
  /** Authored camps. When non-empty, these replace legacy player-relative spawning. */
  spawnAreas?: readonly MapEnemySpawnArea[];
  /** Gives each enemy its immutable camp boundary context. */
  createEnemyContext?: (area?: MapEnemySpawnArea) => EnemyContext;
  /** World bounds for clamping spawn positions. */
  worldWidth: number;
  worldHeight: number;
  /** Physics group to add enemies to (for combat hitbox checks). */
  targetGroup?: Phaser.Physics.Arcade.Group;
  /** Areas where enemies should never spawn. */
  getSafeZones?: () => EnemySafeZone[];
  /** Delay between population refill attempts. */
  spawnIntervalMs: number;
}

export class EnemySpawner {
  private ctx: SpawnerContext;
  private enemies: Enemy[] = [];
  private readonly areaByEnemy = new Map<Enemy, MapEnemySpawnArea | undefined>();
  private readonly areaLastSpawnAt = new Map<string, number>();
  private lastSpawnAt = 0;
  private spawnIntervalMs = 1500;

  constructor(ctx: SpawnerContext) {
    this.ctx = ctx;
    this.spawnIntervalMs = ctx.spawnIntervalMs;
  }

  get group(): Enemy[] {
    return this.enemies;
  }

  get count(): number {
    return this.enemies.filter((e) => !e.dead).length;
  }

  /** Initial population — spawns up to cap immediately. */
  seed(count: number): void {
    if (this.ctx.spawnAreas && this.ctx.spawnAreas.length > 0) {
      const player = this.ctx.getPlayer();
      for (const area of this.ctx.spawnAreas) {
        if (!player || !enemySpawnAreaContainsPlayer(area, player.x, player.y)) continue;
        for (let i = 0; i < Math.min(count, area.maxPopulation); i += 1) this.spawnOne(area);
      }
      return;
    }
    for (let i = 0; i < count; i += 1) {
      this.spawnOne();
    }
  }

  update(time: number, _delta: number): void {
    // Despawn far enemies.
    const player = this.ctx.getPlayer();
    if (player) {
      this.enemies = this.enemies.filter((e) => {
        if (!e.active && !e.dead) {
          this.areaByEnemy.delete(e);
          e.destroy();
          return false;
        }
        if (e.dead) {
          this.areaByEnemy.delete(e);
          return false; // already handled by death tween
        }
        if (this.areaByEnemy.get(e)) return true;
        const d = Phaser.Math.Distance.Between(player.x, player.y, e.x, e.y);
        if (d > this.ctx.despawnRadius) {
          this.areaByEnemy.delete(e);
          e.destroy();
          return false;
        }
        return true;
      });
    }

    // Spawn over time to maintain population.
    if (this.ctx.spawnAreas && this.ctx.spawnAreas.length > 0) {
      for (const area of this.ctx.spawnAreas) {
        if (!enemySpawnAreaContainsPlayer(area, player.x, player.y)) continue;
        const areaCount = this.countForArea(area);
        const lastSpawnAt = this.areaLastSpawnAt.get(area.id) ?? 0;
        if (time > lastSpawnAt + area.intervalMs && areaCount < area.maxPopulation) {
          this.spawnOne(area);
          this.areaLastSpawnAt.set(area.id, time);
        }
      }
      return;
    }

    if (time > this.lastSpawnAt + this.spawnIntervalMs && this.count < this.ctx.maxPopulation) {
      this.spawnOne();
      this.lastSpawnAt = time;
    }
  }

  spawnOne(area?: MapEnemySpawnArea): Enemy | null {
    const player = this.ctx.getPlayer();
    if (!player) return null;

    if (!area && this.ctx.spawnAreas && this.ctx.spawnAreas.length > 0) {
      area = this.ctx.spawnAreas.find((candidate) => (
        enemySpawnAreaContainsPlayer(candidate, player.x, player.y)
        && this.countForArea(candidate) < candidate.maxPopulation
      ));
      if (!area) return null;
    }

    const areaSpawnTable = area?.enemies.map((entry) => ({
      config: getEnemyConfig(entry.type),
      weight: entry.weight,
      maxAlive: entry.maxAlive,
    })) ?? this.ctx.spawnTable;

    // Pick a weighted random enemy type.
    const availableEntries = areaSpawnTable.filter((candidate) => (
      candidate.maxAlive === undefined
      || this.enemies.filter((enemy) => !enemy.dead && enemy.config === candidate.config
        && this.areaByEnemy.get(enemy)?.id === area?.id).length < candidate.maxAlive
    ));
    if (availableEntries.length === 0) return null;

    const totalWeight = availableEntries.reduce((s, e) => s + e.weight, 0);
    let roll = Math.random() * totalWeight;
    let entry = availableEntries[0];
    for (const e of availableEntries) {
      roll -= e.weight;
      if (roll <= 0) {
        entry = e;
        break;
      }
    }

    const spawnPoint = this.findSpawnPoint(player, area);
    if (!spawnPoint) return null;

    const enemyContext = this.ctx.createEnemyContext?.(area) ?? { ...this.ctx.enemyContext, spawnArea: area };
    const enemy = new Enemy(this.ctx.scene, spawnPoint.x, spawnPoint.y, entry.config, enemyContext);
    if (this.ctx.targetGroup) {
      this.ctx.targetGroup.add(enemy);
    }
    this.enemies.push(enemy);
    this.areaByEnemy.set(enemy, area);
    return enemy;
  }

  private countForArea(area: MapEnemySpawnArea): number {
    return this.enemies.filter((enemy) => !enemy.dead && this.areaByEnemy.get(enemy)?.id === area.id).length;
  }

  private findSpawnPoint(player: Phaser.Physics.Arcade.Sprite, area?: MapEnemySpawnArea): Phaser.Math.Vector2 | null {
    const safeZones = this.ctx.getSafeZones?.() ?? [];

    for (let attempt = 0; attempt < 32; attempt += 1) {
      if (area) {
        const candidate = randomPointInPerimeter(area.stayPerimeter);
        const blocked = safeZones.some((zone) => (
          candidate.x >= zone.x && candidate.x <= zone.x + zone.w
          && candidate.y >= zone.y && candidate.y <= zone.y + zone.h
        ));
        if (!blocked) return new Phaser.Math.Vector2(candidate.x, candidate.y);
        continue;
      }
      const angle = Math.random() * Math.PI * 2;
      const dist = this.ctx.minSpawnDistance + Math.random() * (this.ctx.spawnRadius - this.ctx.minSpawnDistance);
      const x = Phaser.Math.Clamp(player.x + Math.cos(angle) * dist, 40, this.ctx.worldWidth - 40);
      const y = Phaser.Math.Clamp(player.y + Math.sin(angle) * dist, 40, this.ctx.worldHeight - 40);

      const blocked = safeZones.some((zone) => (
        x >= zone.x && x <= zone.x + zone.w && y >= zone.y && y <= zone.y + zone.h
      ));
      if (!blocked) return new Phaser.Math.Vector2(x, y);
    }

    return null;
  }

  destroy(): void {
    for (const e of this.enemies) {
      if (e.active) e.destroy();
    }
    this.enemies = [];
    this.areaByEnemy.clear();
    this.areaLastSpawnAt.clear();
  }
}
