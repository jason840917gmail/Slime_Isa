import { formatAnimationTimelineSeconds } from './AnimationTimelineView';

const RESIZE_HANDLE_SELECTOR = '[data-timeline-resize-handle]';
const MAX_SAFE_HOLD = Number.MAX_SAFE_INTEGER;

export interface TimelineHoldResizeCommit {
  readonly keyframeIndex: number;
  readonly sourceFrame: number;
  readonly startFrame: number;
  readonly originalHold: number;
  readonly requestedHold: number;
  readonly validationToken: string;
}

export interface TimelineHoldResizeContext {
  readonly keyframeIndex: number;
  readonly sourceFrame: number;
  readonly startFrame: number;
  readonly originalHold: number;
  readonly framesPerSecond: number;
  readonly timelineFrames: number;
  readonly validationToken: string;
  readonly timeline: HTMLElement;
  readonly lane: HTMLElement;
  readonly tile: HTMLElement;
}

export interface TimelineHoldResizeControllerOptions {
  readonly resolveContext: (keyframeIndex: number, handle: HTMLElement) => TimelineHoldResizeContext | undefined;
  readonly commitHold: (commit: TimelineHoldResizeCommit) => boolean;
  readonly afterCommit?: (keyframeIndex: number) => void;
}

interface TileStyleSnapshot {
  readonly element: HTMLElement;
  readonly index: number;
  readonly gridColumnStart: string;
  readonly gridColumnEnd: string;
}

interface VisibilitySnapshot {
  readonly element: HTMLElement;
  readonly frame: number;
  readonly display: string;
}

interface ResizeDomSnapshot {
  readonly timelineFrameCount: string;
  readonly resizeFrameWidth: string;
  readonly timelineWasResizing: boolean;
  readonly tileWasResizing: boolean;
  readonly labelText: string;
  readonly handleValueNow: string | null;
  readonly handleValueText: string | null;
  readonly tileStyles: readonly TileStyleSnapshot[];
  readonly visibility: readonly VisibilitySnapshot[];
}

interface ActiveResize {
  readonly pointerId: number;
  readonly handle: HTMLElement;
  readonly context: TimelineHoldResizeContext;
  readonly startClientX: number;
  readonly startScrollLeft: number;
  readonly frameWidth: number;
  readonly snapshot: ResizeDomSnapshot;
  previewHold: number;
}

function eventHandle(event: Event): HTMLElement | undefined {
  const target = event.target;
  return target instanceof Element ? target.closest<HTMLElement>(RESIZE_HANDLE_SELECTOR) ?? undefined : undefined;
}

function consumeEvent(event: Event): void {
  event.preventDefault();
  event.stopPropagation();
}

function integerStyle(value: string, fallback: number): number {
  const parsed = Number.parseInt(value, 10);
  return Number.isInteger(parsed) ? parsed : fallback;
}

function releaseCapture(active: ActiveResize): void {
  const { handle, pointerId } = active;
  if (!handle.isConnected) return;
  try {
    if (handle.hasPointerCapture(pointerId)) handle.releasePointerCapture(pointerId);
  } catch {
    // The browser may already have released this pointer.
  }
}

export function roundTimelineResizeFrameDelta(distance: number, frameWidth: number): number {
  if (!Number.isFinite(distance) || !Number.isFinite(frameWidth) || frameWidth <= 0) return 0;
  const frames = distance / frameWidth;
  const rounded = frames >= 0 ? Math.floor(frames + 0.5) : Math.ceil(frames - 0.5);
  return rounded === 0 ? 0 : rounded;
}

export function timelineResizeHold(originalHold: number, frameDelta: number): number {
  const safeOriginal = Math.max(1, Math.round(originalHold));
  const requested = safeOriginal + Math.round(frameDelta);
  return Math.min(MAX_SAFE_HOLD, Math.max(1, requested));
}

export class TimelineHoldResizeController {
  private active: ActiveResize | undefined;
  private disposed = false;

  constructor(private readonly options: TimelineHoldResizeControllerOptions) {}

  pointerDown(event: PointerEvent): boolean {
    const handle = eventHandle(event);
    if (!handle) return false;
    consumeEvent(event);
    if (this.disposed || this.active || event.button !== 0 || !event.isPrimary) return true;
    const keyframeIndex = Number(handle.dataset.keyframeIndex);
    if (!Number.isInteger(keyframeIndex)) return true;
    const context = this.options.resolveContext(keyframeIndex, handle);
    if (!context || context.timelineFrames < 1 || context.framesPerSecond < 1 || !context.tile.isConnected) return true;
    const frameWidth = context.lane.getBoundingClientRect().width / context.timelineFrames;
    if (!Number.isFinite(frameWidth) || frameWidth <= 0) return true;
    const snapshot = this.captureSnapshot(context, handle);
    this.active = {
      pointerId: event.pointerId,
      handle,
      context,
      startClientX: event.clientX,
      startScrollLeft: context.timeline.scrollLeft,
      frameWidth,
      snapshot,
      previewHold: context.originalHold,
    };
    context.timeline.classList.add('is-resizing');
    context.timeline.style.setProperty('--timeline-resize-frame-width', `${frameWidth}px`);
    context.tile.classList.add('is-resizing');
    try { handle.setPointerCapture(event.pointerId); } catch { /* Pointer capture is an enhancement. */ }
    return true;
  }

  pointerMove(event: PointerEvent): boolean {
    const active = this.active;
    if (!active || active.pointerId !== event.pointerId) return false;
    consumeEvent(event);
    const distance = (event.clientX - active.startClientX)
      + (active.context.timeline.scrollLeft - active.startScrollLeft);
    const nextHold = timelineResizeHold(active.context.originalHold, roundTimelineResizeFrameDelta(distance, active.frameWidth));
    if (nextHold !== active.previewHold) this.applyPreview(active, nextHold);
    return true;
  }

  pointerUp(event: PointerEvent): boolean {
    const active = this.active;
    if (!active || active.pointerId !== event.pointerId) return false;
    consumeEvent(event);
    this.active = undefined;
    releaseCapture(active);
    if (active.previewHold === active.context.originalHold) {
      this.restoreSnapshot(active);
      return true;
    }
    const accepted = this.options.commitHold(this.commitFrom(active.context, active.previewHold));
    if (accepted) {
      this.finishAccepted(active);
      this.options.afterCommit?.(active.context.keyframeIndex);
    } else {
      this.restoreSnapshot(active);
    }
    return true;
  }

  pointerCancel(event: PointerEvent): boolean {
    const active = this.active;
    if (!active || active.pointerId !== event.pointerId) return false;
    consumeEvent(event);
    this.cancel();
    return true;
  }

  click(event: MouseEvent): boolean {
    if (!eventHandle(event)) return false;
    consumeEvent(event);
    return true;
  }

  keyDown(event: KeyboardEvent): boolean {
    if (event.key === 'Escape' && this.active) {
      consumeEvent(event);
      this.cancel();
      return true;
    }
    const handle = eventHandle(event);
    if (!handle || !['ArrowLeft', 'ArrowRight', 'Home'].includes(event.key)) return false;
    consumeEvent(event);
    if (this.disposed || this.active) return true;
    const keyframeIndex = Number(handle.dataset.keyframeIndex);
    if (!Number.isInteger(keyframeIndex)) return true;
    const context = this.options.resolveContext(keyframeIndex, handle);
    if (!context) return true;
    const requestedHold = event.key === 'Home'
      ? 1
      : timelineResizeHold(context.originalHold, event.key === 'ArrowLeft' ? -1 : 1);
    if (requestedHold === context.originalHold) return true;
    if (this.options.commitHold(this.commitFrom(context, requestedHold))) this.options.afterCommit?.(keyframeIndex);
    return true;
  }

  cancel(): void {
    const active = this.active;
    if (!active) return;
    this.active = undefined;
    releaseCapture(active);
    this.restoreSnapshot(active);
  }

  dispose(): void {
    if (this.disposed) return;
    this.cancel();
    this.disposed = true;
  }

  private commitFrom(context: TimelineHoldResizeContext, requestedHold: number): TimelineHoldResizeCommit {
    return {
      keyframeIndex: context.keyframeIndex,
      sourceFrame: context.sourceFrame,
      startFrame: context.startFrame,
      originalHold: context.originalHold,
      requestedHold,
      validationToken: context.validationToken,
    };
  }

  private captureSnapshot(context: TimelineHoldResizeContext, handle: HTMLElement): ResizeDomSnapshot {
    const label = context.tile.querySelector<HTMLElement>('.timeline-frame-hold');
    const tileStyles = Array.from(context.lane.querySelectorAll<HTMLElement>('[data-timeline-index]')).map((element) => ({
      element,
      index: Number(element.dataset.timelineIndex),
      gridColumnStart: element.style.gridColumnStart,
      gridColumnEnd: element.style.gridColumnEnd,
    }));
    const visibility: VisibilitySnapshot[] = Array.from(context.timeline.querySelectorAll<HTMLElement>('[data-timeline-frame]')).map((element) => ({
      element,
      frame: Number(element.dataset.timelineFrame),
      display: element.style.display,
    }));
    context.timeline.querySelectorAll<HTMLElement>('.timeline-track-row').forEach((row) => {
      Array.from(row.children).slice(1).forEach((element, frame) => {
        if (element instanceof HTMLElement) visibility.push({ element, frame, display: element.style.display });
      });
    });
    return {
      timelineFrameCount: context.timeline.style.getPropertyValue('--timeline-frame-count'),
      resizeFrameWidth: context.timeline.style.getPropertyValue('--timeline-resize-frame-width'),
      timelineWasResizing: context.timeline.classList.contains('is-resizing'),
      tileWasResizing: context.tile.classList.contains('is-resizing'),
      labelText: label?.textContent ?? '',
      handleValueNow: handle.getAttribute('aria-valuenow'),
      handleValueText: handle.getAttribute('aria-valuetext'),
      tileStyles,
      visibility,
    };
  }

  private applyPreview(active: ActiveResize, requestedHold: number): void {
    const { context, handle, snapshot } = active;
    const delta = requestedHold - context.originalHold;
    const previewFrames = Math.max(1, context.timelineFrames + delta);
    context.timeline.style.setProperty('--timeline-frame-count', String(previewFrames));
    for (const tile of snapshot.tileStyles) {
      if (tile.index === context.keyframeIndex) tile.element.style.gridColumnEnd = `span ${requestedHold}`;
      else if (tile.index > context.keyframeIndex) tile.element.style.gridColumnStart = String(integerStyle(tile.gridColumnStart, 1) + delta);
    }
    for (const item of snapshot.visibility) item.element.style.display = item.frame >= previewFrames ? 'none' : item.display;
    const holdSeconds = requestedHold / context.framesPerSecond;
    const seconds = `${formatAnimationTimelineSeconds(holdSeconds, context.framesPerSecond)}s`;
    const label = context.tile.querySelector<HTMLElement>('.timeline-frame-hold');
    if (label) label.textContent = `${seconds} / ${requestedHold}F`;
    handle.setAttribute('aria-valuenow', String(requestedHold));
    handle.setAttribute('aria-valuetext', `${requestedHold} frame${requestedHold === 1 ? '' : 's'}, ${seconds}`);
    active.previewHold = requestedHold;
  }

  private restoreSnapshot(active: ActiveResize): void {
    const { context, handle, snapshot } = active;
    if (snapshot.timelineFrameCount) context.timeline.style.setProperty('--timeline-frame-count', snapshot.timelineFrameCount);
    else context.timeline.style.removeProperty('--timeline-frame-count');
    if (snapshot.resizeFrameWidth) context.timeline.style.setProperty('--timeline-resize-frame-width', snapshot.resizeFrameWidth);
    else context.timeline.style.removeProperty('--timeline-resize-frame-width');
    context.timeline.classList.toggle('is-resizing', snapshot.timelineWasResizing);
    context.tile.classList.toggle('is-resizing', snapshot.tileWasResizing);
    for (const tile of snapshot.tileStyles) {
      tile.element.style.gridColumnStart = tile.gridColumnStart;
      tile.element.style.gridColumnEnd = tile.gridColumnEnd;
    }
    for (const item of snapshot.visibility) item.element.style.display = item.display;
    const label = context.tile.querySelector<HTMLElement>('.timeline-frame-hold');
    if (label) label.textContent = snapshot.labelText;
    if (snapshot.handleValueNow === null) handle.removeAttribute('aria-valuenow');
    else handle.setAttribute('aria-valuenow', snapshot.handleValueNow);
    if (snapshot.handleValueText === null) handle.removeAttribute('aria-valuetext');
    else handle.setAttribute('aria-valuetext', snapshot.handleValueText);
  }

  private finishAccepted(active: ActiveResize): void {
    active.context.timeline.classList.remove('is-resizing');
    active.context.timeline.style.removeProperty('--timeline-resize-frame-width');
    active.context.tile.classList.remove('is-resizing');
  }
}
