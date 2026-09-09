import { layeredTimelineFrameCount, type LayeredAnimationDocument } from '../shared/animation';
import { LayeredAnimationDocumentState, type LayeredAnimationDocumentStateValue } from './LayeredAnimationDocumentState';
import { reconcileWeaponAttackTrack } from './WeaponAnimationTrackReconciliation';
import { validateWeaponDefinitionForStudioSave } from '../content/weapons/validation';
import type { AuthoredWeaponDefinition, LayeredWeaponDefinition, WeaponAttackDirection } from '../content/weapons/types';

export type WeaponOwnedAnimationSlot =
  | { readonly slot: 'idle' }
  | { readonly slot: 'attack'; readonly direction: WeaponAttackDirection };

export interface WeaponOwnedAnimationSnapshot {
  readonly weapon: LayeredWeaponDefinition;
  readonly revision: string;
  readonly slot: WeaponOwnedAnimationSlot;
  readonly animation: LayeredAnimationDocumentStateValue;
  readonly dirty: boolean;
  readonly errors: readonly string[];
  readonly canUndo: boolean;
  readonly canRedo: boolean;
}

interface HistoryEntry {
  readonly beforeWeapon: LayeredWeaponDefinition;
  readonly beforeAnimation: LayeredAnimationDocumentStateValue;
  readonly afterWeapon: LayeredWeaponDefinition;
  readonly afterAnimation: LayeredAnimationDocumentStateValue;
}

function clone<T>(value: T): T {
  return structuredClone(value);
}

function isLayeredWeapon(value: AuthoredWeaponDefinition): value is LayeredWeaponDefinition {
  return value.version === 2;
}

function animationFor(weapon: LayeredWeaponDefinition, slot: WeaponOwnedAnimationSlot): LayeredAnimationDocument | undefined {
  if (slot.slot === 'idle') return weapon.animations.idle;
  return weapon.directionalAttacks[slot.direction]?.animation;
}

function assertOwnedSlot(weapon: AuthoredWeaponDefinition, slot: WeaponOwnedAnimationSlot): LayeredWeaponDefinition {
  if (!isLayeredWeapon(weapon)) throw new Error('Only version 2 weapons have editable layered animations.');
  if (slot.slot === 'idle') {
    if (weapon.animations.idleAnimationId) throw new Error('Idle animation is a shared reference and is not weapon-owned.');
    if (!weapon.animations.idle) throw new Error('Weapon idle animation is missing.');
  } else {
    const attack = weapon.directionalAttacks[slot.direction];
    if (!attack) throw new Error(`${slot.direction} attack is inherited and is not weapon-owned.`);
    if (attack.animationId) throw new Error(`${slot.direction} attack animation is a shared reference and is not weapon-owned.`);
    if (!attack.animation) throw new Error(`${slot.direction} attack animation is missing.`);
  }
  return weapon;
}

function replaceAnimation(weapon: LayeredWeaponDefinition, slot: WeaponOwnedAnimationSlot, animation: LayeredAnimationDocument): LayeredWeaponDefinition {
  if (slot.slot === 'idle') return { ...weapon, animations: { ...weapon.animations, idle: animation } };
  return { ...weapon, directionalAttacks: { ...weapon.directionalAttacks, [slot.direction]: { ...weapon.directionalAttacks[slot.direction]!, animation } } };
}

function trackFor(weapon: LayeredWeaponDefinition, slot: WeaponOwnedAnimationSlot) {
  return slot.slot === 'attack' ? weapon.directionalAttacks[slot.direction]?.attackTrack : undefined;
}

function replaceTrack(weapon: LayeredWeaponDefinition, slot: WeaponOwnedAnimationSlot, track: NonNullable<ReturnType<typeof trackFor>>): LayeredWeaponDefinition {
  if (slot.slot !== 'attack') return weapon;
  return { ...weapon, directionalAttacks: { ...weapon.directionalAttacks, [slot.direction]: { ...weapon.directionalAttacks[slot.direction]!, attackTrack: track } } };
}

export class WeaponOwnedAnimationDocumentState {
  private draft: LayeredWeaponDefinition;
  private saved: LayeredWeaponDefinition;
  private readonly slot: WeaponOwnedAnimationSlot;
  private readonly document: LayeredAnimationDocumentState;
  private readonly undoStack: HistoryEntry[] = [];
  private readonly redoStack: HistoryEntry[] = [];
  private revision: string;

  constructor(weapon: AuthoredWeaponDefinition, revision: string, slot: WeaponOwnedAnimationSlot) {
    const layered = assertOwnedSlot(clone(weapon), slot);
    const animation = animationFor(layered, slot);
    if (!animation) throw new Error('The selected weapon-owned animation is missing.');
    this.draft = layered;
    this.saved = clone(layered);
    this.slot = slot;
    this.revision = revision;
    this.document = new LayeredAnimationDocumentState(animation);
  }

  get value(): WeaponOwnedAnimationSnapshot {
    const animation = this.document.value;
    return { weapon: clone(this.draft), revision: this.revision, slot: this.slot, animation, dirty: JSON.stringify(this.draft) !== JSON.stringify(this.saved), errors: validateWeaponDefinitionForStudioSave(this.draft), canUndo: this.undoStack.length > 0, canRedo: this.redoStack.length > 0 };
  }

  private mutate(operation: (document: LayeredAnimationDocumentState) => boolean): boolean {
    const beforeWeapon = clone(this.draft);
    const beforeAnimation = this.document.value;
    const previous = animationFor(this.draft, this.slot);
    if (!previous || !operation(this.document)) return false;
    const nextAnimation = this.document.value.animation;
    let nextWeapon = replaceAnimation(this.draft, this.slot, nextAnimation);
    const track = trackFor(this.draft, this.slot);
    if (track && previous && this.slot.slot === 'attack' && (previous.framesPerSecond !== nextAnimation.framesPerSecond || layeredTimelineFrameCount(previous) !== layeredTimelineFrameCount(nextAnimation))) {
      nextWeapon = replaceTrack(nextWeapon, this.slot, reconcileWeaponAttackTrack(track, previous, nextAnimation));
    }
    this.draft = nextWeapon;
    this.undoStack.push({ beforeWeapon, beforeAnimation, afterWeapon: clone(this.draft), afterAnimation: this.document.value });
    this.redoStack.length = 0;
    return true;
  }

  selectLayer(layerId: string): boolean { return this.document.selectLayer(layerId); }
  selectBlock(layerId: string, blockIndex: number): boolean { return this.document.selectBlock(layerId, blockIndex); }
  setPlayhead(frame: number): void { this.document.setPlayhead(frame); }
  addLayer(layer: Parameters<LayeredAnimationDocumentState['addLayer']>[0]): boolean { return this.mutate((document) => document.addLayer(layer)); }
  renameLayer(layerId: string, displayName: string): boolean { return this.mutate((document) => document.renameLayer(layerId, displayName)); }
  setLayerAsset(layerId: string, assetId: string): boolean { return this.mutate((document) => document.setLayerAsset(layerId, assetId)); }
  setLayerTransform(layerId: string, transform: Parameters<LayeredAnimationDocumentState['setLayerTransform']>[1]): boolean { return this.mutate((document) => document.setLayerTransform(layerId, transform)); }
  setBlockTransform(layerId: string, blockIndex: number, transform?: Parameters<LayeredAnimationDocumentState['setBlockTransform']>[2]): boolean { return this.mutate((document) => document.setBlockTransform(layerId, blockIndex, transform)); }
  moveBlock(layerId: string, blockIndex: number, from: number): boolean { return this.mutate((document) => document.moveBlock(layerId, blockIndex, from)); }
  resizeBlock(layerId: string, blockIndex: number, through: number): boolean { return this.mutate((document) => document.resizeBlock(layerId, blockIndex, through)); }
  duplicateBlock(layerId: string, blockIndex: number): boolean { return this.mutate((document) => document.duplicateBlock(layerId, blockIndex)); }
  deleteBlock(layerId: string, blockIndex: number): boolean { return this.mutate((document) => document.deleteBlock(layerId, blockIndex)); }
  insertTiles(layerId: string, frames: readonly number[], from?: number): boolean { return this.mutate((document) => document.placeTiles(layerId, frames, from)); }
  setFramesPerSecond(fps: number): boolean { return this.mutate((document) => document.setFramesPerSecond(fps)); }
  setDurationSeconds(duration: number): boolean { return this.mutate((document) => document.setDurationSeconds(duration)); }
  setLoop(loop: boolean): boolean { return this.mutate((document) => document.setLoop(loop)); }
  setLoopMode(mode: 'wrap' | 'ping-pong'): boolean { return this.mutate((document) => document.setLoopMode(mode)); }

  undo(): boolean {
    const entry = this.undoStack.pop();
    if (!entry) return false;
    this.redoStack.push(entry);
    this.draft = clone(entry.beforeWeapon);
    this.document.restore(entry.beforeAnimation);
    return true;
  }

  redo(): boolean {
    const entry = this.redoStack.pop();
    if (!entry) return false;
    this.undoStack.push(entry);
    this.draft = clone(entry.afterWeapon);
    this.document.restore(entry.afterAnimation);
    return true;
  }

  markSaved(weapon: AuthoredWeaponDefinition, revision: string): void {
    const layered = assertOwnedSlot(clone(weapon), this.slot);
    const animation = animationFor(layered, this.slot);
    if (!animation) throw new Error('Saved weapon is missing the selected animation.');
    this.draft = layered;
    this.saved = clone(layered);
    this.revision = revision;
    this.document.replace(animation);
    this.undoStack.length = 0;
    this.redoStack.length = 0;
  }
}
