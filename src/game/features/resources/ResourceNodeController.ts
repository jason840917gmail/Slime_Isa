import type Phaser from 'phaser';

import {
  getObjectArchetype,
  isObjectArchetypeId,
  type ObjectArchetypeId,
} from '../../content/objects/ObjectCatalog';
import { acceptedDamage, rejectedDamage, type DamageApplicationResult } from '../../combat/DamageableTarget';
import { floatingText } from '../../ui/FloatingText';
import type { CreateObjectOptions } from '../objects/ObjectFactory';
import type { BuiltObjectRegistration } from '../world/MapBuilder';
import { worldProgress, type ResourcePileProgress, type ResourceProgressState } from '../progression/WorldProgress';
import type { CollectibleStateChange } from '../collectibles/CollectibleController';
import type { WorldDimensions } from '../../world/WorldDimensions';
import { completeDropPlacements } from './ResourceDropPlacement';

interface ResourceRecord {
  readonly image: Phaser.GameObjects.Image;
  readonly instanceId: string;
  readonly objectId: ObjectArchetypeId;
  readonly tags: readonly string[];
  health: number;
  maxHealth: number;
  depletionPending?: boolean;
  readonly anchorX: number;
  readonly anchorY: number;
  readonly dropObjectId?: string;
  readonly dropVisualId?: string;
  readonly dropPieces?: number;
}

export interface AcceptedObjectDamageEvent extends DamageApplicationResult {
  readonly status: 'accepted';
  readonly target: Phaser.GameObjects.Image;
  readonly acceptedDamage: number;
  readonly resourceHitEffectId?: string;
  readonly onHitAnimationId?: string;
  readonly depleted: boolean;
}

export type ResourceDamageApplicationResult = DamageApplicationResult | AcceptedObjectDamageEvent;

export interface HarvestRequirement {
  readonly targetTag: string;
  readonly minimumTier: number;
  readonly failureMessage: string;
}

interface ResourceNodeControllerContext {
  readonly scene: Phaser.Scene;
  readonly mapId: string;
  readonly dimensions: WorldDimensions;
  readonly collisionGroup: Phaser.Physics.Arcade.StaticGroup;
  readonly targetGroup: Phaser.GameObjects.Group;
  readonly createObject: (objectId: ObjectArchetypeId, options: CreateObjectOptions) => Phaser.GameObjects.Image;
  readonly registerCollectible: (registration: BuiltObjectRegistration) => void;
  readonly isCellBlocked: (cellX: number, cellY: number, sourceInstanceId: string) => boolean;
}

/** Owns damageable resource nodes and deterministic collectible drop spawning. */
export class ResourceNodeController {
  private readonly records = new Map<Phaser.GameObjects.GameObject, ResourceRecord>();
  private readonly reservedCells = new Set<string>();
  private readonly dropDefinitions = new Map<string, { objectId: string; visualId: string }>();
  private harvestHintReadyAt = 0;

  constructor(private readonly ctx: ResourceNodeControllerContext) {}

  register(registration: BuiltObjectRegistration): void {
    if (!isObjectArchetypeId(registration.objectId)) return;
    const definition = getObjectArchetype(registration.objectId);
    const node = definition.resourceNode;
    if (!node) return;
    this.dropDefinitions.set(registration.instanceId, { objectId: node.drop.objectId, visualId: node.drop.visualId });

    const initialState = registration.initialState ?? {};
    const customDropObjectId = typeof initialState.dropObjectId === 'string' && isObjectArchetypeId(initialState.dropObjectId)
      ? initialState.dropObjectId
      : undefined;
    const inferredDropVisualId = customDropObjectId
      ? getObjectArchetype(customDropObjectId).variants[0]?.frames[0]?.visualId
      : undefined;
    const image = registration.image;
    const savedState = worldProgress.resourceState(this.ctx.mapId, registration.instanceId);
    const record: ResourceRecord = {
      image,
      instanceId: registration.instanceId,
      objectId: registration.objectId,
      tags: definition.tags,
      health: this.numberState(initialState.health, node.health),
      maxHealth: node.health,
      anchorX: this.anchorValue(image, 'objectAnchorX', image.x),
      anchorY: this.anchorValue(image, 'objectAnchorY', image.y),
      ...(customDropObjectId ? { dropObjectId: customDropObjectId } : {}),
      ...(typeof initialState.dropVisualId === 'string'
        ? { dropVisualId: initialState.dropVisualId }
        : inferredDropVisualId ? { dropVisualId: inferredDropVisualId } : {}),
      ...(typeof initialState.dropPieces === 'number' && Number.isInteger(initialState.dropPieces) && initialState.dropPieces > 0 ? { dropPieces: initialState.dropPieces } : {}),
    };
    this.records.set(image, record);
    image.setData('resourceInstanceId', registration.instanceId);
    image.setData('resourceState', 'node');
    image.setData('resourceTags', record.tags);
    image.setData('resourceHealth', record.health);

    if (savedState?.stage === 'depleted') {
      this.removeNodeVisual(record);
      this.records.delete(image);
      return;
    }
    if (savedState?.stage === 'destroyed') {
      this.removeNodeVisual(record);
      this.records.delete(image);
      this.restoreDynamicDrops(registration.instanceId, savedState.piles ?? []);
      return;
    }
    // Older saves used the intermediate `pile` stage for a wood replacement.
    if (savedState?.stage === 'pile') {
      this.removeNodeVisual(record);
      this.records.delete(image);
      this.restoreLegacySingleDrop(record, savedState.value);
      return;
    }
    if (savedState?.stage === 'node' && node.persistHealth !== false) {
      record.health = Math.min(node.health, savedState.value);
      image.setData('resourceHealth', record.health);
    }
    if (record.health <= 0) {
      this.removeNodeVisual(record);
      this.records.delete(image);
      this.spawnDrops(record);
      return;
    }
    this.ctx.targetGroup.add(image);
  }

  isResourceTarget(target: Phaser.GameObjects.GameObject): boolean {
    return this.records.has(target);
  }

  tagsFor(target: Phaser.GameObjects.GameObject): readonly string[] {
    return this.records.get(target)?.tags ?? [];
  }

  harvestRequirementFor(target: Phaser.GameObjects.GameObject): HarvestRequirement | undefined {
    const record = this.records.get(target);
    if (!record) return undefined;
    return getObjectArchetype(record.objectId).resourceNode?.harvestRequirement;
  }

  showHarvestFailure(target: Phaser.GameObjects.GameObject, message: string): void {
    const record = this.records.get(target);
    if (!record || this.ctx.scene.time.now < this.harvestHintReadyAt) return;
    this.harvestHintReadyAt = this.ctx.scene.time.now + 900;
    floatingText.spawn(this.ctx.scene, record.image.x, record.image.y - 58, message, 'white', true);
  }

  applyDamage(target: Phaser.GameObjects.GameObject, amount: number): ResourceDamageApplicationResult {
    const record = this.records.get(target);
    if (!record || !Number.isFinite(amount) || amount <= 0) return rejectedDamage('invalid');
    if (record.health <= 0) return rejectedDamage('dead');

    const before = record.health;
    const node = getObjectArchetype(record.objectId).resourceNode;
    const resourceHitEffectId = node?.hitEffectId;
    const onHitAnimationId = record.image.getData('onHitAnimationId') as string | undefined;
    record.health = Math.max(0, record.health - amount);
    record.image.setData('resourceHealth', record.health);
    if (node?.persistHealth !== false) this.saveState(record, 'node', record.health);
    record.image.setTintFill(0xffd277);
    this.ctx.scene.time.delayedCall(110, () => {
      if (record.image.active) record.image.clearTint();
    });
    floatingText.spawn(this.ctx.scene, record.image.x, record.image.y - 54, `-${Math.round(amount)}`, 'white');

    if (record.health <= 0) {
      record.depletionPending = true;
      this.ctx.targetGroup.remove(record.image, false, false);
      const body = record.image.body as Phaser.Physics.Arcade.StaticBody | Phaser.Physics.Arcade.Body | null;
      if (body) body.enable = false;
      // Keep the zero-health node recoverable until the drop list is authored
      // and persisted by completeDepletion(). A quit during the hit animation
      // will rebuild the drops instead of silently consuming them.
      this.saveState(record, 'node', 0);
    }
    const result = acceptedDamage(before, record.health);
    return {
      ...result,
      status: 'accepted',
      target: record.image,
      acceptedDamage: result.actualDamage,
      depleted: result.defeated,
      ...(resourceHitEffectId ? { resourceHitEffectId } : {}),
      ...(onHitAnimationId ? { onHitAnimationId } : {}),
    };
  }

  completeDepletion(target: Phaser.GameObjects.GameObject): void {
    const record = this.records.get(target);
    if (!record || !record.depletionPending) return;
    record.depletionPending = false;
    this.removeNodeVisual(record);
    this.records.delete(record.image);
    this.spawnDrops(record);
  }

  onCollectibleStateChanged(change: CollectibleStateChange): void {
    if (!change.sourceResourceInstanceId) return;
    const state = worldProgress.resourceState(this.ctx.mapId, change.sourceResourceInstanceId);
    if (!state || state.stage !== 'destroyed' || !state.piles) return;
    const changedPile = state.piles.find((pile) => pile.id === change.instanceId);
    if (changedPile && change.remaining <= 0) this.reservedCells.delete(this.cellKey(changedPile.cellX, changedPile.cellY));
    const piles = state.piles
      .map((pile) => pile.id === change.instanceId ? { ...pile, amount: change.remaining } : pile)
      .filter((pile) => pile.amount > 0);
    if (piles.length === 0) {
      worldProgress.setResourceState(this.ctx.mapId, change.sourceResourceInstanceId, { stage: 'depleted', value: 0 });
      return;
    }
    worldProgress.setResourceState(this.ctx.mapId, change.sourceResourceInstanceId, {
      stage: 'destroyed',
      value: piles.reduce((sum, pile) => sum + pile.amount, 0),
      piles,
    });
  }

  destroy(): void {
    for (const record of this.records.values()) {
      if (record.depletionPending) this.completeDepletion(record.image);
    }
    this.records.clear();
    this.reservedCells.clear();
    this.dropDefinitions.clear();
  }

  private spawnDrops(record: ResourceRecord, piecesOverride?: number, amountOverride?: number): void {
    const source = getObjectArchetype(record.objectId).resourceNode;
    if (!source) return;
    const drop = {
      objectId: record.dropObjectId ?? source.drop.objectId,
      visualId: record.dropVisualId ?? source.drop.visualId,
      pieces: record.dropPieces ?? source.drop.pieces,
    };
    if (!isObjectArchetypeId(drop.objectId)) return;
    const collectible = getObjectArchetype(drop.objectId).collectible;
    if (!collectible) return;

    const sourceCell = this.cellForAnchor(record.anchorX, record.anchorY);
    const pieces = piecesOverride ?? drop.pieces;
    const cells = this.findDropCells(sourceCell.cellX, sourceCell.cellY, record.instanceId, pieces);
    const placements = completeDropPlacements(cells, sourceCell, pieces, this.ctx.dimensions.tileSize);
    const piles: ResourcePileProgress[] = placements.map((cell, index) => ({
      id: `${record.instanceId}-drop-${index + 1}`,
      cellX: cell.cellX,
      cellY: cell.cellY,
      ...(cell.offsetX !== 0 ? { offsetX: cell.offsetX } : {}),
      ...(cell.offsetY !== 0 ? { offsetY: cell.offsetY } : {}),
      amount: amountOverride ?? collectible.quantity,
      objectId: drop.objectId,
      visualId: drop.visualId,
    }));
    piles.forEach((pile) => this.createDynamicDrop(record.instanceId, pile));
    this.saveDestroyedState(record.instanceId, piles);
    floatingText.spawn(this.ctx.scene, record.anchorX, record.anchorY - 46, source.depletionMessage ?? 'Resource depleted', 'yellow', true);
  }

  private restoreDynamicDrops(sourceInstanceId: string, piles: readonly ResourcePileProgress[]): void {
    const sourceDrop = this.sourceDropFor(sourceInstanceId);
    const active = piles.filter((pile) => pile.amount > 0);
    if (active.length === 0) {
      worldProgress.setResourceState(this.ctx.mapId, sourceInstanceId, { stage: 'depleted', value: 0 });
      return;
    }
    active.forEach((pile) => this.createDynamicDrop(sourceInstanceId, {
      ...pile,
      objectId: pile.objectId ?? sourceDrop?.objectId,
      visualId: pile.visualId ?? sourceDrop?.visualId,
    }));
  }

  private restoreLegacySingleDrop(record: ResourceRecord, amount: number): void {
    const source = getObjectArchetype(record.objectId).resourceNode;
    if (!source) return;
    const cell = this.cellForAnchor(record.anchorX, record.anchorY);
    const pile: ResourcePileProgress = {
      id: `${record.instanceId}-drop-1`,
      cellX: cell.cellX,
      cellY: cell.cellY,
      amount,
      objectId: source.drop.objectId,
      visualId: source.drop.visualId,
    };
    this.createDynamicDrop(record.instanceId, pile);
    this.saveDestroyedState(record.instanceId, [pile]);
  }

  private createDynamicDrop(sourceInstanceId: string, pile: ResourcePileProgress): void {
    const sourceDrop = this.sourceDropFor(sourceInstanceId);
    const authoredObjectId = pile.objectId;
    const migratedObjectId = authoredObjectId === 'resource.wood-pile'
      ? 'collectible.wood-pile'
      : authoredObjectId === 'resource.stone-pile'
        ? 'collectible.stone-pile'
        : authoredObjectId;
    const objectId = migratedObjectId ?? sourceDrop?.objectId;
    const visualId = pile.visualId ?? sourceDrop?.visualId;
    if (!objectId || !visualId || !isObjectArchetypeId(objectId)) return;
    const x = pile.cellX * this.ctx.dimensions.tileSize + this.ctx.dimensions.tileSize / 2 + (pile.offsetX ?? 0);
    const y = (pile.cellY + 1) * this.ctx.dimensions.tileSize + (pile.offsetY ?? 0);
    const image = this.ctx.createObject(objectId, { x, y, visualId, sortId: pile.id });
    this.reservedCells.add(this.cellKey(pile.cellX, pile.cellY));
    this.ctx.registerCollectible({
      image,
      objectId,
      instanceId: pile.id,
      initialState: { remaining: pile.amount, sourceResourceInstanceId: sourceInstanceId },
    });
  }

  private sourceDropFor(instanceId: string): { objectId: string; visualId: string } | undefined {
    return this.dropDefinitions.get(instanceId);
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
        candidates.push({ cellX, cellY, distance: Math.max(Math.abs(cellX - sourceCellX), Math.abs(cellY - sourceCellY)) });
      }
    }
    candidates.sort((a, b) => a.distance - b.distance || a.cellY - b.cellY || a.cellX - b.cellX);
    return candidates.slice(0, limit).map(({ cellX, cellY }) => ({ cellX, cellY }));
  }

  private removeNodeVisual(record: ResourceRecord): void {
    const registration = record.image.getData('occlusionRegistration') as { dispose(): void } | undefined;
    registration?.dispose();
    this.ctx.targetGroup.remove(record.image, false, false);
    this.ctx.collisionGroup.remove(record.image, false, false);
    const body = record.image.body as Phaser.Physics.Arcade.StaticBody | Phaser.Physics.Arcade.Body | null;
    if (body) body.enable = false;
    record.image.destroy();
  }

  private saveState(record: ResourceRecord, stage: ResourceProgressState['stage'], value: number): void {
    worldProgress.setResourceState(this.ctx.mapId, record.instanceId, { stage, value });
  }

  private numberState(value: unknown, fallback: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, value) : fallback;
  }

  private anchorValue(image: Phaser.GameObjects.Image, key: string, fallback: number): number {
    const value = image.getData(key);
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  private cellForAnchor(anchorX: number, anchorY: number): { cellX: number; cellY: number } {
    return { cellX: Math.floor(anchorX / this.ctx.dimensions.tileSize), cellY: Math.floor(anchorY / this.ctx.dimensions.tileSize) - 1 };
  }

  private cellKey(cellX: number, cellY: number): string {
    return `${cellX}:${cellY}`;
  }

}
