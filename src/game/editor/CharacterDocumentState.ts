import {
  addTrackEvent,
  addTrackSpan,
  canonicalizeSpans,
  duplicateTimelineFrame,
  insertTimelineFrames,
  removeTimelineFrame,
  removeTrackEvent,
  removeTrackSpan,
  reorderTimelineFrame,
} from './CharacterTimeline';
import { cloneCharacterPackage, normalizeCharacterPackage, validateCharacterPackage, type CharacterValidationIssue } from '../content/characters/validation';
import { AnimationTimelineError, normalizeAnimationClip, rescaleKeyframeTimes } from '../shared/animation';
import type {
  CharacterBodyDocument,
  CharacterAttributeSet,
  CharacterEventDocument,
  CharacterHitboxDocument,
  CharacterPackage,
  HitboxSpanDocument,
  JsonValue,
  VisualLoopMode,
  VisualTransformDocument,
} from '../content/characters/types';

export type CharacterSaveState = 'clean' | 'dirty' | 'saving' | 'saved' | 'error' | 'conflict';

export interface CharacterDocumentSnapshot extends CharacterPackage {
  readonly selectedClipId: string;
  readonly selectedTimelineIndex: number;
  readonly selectedSourceFrame: number;
  readonly selectedSourceFrames: readonly number[];
  readonly errors: readonly CharacterValidationIssue[];
  readonly saveState: CharacterSaveState;
  readonly dirty: boolean;
  readonly revision: string;
  readonly previewRevision: number;
  readonly statusMessage: string;
}

type Listener = (snapshot: CharacterDocumentSnapshot) => void;
type Mutation = (draft: CharacterPackage) => void;

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

export class CharacterDocumentState {
  private draft: CharacterPackage;
  private saved: CharacterPackage;
  private revision: string;
  private selectedClipId: string;
  private selectedTimelineIndex = 0;
  private selectedSourceFrame = 0;
  private readonly selectedSourceFrames = new Set<number>();
  private errors: CharacterValidationIssue[] = [];
  private saveState: CharacterSaveState = 'clean';
  private statusMessage = 'Saved package';
  private previewRevision = 0;
  private readonly undoStack: Array<{ label: string; before: CharacterPackage; after: CharacterPackage }> = [];
  private readonly redoStack: Array<{ label: string; before: CharacterPackage; after: CharacterPackage }> = [];
  private readonly listeners = new Set<Listener>();

  constructor(packageValue: CharacterPackage, revision: string) {
    this.draft = cloneCharacterPackage(packageValue);
    this.saved = cloneCharacterPackage(packageValue);
    this.revision = revision;
    this.selectedClipId = Object.keys(this.draft.visualSet.clips)[0] ?? '';
    this.revalidate();
  }

  get value(): CharacterDocumentSnapshot {
    return {
      character: clone(this.draft.character),
      visualSet: clone(this.draft.visualSet),
      selectedClipId: this.selectedClipId,
      selectedTimelineIndex: this.selectedTimelineIndex,
      selectedSourceFrame: this.selectedSourceFrame,
      selectedSourceFrames: [...this.selectedSourceFrames],
      errors: [...this.errors],
      saveState: this.saveState,
      dirty: JSON.stringify(this.draft) !== JSON.stringify(this.saved),
      revision: this.revision,
      previewRevision: this.previewRevision,
      statusMessage: this.statusMessage,
    };
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.value);
    return () => this.listeners.delete(listener);
  }

  selectClip(clipId: string): void {
    if (!this.draft.visualSet.clips[clipId]) return;
    this.selectedClipId = clipId;
    this.selectedTimelineIndex = 0;
    this.selectedSourceFrame = this.draft.visualSet.clips[clipId].frames[0] ?? 0;
    this.selectedSourceFrames.clear();
    this.emit();
  }

  selectTimelineIndex(index: number): void {
    const clip = this.draft.visualSet.clips[this.selectedClipId];
    if (!clip) return;
    this.selectedTimelineIndex = Math.max(0, Math.min(index, clip.frames.length - 1));
    this.selectedSourceFrame = clip.frames[this.selectedTimelineIndex] ?? 0;
    this.emit();
  }

  selectSourceFrame(frame: number): void {
    this.selectedSourceFrame = frame;
    if (this.selectedSourceFrames.has(frame)) this.selectedSourceFrames.delete(frame);
    else this.selectedSourceFrames.add(frame);
    this.emit();
  }

  mutate(label: string, mutation: Mutation): boolean {
    const before = cloneCharacterPackage(this.draft);
    mutation(this.draft);
    if (JSON.stringify(before) === JSON.stringify(this.draft)) return false;
    this.undoStack.push({ label, before, after: cloneCharacterPackage(this.draft) });
    this.redoStack.length = 0;
    this.previewRevision += 1;
    this.saveState = 'dirty';
    this.statusMessage = `${label} — unsaved`;
    this.revalidate();
    return true;
  }

  undo(): void {
    const command = this.undoStack.pop();
    if (!command) return;
    this.redoStack.push({ ...command });
    this.draft = cloneCharacterPackage(command.before);
    this.previewRevision += 1;
    this.saveState = 'dirty';
    this.statusMessage = `Undid ${command.label}`;
    this.revalidate();
  }

  redo(): void {
    const command = this.redoStack.pop();
    if (!command) return;
    this.undoStack.push({ ...command });
    this.draft = cloneCharacterPackage(command.after);
    this.previewRevision += 1;
    this.saveState = 'dirty';
    this.statusMessage = `Redid ${command.label}`;
    this.revalidate();
  }

  addClip(clipId: string): boolean {
    return this.mutate(`Added ${clipId}`, (draft) => {
      if (draft.visualSet.clips[clipId] || !/^[a-z0-9]+(?:[.-][a-z0-9-]+)*$/.test(clipId)) return;
      draft.visualSet.clips[clipId] = { frames: [], framesPerSecond: 8, loop: true, loopMode: 'wrap' };
      this.selectedClipId = clipId;
      this.selectedTimelineIndex = 0;
      draft.character.animationTracks[clipId] = {};
    });
  }

  renameClip(nextClipId: string): boolean {
    const oldClipId = this.selectedClipId;
    return this.mutate(`Renamed ${oldClipId}`, (draft) => {
      if (!draft.visualSet.clips[oldClipId] || draft.visualSet.clips[nextClipId] || !/^[a-z0-9]+(?:[.-][a-z0-9-]+)*$/.test(nextClipId)) return;
      draft.visualSet.clips[nextClipId] = draft.visualSet.clips[oldClipId];
      delete draft.visualSet.clips[oldClipId];
      if (draft.character.animationTracks[oldClipId]) {
        draft.character.animationTracks[nextClipId] = draft.character.animationTracks[oldClipId];
        delete draft.character.animationTracks[oldClipId];
      }
      this.selectedClipId = nextClipId;
    });
  }

  duplicateClip(nextClipId: string): boolean {
    const sourceClipId = this.selectedClipId;
    return this.mutate(`Duplicated ${sourceClipId}`, (draft) => {
      if (!draft.visualSet.clips[sourceClipId] || draft.visualSet.clips[nextClipId] || !/^[a-z0-9]+(?:[.-][a-z0-9-]+)*$/.test(nextClipId)) return;
      draft.visualSet.clips[nextClipId] = clone(draft.visualSet.clips[sourceClipId]);
      draft.character.animationTracks[nextClipId] = clone(draft.character.animationTracks[sourceClipId] ?? {});
      this.selectedClipId = nextClipId;
      this.selectedTimelineIndex = 0;
    });
  }

  removeClip(): boolean {
    const clipId = this.selectedClipId;
    return this.mutate(`Removed ${clipId}`, (draft) => {
      if (Object.keys(draft.visualSet.clips).length <= 1) return;
      delete draft.visualSet.clips[clipId];
      delete draft.character.animationTracks[clipId];
      this.selectedClipId = Object.keys(draft.visualSet.clips)[0] ?? '';
      this.selectedTimelineIndex = 0;
    });
  }

  appendSelectedFrames(frames: readonly number[]): boolean {
    return this.mutate(`Added ${frames.length} timeline frame${frames.length === 1 ? '' : 's'}`, (draft) => {
      insertTimelineFrames(draft.character, draft.visualSet, this.selectedClipId, draft.visualSet.clips[this.selectedClipId]?.frames.length ?? 0, frames);
    });
  }

  insertSelectedFrames(frames: readonly number[]): boolean {
    return this.mutate(`Inserted ${frames.length} timeline frame${frames.length === 1 ? '' : 's'}`, (draft) => {
      insertTimelineFrames(draft.character, draft.visualSet, this.selectedClipId, this.selectedTimelineIndex, frames);
    });
  }

  removeSelectedFrame(): boolean {
    return this.mutate('Removed timeline frame', (draft) => removeTimelineFrame(draft.character, draft.visualSet, this.selectedClipId, this.selectedTimelineIndex));
  }

  duplicateSelectedFrame(): boolean {
    return this.mutate('Duplicated timeline frame', (draft) => duplicateTimelineFrame(draft.character, draft.visualSet, this.selectedClipId, this.selectedTimelineIndex));
  }

  reorderFrame(to: number): boolean {
    const from = this.selectedTimelineIndex;
    const clip = this.draft.visualSet.clips[this.selectedClipId];
    if (!clip || from < 0 || to < 0 || from >= clip.frames.length || to >= clip.frames.length || from === to) return false;
    return this.mutate('Reordered timeline frame', (draft) => {
      reorderTimelineFrame(draft.visualSet, this.selectedClipId, from, to);
      this.selectedTimelineIndex = to;
      this.selectedSourceFrame = draft.visualSet.clips[this.selectedClipId]?.frames[to] ?? this.selectedSourceFrame;
    });
  }

  reorderFrameFrom(from: number, to: number): boolean {
    const clip = this.draft.visualSet.clips[this.selectedClipId];
    if (!clip || from < 0 || to < 0 || from >= clip.frames.length || to >= clip.frames.length || from === to) return false;
    return this.mutate('Reordered timeline frame', (draft) => {
      reorderTimelineFrame(draft.visualSet, this.selectedClipId, from, to);
      this.selectedTimelineIndex = to;
      this.selectedSourceFrame = draft.visualSet.clips[this.selectedClipId]?.frames[to] ?? this.selectedSourceFrame;
    });
  }

  updatePlayback(framesPerSecond: number, loop: boolean, loopMode: VisualLoopMode, durationSeconds?: number): boolean {
    return this.mutate('Updated playback', (draft) => {
      const clip = draft.visualSet.clips[this.selectedClipId];
      if (!clip) return;
      const nextDuration = durationSeconds === undefined ? clip.durationSeconds : durationSeconds;
      if (nextDuration !== undefined && clip.frames.length > 0) {
        try {
          const normalized = normalizeAnimationClip(clip);
          clip.keyframeTimes = rescaleKeyframeTimes(normalized, nextDuration, framesPerSecond);
          clip.durationSeconds = nextDuration;
        } catch (error) {
          if (error instanceof AnimationTimelineError) return;
          throw error;
        }
      } else if (nextDuration !== undefined) {
        clip.durationSeconds = nextDuration;
      }
      clip.framesPerSecond = framesPerSecond;
      clip.loop = loop;
      clip.loopMode = loopMode;
    });
  }

  updateDefaults(transform: VisualTransformDocument): boolean {
    return this.mutate('Updated default visual alignment', (draft) => { draft.visualSet.defaults = { ...draft.visualSet.defaults, ...clone(transform) }; });
  }

  updateAnimationVisual(sourceOffset: [number, number]): boolean {
    return this.mutate(`Updated ${this.selectedClipId} animation alignment`, (draft) => {
      const clip = draft.visualSet.clips[this.selectedClipId];
      if (clip) clip.sourceOffset = clone(sourceOffset);
    });
  }

  resetAnimationVisual(): boolean {
    return this.mutate(`Reset ${this.selectedClipId} animation alignment`, (draft) => {
      const clip = draft.visualSet.clips[this.selectedClipId];
      if (clip) delete clip.sourceOffset;
    });
  }

  updateFrameVisual(frame: number, transform: VisualTransformDocument): boolean {
    return this.mutate(`Updated frame ${frame} alignment`, (draft) => {
      draft.visualSet.frameVisuals ??= {};
      draft.visualSet.frameVisuals[String(frame)] = { ...draft.visualSet.frameVisuals[String(frame)], ...clone(transform) };
    });
  }

  resetFrameVisual(frame: number): boolean {
    return this.mutate(`Reset frame ${frame} alignment`, (draft) => { delete draft.visualSet.frameVisuals?.[String(frame)]; });
  }

  updateBody(body: Partial<CharacterBodyDocument>): boolean {
    return this.mutate('Updated stable body', (draft) => {
      draft.character.body = { ...draft.character.body, ...clone(body) };
      if (draft.character.body.shape === 'circle') {
        draft.character.body.radius ??= Math.min(draft.character.body.width, draft.character.body.height) / 2;
        delete draft.character.body.radiusX;
        delete draft.character.body.radiusY;
      } else if (draft.character.body.shape === 'ellipse') {
        draft.character.body.radiusX ??= draft.character.body.width / 2;
        draft.character.body.radiusY ??= draft.character.body.height / 2;
        delete draft.character.body.radius;
      } else {
        delete draft.character.body.shape;
        delete draft.character.body.radius;
        delete draft.character.body.radiusX;
        delete draft.character.body.radiusY;
      }
    });
  }

  updateAttributes(attributes: Partial<CharacterAttributeSet>): boolean {
    return this.mutate('Updated character attributes', (draft) => {
      draft.character.attributes = {
        strength: 10,
        vitality: 10,
        agility: 10,
        intellect: 10,
        ...(draft.character.attributes ?? {}),
        ...clone(attributes),
      };
    });
  }

  updateHitbox(hitboxId: string, hitbox: Partial<CharacterHitboxDocument>): boolean {
    return this.mutate(`Updated ${hitboxId} hitbox`, (draft) => {
      const current = draft.character.hitboxes[hitboxId] ?? { shape: 'rectangle' as const, width: 1, height: 1, offsetX: 0, offsetY: 0, mirrorX: false };
      draft.character.hitboxes[hitboxId] = { ...current, ...clone(hitbox) };
      const next = draft.character.hitboxes[hitboxId];
      if (next.shape === 'circle') {
        next.radius ??= Math.min(next.width, next.height) / 2;
        delete next.radiusX;
        delete next.radiusY;
      } else if (next.shape === 'ellipse') {
        next.radiusX ??= next.width / 2;
        next.radiusY ??= next.height / 2;
        delete next.radius;
      } else {
        delete next.radius;
        delete next.radiusX;
        delete next.radiusY;
      }
    });
  }

  setEnemyRanged(enabled: boolean, projectileAssetId: string): boolean {
    return this.mutate(enabled ? 'Enabled ranged capability' : 'Disabled ranged capability', (draft) => {
      const enemy = draft.character.enemy;
      if (!enemy) return;
      enemy.ai.isRanged = enabled;
      if (enabled) {
        enemy.ai.projectileSpeed ??= 180;
        enemy.projectile ??= { assetId: projectileAssetId, damage: enemy.ai.contactDamage };
        if (!enemy.projectile.assetId && projectileAssetId) enemy.projectile.assetId = projectileAssetId;
      } else {
        delete enemy.ai.projectileSpeed;
        delete enemy.projectile;
      }
    });
  }

  setEnemyLeaper(enabled: boolean): boolean {
    return this.mutate(enabled ? 'Enabled leap capability' : 'Disabled leap capability', (draft) => {
      const enemy = draft.character.enemy;
      if (!enemy) return;
      enemy.ai.isLeaper = enabled;
      if (enabled) enemy.ai.leapRange ??= Math.max(enemy.ai.attackRange * 2, 1);
      else delete enemy.ai.leapRange;
    });
  }

  updateEnemyProjectileAsset(assetId: string): boolean {
    return this.mutate('Updated projectile asset', (draft) => {
      const enemy = draft.character.enemy;
      if (!enemy) return;
      enemy.projectile ??= { assetId, damage: enemy.ai.contactDamage };
      enemy.projectile.assetId = assetId;
    });
  }

  addHitbox(hitboxId: string): boolean {
    return this.mutate(`Added ${hitboxId} hitbox`, (draft) => {
      if (!/^[a-z0-9]+(?:[.-][a-z0-9-]+)*$/.test(hitboxId) || draft.character.hitboxes[hitboxId]) return;
      draft.character.hitboxes[hitboxId] = { shape: 'rectangle', width: 24, height: 16, offsetX: 18, offsetY: 0, mirrorX: true };
    });
  }

  removeHitbox(hitboxId: string): boolean {
    return this.mutate(`Removed ${hitboxId} hitbox`, (draft) => {
      delete draft.character.hitboxes[hitboxId];
      for (const track of Object.values(draft.character.animationTracks)) track.hitboxSpans = track.hitboxSpans?.filter((span) => span.hitboxId !== hitboxId);
    });
  }

  addSpan(span: HitboxSpanDocument): boolean { return this.mutate('Added hitbox span', (draft) => addTrackSpan(draft.character, this.selectedClipId, span)); }
  removeSpan(index: number): boolean { return this.mutate('Removed hitbox span', (draft) => removeTrackSpan(draft.character, this.selectedClipId, index)); }
  addEvent(event: CharacterEventDocument): boolean { return this.mutate('Added event marker', (draft) => addTrackEvent(draft.character, this.selectedClipId, event)); }
  removeEvent(index: number): boolean { return this.mutate('Removed event marker', (draft) => removeTrackEvent(draft.character, this.selectedClipId, index)); }

  updateGameplay(path: string[], value: JsonValue): boolean {
    return this.mutate(`Updated ${path.join('.')}`, (draft) => {
      let cursor: Record<string, unknown> = draft.character as unknown as Record<string, unknown>;
      for (const segment of path.slice(0, -1)) {
        const next = cursor[segment];
        if (!next || typeof next !== 'object' || Array.isArray(next)) return;
        cursor = next as Record<string, unknown>;
      }
      cursor[path[path.length - 1] ?? ''] = value;
    });
  }

  markSaving(): void { this.saveState = 'saving'; this.statusMessage = 'Saving package…'; this.emit(); }

  markSaved(packageValue: CharacterPackage, revision: string): void {
    this.draft = cloneCharacterPackage(normalizeCharacterPackage(packageValue));
    this.saved = cloneCharacterPackage(this.draft);
    this.revision = revision;
    this.saveState = 'saved';
    this.statusMessage = 'Saved to disk';
    this.errors = [];
    this.emit();
  }

  markSaveFailure(message: string, conflict = false): void { this.saveState = conflict ? 'conflict' : 'error'; this.statusMessage = message; this.emit(); }

  private revalidate(): void {
    this.errors = validateCharacterPackage(this.draft);
    if (this.errors.length > 0) this.statusMessage = `${this.errors.length} validation issue${this.errors.length === 1 ? '' : 's'}`;
    this.emit();
  }

  private emit(): void { for (const listener of this.listeners) listener(this.value); }
}

export { canonicalizeSpans };
