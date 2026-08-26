import { ModalStack, type ModalHandle } from './ModalStack';

export interface TransientModalSession {
  isOpen(): boolean;
  requestClose(): boolean;
}

export interface TransientModalSessionOptions {
  readonly modalStack: ModalStack;
  readonly id: string;
  readonly canClose: () => boolean;
  readonly onClosed: () => void;
}

/** Owns one open/unregister lifecycle for a short-lived modal registration. */
export function createTransientModalSession(
  options: TransientModalSessionOptions,
): TransientModalSession {
  let open = true;
  let modalHandle: ModalHandle;

  const session: TransientModalSession = {
    isOpen: () => open,
    requestClose: () => {
      if (!open || !options.canClose()) return false;

      open = false;
      modalHandle.unregister();
      options.onClosed();
      return true;
    },
  };

  modalHandle = options.modalStack.register(options.id, {
    isOpen: session.isOpen,
    canClose: () => open && options.canClose(),
    close: () => {
      session.requestClose();
    },
  });
  modalHandle.open();

  return session;
}
