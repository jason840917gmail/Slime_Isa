import type { PropertyDescriptor } from '../../../content/scenes/propertyDescriptors';
import type { JsonValue } from '../../../content/scenes/types';
import { ANIMATION_KEY_TRANSITIONS, type AnimationDomain, type AnimationKeyTransition, type AnimationPropertyKey, type AnimationTrackInterpolation } from '../../../runtime/scene/animation/AnimationBinding';
import type { UniversalAnimationEvent } from '../../../runtime/scene/animation/AnimationEvent';
import type { UniversalAnimationDocument, UniversalAnimationPropertyTrack } from '../../../runtime/scene/animation/AnimationPlayerNode';
import type { ComposedSceneNode } from '../SceneViewport';
import {
  addEvent,
  addTrack,
  clipDomainIssues,
  clipFrameCount,
  copyKeys,
  createClip,
  deleteClip,
  deleteFrames,
  duplicateClip,
  formatClipSeconds,
  insertFrames,
  keyAt,
  mirrorClip,
  moveKeys,
  moveTrack,
  pasteKeys,
  removeEvent,
  removeKeys,
  removeTrack,
  renameClip,
  retargetTrack,
  sampleTrack,
  setFrameCount,
  setFramesPerSecond,
  setKey,
  setKeyTransition,
  setLoop,
  setTrackEnabled,
  setTrackInterpolation,
  simplifyKeys,
  uniqueClipId,
  updateEvent,
  type AnimationClips,
  type AnimationKeyClipboard,
  type AnimationKeyRef,
  type ClipEdit,
} from './AnimationClipModel';
import { descriptorIsNumeric, initialKeyValue, resolveBinding, type AnimationTarget } from './AnimationTargets';
import { animationValueKind, formatAnimationValue, readAnimationValue, renderAnimationValueFields, type AnimationValueKind } from './AnimationValueFields';
import { attackLanes, hitboxActiveAt, planDirectionsForClip, removeHitboxSpan, renamePlanClip, setHitboxFrame, syncPlansWithClip, updateHitboxSpan, type AttackPlans, type WeaponAttackLane } from './WeaponAttackLanes';

/** Everything the timeline needs to know about the selected AnimationPlayer. */
export interface AnimationEditorContext {
  readonly playerKey: string;
  readonly playerName: string;
  readonly libraryId: string;
  readonly clips: AnimationClips;
  readonly domain: AnimationDomain;
  readonly autoplay?: string;
  /** Why edits are disabled (instanced or read-only players), if they are. */
  readonly readOnlyReason?: string;
  readonly sourceSceneId?: string;
  readonly nodes: readonly ComposedSceneNode[];
  readonly targets: readonly AnimationTarget[];
  readonly attack?: { readonly plans: AttackPlans; readonly shapeNames: readonly string[] };
  readonly propertyDescriptors: (node: ComposedSceneNode) => readonly PropertyDescriptor[];
}

export interface AnimationLibraryChange {
  readonly clips: AnimationClips;
  readonly plans?: AttackPlans;
  /** New autoplay clip, or null to clear it. */
  readonly autoplay?: string | null;
}

export interface AnimationPreviewState {
  readonly clip?: string;
  readonly frame: number;
  readonly playing: boolean;
}

export interface AnimationEditorHost {
  /** Applies one undoable change; returns false (and reports) when it was rejected. */
  commit(label: string, change: AnimationLibraryChange): boolean;
  notify(message: string): void;
  pose(clip: string, frame: number): boolean;
  play(clip: string, frame: number): boolean;
  pause(): void;
  stop(): void;
  previewState(): AnimationPreviewState | undefined;
  onionSkin(frames: readonly { readonly frame: number; readonly tint: number }[]): void;
  /** Sprite-sheet frame image and frame count for a Sprite2D texture reference. */
  spriteFrames(texture: JsonValue | undefined): { readonly count: number; readonly thumbnail: (frame: number) => string | undefined } | undefined;
  openScene(sceneId: string): void;
  /** Selects a node in the scene tree and viewport (e.g. a hitbox shape to edit its geometry). */
  selectNode(nodeKey: string): void;
  /** The playhead moved or the clip changed (the viewport highlights active hitboxes). */
  playheadChanged(): void;
  close(): void;
}

type Selection =
  | { readonly kind: 'none' }
  | { readonly kind: 'keys'; readonly refs: readonly AnimationKeyRef[] }
  | { readonly kind: 'event'; readonly index: number }
  | { readonly kind: 'span'; readonly direction: string; readonly index: number };

interface TrackView {
  readonly index: number;
  readonly track: UniversalAnimationPropertyTrack;
  readonly node?: ComposedSceneNode;
  readonly descriptor?: PropertyDescriptor;
  readonly linear: boolean;
}

type Drag =
  | { readonly kind: 'scrub'; readonly lane: HTMLElement }
  | { readonly kind: 'keys'; readonly startX: number; readonly refs: readonly AnimationKeyRef[]; readonly clickedRef: AnimationKeyRef; readonly additive: boolean; delta: number; moved: boolean }
  | { readonly kind: 'marquee'; readonly startX: number; readonly startY: number; readonly lane: HTMLElement; readonly track?: number; moved: boolean; readonly box: HTMLElement }
  | { readonly kind: 'event'; readonly startX: number; readonly index: number; delta: number; moved: boolean }
  | { readonly kind: 'paint'; readonly lane: HTMLElement; readonly direction: string; readonly hitboxId: string; readonly active: boolean; readonly frames: Set<number> }
  | { readonly kind: 'resize'; readonly startY: number; readonly startHeight: number };

const ONION_PAST = 0x4fb4ff;
const ONION_FUTURE = 0xff7a59;
const LABEL_WIDTH = 340;

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character] ?? character);
}

function refId(ref: AnimationKeyRef): string { return `${ref.track}:${ref.at}`; }

/**
 * Godot-style animation dock: clip toolbar, per-node track groups with keys,
 * an event lane, weapon hitbox lanes and a key inspector. It owns its DOM so
 * Scene Studio's full re-renders only re-attach it, keeping drags smooth.
 */
export class AnimationTimelinePanel {
  readonly element: HTMLElement;
  private context?: AnimationEditorContext;
  private clipId?: string;
  private playhead = 0;
  private playing = false;
  private selection: Selection = { kind: 'none' };
  private focusedTrack?: number;
  private zoom = 18;
  private height = 300;
  private onion = false;
  /** Viewport drags and inspector edits of animated nodes become keys at the playhead. */
  private autoKey = true;
  private keepDuration = true;
  private stretchLength = false;
  private addTrackFilter?: string;
  private clipboard?: AnimationKeyClipboard;
  private drag?: Drag;
  private raf?: number;
  private scroll = { left: 0, top: 0 };

  constructor(private readonly host: AnimationEditorHost) {
    this.element = document.createElement('section');
    this.element.className = 'anim-dock';
    this.element.tabIndex = -1;
    this.element.setAttribute('aria-label', 'Animation timeline');
    this.element.addEventListener('click', (event) => this.onClick(event));
    this.element.addEventListener('dblclick', (event) => this.onDoubleClick(event));
    this.element.addEventListener('change', (event) => this.onChange(event));
    this.element.addEventListener('input', (event) => this.onInput(event));
    this.element.addEventListener('pointerdown', (event) => this.onPointerDown(event));
    this.element.addEventListener('pointermove', (event) => this.onPointerMove(event));
    this.element.addEventListener('pointerup', (event) => this.onPointerUp(event));
    this.element.addEventListener('pointercancel', () => this.cancelDrag());
    this.element.addEventListener('keydown', (event) => this.onKeyDown(event));
    this.element.addEventListener('wheel', (event) => this.onWheel(event), { passive: false });
  }

  get visible(): boolean { return this.context !== undefined; }

  /** Weapon hitboxes whose attack window covers the playhead. */
  activeHitboxes(): readonly { readonly direction: string; readonly hitboxId: string }[] {
    return this.lanes().filter((lane) => lane.spans.some((span) => span.from <= this.playhead && this.playhead <= span.through)).map((lane) => ({ direction: lane.direction, hitboxId: lane.hitboxId }));
  }

  destroy(): void {
    if (this.raf !== undefined) cancelAnimationFrame(this.raf);
    this.raf = undefined;
    this.element.remove();
  }

  /** Receives a fresh context after every studio change; renders only when something shown differs. */
  update(context: AnimationEditorContext | undefined): void {
    const previousPlayer = this.context?.playerKey;
    this.context = context;
    if (!context) { this.stopPlayback(); this.element.replaceChildren(); return; }
    if (previousPlayer !== context.playerKey) {
      this.clipId = undefined;
      this.selection = { kind: 'none' };
      this.focusedTrack = undefined;
      this.playhead = 0;
    }
    if (!this.clipId || !context.clips[this.clipId]) {
      this.clipId = context.autoplay && context.clips[context.autoplay] ? context.autoplay : Object.keys(context.clips)[0];
      this.selection = { kind: 'none' };
      this.playhead = 0;
    }
    this.clampState();
    this.render();
  }

  /** Animatable properties of a node the pinned player can bind, or undefined when it cannot key it. */
  private keyableTarget(nodeKey: string): AnimationTarget | undefined {
    if (!this.editable || !this.clip) return undefined;
    return this.context?.targets.find((target) => target.key === nodeKey);
  }

  /** Whether viewport and inspector edits of this node should become keys (auto-key on). */
  autoKeys(nodeKey: string): boolean {
    return this.autoKey && this.keyableTarget(nodeKey) !== undefined;
  }

  /** Keys a node property at the playhead, creating its track when needed. */
  keyNodeProperty(nodeKey: string, property: string, value: JsonValue): boolean {
    const target = this.keyableTarget(nodeKey);
    const clip = this.clip;
    if (!target || !clip) return false;
    if (!target.properties.some((descriptor) => descriptor.key === property)) { this.host.notify(`'${property}' cannot be animated here`); return false; }
    try {
      const index = clip.tracks.findIndex((track) => track.binding === target.binding && track.property === property);
      const next = index >= 0 ? setKey(clip, index, this.playhead, value) : addTrack(clip, target.binding, property, { at: this.playhead, value });
      const trackIndex = index >= 0 ? index : next.tracks.length - 1;
      if (!this.commitClip(`Key ${target.name} ${property} @ ${this.playhead}`, next)) return false;
      this.focusedTrack = trackIndex;
      this.selection = { kind: 'keys', refs: [{ track: trackIndex, at: this.playhead }] };
      return true;
    } catch (error) {
      this.host.notify(error instanceof Error ? error.message : String(error));
      return false;
    }
  }

  /** Inserts a key holding the current value, or removes the key already at the playhead. */
  toggleNodeKey(nodeKey: string, property: string): void {
    const target = this.keyableTarget(nodeKey);
    const clip = this.clip;
    const descriptor = target?.properties.find((candidate) => candidate.key === property);
    if (!target || !clip || !descriptor) return;
    const index = clip.tracks.findIndex((track) => track.binding === target.binding && track.property === property);
    if (index >= 0 && keyAt(clip.tracks[index], this.playhead)) {
      this.attempt(() => { if (this.commitClip('Remove key', removeKeys(clip, [{ track: index, at: this.playhead }]))) this.selection = { kind: 'none' }; });
      return;
    }
    this.keyNodeProperty(nodeKey, property, this.nodeValue(target, descriptor));
  }

  /** Posed values of every enabled track at the playhead, keyed by composed node key. */
  poseOverrides(): ReadonlyMap<string, Readonly<Record<string, JsonValue>>> {
    const output = new Map<string, Record<string, JsonValue>>();
    for (const view of this.trackViews()) {
      if (!view.node || view.track.enabled === false) continue;
      const value = sampleTrack(view.track, this.playhead, view.linear);
      if (value === undefined) continue;
      output.set(view.node.key, { ...(output.get(view.node.key) ?? {}), [view.track.property]: value });
    }
    return output;
  }

  /** Keyframe rows for the node inspector (Godot's key icons), or '' when the node is not animatable here. */
  renderNodeKeyframes(nodeKey: string): string {
    const target = this.keyableTarget(nodeKey);
    const clip = this.clip;
    if (!target || !clip) return '';
    const rows = target.properties.map((descriptor) => {
      const track = clip.tracks.find((candidate) => candidate.binding === target.binding && candidate.property === descriptor.key);
      const value = this.nodeValue(target, descriptor);
      const kind = animationValueKind(descriptor.key, descriptor, value);
      const keyed = Boolean(track && keyAt(track, this.playhead));
      const state = !track ? 'not animated' : keyed ? 'key on this frame' : 'animated';
      return `<div class="scene-keyframe-row${track ? ' is-animated' : ''}" data-key-node="${escapeHtml(nodeKey)}" data-key-property="${escapeHtml(descriptor.key)}" data-kind="${kind}"><span title="${escapeHtml(state)}">${escapeHtml(descriptor.label)}</span><div>${renderAnimationValueFields(kind, value, { disabled: false, descriptor, label: descriptor.label, compact: true })}</div><button type="button" class="anim-key-toggle${keyed ? ' is-keyed' : ''}" data-key-toggle title="${keyed ? 'Remove the key at the playhead' : 'Insert a key at the playhead'}" aria-label="${keyed ? 'Remove key' : 'Insert key'} for ${escapeHtml(descriptor.label)}">${keyed ? '◆' : '◇'}</button></div>`;
    }).join('');
    return `<section class="scene-keyframes" aria-label="Animation keyframes"><header><span>KEYFRAMES · ${escapeHtml(this.clipId)} @ ${this.playhead}</span></header><p>Edits key this frame. ◆ = key here · filled label = animated.</p>${rows}</section>`;
  }

  private nodeValue(target: AnimationTarget, descriptor: PropertyDescriptor): JsonValue {
    const view = this.trackViews().find((candidate) => candidate.track.binding === target.binding && candidate.track.property === descriptor.key);
    return (view ? sampleTrack(view.track, this.playhead, view.linear) : undefined) ?? initialKeyValue(target.node, descriptor);
  }

  private keyTrackValue(index: number, value: JsonValue): void {
    const clip = this.clip;
    if (!clip) return;
    if (this.commitClip('Key value', setKey(clip, index, this.playhead, value))) {
      this.focusedTrack = index;
      this.selection = { kind: 'keys', refs: [{ track: index, at: this.playhead }] };
    }
  }

  /** Called after the preview re-mounted (every draft edit rebuilds it) to restore the pose or playback. */
  previewRemounted(): void {
    if (!this.context || !this.clipId) return;
    if (this.playing) { this.host.play(this.clipId, this.playhead); return; }
    this.pose();
    // Sprite-frame thumbnails come from the preview's textures, available once it is mounted.
    if (!this.drag) this.render();
  }

  // -------------------------------------------------------------------------
  // Model helpers
  // -------------------------------------------------------------------------

  private get clip(): UniversalAnimationDocument | undefined {
    return this.clipId ? this.context?.clips[this.clipId] : undefined;
  }

  private get frames(): number { return this.clip ? clipFrameCount(this.clip) : 1; }

  private get editable(): boolean { return Boolean(this.context && !this.context.readOnlyReason); }

  private trackViews(): readonly TrackView[] {
    const context = this.context;
    const clip = this.clip;
    if (!context || !clip) return [];
    return clip.tracks.map((track, index) => {
      const node = resolveBinding(context.nodes, context.playerKey, track.binding);
      const descriptor = node ? context.propertyDescriptors(node).find((candidate) => candidate.key === track.property) : undefined;
      const linear = descriptorIsNumeric(descriptor) && track.interpolation !== 'nearest';
      return { index, track, ...(node ? { node } : {}), ...(descriptor ? { descriptor } : {}), linear };
    });
  }

  private lanes(): readonly WeaponAttackLane[] {
    const attack = this.context?.attack;
    return attack && this.clipId ? attackLanes(attack.plans, this.clipId, attack.shapeNames) : [];
  }

  private clampState(): void {
    this.playhead = Math.max(0, Math.min(this.playhead, this.frames - 1));
    const clip = this.clip;
    if (!clip) { this.selection = { kind: 'none' }; return; }
    if (this.selection.kind === 'keys') {
      const refs = this.selection.refs.filter((ref) => clip.tracks[ref.track] && keyAt(clip.tracks[ref.track], ref.at));
      this.selection = refs.length > 0 ? { kind: 'keys', refs } : { kind: 'none' };
    } else if (this.selection.kind === 'event' && !clip.events?.[this.selection.index]) this.selection = { kind: 'none' };
    if (this.focusedTrack !== undefined && !clip.tracks[this.focusedTrack]) this.focusedTrack = undefined;
  }

  /** Commits a clip edit, keeping weapon attack plans in step with timing changes. */
  private commitClip(label: string, next: UniversalAnimationDocument, edit?: Pick<ClipEdit, 'remap'>): boolean {
    const context = this.context;
    const clipId = this.clipId;
    if (!context || !clipId) return false;
    const clips = { ...context.clips, [clipId]: next };
    const timingChanged = edit !== undefined || next.durationSeconds !== this.clip?.durationSeconds || next.framesPerSecond !== this.clip?.framesPerSecond;
    const plans = context.attack && timingChanged ? syncPlansWithClip(context.attack.plans, clipId, next, edit?.remap) : undefined;
    return this.host.commit(label, { clips, ...(plans ? { plans } : {}) });
  }

  private attempt(action: () => void): void {
    if (!this.editable) { this.host.notify(this.context?.readOnlyReason ?? 'Nothing to edit'); return; }
    try { action(); } catch (error) { this.host.notify(error instanceof Error ? error.message : String(error)); }
  }

  // -------------------------------------------------------------------------
  // Preview
  // -------------------------------------------------------------------------

  private pose(): void {
    if (!this.clipId) return;
    this.host.pose(this.clipId, this.playhead);
    if (this.onion && this.frames > 1) {
      const ghosts = [
        ...(this.playhead > 0 ? [{ frame: this.playhead - 1, tint: ONION_PAST }] : []),
        ...(this.playhead < this.frames - 1 ? [{ frame: this.playhead + 1, tint: ONION_FUTURE }] : []),
      ];
      this.host.onionSkin(ghosts);
    }
  }

  private seek(frame: number): void {
    this.playhead = Math.max(0, Math.min(Math.round(frame), this.frames - 1));
    if (this.playing) this.stopPlayback(false);
    this.pose();
    this.syncPlayhead();
  }

  private togglePlayback(): void {
    if (!this.clipId) return;
    if (this.playing) { this.stopPlayback(true); this.render(); return; }
    const from = !this.clip?.loop && this.playhead >= this.frames - 1 ? 0 : this.playhead;
    if (!this.host.play(this.clipId, from)) { this.host.notify(`'${this.clipId}' is not mounted in the preview yet`); return; }
    this.playhead = from;
    this.playing = true;
    this.render();
    const tick = (): void => {
      const state = this.host.previewState();
      if (!this.playing) return;
      if (!state || !state.playing || state.clip !== this.clipId) {
        // One-shot clips end on their last frame, like Godot's editor.
        this.playing = false;
        this.playhead = state && state.clip === this.clipId ? state.frame : this.frames - 1;
        this.pose();
        this.render();
        return;
      }
      this.playhead = state.frame;
      this.syncPlayhead();
      this.raf = requestAnimationFrame(tick);
    };
    this.raf = requestAnimationFrame(tick);
  }

  private stopPlayback(keepPose = true): void {
    if (this.raf !== undefined) cancelAnimationFrame(this.raf);
    this.raf = undefined;
    if (!this.playing) return;
    this.playing = false;
    const state = this.host.previewState();
    if (state && state.clip === this.clipId) this.playhead = state.frame;
    if (keepPose) { this.host.pause(); this.pose(); }
  }

  /** Moves the playhead line and frame readout without a full render. */
  private syncPlayhead(): void {
    const line = this.element.querySelector<HTMLElement>('.anim-playhead');
    if (line) line.style.left = `${LABEL_WIDTH + (this.playhead + 0.5) * this.zoom}px`;
    const readout = this.element.querySelector<HTMLElement>('[data-anim-readout]');
    if (readout && this.clip) readout.textContent = `${this.playhead} / ${this.frames - 1} · ${formatClipSeconds(this.playhead, this.clip.framesPerSecond)}`;
    for (const cell of this.element.querySelectorAll<HTMLElement>('.anim-ruler-cell.is-current')) cell.classList.remove('is-current');
    this.element.querySelector<HTMLElement>(`.anim-ruler-cell[data-frame="${this.playhead}"]`)?.classList.add('is-current');
    this.syncTrackValues();
    this.host.playheadChanged();
    if (this.playing) {
      const scroller = this.element.querySelector<HTMLElement>('.anim-scroll');
      const x = LABEL_WIDTH + this.playhead * this.zoom;
      if (scroller && (x < scroller.scrollLeft + LABEL_WIDTH || x > scroller.scrollLeft + scroller.clientWidth - this.zoom)) scroller.scrollLeft = Math.max(0, x - LABEL_WIDTH - 40);
    }
  }

  // -------------------------------------------------------------------------
  // Rendering
  // -------------------------------------------------------------------------

  private render(): void {
    const context = this.context;
    if (!context) return;
    const scroller = this.element.querySelector<HTMLElement>('.anim-scroll');
    if (scroller) this.scroll = { left: scroller.scrollLeft, top: scroller.scrollTop };
    const focusedSelector = this.focusSnapshot();
    this.element.style.setProperty('--anim-dock-height', `${this.height}px`);
    this.element.style.setProperty('--anim-zoom', `${this.zoom}px`);
    this.element.style.setProperty('--anim-label-width', `${LABEL_WIDTH}px`);
    this.element.innerHTML = `<div class="anim-resizer" data-anim-resize role="separator" aria-orientation="horizontal" aria-label="Resize animation dock" tabindex="0"></div>${this.renderToolbar()}<div class="anim-body">${this.clip ? this.renderTimeline() : this.renderEmpty()}${this.renderInspector()}</div>${this.addTrackFilter !== undefined ? this.renderAddTrack() : ''}`;
    const nextScroller = this.element.querySelector<HTMLElement>('.anim-scroll');
    if (nextScroller) { nextScroller.scrollLeft = this.scroll.left; nextScroller.scrollTop = this.scroll.top; }
    this.restoreFocus(focusedSelector);
    this.host.playheadChanged();
  }

  /** A selector for the focused dock control, so focus survives re-renders and re-attachment. */
  focusSnapshot(): string | undefined {
    const active = document.activeElement;
    if (!(active instanceof HTMLElement) || !this.element.contains(active)) return undefined;
    const valueHost = active.closest<HTMLElement>('[data-anim-value-track]');
    if (valueHost && active.dataset.valuePart) return `[data-anim-value-track="${valueHost.dataset.animValueTrack}"] [data-value-part="${active.dataset.valuePart}"]`;
    if (active.dataset.animField) return `[data-anim-field="${CSS.escape(active.dataset.animField)}"]`;
    if (active.dataset.animAction) return `[data-anim-action="${CSS.escape(active.dataset.animAction)}"]`;
    if (active.dataset.animAddFilter !== undefined) return '[data-anim-add-filter]';
    return '.anim-scroll';
  }

  restoreFocus(selector: string | undefined): void {
    if (selector) this.element.querySelector<HTMLElement>(selector)?.focus({ preventScroll: true });
  }

  private renderToolbar(): string {
    const context = this.context!;
    const clip = this.clip;
    const disabled = this.editable ? '' : 'disabled';
    const options = Object.keys(context.clips).map((id) => `<option value="${escapeHtml(id)}" ${id === this.clipId ? 'selected' : ''}>${escapeHtml(id)}${id === context.autoplay ? ' ★' : ''}</option>`).join('');
    const issues = clip ? clipDomainIssues(clip, context.domain) : [];
    const readOnly = context.readOnlyReason
      ? `<span class="anim-readonly">${escapeHtml(context.readOnlyReason)}${context.sourceSceneId ? ` <button type="button" data-anim-open-scene="${escapeHtml(context.sourceSceneId)}">Open source</button>` : ''}</span>`
      : '';
    return `<header class="anim-toolbar" role="toolbar" aria-label="Animation controls">
      <span class="anim-title">ANIMATION · ${escapeHtml(context.playerName)}</span>
      <label class="anim-clip-select"><span class="anim-sr">Animation</span><select data-anim-field="clip" aria-label="Animation clip">${options || '<option>—</option>'}</select></label>
      <span class="anim-group">
        <button type="button" data-anim-action="new-clip" ${disabled} title="New animation">New</button>
        <button type="button" data-anim-action="rename-clip" ${disabled || (clip ? '' : 'disabled')} title="Rename animation">Rename</button>
        <button type="button" data-anim-action="duplicate-clip" ${disabled || (clip ? '' : 'disabled')} title="Duplicate animation">Dup</button>
        <button type="button" data-anim-action="mirror-x" ${disabled || (clip ? '' : 'disabled')} title="Duplicate mirrored horizontally (right → left)">Mirror ↔</button>
        <button type="button" data-anim-action="mirror-y" ${disabled || (clip ? '' : 'disabled')} title="Duplicate mirrored vertically (down → up)">Mirror ↕</button>
        <button type="button" data-anim-action="delete-clip" ${disabled || (clip ? '' : 'disabled')} title="Delete animation">Delete</button>
        <button type="button" data-anim-action="autoplay" ${disabled || (clip ? '' : 'disabled')} aria-pressed="${clip !== undefined && this.clipId === context.autoplay}" title="Autoplay on load">★ Autoplay</button>
      </span>
      ${clip ? `<span class="anim-group anim-transport">
        <button type="button" data-anim-action="first-frame" title="Go to start (Home)">⏮</button>
        <button type="button" data-anim-action="prev-frame" title="Previous frame (,)">◀|</button>
        <button type="button" class="anim-play" data-anim-action="play" aria-pressed="${this.playing}" title="Play / pause (Space)">${this.playing ? '❚❚' : '▶'}</button>
        <button type="button" data-anim-action="next-frame" title="Next frame (.)">|▶</button>
        <button type="button" data-anim-action="last-frame" title="Go to end (End)">⏭</button>
        <button type="button" data-anim-action="stop" title="Stop and restore the scene pose">⏹</button>
        <output data-anim-readout>${this.playhead} / ${this.frames - 1} · ${formatClipSeconds(this.playhead, clip.framesPerSecond)}</output>
      </span>
      <span class="anim-group">
        <label title="Loop"><input type="checkbox" data-anim-field="loop" ${clip.loop ? 'checked' : ''} ${disabled} /> Loop</label>
        <select data-anim-field="loopMode" aria-label="Loop mode" ${disabled || (clip.loop ? '' : 'disabled')}><option value="wrap" ${clip.loopMode !== 'ping-pong' ? 'selected' : ''}>Wrap</option><option value="ping-pong" ${clip.loopMode === 'ping-pong' ? 'selected' : ''}>Ping-pong</option></select>
      </span>
      <span class="anim-group">
        <label title="Frames per second">FPS <input type="number" min="1" max="240" step="1" data-anim-field="fps" value="${clip.framesPerSecond}" ${disabled} /></label>
        <label title="Keep key timing in seconds when the frame rate changes"><input type="checkbox" data-anim-field="keepDuration" ${this.keepDuration ? 'checked' : ''} /> keep time</label>
        <label title="Length in frames">Length <input type="number" min="1" step="1" data-anim-field="length" value="${this.frames}" ${disabled} /></label>
        <label title="Stretch keys to the new length instead of trimming"><input type="checkbox" data-anim-field="stretch" ${this.stretchLength ? 'checked' : ''} /> stretch</label>
        <small>${(clip.durationSeconds).toFixed(3)}s</small>
      </span>
      <span class="anim-group">
        <button type="button" data-anim-action="insert-frame" ${disabled} title="Insert a frame at the playhead">+ Frame</button>
        <button type="button" data-anim-action="delete-frame" ${disabled} title="Delete the frame at the playhead">− Frame</button>
        <button type="button" data-anim-action="simplify" ${disabled} title="Remove keys that do not change the result">Simplify keys</button>
        <button type="button" data-anim-action="auto-key" aria-pressed="${this.autoKey}" title="Auto-key: moving or rotating an animated node in the viewport, or editing it in the inspector's Keyframes section, keys it at the playhead">● Auto-key</button>
        <button type="button" data-anim-action="onion" aria-pressed="${this.onion}" title="Onion skin: previous (blue) and next (orange) frames">Onion</button>
        <label title="Timeline zoom (Ctrl+wheel)">Zoom <input type="range" min="6" max="48" step="1" data-anim-field="zoom" value="${this.zoom}" /></label>
      </span>` : ''}
      ${issues.length ? `<span class="anim-warning">⚠ ${escapeHtml(issues.join('; '))}</span>` : ''}
      ${readOnly}
      <button type="button" class="anim-close" data-anim-action="close" aria-label="Close animation dock" title="Close">×</button>
    </header>`;
  }

  private renderEmpty(): string {
    return `<div class="anim-empty"><p>This AnimationPlayer's library <code>${escapeHtml(this.context?.libraryId)}</code> has no animations yet.</p>${this.editable ? '<button type="button" data-anim-action="new-clip">Create animation</button>' : ''}</div>`;
  }

  private renderTimeline(): string {
    const clip = this.clip!;
    const frames = this.frames;
    const views = this.trackViews();
    const laneWidth = frames * this.zoom;
    const ruler = Array.from({ length: frames }, (_, frame) => {
      const labelled = frame % Math.max(1, Math.ceil(28 / this.zoom)) === 0 || frame === frames - 1;
      return `<span class="anim-ruler-cell${frame === this.playhead ? ' is-current' : ''}${frame % 5 === 0 ? ' is-major' : ''}" data-frame="${frame}">${labelled ? frame : ''}</span>`;
    }).join('');
    const groups = new Map<string, TrackView[]>();
    for (const view of views) groups.set(view.track.binding, [...(groups.get(view.track.binding) ?? []), view]);
    const disabled = this.editable ? '' : 'disabled';
    const trackRows = [...groups.entries()].map(([binding, members]) => {
      const node = members[0].node;
      const header = `<div class="anim-row anim-group-row${node ? '' : ' is-broken'}"><div class="anim-label"><span class="anim-node-type">${escapeHtml(node?.type ?? 'MISSING')}</span><strong title="${escapeHtml(binding)}">${escapeHtml(node?.name ?? binding)}</strong>${node ? `<button type="button" data-anim-key-group="${escapeHtml(binding)}" ${disabled} title="Key every track of this node at the playhead">◆ all</button>` : `<select data-anim-retarget="${escapeHtml(binding)}" aria-label="Fix track path" ${disabled}><option value="">Fix path…</option>${this.context!.targets.map((target) => `<option value="${escapeHtml(target.binding)}">${escapeHtml(target.binding)}</option>`).join('')}</select>`}</div><div class="anim-lane anim-group-lane" style="width:${laneWidth}px"></div></div>`;
      return header + members.map((view) => this.renderTrackRow(view, laneWidth)).join('');
    }).join('');
    const events = clip.events ?? [];
    const eventMarkers = events.map((event, index) => {
      const selected = this.selection.kind === 'event' && this.selection.index === index;
      return `<button type="button" class="anim-event${selected ? ' is-selected' : ''}${event.gameplay ? ' is-gameplay' : ''}" data-anim-event="${index}" style="left:${(event.at + 0.5) * this.zoom}px" title="${escapeHtml(event.eventId)} @ ${event.at}${event.gameplay ? ' · gameplay' : ''}"><span>${escapeHtml(event.eventId)}</span></button>`;
    }).join('');
    const eventRow = `<div class="anim-row anim-event-row"><div class="anim-label"><span class="anim-node-type">EVENTS</span><strong>Call events</strong><button type="button" data-anim-action="add-event" ${disabled} title="Add an event at the playhead">+ Event</button></div><div class="anim-lane" data-anim-lane="events" style="width:${laneWidth}px">${eventMarkers}</div></div>`;
    const hitboxRows = this.lanes().map((lane) => this.renderHitboxRow(lane, laneWidth)).join('');
    const hitboxHeader = hitboxRows ? `<div class="anim-row anim-group-row anim-hitbox-header"><div class="anim-label"><span class="anim-node-type">HITBOXES</span><strong>Attack windows</strong><small>Red frames = when the shape deals damage. Its size and position = the CollisionShape2D named on each row (Edit shape). Click or drag frames to change timing.</small></div></div>` : '';
    return `<div class="anim-timeline">
      <div class="anim-scroll" tabindex="0" aria-label="Tracks and keys">
        <div class="anim-content" style="width:${LABEL_WIDTH + laneWidth}px">
          <div class="anim-row anim-ruler-row"><div class="anim-label anim-track-tools"><button type="button" data-anim-action="open-add-track" ${disabled}>+ Track</button><small>${views.length} tracks · ${frames}f @ ${clip.framesPerSecond}fps</small></div><div class="anim-lane anim-ruler" data-anim-lane="ruler" style="width:${laneWidth}px">${ruler}</div></div>
          ${trackRows || `<div class="anim-row anim-hint-row"><div class="anim-label"><small>No tracks. Use + Track to animate a node property.</small></div><div class="anim-lane" style="width:${laneWidth}px"></div></div>`}
          ${eventRow}
          ${hitboxHeader}${hitboxRows}
          <div class="anim-playhead" style="left:${LABEL_WIDTH + (this.playhead + 0.5) * this.zoom}px" aria-hidden="true"></div>
        </div>
      </div>
    </div>`;
  }

  private renderTrackRow(view: TrackView, laneWidth: number): string {
    const { track, index, descriptor, linear } = view;
    const disabled = this.editable ? '' : 'disabled';
    const selected = new Set(this.selection.kind === 'keys' ? this.selection.refs.map(refId) : []);
    const keys = [...track.keys].sort((left, right) => left.at - right.at);
    const holds = keys.map((key, keyIndex) => {
      const end = keyIndex + 1 < keys.length ? keys[keyIndex + 1].at : this.frames;
      const width = (end - key.at) * this.zoom;
      const thumbnail = track.property === 'frame' && typeof key.value === 'number' ? this.thumbnailFor(view, key.value) : undefined;
      return `<span class="anim-hold${linear ? ' is-linear' : ''}" style="left:${key.at * this.zoom}px;width:${width}px">${thumbnail ? `<img src="${escapeHtml(thumbnail)}" alt="" />` : ''}<em>${escapeHtml(formatAnimationValue(track.property, key.value))}</em></span>`;
    }).join('');
    const keyButtons = keys.map((key) => {
      const id = `${index}:${key.at}`;
      return `<button type="button" class="anim-key${selected.has(id) ? ' is-selected' : ''}${key.transition ? ' is-eased' : ''}" data-anim-key="${id}" style="left:${(key.at + 0.5) * this.zoom}px" title="${escapeHtml(track.property)} @ ${key.at}: ${escapeHtml(formatAnimationValue(track.property, key.value))}${key.transition ? ` · ${key.transition}` : ''}" aria-pressed="${selected.has(id)}"></button>`;
    }).join('');
    const keyed = keyAt(track, this.playhead) !== undefined;
    const enabled = track.enabled !== false;
    const focused = this.focusedTrack === index;
    return `<div class="anim-row anim-track-row${enabled ? '' : ' is-disabled'}${focused ? ' is-focused' : ''}${view.node && descriptor ? '' : ' is-broken'}">
      <div class="anim-label" data-anim-track="${index}">
        <button type="button" class="anim-toggle" data-anim-enable="${index}" aria-pressed="${enabled}" ${disabled} title="${enabled ? 'Disable track' : 'Enable track'}">${enabled ? '●' : '○'}</button>
        <span class="anim-property" title="${escapeHtml(track.binding)}:${escapeHtml(track.property)}${linear ? ' · linear' : ' · step'}">${escapeHtml(descriptor?.label ?? track.property)}</span>
        ${this.renderTrackValue(view)}
        <button type="button" class="anim-key-toggle${keyed ? ' is-keyed' : ''}" data-anim-key-toggle="${index}" ${disabled} title="${keyed ? 'Remove the key at the playhead' : 'Insert a key at the playhead (K)'}" aria-label="${keyed ? 'Remove key at playhead' : 'Insert key at playhead'}">${keyed ? '◆' : '◇'}</button>
        <span class="anim-track-menu">
          <button type="button" data-anim-track-up="${index}" ${disabled} title="Move track up" aria-label="Move track up">↑</button>
          <button type="button" data-anim-track-down="${index}" ${disabled} title="Move track down" aria-label="Move track down">↓</button>
          <button type="button" data-anim-track-remove="${index}" ${disabled} title="Remove track" aria-label="Remove track">✕</button>
        </span>
      </div>
      <div class="anim-lane" data-anim-lane="track" data-anim-lane-track="${index}" style="width:${laneWidth}px">${holds}${keyButtons}</div>
    </div>`;
  }

  /** Inline editor showing the track's value at the playhead; editing it keys that frame. */
  private renderTrackValue(view: TrackView): string {
    const value = sampleTrack(view.track, this.playhead, view.linear) ?? (view.descriptor ? initialKeyValue(view.node, view.descriptor) : undefined);
    const kind = animationValueKind(view.track.property, view.descriptor, value);
    return `<span class="anim-value" data-anim-value-track="${view.index}" data-kind="${kind}">${renderAnimationValueFields(kind, value, { disabled: !this.editable || !view.node || !view.descriptor, descriptor: view.descriptor, label: `${view.node?.name ?? view.track.binding} ${view.descriptor?.label ?? view.track.property}`, compact: true })}</span>`;
  }

  /** Refreshes the per-row values and key markers after the playhead moves. */
  private syncTrackValues(): void {
    const views = this.trackViews();
    const active = document.activeElement;
    for (const host of this.element.querySelectorAll<HTMLElement>('[data-anim-value-track]')) {
      if (active instanceof Node && host.contains(active)) continue;
      const view = views[Number(host.dataset.animValueTrack)];
      if (view) host.outerHTML = this.renderTrackValue(view);
    }
    for (const toggle of this.element.querySelectorAll<HTMLElement>('[data-anim-key-toggle]')) {
      const track = this.clip?.tracks[Number(toggle.dataset.animKeyToggle)];
      const keyed = Boolean(track && keyAt(track, this.playhead));
      toggle.classList.toggle('is-keyed', keyed);
      toggle.textContent = keyed ? '◆' : '◇';
    }
  }

  private renderHitboxRow(lane: WeaponAttackLane, laneWidth: number): string {
    const cells = Array.from({ length: this.frames }, (_, frame) => {
      const span = lane.spans.find((candidate) => candidate.from <= frame && frame <= candidate.through);
      const selected = span && this.selection.kind === 'span' && this.selection.direction === lane.direction && this.selection.index === span.index;
      return `<span class="anim-hit-cell${span ? ' is-active' : ''}${selected ? ' is-selected' : ''}" data-frame="${frame}"${span ? ` data-anim-span="${span.index}"` : ''}></span>`;
    }).join('');
    const shapeName = `${lane.direction}--${lane.hitboxId}`;
    const shape = this.context?.nodes.find((node) => node.type === 'CollisionShape2D' && node.name === shapeName);
    const frames = lane.spans.length > 0 ? lane.spans.map((span) => span.from === span.through ? `${span.from}` : `${span.from}–${span.through}`).join(', ') : 'never active';
    return `<div class="anim-row anim-hitbox-row${lane.hasShape ? '' : ' is-broken'}"><div class="anim-label"><span class="anim-node-type">${escapeHtml(lane.direction.toUpperCase())}</span><strong title="Shape node ${escapeHtml(shapeName)}">${escapeHtml(shapeName)}</strong><small>frames ${escapeHtml(frames)}</small>${shape ? `<button type="button" data-anim-select-node="${escapeHtml(shape.key)}" title="Select ${escapeHtml(shapeName)} to resize or move the hitbox">Edit shape</button>` : `<small title="Add a CollisionShape2D named ${escapeHtml(shapeName)} under the attack area">no shape</small>`}</div><div class="anim-lane anim-hit-lane" data-anim-lane="hitbox" data-direction="${escapeHtml(lane.direction)}" data-hitbox="${escapeHtml(lane.hitboxId)}" style="width:${laneWidth}px">${cells}</div></div>`;
  }

  private thumbnailFor(view: TrackView, frame: number): string | undefined {
    return this.host.spriteFrames(view.node?.properties.texture)?.thumbnail(frame);
  }

  private renderInspector(): string {
    const clip = this.clip;
    if (!clip) return '<aside class="anim-inspector"></aside>';
    const disabled = this.editable ? '' : 'disabled';
    const selection = this.selection;
    let body: string;
    if (selection.kind === 'keys' && selection.refs.length === 1) body = this.renderKeyInspector(selection.refs[0]);
    else if (selection.kind === 'keys') {
      const transitions = new Set(selection.refs.map((ref) => keyAt(clip.tracks[ref.track], ref.at)?.transition ?? 'linear'));
      body = `<h3>${selection.refs.length} keys</h3>
        <label>Transition <select data-anim-field="transition" ${disabled}>${ANIMATION_KEY_TRANSITIONS.map((transition) => `<option value="${transition}" ${transitions.size === 1 && transitions.has(transition) ? 'selected' : ''}>${transition}</option>`).join('')}${transitions.size > 1 ? '<option selected disabled>mixed</option>' : ''}</select></label>
        <div class="anim-inspector-actions"><button type="button" data-anim-action="copy-keys">Copy</button><button type="button" data-anim-action="delete-keys" ${disabled}>Delete</button></div>
        <p class="anim-help">Drag to move · Alt+drag duplicates · ←/→ nudge · Ctrl+C / Ctrl+V pastes at the playhead.</p>`;
    } else if (selection.kind === 'event') body = this.renderEventInspector(selection.index);
    else if (selection.kind === 'span') body = this.renderSpanInspector(selection.direction, selection.index);
    else if (this.focusedTrack !== undefined) body = this.renderTrackInspector(this.focusedTrack);
    else {
      body = `<h3>${escapeHtml(this.clipId)}</h3>
        <dl><dt>Frames</dt><dd>${this.frames}</dd><dt>Length</dt><dd>${clip.durationSeconds.toFixed(3)}s</dd><dt>Tracks</dt><dd>${clip.tracks.length}</dd><dt>Events</dt><dd>${clip.events?.length ?? 0}</dd><dt>Library</dt><dd><code>${escapeHtml(this.context?.libraryId)}</code></dd></dl>
        <p class="anim-help">Click a key to edit it · double-click a lane to key the current value · drag on empty lane space to box-select · K keys the focused track · Space plays.</p>`;
    }
    return `<aside class="anim-inspector" aria-label="Key inspector">${body}</aside>`;
  }

  private renderKeyInspector(ref: AnimationKeyRef): string {
    const view = this.trackViews()[ref.track];
    const key = view ? keyAt(view.track, ref.at) : undefined;
    if (!view || !key) return '<p>Key missing</p>';
    const disabled = this.editable ? '' : 'disabled';
    const transition = view.linear
      ? `<label>Transition <select data-anim-field="transition" ${disabled}>${ANIMATION_KEY_TRANSITIONS.map((candidate) => `<option value="${candidate}" ${(key.transition ?? 'linear') === candidate ? 'selected' : ''}>${candidate}</option>`).join('')}</select></label>`
      : '';
    return `<h3>${escapeHtml(view.node?.name ?? view.track.binding)} · ${escapeHtml(view.descriptor?.label ?? view.track.property)}</h3>
      <label>Frame <input type="number" min="0" max="${this.frames - 1}" step="1" data-anim-field="key-at" value="${key.at}" ${disabled} /></label>
      ${this.renderKeyValue(view, key.value)}
      ${transition}
      <div class="anim-inspector-actions"><button type="button" data-anim-action="copy-keys">Copy</button><button type="button" data-anim-action="delete-keys" ${disabled}>Delete key</button></div>
      ${view.track.property === 'frame' ? this.renderFramePicker(view, key.value, disabled) : ''}`;
  }

  private renderKeyValue(view: TrackView, value: JsonValue): string {
    const kind = animationValueKind(view.track.property, view.descriptor, value);
    const label = view.descriptor?.label ?? view.track.property;
    return `<div class="anim-key-value" data-anim-key-value data-kind="${kind}"><span>${escapeHtml(label)}${kind === 'vector' ? ' (x, y)' : ''}</span><div>${renderAnimationValueFields(kind, value, { disabled: !this.editable, descriptor: view.descriptor, label })}</div></div>`;
  }

  private renderFramePicker(view: TrackView, value: JsonValue, disabled: string): string {
    const sheet = this.host.spriteFrames(view.node?.properties.texture);
    if (!sheet || sheet.count <= 0) return '';
    const cells = Array.from({ length: Math.min(sheet.count, 256) }, (_, frame) => {
      const url = sheet.thumbnail(frame);
      return `<button type="button" class="anim-frame-cell${frame === value ? ' is-selected' : ''}" data-anim-pick-frame="${frame}" ${disabled} title="Frame ${frame}">${url ? `<img src="${escapeHtml(url)}" alt="" />` : ''}<span>${frame}</span></button>`;
    }).join('');
    return `<section class="anim-frame-picker" aria-label="Sprite sheet frames"><header>SOURCE FRAMES · ${sheet.count}</header><div>${cells}</div></section>`;
  }

  private renderTrackInspector(index: number): string {
    const view = this.trackViews()[index];
    if (!view) return '';
    const disabled = this.editable ? '' : 'disabled';
    const current = sampleTrack(view.track, this.playhead, view.linear);
    return `<h3>${escapeHtml(view.node?.name ?? view.track.binding)} · ${escapeHtml(view.descriptor?.label ?? view.track.property)}</h3>
      <dl><dt>Path</dt><dd><code>${escapeHtml(view.track.binding)}</code></dd><dt>Keys</dt><dd>${view.track.keys.length}</dd><dt>At ${this.playhead}</dt><dd>${escapeHtml(formatAnimationValue(view.track.property, current))}</dd></dl>
      ${descriptorIsNumeric(view.descriptor) ? `<label>Interpolation <select data-anim-interp="${index}" ${disabled}><option value="linear" ${view.track.interpolation !== 'nearest' ? 'selected' : ''}>Linear (blend between keys)</option><option value="nearest" ${view.track.interpolation === 'nearest' ? 'selected' : ''}>Nearest (hold each key)</option></select></label>` : '<p class="anim-help">Discrete property: each key holds until the next.</p>'}
      ${view.node && view.descriptor ? '' : '<p class="anim-warning">The track path or property no longer resolves. Fix it from the node row.</p>'}
      <div class="anim-inspector-actions"><button type="button" data-anim-action="key-track" ${disabled}>◆ Insert key (K)</button><button type="button" data-anim-action="paste-keys" ${disabled || (this.clipboard ? '' : 'disabled')}>Paste</button></div>`;
  }

  private renderEventInspector(index: number): string {
    const event = this.clip?.events?.[index];
    if (!event) return '';
    const disabled = this.editable ? '' : 'disabled';
    return `<h3>Event</h3>
      <label>ID <input type="text" data-anim-field="event-id" value="${escapeHtml(event.eventId)}" ${disabled} /></label>
      <label>Frame <input type="number" min="0" max="${this.frames - 1}" step="1" data-anim-field="event-at" value="${event.at}" ${disabled} /></label>
      <label class="anim-check" title="Gameplay events drive hitboxes and damage and require the physics clock"><input type="checkbox" data-anim-field="event-gameplay" ${event.gameplay ? 'checked' : ''} ${disabled} /> Gameplay event</label>
      <label>Payload (JSON) <textarea rows="4" data-anim-field="event-payload" ${disabled}>${escapeHtml(event.payload === undefined ? '' : JSON.stringify(event.payload, null, 1))}</textarea></label>
      <div class="anim-inspector-actions"><button type="button" data-anim-action="delete-event" ${disabled}>Delete event</button></div>`;
  }

  private renderSpanInspector(direction: string, index: number): string {
    const lane = this.lanes().find((candidate) => candidate.direction === direction && candidate.spans.some((span) => span.index === index));
    const span = lane?.spans.find((candidate) => candidate.index === index);
    if (!lane || !span) return '';
    const disabled = this.editable ? '' : 'disabled';
    return `<h3>Hitbox · ${escapeHtml(direction)} · ${escapeHtml(span.hitboxId)}</h3>
      <div class="anim-vector"><label>From <input type="number" min="0" step="1" data-anim-field="span-from" value="${span.from}" ${disabled} /></label><label>Through <input type="number" min="0" step="1" data-anim-field="span-through" value="${span.through}" ${disabled} /></label></div>
      <label>Damage × <input type="number" min="0" step="0.05" data-anim-field="span-damage" value="${span.damageMultiplier}" ${disabled} /></label>
      <label>Knockback × <input type="number" min="0" step="0.05" data-anim-field="span-knockback" value="${span.knockbackMultiplier}" ${disabled} /></label>
      <div class="anim-inspector-actions"><button type="button" data-anim-action="delete-span" ${disabled}>Delete window</button></div>
      <p class="anim-help">Edit the hitbox geometry by selecting its CollisionShape2D (<code>${escapeHtml(direction)}--${escapeHtml(span.hitboxId)}</code>) in the scene tree.</p>`;
  }

  private renderAddTrack(): string {
    const context = this.context!;
    const filter = (this.addTrackFilter ?? '').trim().toLowerCase();
    const existing = new Set(this.clip?.tracks.map((track) => `${track.binding}::${track.property}`) ?? []);
    const rows = context.targets.map((target) => {
      const properties = target.properties.filter((descriptor) => !filter || `${target.name} ${target.type} ${descriptor.key} ${descriptor.label}`.toLowerCase().includes(filter));
      if (properties.length === 0) return '';
      return `<div class="anim-add-node" style="--depth:${target.depth}"><header><span>${escapeHtml(target.type)}</span><strong>${escapeHtml(target.name)}</strong><code>${escapeHtml(target.binding)}</code></header><div>${properties.map((descriptor) => {
        const taken = existing.has(`${target.binding}::${descriptor.key}`);
        return `<button type="button" data-anim-add-binding="${escapeHtml(target.binding)}" data-anim-add-property="${escapeHtml(descriptor.key)}" ${taken ? 'disabled' : ''} title="${escapeHtml(descriptor.help ?? descriptor.label)}">${escapeHtml(descriptor.label)}${taken ? ' ✓' : ''}</button>`;
      }).join('')}</div></div>`;
    }).join('');
    return `<div class="anim-popover" role="dialog" aria-label="Add track"><header><strong>Add property track</strong><input type="search" data-anim-add-filter value="${escapeHtml(this.addTrackFilter)}" placeholder="Filter nodes or properties" aria-label="Filter nodes or properties" /><button type="button" data-anim-action="close-add-track" aria-label="Close">×</button></header><div class="anim-add-list">${rows || `<p>No animatable properties in the ${escapeHtml(context.domain)} domain${filter ? ' match the filter' : ''}.</p>`}</div></div>`;
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  private selectClip(id: string): void {
    if (!this.context?.clips[id]) return;
    this.stopPlayback(false);
    this.clipId = id;
    this.selection = { kind: 'none' };
    this.focusedTrack = undefined;
    this.playhead = 0;
    this.pose();
    this.render();
  }

  private runAction(action: string): void {
    const context = this.context;
    if (!context) return;
    const clip = this.clip;
    const clipId = this.clipId;
    switch (action) {
      case 'play': this.togglePlayback(); return;
      case 'stop': this.stopPlayback(false); this.host.stop(); this.playhead = 0; this.render(); return;
      case 'first-frame': this.seek(0); return;
      case 'last-frame': this.seek(this.frames - 1); return;
      case 'prev-frame': this.seek(this.playhead - 1); return;
      case 'next-frame': this.seek(this.playhead + 1); return;
      case 'onion': this.onion = !this.onion; if (!this.onion) this.host.onionSkin([]); this.pose(); this.render(); return;
      case 'open-add-track': if (this.editable) { this.addTrackFilter = ''; this.render(); this.element.querySelector<HTMLElement>('[data-anim-add-filter]')?.focus(); } return;
      case 'close-add-track': this.addTrackFilter = undefined; this.render(); return;
      case 'copy-keys': this.copySelection(); return;
      case 'paste-keys': this.paste(); return;
      case 'auto-key': this.autoKey = !this.autoKey; this.render(); return;
      case 'close': this.stopPlayback(false); this.host.stop(); this.host.close(); return;
    }
    this.attempt(() => {
      switch (action) {
        case 'new-clip': {
          const name = window.prompt('New animation name', uniqueClipId(context.clips, 'new-animation'));
          if (!name) return;
          const fps = clip?.framesPerSecond ?? 12;
          if (this.host.commit(`Create animation ${name}`, { clips: createClip(context.clips, name, { framesPerSecond: fps, frameCount: fps }) })) this.clipId = name.trim();
          return;
        }
        case 'rename-clip': {
          if (!clip || !clipId) return;
          const name = window.prompt(`Rename '${clipId}' to`, clipId)?.trim();
          if (!name || name === clipId) return;
          const clips = renameClip(context.clips, clipId, name);
          if (this.host.commit(`Rename animation ${clipId}`, { clips, ...(context.attack ? { plans: renamePlanClip(context.attack.plans, clipId, name) } : {}), ...(context.autoplay === clipId ? { autoplay: name } : {}) })) this.clipId = name;
          return;
        }
        case 'duplicate-clip': {
          if (!clipId) return;
          const name = window.prompt(`Duplicate '${clipId}' as`, uniqueClipId(context.clips, `${clipId}-copy`))?.trim();
          if (name && this.host.commit(`Duplicate animation ${clipId}`, { clips: duplicateClip(context.clips, clipId, name) })) this.clipId = name;
          return;
        }
        case 'mirror-x':
        case 'mirror-y': {
          if (!clipId) return;
          const axis = action === 'mirror-x' ? 'x' : 'y';
          const suggestion = axis === 'x'
            ? clipId.replace(/right/g, '\u0000').replace(/left/g, 'right').replace(/\u0000/g, 'left')
            : clipId.replace(/down/g, '\u0000').replace(/up/g, 'down').replace(/\u0000/g, 'up');
          const name = window.prompt(`Mirror '${clipId}' ${axis === 'x' ? 'horizontally' : 'vertically'} into (an existing name is replaced)`, suggestion === clipId ? uniqueClipId(context.clips, `${clipId}-mirrored`) : suggestion)?.trim();
          if (!name) return;
          if (context.clips[name] && name !== clipId && !window.confirm(`Replace the existing '${name}' with the mirrored copy?`)) return;
          const clips = mirrorClip(name === clipId ? context.clips : deleteClipIfPresent(context.clips, name), clipId, name, axis);
          const plans = context.attack ? syncPlansWithClip(context.attack.plans, name, clips[name]) : undefined;
          if (this.host.commit(`Mirror animation ${clipId}`, { clips, ...(plans ? { plans } : {}) })) this.clipId = name;
          return;
        }
        case 'delete-clip': {
          if (!clipId || !window.confirm(`Delete animation '${clipId}'?`)) return;
          const used = context.attack ? planDirectionsForClip(context.attack.plans, clipId).length > 0 : false;
          if (used && !window.confirm(`'${clipId}' is played by the weapon's attack plans. Delete anyway?`)) return;
          this.host.commit(`Delete animation ${clipId}`, { clips: deleteClip(context.clips, clipId), ...(context.autoplay === clipId ? { autoplay: null } : {}) });
          return;
        }
        case 'autoplay':
          if (clipId) this.host.commit(context.autoplay === clipId ? 'Clear autoplay' : `Autoplay ${clipId}`, { clips: context.clips, autoplay: context.autoplay === clipId ? null : clipId });
          return;
        case 'insert-frame': if (clip) { const edit = insertFrames(clip, this.playhead, 1); this.commitClip('Insert frame', edit.clip, edit); } return;
        case 'delete-frame': if (clip) { const edit = deleteFrames(clip, this.playhead, 1); this.commitClip('Delete frame', edit.clip, edit); } return;
        case 'simplify': {
          if (!clip) return;
          const views = this.trackViews();
          const result = simplifyKeys(clip, (track) => views[clip.tracks.indexOf(track)]?.linear ?? false);
          if (result.removed === 0) { this.host.notify('Every key already changes the result'); return; }
          if (this.commitClip(`Simplify keys (${result.removed} removed)`, result.clip)) this.host.notify(`Removed ${result.removed} redundant keys`);
          return;
        }
        case 'add-event': {
          if (!clip) return;
          const id = window.prompt('Event ID', 'event')?.trim();
          if (!id) return;
          const result = addEvent(clip, { at: this.playhead, eventId: id });
          if (this.commitClip(`Add event ${id}`, result.clip)) this.selection = { kind: 'event', index: result.index };
          return;
        }
        case 'delete-event': if (clip && this.selection.kind === 'event') { const index = this.selection.index; this.selection = { kind: 'none' }; this.commitClip('Delete event', removeEvent(clip, index)); } return;
        case 'delete-keys': this.deleteSelectedKeys(); return;
        case 'key-track': if (this.focusedTrack !== undefined) this.keyTracks([this.focusedTrack]); return;
        case 'delete-span': {
          if (this.selection.kind !== 'span' || !context.attack) return;
          const plans = removeHitboxSpan(context.attack.plans, this.selection.direction, this.selection.index);
          this.selection = { kind: 'none' };
          this.host.commit('Delete hitbox window', { clips: context.clips, plans });
          return;
        }
      }
    });
  }

  /** Inserts keys holding each track's current value at the playhead (Godot's key button). */
  private keyTracks(indexes: readonly number[]): void {
    let clip = this.clip;
    if (!clip) return;
    const views = this.trackViews();
    const refs: AnimationKeyRef[] = [];
    for (const index of indexes) {
      const view = views[index];
      if (!view) continue;
      const value = sampleTrack(view.track, this.playhead, view.linear) ?? (view.descriptor ? initialKeyValue(view.node, view.descriptor) : undefined);
      if (value === undefined) continue;
      clip = setKey(clip, index, this.playhead, value);
      refs.push({ track: index, at: this.playhead });
    }
    if (refs.length > 0 && this.commitClip(refs.length === 1 ? 'Insert key' : `Insert ${refs.length} keys`, clip)) this.selection = { kind: 'keys', refs };
  }

  private deleteSelectedKeys(): void {
    const clip = this.clip;
    if (!clip || this.selection.kind !== 'keys') return;
    const refs = this.selection.refs;
    this.selection = { kind: 'none' };
    this.commitClip(refs.length === 1 ? 'Delete key' : `Delete ${refs.length} keys`, removeKeys(clip, refs));
  }

  private copySelection(): void {
    const clip = this.clip;
    if (!clip || this.selection.kind !== 'keys') return;
    this.clipboard = copyKeys(clip, this.selection.refs);
    this.host.notify(`Copied ${this.clipboard.entries.length} key${this.clipboard.entries.length === 1 ? '' : 's'}`);
    this.render();
  }

  private paste(): void {
    this.attempt(() => {
      const clip = this.clip;
      if (!clip || !this.clipboard) return;
      const result = pasteKeys(clip, this.clipboard, this.playhead, this.focusedTrack);
      if (this.commitClip(`Paste ${result.refs.length} keys`, result.clip)) this.selection = { kind: 'keys', refs: result.refs };
    });
  }

  private nudgeKeys(delta: number): void {
    this.attempt(() => {
      const clip = this.clip;
      if (!clip || this.selection.kind !== 'keys') return;
      const result = moveKeys(clip, this.selection.refs, delta);
      if (this.commitClip('Move keys', result.clip)) this.selection = { kind: 'keys', refs: result.refs };
    });
  }

  private updateSelectedKey(value: JsonValue): void {
    this.attempt(() => {
      const clip = this.clip;
      if (!clip || this.selection.kind !== 'keys' || this.selection.refs.length !== 1) return;
      const ref = this.selection.refs[0];
      this.commitClip('Edit key', setKey(clip, ref.track, ref.at, value));
    });
  }

  private addTrackFor(binding: string, property: string): void {
    this.attempt(() => {
      const context = this.context!;
      const clip = this.clip;
      if (!clip) return;
      const node = resolveBinding(context.nodes, context.playerKey, binding);
      const resolved = node ? context.propertyDescriptors(node).find((candidate) => candidate.key === property && candidate.animation?.domains.includes(context.domain)) : undefined;
      if (!resolved) throw new Error(`'${property}' is not animatable on ${binding} in the ${context.domain} domain`);
      const firstKey: AnimationPropertyKey = { at: this.playhead, value: initialKeyValue(node, resolved) };
      const next = addTrack(clip, binding, property, firstKey);
      if (this.commitClip(`Add track ${binding}:${property}`, next)) {
        this.focusedTrack = next.tracks.length - 1;
        this.selection = { kind: 'keys', refs: [{ track: next.tracks.length - 1, at: this.playhead }] };
        this.addTrackFilter = undefined;
      }
    });
  }

  // -------------------------------------------------------------------------
  // DOM events
  // -------------------------------------------------------------------------

  private onClick(event: MouseEvent): void {
    const target = event.target instanceof Element ? event.target : null;
    if (!target) return;
    const button = target.closest<HTMLElement>('[data-anim-select-node],[data-anim-key-toggle],[data-anim-action],[data-anim-open-scene],[data-anim-enable],[data-anim-track-up],[data-anim-track-down],[data-anim-track-remove],[data-anim-key-group],[data-anim-add-binding],[data-anim-pick-frame],[data-anim-track]');
    if (!button) return;
    const data = button.dataset;
    if (data.animAction) { this.runAction(data.animAction); return; }
    if (data.animOpenScene) { this.host.openScene(data.animOpenScene); return; }
    if (data.animSelectNode) { this.host.selectNode(data.animSelectNode); return; }
    if (data.animAddBinding && data.animAddProperty) { this.addTrackFor(data.animAddBinding, data.animAddProperty); return; }
    if (data.animPickFrame !== undefined) { this.updateSelectedKey(Number(data.animPickFrame)); return; }
    const clip = this.clip;
    if (!clip) return;
    if (data.animKeyToggle !== undefined) {
      const index = Number(data.animKeyToggle);
      this.attempt(() => {
        const track = clip.tracks[index];
        if (track && keyAt(track, this.playhead)) {
          if (this.commitClip('Remove key', removeKeys(clip, [{ track: index, at: this.playhead }]))) this.selection = { kind: 'none' };
        } else this.keyTracks([index]);
      });
      return;
    }
    if (data.animEnable !== undefined) { const index = Number(data.animEnable); this.attempt(() => { this.commitClip('Toggle track', setTrackEnabled(clip, index, clip.tracks[index]?.enabled === false)); }); return; }
    if (data.animTrackUp !== undefined) { const index = Number(data.animTrackUp); this.attempt(() => { if (this.commitClip('Move track', moveTrack(clip, index, -1))) { this.selection = { kind: 'none' }; this.focusedTrack = Math.max(0, index - 1); } }); return; }
    if (data.animTrackDown !== undefined) { const index = Number(data.animTrackDown); this.attempt(() => { if (this.commitClip('Move track', moveTrack(clip, index, 1))) { this.selection = { kind: 'none' }; this.focusedTrack = Math.min(clip.tracks.length - 1, index + 1); } }); return; }
    if (data.animTrackRemove !== undefined) {
      const index = Number(data.animTrackRemove);
      const track = clip.tracks[index];
      if (track && (track.keys.length <= 1 || window.confirm(`Remove track ${track.binding}:${track.property} and its ${track.keys.length} keys?`))) {
        this.attempt(() => { if (this.commitClip('Remove track', removeTrack(clip, index))) { this.selection = { kind: 'none' }; this.focusedTrack = undefined; } });
      }
      return;
    }
    if (data.animKeyGroup !== undefined) {
      const indexes = clip.tracks.flatMap((track, index) => track.binding === data.animKeyGroup ? [index] : []);
      this.attempt(() => this.keyTracks(indexes));
      return;
    }
    if (data.animTrack !== undefined && !target.closest('button,select,input,textarea')) {
      this.focusedTrack = Number(data.animTrack);
      this.selection = { kind: 'none' };
      this.render();
    }
  }

  private onDoubleClick(event: MouseEvent): void {
    const lane = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-anim-lane]') : null;
    if (!lane || !this.clip) return;
    const frame = this.frameAt(event.clientX, lane);
    if (lane.dataset.animLane === 'track') {
      this.playhead = frame;
      this.keyTracks([Number(lane.dataset.animLaneTrack)]);
    } else if (lane.dataset.animLane === 'events' && !(event.target instanceof Element && event.target.closest('[data-anim-event]'))) {
      this.playhead = frame;
      this.runAction('add-event');
    }
  }

  private onChange(event: Event): void {
    const input = event.target;
    if (!(input instanceof HTMLInputElement || input instanceof HTMLSelectElement || input instanceof HTMLTextAreaElement)) return;
    const clip = this.clip;
    const context = this.context;
    const valueHost = input.closest<HTMLElement>('[data-anim-value-track],[data-anim-key-value]');
    if (valueHost) {
      this.attempt(() => {
        const value = readAnimationValue(valueHost, valueHost.dataset.kind as AnimationValueKind);
        if (valueHost.dataset.animValueTrack !== undefined) this.keyTrackValue(Number(valueHost.dataset.animValueTrack), value);
        else this.updateSelectedKey(value);
      });
      return;
    }
    if (input.dataset.animInterp !== undefined && clip) {
      const index = Number(input.dataset.animInterp);
      this.attempt(() => { this.commitClip('Change interpolation', setTrackInterpolation(clip, index, input.value === 'nearest' ? 'nearest' : undefined as AnimationTrackInterpolation | undefined)); });
      return;
    }
    if (input.dataset.animRetarget !== undefined && clip && input.value) {
      const binding = input.dataset.animRetarget;
      this.attempt(() => {
        let next = clip;
        clip.tracks.forEach((track, index) => { if (track.binding === binding) next = retargetTrack(next, index, input.value); });
        this.commitClip('Fix track path', next);
      });
      return;
    }
    const field = input.dataset.animField;
    if (!field || !context) return;
    const checked = input instanceof HTMLInputElement && input.checked;
    const number = Number(input.value);
    switch (field) {
      case 'clip': this.selectClip(input.value); return;
      case 'zoom': return;
      case 'keepDuration': this.keepDuration = checked; return;
      case 'stretch': this.stretchLength = checked; return;
    }
    if (!clip) return;
    this.attempt(() => {
      switch (field) {
        case 'loop': this.commitClip(checked ? 'Enable loop' : 'Disable loop', setLoop(clip, checked, clip.loopMode ?? 'wrap')); return;
        case 'loopMode': this.commitClip('Change loop mode', setLoop(clip, clip.loop, input.value === 'ping-pong' ? 'ping-pong' : 'wrap')); return;
        case 'fps': { const edit = setFramesPerSecond(clip, number, this.keepDuration); this.commitClip('Change frame rate', edit.clip, edit); return; }
        case 'length': {
          const edit = setFrameCount(clip, number, this.stretchLength);
          const lost = !this.stretchLength && clip.tracks.some((track) => track.keys.some((key) => key.at >= number));
          if (lost && !window.confirm(`Keys after frame ${number - 1} will be removed. Continue?`)) { this.render(); return; }
          this.commitClip('Change length', edit.clip, edit);
          return;
        }
        case 'transition':
          if (this.selection.kind === 'keys') this.commitClip('Change transition', setKeyTransition(clip, this.selection.refs, input.value as AnimationKeyTransition));
          return;
        case 'key-at': {
          if (this.selection.kind !== 'keys' || this.selection.refs.length !== 1) return;
          const result = moveKeys(clip, this.selection.refs, Math.round(number) - this.selection.refs[0].at);
          if (this.commitClip('Move key', result.clip)) this.selection = { kind: 'keys', refs: result.refs };
          return;
        }
        case 'event-id':
        case 'event-at':
        case 'event-gameplay':
        case 'event-payload': {
          if (this.selection.kind !== 'event') return;
          const patch = field === 'event-id' ? { eventId: input.value.trim() }
            : field === 'event-at' ? { at: Math.round(number) }
              : field === 'event-gameplay' ? { gameplay: checked }
                : { payload: input.value.trim() ? JSON.parse(input.value) as UniversalAnimationEvent['payload'] : undefined };
          const result = updateEvent(clip, this.selection.index, patch);
          if (this.commitClip('Edit event', result.clip)) this.selection = { kind: 'event', index: result.index };
          return;
        }
        case 'span-from':
        case 'span-through':
        case 'span-damage':
        case 'span-knockback': {
          if (this.selection.kind !== 'span' || !context.attack) return;
          const key = field === 'span-from' ? 'from' : field === 'span-through' ? 'through' : field === 'span-damage' ? 'damageMultiplier' : 'knockbackMultiplier';
          const plans = updateHitboxSpan(context.attack.plans, this.selection.direction, this.selection.index, { [key]: key === 'from' || key === 'through' ? Math.round(number) : number }, this.frames);
          this.host.commit('Edit hitbox window', { clips: context.clips, plans });
          return;
        }
      }
    });
  }

  private onInput(event: Event): void {
    const input = event.target;
    if (!(input instanceof HTMLInputElement)) return;
    if (input.dataset.animAddFilter !== undefined) {
      this.addTrackFilter = input.value;
      const list = this.element.querySelector('.anim-add-list');
      const popover = document.createElement('div');
      popover.innerHTML = this.renderAddTrack();
      const nextList = popover.querySelector('.anim-add-list');
      if (list && nextList) list.replaceWith(nextList);
      return;
    }
    if (input.dataset.animField === 'zoom') {
      this.setZoom(Number(input.value));
    }
  }

  private setZoom(zoom: number): void {
    const next = Math.max(6, Math.min(48, Math.round(zoom)));
    if (next === this.zoom) return;
    const scroller = this.element.querySelector<HTMLElement>('.anim-scroll');
    const anchor = scroller ? (scroller.scrollLeft + scroller.clientWidth / 2 - LABEL_WIDTH) / this.zoom : 0;
    this.zoom = next;
    this.render();
    const nextScroller = this.element.querySelector<HTMLElement>('.anim-scroll');
    if (nextScroller) nextScroller.scrollLeft = Math.max(0, anchor * this.zoom + LABEL_WIDTH - nextScroller.clientWidth / 2);
  }

  private onWheel(event: WheelEvent): void {
    if (!(event.ctrlKey || event.metaKey) || !(event.target instanceof Element) || !event.target.closest('.anim-scroll')) return;
    event.preventDefault();
    this.setZoom(this.zoom * (event.deltaY < 0 ? 1.15 : 1 / 1.15));
  }

  private frameAt(clientX: number, lane: HTMLElement): number {
    const rect = lane.getBoundingClientRect();
    return Math.max(0, Math.min(this.frames - 1, Math.floor((clientX - rect.left) / this.zoom)));
  }

  private onPointerDown(event: PointerEvent): void {
    if (event.button !== 0 || !(event.target instanceof Element)) return;
    const target = event.target;
    if (target.closest('[data-anim-resize]')) {
      this.drag = { kind: 'resize', startY: event.clientY, startHeight: this.height };
      this.capturePointer(event.pointerId);
      event.preventDefault();
      return;
    }
    const lane = target.closest<HTMLElement>('[data-anim-lane]');
    if (!lane || !this.clip) return;
    this.element.querySelector<HTMLElement>('.anim-scroll')?.focus({ preventScroll: true });
    const kind = lane.dataset.animLane;
    if (kind === 'ruler') {
      this.drag = { kind: 'scrub', lane };
      this.seek(this.frameAt(event.clientX, lane));
    } else if (kind === 'track') {
      const keyElement = target.closest<HTMLElement>('[data-anim-key]');
      if (keyElement) {
        const [track, at] = (keyElement.dataset.animKey ?? '').split(':').map(Number);
        const clickedRef = { track, at };
        const current = this.selection.kind === 'keys' ? this.selection.refs : [];
        const isSelected = current.some((ref) => ref.track === track && ref.at === at);
        const additive = event.shiftKey || event.ctrlKey || event.metaKey;
        let refs: readonly AnimationKeyRef[];
        if (additive) refs = isSelected ? current.filter((ref) => !(ref.track === track && ref.at === at)) : [...current, clickedRef];
        else refs = isSelected ? current : [clickedRef];
        this.selection = refs.length > 0 ? { kind: 'keys', refs } : { kind: 'none' };
        this.focusedTrack = track;
        this.markSelection();
        this.drag = { kind: 'keys', startX: event.clientX, refs, clickedRef, additive, delta: 0, moved: false };
      } else {
        const box = document.createElement('div');
        box.className = 'anim-marquee';
        this.element.querySelector('.anim-content')?.append(box);
        this.drag = { kind: 'marquee', startX: event.clientX, startY: event.clientY, lane, track: Number(lane.dataset.animLaneTrack), moved: false, box };
      }
    } else if (kind === 'events') {
      const marker = target.closest<HTMLElement>('[data-anim-event]');
      if (marker) {
        const index = Number(marker.dataset.animEvent);
        this.selection = { kind: 'event', index };
        this.drag = { kind: 'event', startX: event.clientX, index, delta: 0, moved: false };
      } else {
        this.drag = { kind: 'scrub', lane };
        this.seek(this.frameAt(event.clientX, lane));
      }
    } else if (kind === 'hitbox') {
      if (!this.editable) { this.host.notify(this.context?.readOnlyReason ?? 'Read only'); return; }
      const frame = this.frameAt(event.clientX, lane);
      const direction = lane.dataset.direction ?? '';
      const hitboxId = lane.dataset.hitbox ?? '';
      const spanIndex = target.closest<HTMLElement>('[data-anim-span]')?.dataset.animSpan;
      if (event.altKey && spanIndex !== undefined) {
        this.selection = { kind: 'span', direction, index: Number(spanIndex) };
        this.render();
        return;
      }
      const active = !hitboxActiveAt(this.context!.attack!.plans, direction, hitboxId, frame);
      this.drag = { kind: 'paint', lane, direction, hitboxId, active, frames: new Set([frame]) };
      lane.querySelector<HTMLElement>(`.anim-hit-cell[data-frame="${frame}"]`)?.classList.toggle('is-active', active);
    } else return;
    this.capturePointer(event.pointerId);
    event.preventDefault();
  }

  private onPointerMove(event: PointerEvent): void {
    const drag = this.drag;
    if (!drag) return;
    if (drag.kind === 'resize') {
      this.height = Math.max(150, Math.min(window.innerHeight * 0.75, drag.startHeight + (drag.startY - event.clientY)));
      this.element.style.setProperty('--anim-dock-height', `${this.height}px`);
    } else if (drag.kind === 'scrub') {
      const frame = this.frameAt(event.clientX, drag.lane);
      if (frame !== this.playhead) this.seek(frame);
    } else if (drag.kind === 'keys') {
      if (!this.editable) return;
      const delta = Math.round((event.clientX - drag.startX) / this.zoom);
      if (Math.abs(event.clientX - drag.startX) > 3) drag.moved = true;
      if (delta === drag.delta) return;
      drag.delta = delta;
      const ids = new Set(drag.refs.map(refId));
      const blocked = drag.refs.some((ref) => ref.at + delta < 0 || ref.at + delta >= this.frames);
      for (const element of this.element.querySelectorAll<HTMLElement>('[data-anim-key]')) {
        if (!ids.has(element.dataset.animKey ?? '')) continue;
        element.style.transform = `translateX(${delta * this.zoom}px)`;
        element.classList.toggle('is-blocked', blocked);
        element.classList.toggle('is-copying', event.altKey);
      }
    } else if (drag.kind === 'marquee') {
      const content = this.element.querySelector<HTMLElement>('.anim-content');
      if (!content) return;
      if (Math.abs(event.clientX - drag.startX) + Math.abs(event.clientY - drag.startY) > 4) drag.moved = true;
      const origin = content.getBoundingClientRect();
      const left = Math.min(drag.startX, event.clientX) - origin.left;
      const top = Math.min(drag.startY, event.clientY) - origin.top;
      Object.assign(drag.box.style, { left: `${left}px`, top: `${top}px`, width: `${Math.abs(event.clientX - drag.startX)}px`, height: `${Math.abs(event.clientY - drag.startY)}px` });
    } else if (drag.kind === 'event') {
      if (!this.editable) return;
      const delta = Math.round((event.clientX - drag.startX) / this.zoom);
      if (Math.abs(event.clientX - drag.startX) > 3) drag.moved = true;
      drag.delta = delta;
      const marker = this.element.querySelector<HTMLElement>(`[data-anim-event="${drag.index}"]`);
      if (marker) marker.style.transform = `translateX(${delta * this.zoom}px)`;
    } else if (drag.kind === 'paint') {
      const frame = this.frameAt(event.clientX, drag.lane);
      if (drag.frames.has(frame)) return;
      drag.frames.add(frame);
      drag.lane.querySelector<HTMLElement>(`.anim-hit-cell[data-frame="${frame}"]`)?.classList.toggle('is-active', drag.active);
    }
  }

  private onPointerUp(event: PointerEvent): void {
    const drag = this.drag;
    this.drag = undefined;
    if (!drag) return;
    if (this.element.hasPointerCapture(event.pointerId)) this.element.releasePointerCapture(event.pointerId);
    const clip = this.clip;
    if (drag.kind === 'resize' || drag.kind === 'scrub' || !clip) return;
    if (drag.kind === 'keys') {
      if (drag.moved && drag.delta !== 0 && this.editable) {
        this.attempt(() => {
          const result = moveKeys(clip, drag.refs, drag.delta, event.altKey);
          if (this.commitClip(event.altKey ? 'Duplicate keys' : 'Move keys', result.clip)) this.selection = { kind: 'keys', refs: result.refs };
        });
        this.render();
        return;
      }
      if (!drag.moved && !drag.additive) this.selection = { kind: 'keys', refs: [drag.clickedRef] };
      this.playhead = drag.clickedRef.at;
      this.pose();
      this.render();
      return;
    }
    if (drag.kind === 'marquee') {
      drag.box.remove();
      if (!drag.moved) {
        this.selection = { kind: 'none' };
        this.focusedTrack = Number.isInteger(drag.track) ? drag.track : undefined;
        this.seek(this.frameAt(event.clientX, drag.lane));
        this.render();
        return;
      }
      const left = Math.min(drag.startX, event.clientX);
      const right = Math.max(drag.startX, event.clientX);
      const top = Math.min(drag.startY, event.clientY);
      const bottom = Math.max(drag.startY, event.clientY);
      const refs: AnimationKeyRef[] = [];
      for (const element of this.element.querySelectorAll<HTMLElement>('[data-anim-key]')) {
        const rect = element.getBoundingClientRect();
        if (rect.right < left || rect.left > right || rect.bottom < top || rect.top > bottom) continue;
        const [track, at] = (element.dataset.animKey ?? '').split(':').map(Number);
        refs.push({ track, at });
      }
      const previous = event.shiftKey && this.selection.kind === 'keys' ? this.selection.refs : [];
      const merged = [...new Map([...previous, ...refs].map((ref) => [refId(ref), ref])).values()];
      this.selection = merged.length > 0 ? { kind: 'keys', refs: merged } : { kind: 'none' };
      this.render();
      return;
    }
    if (drag.kind === 'event') {
      if (drag.moved && drag.delta !== 0 && this.editable) {
        this.attempt(() => {
          const event = clip.events?.[drag.index];
          if (!event) return;
          const result = updateEvent(clip, drag.index, { at: Math.max(0, Math.min(this.frames - 1, event.at + drag.delta)) });
          if (this.commitClip('Move event', result.clip)) this.selection = { kind: 'event', index: result.index };
        });
      } else {
        const at = clip.events?.[drag.index]?.at;
        if (at !== undefined) { this.playhead = at; this.pose(); }
      }
      this.render();
      return;
    }
    if (drag.kind === 'paint') {
      const context = this.context;
      if (!context?.attack) return;
      this.attempt(() => {
        let plans = context.attack!.plans;
        for (const frame of [...drag.frames].sort((left, right) => left - right)) plans = setHitboxFrame(plans, drag.direction, drag.hitboxId, frame, drag.active);
        this.host.commit(drag.active ? 'Activate hitbox frames' : 'Clear hitbox frames', { clips: context.clips, plans });
      });
      const frame = Math.min(...drag.frames);
      this.playhead = frame;
      this.pose();
      this.render();
    }
  }

  /** Keeps drags alive outside the dock; synthetic or already-released pointers cannot be captured. */
  private capturePointer(pointerId: number): void {
    try { this.element.setPointerCapture(pointerId); } catch { /* no active pointer */ }
  }

  private cancelDrag(): void {
    const drag = this.drag;
    this.drag = undefined;
    if (drag?.kind === 'marquee') drag.box.remove();
    if (drag) this.render();
  }

  /** Updates key selection classes without rebuilding the DOM (keeps pointer capture alive). */
  private markSelection(): void {
    const ids = new Set(this.selection.kind === 'keys' ? this.selection.refs.map(refId) : []);
    for (const element of this.element.querySelectorAll<HTMLElement>('[data-anim-key]')) {
      const selected = ids.has(element.dataset.animKey ?? '');
      element.classList.toggle('is-selected', selected);
      element.setAttribute('aria-pressed', String(selected));
    }
  }

  private onKeyDown(event: KeyboardEvent): void {
    const target = event.target;
    if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement) {
      if (event.key === 'Escape' && this.addTrackFilter !== undefined) { this.addTrackFilter = undefined; this.render(); event.stopPropagation(); }
      return;
    }
    if (!this.clip) return;
    const modifier = event.ctrlKey || event.metaKey;
    const key = event.key.toLowerCase();
    let handled = true;
    if (key === ' ') this.togglePlayback();
    else if (key === ',' ) this.seek(this.playhead - 1);
    else if (key === '.') this.seek(this.playhead + 1);
    else if (event.key === 'Home') this.seek(0);
    else if (event.key === 'End') this.seek(this.frames - 1);
    else if ((event.key === 'ArrowLeft' || event.key === 'ArrowRight') && this.selection.kind === 'keys') this.nudgeKeys((event.key === 'ArrowLeft' ? -1 : 1) * (event.shiftKey ? 5 : 1));
    else if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') this.seek(this.playhead + (event.key === 'ArrowLeft' ? -1 : 1) * (event.shiftKey ? 5 : 1));
    else if (event.key === 'Delete' || event.key === 'Backspace') {
      if (this.selection.kind === 'keys') this.attempt(() => this.deleteSelectedKeys());
      else if (this.selection.kind === 'event') this.runAction('delete-event');
      else if (this.selection.kind === 'span') this.runAction('delete-span');
      else handled = false;
    } else if (modifier && key === 'c') this.copySelection();
    else if (modifier && key === 'v') this.paste();
    else if (modifier && key === 'd' && this.selection.kind === 'keys') {
      const clip = this.clip;
      const refs = this.selection.refs;
      this.attempt(() => {
        const delta = this.playhead - Math.min(...refs.map((ref) => ref.at));
        const result = moveKeys(clip, refs, delta === 0 ? 1 : delta, true);
        if (this.commitClip('Duplicate keys', result.clip)) this.selection = { kind: 'keys', refs: result.refs };
      });
    } else if (modifier && key === 'a') {
      this.selection = { kind: 'keys', refs: this.clip.tracks.flatMap((track, index) => track.keys.map((candidate) => ({ track: index, at: candidate.at }))) };
      this.render();
    } else if (!modifier && key === 'k' && this.focusedTrack !== undefined) this.attempt(() => this.keyTracks([this.focusedTrack!]));
    else if (event.key === 'Escape') { this.selection = { kind: 'none' }; this.addTrackFilter = undefined; this.render(); }
    else handled = false;
    if (handled) { event.preventDefault(); event.stopPropagation(); }
  }
}

function deleteClipIfPresent(clips: AnimationClips, id: string): AnimationClips {
  return clips[id] ? deleteClip(clips, id) : clips;
}
