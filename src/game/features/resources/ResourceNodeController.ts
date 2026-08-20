import Phaser from 'phaser';

import {
  getObjectArchetype,
  getObjectVisualChoice,
  isObjectArchetypeId,
  type ObjectArchetypeId,
} from '../../content/objects/ObjectCatalog';
import { acceptedDamage, rejectedDamage, type DamageApplicationResult } from '../../combat/DamageableTarget';
import { floatingText } from '../../ui/FloatingText';
import { itemRegistry, playerInventory } from '../../systems/Inventory';
import { applyObjectVisual } from '../objects/ObjectFactory';
import type { CreateObjectOptions } from '../objects/ObjectFactory';
import type { BuiltObjectRegistration } from '../world/MapBuilder';
import { worldProgress, type ResourcePileProgress, type ResourceProgressState } from '../progression/WorldProgress';
import type { WorldDimensions } from '../../world/WorldDimensions';

const INTERACTION_RADIUS = 96;
const STONE_PILE_OBJECT_ID: ObjectArchetypeId = 'resource.stone-pile';

interface ResourceRecord {
  readonly image: Phaser.GameObjects.Image;
  readonly instanceId: string;
  readonly sourceInstanceId: string;
  objectId: ObjectArchetypeId;
  tags: readonly string[];
  kind: 'node' | 'pile';
  health: number;
  maxHealth: number;
  itemId: string;
  remaining: number;
  readonly anchorX: number;
  readonly anchorY: number;
}

export interface ResourceDamageApplicationResult extends DamageApplicationResult {
  /** Snapshotted before depletion so the final hit still has material feedback. */
  readonly resourceHitEffectId?: string;
}

interface ResourceNodeControllerContext {
  readonly scene: Phaser.Scene;
  readonly mapId: string;
  readonly dimensions: WorldDimensions;
  readonly collisionGroup: Phaser.Physics.Arcade.StaticGroup;
  readonly targetGroup: Phaser.GameObjects.Group;
  readonly interactionGroup: Phaser.GameObjects.Group;
  readonly createObject: (objectId: ObjectArchetypeId, options: CreateObjectOptions) => Phaser.GameObjects.Image;
  readonly isCellBlocked: (cellX: number, cellY: number, sourceInstanceId: string) => boolean;
}

/** Owns authored resource-node state, including deterministic dynamic drops. */
export class ResourceNodeController {
  private readonly records = new Map<Phaser.GameObjects.GameObject, ResourceRecord>();
  private readonly reservedCells = new Set<string>();
  private readonly prompt: Phaser.GameObjects.Text;

  constructor(private readonly ctx: ResourceNodeControllerContext) {
    this.prompt = ctx.scene.add.text(0, 0, '', {
      fontFamily: 'Trebuchet MS, Segoe UI Variable, sans-serif',
      fontSize: '14px',
      color: '#f7ffe8',
      backgroundColor: '#10233bcc',
      padding: { left: 8, right: 8, top: 5, bottom: 5 },
      stroke: '#07111d',
      strokeThickness: 3,
    }).setOrigin(0.5, 1).setDepth(100000).setVisible(false);
  }

  register(registration: BuiltObjectRegistration): void {
    if (!isObjectArchetypeId(registration.objectId)) return;
    const definition = getObjectArchetype(registration.objectId);
    const node = definition.resourceNode;
    const pile = definition.resourcePile;
    if (!node && !pile) return;

    const initialState = registration.initialState ?? {};
    const image = registration.image;
    const savedState = worldProgress.resourceState(this.ctx.mapId, registration.instanceId);
    const record: ResourceRecord = {
      image,
      instanceId: registration.instanceId,
      sourceInstanceId: registration.instanceId,
      objectId: registration.objectId,
      tags: definition.tags,
      kind: node ? 'node' : 'pile',
      health: node ? this.numberState(initialState.health, node.health) : 0,
      maxHealth: node?.health ?? 0,
      itemId: node?.dropItem ?? pile!.itemId,
      remaining: this.numberState(initialState.remaining, node?.dropCount ?? pile!.amount),
      anchorX: this.anchorValue(image, 'objectAnchorX', image.x),
      anchorY: this.anchorValue(image, 'objectAnchorY', image.y),
    };
    this.records.set(image, record);
    image.setData('resourceInstanceId', registration.instanceId);
    image.setData('resourceState', record.kind);
    image.setData('resourceTags', record.tags);
    image.setData('resourceRemaining', record.remaining);

    if (savedState?.stage === 'depleted') {
      this.deplete(record, false);
      return;
    }
    if (savedState?.stage === 'destroyed' && node) {
      this.removeRecordVisual(record);
      this.records.delete(image);
      this.restoreDynamicPiles(registration.instanceId, savedState.piles ?? []);
      return;
    }
    if (savedState?.stage === 'node' && node && node.persistHealth !== false) {
      record.health = savedState.value;
      image.setData('resourceHealth', record.health);
    } else if (savedState?.stage === 'pile' && node) {
      this.replaceWithPile(record, savedState.value, false);
      return;
    } else if (savedState?.stage === 'pile' && pile) {
      record.remaining = savedState.value;
      image.setData('resourceRemaining', record.remaining);
    }

    if (record.kind === 'node' && record.health > 0) {
      this.ctx.targetGroup.add(image);
    } else if (record.kind === 'pile' && record.remaining > 0) {
      this.ctx.interactionGroup.add(image);
    } else {
      this.deplete(record);
    }
  }

  update(player: Phaser.Physics.Arcade.Sprite): void {
    const target = this.nearestPile(player.x, player.y);
    if (!target) {
      this.prompt.setVisible(false);
      return;
    }

    const itemName = itemRegistry.get(target.itemId)?.name ?? target.itemId;
    this.prompt
      .setText(`F  Collect ${itemName} (${target.remaining})`)
      .setPosition(target.image.x, target.image.y - 42)
      .setDepth(target.image.depth + 20)
      .setVisible(true);
  }

  tryInteract(player: Phaser.Physics.Arcade.Sprite): boolean {
    const target = this.nearestPile(player.x, player.y);
    if (!target) return false;

    const added = playerInventory.add(target.itemId, target.remaining);
    if (added <= 0) {
      floatingText.spawn(this.ctx.scene, player.x, player.y - 30, 'Inventory full', 'white');
      return true;
    }

    target.remaining -= added;
    target.image.setData('resourceRemaining', target.remaining);
    if (target.objectId === STONE_PILE_OBJECT_ID) {
      this.persistStonePiles(target.sourceInstanceId);
    } else {
      this.saveState(target, target.remaining > 0 ? 'pile' : 'depleted', target.remaining);
    }
    floatingText.spawn(
      this.ctx.scene,
      target.image.x,
      target.image.y - 42,
      `+${added} ${itemRegistry.get(target.itemId)?.name ?? target.itemId}`,
      'green',
      true,
    );
    if (target.remaining <= 0) this.deplete(target, false);
    return true;
  }

  isResourceTarget(target: Phaser.GameObjects.GameObject): boolean {
    return this.records.get(target)?.kind === 'node';
  }

  tagsFor(target: Phaser.GameObjects.GameObject): readonly string[] {
    return this.records.get(target)?.tags ?? [];
  }

  applyDamage(target: Phaser.GameObjects.GameObject, amount: number): ResourceDamageApplicationResult {
    const record = this.records.get(target);
    if (!record || record.kind !== 'node') return rejectedDamage('invalid');
    if (!Number.isFinite(amount) || amount <= 0) return rejectedDamage('invalid');
    if (record.health <= 0) return rejectedDamage('dead');

    const before = record.health;
    const resourceHitEffectId = getObjectArchetype(record.objectId).resourceNode?.hitEffectId;
    record.health = Math.max(0, record.health - amount);
    record.image.setData('resourceHealth', record.health);
    const node = getObjectArchetype(record.objectId).resourceNode;
    if (node?.persistHealth !== false) this.saveState(record, 'node', record.health);
    record.image.setTintFill(0xffd277);
    this.ctx.scene.time.delayedCall(110, () => {
      if (record.image.active) record.image.clearTint();
    });
    floatingText.spawn(this.ctx.scene, record.image.x, record.image.y - 54, `-${Math.round(amount)}`, 'white');

    if (record.health <= 0) this.replaceWithPile(record);
    return { ...acceptedDamage(before, record.health), ...(resourceHitEffectId ? { resourceHitEffectId } : {}) };
  }

  destroy(): void {
    this.prompt.destroy();
    this.records.clear();
    this.reservedCells.clear();
  }

  private nearestPile(x: number, y: number): ResourceRecord | undefined {
    let nearest: ResourceRecord | undefined;
    let nearestDistance = INTERACTION_RADIUS;
    for (const record of this.records.values()) {
      if (record.kind !== 'pile' || !record.image.active || record.remaining <= 0) continue;
      const distance = Phaser.Math.Distance.Between(x, y, record.image.x, record.image.y);
      if (distance < nearestDistance) {
        nearest = record;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  private replaceWithPile(record: ResourceRecord, remainingOverride?: number, announce = true): void {
    const source = getObjectArchetype(record.objectId).resourceNode;
    if (!source) {
      this.deplete(record);
      return;
    }
    if (record.tags.includes('stone')) {
      this.replaceStoneWithPiles(record, announce);
      return;
    }

    const replacement = source.replacement;
    if (!replacement || !isObjectArchetypeId(replacement.objectId)) {
      this.deplete(record);
      return;
    }

    const pileDefinition = getObjectArchetype(replacement.objectId).resourcePile;
    if (!pileDefinition) {
      this.deplete(record);
      return;
    }

    const choice = getObjectVisualChoice(replacement.objectId, replacement.visualId);
    if (!choice) {
      this.deplete(record);
      return;
    }
    const registration = record.image.getData('occlusionRegistration') as { dispose(): void } | undefined;
    registration?.dispose();

    this.ctx.collisionGroup.remove(record.image, false, false);
    this.ctx.targetGroup.remove(record.image, false, false);
    const body = record.image.body as Phaser.Physics.Arcade.StaticBody | Phaser.Physics.Arcade.Body | null;
    if (body) body.enable = false;

    applyObjectVisual(record.image, replacement.objectId, replacement.visualId);
    record.image.clearTint();
    record.image.setData('resourceState', 'pile');
    record.image.setData('resourceTags', getObjectArchetype(replacement.objectId).tags);
    record.image.setData('resourceRemaining', remainingOverride ?? source.dropCount);
    record.image.setData('occlusionRegistration', undefined);
    record.objectId = replacement.objectId;
    record.tags = getObjectArchetype(replacement.objectId).tags;
    record.kind = 'pile';
    record.health = 0;
    record.maxHealth = 0;
    record.itemId = pileDefinition.itemId;
    record.remaining = remainingOverride ?? source.dropCount;
    this.ctx.interactionGroup.add(record.image);
    this.saveState(record, 'pile', record.remaining);
    if (announce) {
      floatingText.spawn(this.ctx.scene, record.image.x, record.image.y - 46, source.depletionMessage ?? 'Resource depleted', 'yellow', true);
    }
  }

  private replaceStoneWithPiles(record: ResourceRecord, announce: boolean): void {
    const source = getObjectArchetype(record.objectId).resourceNode;
    if (!source) {
      this.deplete(record);
      return;
    }
    const sourceCell = this.cellForAnchor(record.anchorX, record.anchorY);
    this.removeRecordVisual(record);
    this.records.delete(record.image);

    const cells = this.findDropCells(sourceCell.cellX, sourceCell.cellY, record.instanceId, 3);
    const selected = cells.length > 0 ? cells : [{ cellX: sourceCell.cellX, cellY: sourceCell.cellY }];
    const piles: ResourcePileProgress[] = selected.map((cell, index) => ({
      id: `${record.instanceId}-stone-pile-${index + 1}`,
      cellX: cell.cellX,
      cellY: cell.cellY,
      amount: 10,
    }));
    const remainder = Math.max(0, source.dropCount - piles.reduce((sum, pile) => sum + pile.amount, 0));
    if (piles.length > 0) piles[piles.length - 1] = { ...piles[piles.length - 1], amount: piles[piles.length - 1].amount + remainder };
    piles.forEach((pile) => this.createDynamicPile(record.instanceId, pile));
    this.saveDestroyedState(record.instanceId, piles);
    if (announce) floatingText.spawn(this.ctx.scene, record.anchorX, record.anchorY - 46, source.depletionMessage ?? 'Resource depleted', 'yellow', true);
  }

  private restoreDynamicPiles(sourceInstanceId: string, piles: readonly ResourcePileProgress[]): void {
    const active = piles.filter((pile) => pile.amount > 0);
    if (active.length === 0) {
      worldProgress.setResourceState(this.ctx.mapId, sourceInstanceId, { stage: 'depleted', value: 0 });
      return;
    }
    active.forEach((pile) => this.createDynamicPile(sourceInstanceId, pile));
  }

  private createDynamicPile(sourceInstanceId: string, pile: ResourcePileProgress): void {
    const x = pile.cellX * this.ctx.dimensions.tileSize + this.ctx.dimensions.tileSize / 2;
    const y = (pile.cellY + 1) * this.ctx.dimensions.tileSize;
    const image = this.ctx.createObject(STONE_PILE_OBJECT_ID, {
      x,
      y,
      visualId: 'stone-pile',
      sortId: pile.id,
    });
    const definition = getObjectArchetype(STONE_PILE_OBJECT_ID);
    const record: ResourceRecord = {
      image,
      instanceId: pile.id,
      sourceInstanceId,
      objectId: STONE_PILE_OBJECT_ID,
      tags: definition.tags,
      kind: 'pile',
      health: 0,
      maxHealth: 0,
      itemId: definition.resourcePile?.itemId ?? 'stone',
      remaining: Math.max(0, pile.amount),
      anchorX: x,
      anchorY: y,
    };
    image.setData('resourceInstanceId', pile.id);
    image.setData('resourceState', 'pile');
    image.setData('resourceTags', record.tags);
    image.setData('resourceRemaining', record.remaining);
    this.records.set(image, record);
    this.reservedCells.add(this.cellKey(pile.cellX, pile.cellY));
    if (record.remaining > 0) this.ctx.interactionGroup.add(image);
    else this.deplete(record, false);
  }

  private persistStonePiles(sourceInstanceId: string): void {
    const piles = [...this.records.values()]
      .filter((record) => record.sourceInstanceId === sourceInstanceId && record.objectId === STONE_PILE_OBJECT_ID && record.remaining > 0)
      .map((record) => {
        const cell = this.cellForAnchor(record.anchorX, record.anchorY);
        return { id: record.instanceId, cellX: cell.cellX, cellY: cell.cellY, amount: record.remaining };
      });
    if (piles.length === 0) {
      worldProgress.setResourceState(this.ctx.mapId, sourceInstanceId, { stage: 'depleted', value: 0 });
      return;
    }
    this.saveDestroyedState(sourceInstanceId, piles);
  }

  private saveDestroyedState(sourceInstanceId: string, piles: readonly ResourcePileProgress[]): void {
    worldProgress.setResourceState(this.ctx.mapId, sourceInstanceId, {
      stage: 'destroyed',
      value: piles.reduce((sum, pile) => sum + pile.amount, 0),
      piles,
    });
  }

  private findDropCells(sourceCellX: number, sourceCellY: number, sourceInstanceId: string, limit: number): Array<{ cellX: number; cellY: number }> {
    const candidates: Array<{ cellX: number; cellY: number; distance: number }> = [];
    for (let cellY = 0; cellY < this.ctx.dimensions.rows; cellY += 1) {
      for (let cellX = 0; cellX < this.ctx.dimensions.columns; cellX += 1) {
        if (cellX === sourceCellX && cellY === sourceCellY) continue;
        if (this.reservedCells.has(this.cellKey(cellX, cellY))) continue;
        if (this.ctx.isCellBlocked(cellX, cellY, sourceInstanceId)) continue;
        candidates.push({
          cellX,
          cellY,
          distance: Math.max(Math.abs(cellX - sourceCellX), Math.abs(cellY - sourceCellY)),
        });
      }
    }
    candidates.sort((a, b) => a.distance - b.distance || a.cellY - b.cellY || a.cellX - b.cellX);
    return candidates.slice(0, limit).map(({ cellX, cellY }) => ({ cellX, cellY }));
  }

  private deplete(record: ResourceRecord, save = true): void {
    if (save) this.saveState(record, 'depleted', 0);
    this.removeRecordVisual(record);
    this.records.delete(record.image);
  }

  private removeRecordVisual(record: ResourceRecord): void {
    const registration = record.image.getData('occlusionRegistration') as { dispose(): void } | undefined;
    registration?.dispose();
    this.ctx.targetGroup.remove(record.image, false, false);
    this.ctx.interactionGroup.remove(record.image, false, false);
    this.ctx.collisionGroup.remove(record.image, false, false);
    if (record.kind === 'pile') {
      const cell = this.cellForAnchor(record.anchorX, record.anchorY);
      this.reservedCells.delete(this.cellKey(cell.cellX, cell.cellY));
    }
    const body = record.image.body as Phaser.Physics.Arcade.StaticBody | Phaser.Physics.Arcade.Body | null;
    if (body) body.enable = false;
    record.image.destroy();
  }

  private numberState(value: unknown, fallback: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, value) : fallback;
  }

  private saveState(record: ResourceRecord, stage: ResourceProgressState['stage'], value: number): void {
    worldProgress.setResourceState(this.ctx.mapId, record.sourceInstanceId, { stage, value });
  }

  private cellForAnchor(anchorX: number, anchorY: number): { cellX: number; cellY: number } {
    return {
      cellX: Math.floor(anchorX / this.ctx.dimensions.tileSize),
      cellY: Math.floor((anchorY - 1) / this.ctx.dimensions.tileSize),
    };
  }

  private cellKey(cellX: number, cellY: number): string {
    return `${cellX}:${cellY}`;
  }

  private anchorValue(image: Phaser.GameObjects.Image, key: string, fallback: number): number {
    const value = image.getData(key);
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }
}
