import type Phaser from 'phaser';

import { floatingText } from '../../ui/FloatingText';
import { worldProgress, type ResourcePileProgress } from '../progression/WorldProgress';
import type { CollectibleStateChange } from '../collectibles/CollectibleController';
import type { WorldDropRequest } from '../collectibles/WorldDropRequest';
import type { WorldDimensions } from '../../world/WorldDimensions';
import { completeDropPlacements } from './ResourceDropPlacement';
import type { ResourceDropRequest } from '../scripts/ResourceNodeScript';

export interface ManagedResourceRegistration {
  readonly instanceId: string;
  readonly dropObjectId: string;
  readonly dropVisualId: string;
}

interface ResourceNodeControllerContext {
  readonly scene: Phaser.Scene;
  readonly mapId: string;
  readonly dimensions: WorldDimensions;
  readonly getCollectibleQuantity: (objectId: string) => number;
  readonly spawnWorldDrop: (request: WorldDropRequest) => void;
  readonly isCellBlocked: (cellX: number, cellY: number, sourceInstanceId: string) => boolean;
}

/** Places scene-owned resource drops and restores their persisted piles. */
export class ResourceNodeController {
  private readonly reservedCells = new Set<string>();
  private readonly dropDefinitions = new Map<string, { objectId: string; visualId: string }>();

  constructor(private readonly ctx: ResourceNodeControllerContext) {}

  registerManagedResource(registration: ManagedResourceRegistration): void {
    this.dropDefinitions.set(registration.instanceId, {
      objectId: registration.dropObjectId,
      visualId: registration.dropVisualId,
    });
    const savedState = worldProgress.resourceState(this.ctx.mapId, registration.instanceId);
    if (savedState?.stage === 'destroyed') this.restoreDynamicDrops(registration.instanceId, savedState.piles ?? []);
  }

  spawnManagedResourceDrops(request: ResourceDropRequest): void {
    const quantity = this.ctx.getCollectibleQuantity(request.dropObjectId);
    this.spawnConfiguredDrops({
      sourceInstanceId: request.instanceId,
      anchorX: request.x,
      anchorY: request.y,
      dropObjectId: request.dropObjectId,
      dropVisualId: request.dropVisualId,
      pieces: request.pieces,
      amount: quantity,
      depletionMessage: request.depletionMessage ?? 'Resource depleted',
    });
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
    this.reservedCells.clear();
    this.dropDefinitions.clear();
  }

  private spawnConfiguredDrops(request: {
    readonly sourceInstanceId: string;
    readonly anchorX: number;
    readonly anchorY: number;
    readonly dropObjectId: string;
    readonly dropVisualId: string;
    readonly pieces: number;
    readonly amount: number;
    readonly depletionMessage: string;
  }): void {
    const sourceCell = this.cellForAnchor(request.anchorX, request.anchorY);
    const cells = this.findDropCells(sourceCell.cellX, sourceCell.cellY, request.sourceInstanceId, request.pieces);
    const placements = completeDropPlacements(cells, sourceCell, request.pieces, this.ctx.dimensions.tileSize);
    const piles: ResourcePileProgress[] = placements.map((cell, index) => ({
      id: `${request.sourceInstanceId}-drop-${index + 1}`,
      cellX: cell.cellX,
      cellY: cell.cellY,
      ...(cell.offsetX !== 0 ? { offsetX: cell.offsetX } : {}),
      ...(cell.offsetY !== 0 ? { offsetY: cell.offsetY } : {}),
      amount: request.amount,
      objectId: request.dropObjectId,
      visualId: request.dropVisualId,
    }));
    this.saveDestroyedState(request.sourceInstanceId, piles);
    piles.forEach((pile, index) => this.createDynamicDrop(request.sourceInstanceId, pile, {
      mode: 'launch',
      source: { x: request.anchorX, y: request.anchorY },
      launchIndex: index,
    }));
    floatingText.spawn(this.ctx.scene, request.anchorX, request.anchorY - 46, request.depletionMessage, 'yellow', true);
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
    }, { mode: 'settled' }));
  }

  private createDynamicDrop(
    sourceInstanceId: string,
    pile: ResourcePileProgress,
    presentation: { readonly mode: 'settled' } | {
      readonly mode: 'launch';
      readonly source: { readonly x: number; readonly y: number };
      readonly launchIndex: number;
    },
  ): void {
    const sourceDrop = this.sourceDropFor(sourceInstanceId);
    const authoredObjectId = pile.objectId;
    const objectId = authoredObjectId ?? sourceDrop?.objectId;
    const visualId = pile.visualId ?? sourceDrop?.visualId;
    if (!objectId || !visualId) return;
    const x = pile.cellX * this.ctx.dimensions.tileSize + this.ctx.dimensions.tileSize / 2 + (pile.offsetX ?? 0);
    const y = (pile.cellY + 1) * this.ctx.dimensions.tileSize + (pile.offsetY ?? 0);
    this.ctx.spawnWorldDrop(presentation.mode === 'launch' ? {
      mode: 'launch',
      source: presentation.source,
      destination: { x, y },
      launchIndex: presentation.launchIndex,
      drop: {
        objectId,
        visualId,
        instanceId: pile.id,
        initialState: { remaining: pile.amount, sourceResourceInstanceId: sourceInstanceId },
      },
    } : {
      mode: 'settled',
      destination: { x, y },
      drop: {
        objectId,
        visualId,
        instanceId: pile.id,
        initialState: { remaining: pile.amount, sourceResourceInstanceId: sourceInstanceId },
      },
    });
    this.reservedCells.add(this.cellKey(pile.cellX, pile.cellY));
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

  private cellForAnchor(anchorX: number, anchorY: number): { cellX: number; cellY: number } {
    return { cellX: Math.floor(anchorX / this.ctx.dimensions.tileSize), cellY: Math.floor(anchorY / this.ctx.dimensions.tileSize) - 1 };
  }

  private cellKey(cellX: number, cellY: number): string {
    return `${cellX}:${cellY}`;
  }

}
