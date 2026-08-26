export interface ModalRegistration {
  readonly isOpen: () => boolean;
  readonly canClose?: () => boolean;
  readonly close: () => void;
}

export interface ModalHandle {
  readonly id: string;
  open(): void;
  close(): void;
  unregister(): void;
}

export interface ModalStackEventTarget {
  addEventListener(
    type: 'keydown',
    listener: (event: KeyboardEvent) => void,
    options: { readonly capture: true },
  ): void;
  removeEventListener(
    type: 'keydown',
    listener: (event: KeyboardEvent) => void,
    options: { readonly capture: true },
  ): void;
}

interface RegisteredModal {
  readonly id: string;
  readonly token: symbol;
  readonly registration: ModalRegistration;
}

const CAPTURE_OPTIONS = { capture: true } as const;

/**
 * Routes one Escape press to the most recently opened active surface.
 *
 * The stack is deliberately independent of Phaser so Phaser overlays and DOM
 * overlays share the same lifecycle and can be tested without a running scene.
 */
export class ModalStack {
  private readonly registrations = new Map<string, RegisteredModal>();
  private readonly stack: RegisteredModal[] = [];
  private readonly eventTarget: ModalStackEventTarget;
  private destroyed = false;
  private handlingEscape = false;

  private readonly handleKeyDown = (event: KeyboardEvent): void => {
    if (event.key !== 'Escape') return;
    if (!this.closeTopmost()) return;

    event.preventDefault();
    event.stopPropagation();
  };

  constructor(eventTarget: ModalStackEventTarget = document as ModalStackEventTarget) {
    this.eventTarget = eventTarget;
    this.eventTarget.addEventListener('keydown', this.handleKeyDown, CAPTURE_OPTIONS);
  }

  register(id: string, registration: ModalRegistration): ModalHandle {
    if (this.destroyed) {
      throw new Error('Cannot register a modal after ModalStack.destroy().');
    }
    if (this.registrations.has(id)) {
      throw new Error(`Modal ID '${id}' is already registered.`);
    }

    const entry: RegisteredModal = {
      id,
      token: Symbol(id),
      registration,
    };
    this.registrations.set(id, entry);

    let registered = true;
    const isCurrent = (): boolean => {
      return registered && !this.destroyed && this.registrations.get(id)?.token === entry.token;
    };

    return {
      id,
      open: () => {
        if (!isCurrent()) return;
        this.removeEntry(entry);
        this.stack.push(entry);
      },
      close: () => {
        if (!isCurrent()) return;
        this.removeEntry(entry);
      },
      unregister: () => {
        if (!registered) return;
        registered = false;
        if (this.registrations.get(id)?.token === entry.token) {
          this.registrations.delete(id);
        }
        this.removeEntry(entry);
      },
    };
  }

  hasActiveSurface(): boolean {
    if (this.destroyed) return false;
    this.pruneStaleEntries();
    return this.stack.length > 0;
  }

  /**
   * Returns true when the top surface consumes the close request, including
   * when its guard refuses to close it. It does not mean the surface closed.
   */
  closeTopmost(): boolean {
    if (this.destroyed || this.handlingEscape) return false;

    this.pruneStaleEntries();
    const entry = this.stack[this.stack.length - 1];
    if (!entry) return false;

    this.handlingEscape = true;
    try {
      if (entry.registration.canClose?.() === false) return true;

      this.removeEntry(entry);
      entry.registration.close();
      return true;
    } catch (error) {
      if (this.isCurrentEntry(entry) && entry.registration.isOpen()) {
        this.removeEntry(entry);
        this.stack.push(entry);
      }
      throw error;
    } finally {
      this.handlingEscape = false;
    }
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.eventTarget.removeEventListener('keydown', this.handleKeyDown, CAPTURE_OPTIONS);
    this.stack.length = 0;
    this.registrations.clear();
  }

  private isCurrentEntry(entry: RegisteredModal): boolean {
    return this.registrations.get(entry.id)?.token === entry.token;
  }

  private pruneStaleEntries(): void {
    for (let index = this.stack.length - 1; index >= 0; index -= 1) {
      const entry = this.stack[index];
      if (!this.isCurrentEntry(entry) || !entry.registration.isOpen()) {
        this.stack.splice(index, 1);
      }
    }
  }

  private removeEntry(entry: RegisteredModal): void {
    for (let index = this.stack.length - 1; index >= 0; index -= 1) {
      if (this.stack[index] === entry) this.stack.splice(index, 1);
    }
  }
}
