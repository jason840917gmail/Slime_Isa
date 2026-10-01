import type { JsonValue } from '../../content/scenes/types';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

const SURFACE_ID = 'npc-dialogue';
const REVEAL_CHARS_PER_SECOND = 45;
const REVEAL_TICK_MS = 30;
const ADVANCE_KEYS = new Set(['Space', 'Enter', 'NumpadEnter']);

export interface NpcDialogueSurfaceOptions {
  readonly modalStack: ModalStack;
  readonly uiRoot: HTMLElement;
  readonly onPausedChange: (paused: boolean) => void;
  readonly keyboardTarget?: Pick<Document, 'addEventListener' | 'removeEventListener'>;
}

export interface NpcDialogueRequest {
  readonly speaker: string;
  readonly pages: readonly string[];
  /** Runs once when the conversation closes by any path (finished, Esc, teardown). */
  readonly onClosed?: () => void;
  /** Runs instead of `onClosed` when the player reads through the last page (not Esc / ✕). */
  readonly onFinished?: () => void;
  /** Label for the last page's button, e.g. 'Continue  ▸' when a choice follows. */
  readonly finishLabel?: string;
}

interface DialogueSession extends NpcDialogueRequest {
  page: number;
  revealed: number;
}

/**
 * Paged NPC conversation box: text reveals progressively, F/Space/Enter skips the
 * reveal or advances, Esc or Close ends it. Gameplay stays paused while it is open.
 */
export class NpcDialogueSurfacePort implements UiSurfacePort {
  private readonly handle: ModalHandle;
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private readonly resizeObserver: ResizeObserver;
  private readonly keyboardTarget: Pick<Document, 'addEventListener' | 'removeEventListener'>;
  private session?: DialogueSession;
  private revealTimer?: ReturnType<typeof setInterval>;
  private stopped = false;

  constructor(private readonly options: NpcDialogueSurfaceOptions) {
    this.handle = options.modalStack.register(SURFACE_ID, {
      isOpen: () => this.isOpen(), close: () => this.close(),
    });
    this.resizeObserver = new ResizeObserver(this.publish);
    this.resizeObserver.observe(options.uiRoot);
    this.keyboardTarget = options.keyboardTarget ?? document;
    this.keyboardTarget.addEventListener('keydown', this.handleKeyDown, { capture: true });
  }

  isOpen(): boolean { return !!this.session; }

  open(request: NpcDialogueRequest): void {
    if (this.stopped) return;
    this.close();
    const pages = request.pages.map((page) => page.trim()).filter((page) => page.length > 0);
    this.session = { ...request, pages: pages.length > 0 ? pages : ['...'], page: 0, revealed: 0 };
    this.options.onPausedChange(true);
    this.handle.open();
    this.startReveal();
    this.publish();
  }

  /** Skips the typing reveal, turns the page, or finishes on the last page. */
  advance(): void {
    const session = this.session;
    if (!session) return;
    if (session.revealed < currentText(session).length) {
      session.revealed = currentText(session).length;
      this.stopReveal();
      this.publish();
      return;
    }
    if (session.page >= session.pages.length - 1) { this.close(true); return; }
    session.page += 1;
    session.revealed = 0;
    this.startReveal();
    this.publish();
  }

  close(finished = false): void {
    const session = this.session;
    this.stopReveal();
    if (!session) { this.handle.close(); return; }
    this.session = undefined;
    this.handle.close();
    try {
      this.options.onPausedChange(false);
    } finally {
      this.publish();
      if (finished && session.onFinished) session.onFinished();
      else session.onClosed?.();
    }
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== SURFACE_ID || this.stopped) return {};
    const session = this.session;
    const width = Math.min(760, Math.max(1, this.options.uiRoot.clientWidth - 24));
    const height = 196;
    const bottomGap = 24;
    const lastPage = !session || session.page >= session.pages.length - 1;
    const typing = !!session && session.revealed < currentText(session).length;
    return {
      open: !!session,
      offsetMin: [-Math.round(width / 2), -(height + bottomGap)],
      offsetMax: [Math.round(width / 2), -bottomGap],
      speaker: session?.speaker ?? '',
      text: session ? currentText(session).slice(0, session.revealed) : '',
      pageLabel: session && session.pages.length > 1 ? `${session.page + 1} / ${session.pages.length}` : '',
      nextLabel: typing ? 'Skip  ▸▸' : lastPage ? session?.finishLabel ?? 'Done  ✓' : 'Next  ▸',
      hint: 'Space / Enter  continue   ·   Esc  close',
    };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== SURFACE_ID || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(surfaceId: string, actionId: string, _payload?: JsonValue): void {
    if (surfaceId !== SURFACE_ID || this.stopped) return;
    if (actionId === 'next') this.advance();
    else if (actionId === 'close') this.close();
  }

  destroy(): void {
    if (this.stopped) return;
    this.close();
    this.stopped = true;
    this.keyboardTarget.removeEventListener('keydown', this.handleKeyDown, { capture: true });
    this.resizeObserver.disconnect();
    this.handle.unregister();
    this.listeners.clear();
  }

  private startReveal(): void {
    this.stopReveal();
    const startedAt = performance.now();
    this.revealTimer = setInterval(() => {
      const session = this.session;
      if (!session) { this.stopReveal(); return; }
      const length = currentText(session).length;
      session.revealed = Math.min(length, Math.floor(((performance.now() - startedAt) / 1000) * REVEAL_CHARS_PER_SECOND));
      if (session.revealed >= length) this.stopReveal();
      this.publish();
    }, REVEAL_TICK_MS);
  }

  private stopReveal(): void {
    if (this.revealTimer === undefined) return;
    clearInterval(this.revealTimer);
    this.revealTimer = undefined;
  }

  /** Captures advance keys while open so they never leak into gameplay (e.g. Space jumping). */
  private readonly handleKeyDown = (event: KeyboardEvent): void => {
    if (!this.session || !ADVANCE_KEYS.has(event.code)) return;
    event.preventDefault();
    event.stopPropagation();
    if (!event.repeat) this.advance();
  };

  private readonly publish = (): void => {
    if (this.stopped) return;
    const model = this.snapshot(SURFACE_ID);
    for (const listener of this.listeners) listener(model);
  };
}

function currentText(session: DialogueSession): string {
  return session.pages[session.page] ?? '';
}
