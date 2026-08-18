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
import type { BuiltObjectRegistration } from '../world/MapBuilder';
import { worldProgress } from '../progression/WorldProgress';

const INTERACTION_RADIUS = 96;

interface ResourceRecord {
  readonly image: Phaser.GameObjects.Image;
  readonly instanceId: string;
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

interface ResourceNodeControllerContext {
  readonly scene: Phaser.Scene;
  readonly mapId: string;
  readonly collisionGroup: Phaser.Physics.Arcade.StaticGroup;
  readonly targetGroup: Phaser.GameObjects.Group;
  readonly interactionGroup: Phaser.GameObjects.Group;
}

/** Owns authored resource-node state without coupling object content to WorldScene. */
export class ResourceNodeController {
  private readonly records = new Map<Phaser.GameObjects.GameObject, ResourceRecord>();
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
      objectId: registration.objectId,
      tags: definition.tags,
      kind: node ? 'node' : 'pile',
      health: node ? this.numberState(initialState.health, node.health) : 0,
      maxHealth: node?.health ?? 0,
      itemId: node?.dropItem ?? pile!.itemId,
      remaining: this.numberState(initialState.remaining, node?.dropCount ?? pile!.amount),
      anchorX: image.getData('objectAnchorX') as number ?? image.x,
      anchorY: image.getData('objectAnchorY') as number ?? image.y,
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
    if (savedState?.stage === 'node' && node) {
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
    this.saveState(target, target.remaining > 0 ? 'pile' : 'depleted', target.remaining);
    floatingText.spawn(
      this.ctx.scene,
      target.image.x,
      target.image.y - 42,
      `+${added} ${itemRegistry.get(target.itemId)?.name ?? target.itemId}`,
      'green',
      true,
    );
    if (target.remaining <= 0) this.deplete(target);
    return true;
  }

  isResourceTarget(target: Phaser.GameObjects.GameObject): boolean {
    return this.records.get(target)?.kind === 'node';
  }

  tagsFor(target: Phaser.GameObjects.GameObject): readonly string[] {
    return this.records.get(target)?.tags ?? [];
  }

  applyDamage(target: Phaser.GameObjects.GameObject, amount: number): DamageApplicationResult {
    const record = this.records.get(target);
    if (!record || record.kind !== 'node') return rejectedDamage('invalid');
    if (!Number.isFinite(amount) || amount < 0) return rejectedDamage('invalid');
    if (record.health <= 0) return rejectedDamage('dead');

    const before = record.health;
    record.health = Math.max(0, record.health - amount);
    record.image.setData('resourceHealth', record.health);
    this.saveState(record, 'node', record.health);
    record.image.setTintFill(0xffd277);
    this.ctx.scene.time.delayedCall(110, () => {
      if (record.image.active) record.image.clearTint();
    });
    floatingText.spawn(this.ctx.scene, record.image.x, record.image.y - 54, `-${Math.round(amount)}`, 'white');

    if (record.health <= 0) this.replaceWithPile(record);
    return acceptedDamage(before, record.health);
  }

  destroy(): void {
    this.prompt.destroy();
    this.records.clear();
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
    const replacement = source?.replacement;
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

    // Reuse the same catalog visual path as authored map placement so the
    // replacement inherits its editor-authored origin, scale, and geometry.
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
    if (announce) floatingText.spawn(this.ctx.scene, record.image.x, record.image.y - 46, 'Tree felled', 'yellow', true);
  }

  private deplete(record: ResourceRecord, save = true): void {
    if (save) this.saveState(record, 'depleted', 0);
    const registration = record.image.getData('occlusionRegistration') as { dispose(): void } | undefined;
    registration?.dispose();
    this.ctx.targetGroup.remove(record.image, false, false);
    this.ctx.interactionGroup.remove(record.image, false, false);
    this.ctx.collisionGroup.remove(record.image, false, false);
    this.records.delete(record.image);
    record.image.destroy();
  }

  private numberState(value: unknown, fallback: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, value) : fallback;
  }

  private saveState(
    record: ResourceRecord,
    stage: 'node' | 'pile' | 'depleted',
    value: number,
  ): void {
    worldProgress.setResourceState(this.ctx.mapId, record.instanceId, { stage, value });
  }
}
