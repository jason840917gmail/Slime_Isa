import type { ModalStack } from './ModalStack';

export interface PendingLevelUpState {
  readonly isOpen: boolean;
  readonly isClosing: boolean;
  readonly choiceCount: number;
}

export interface PendingLevelUpModal {
  reopenPending(): boolean;
}

export function canReopenPendingLevelUp(state: PendingLevelUpState): boolean {
  return !state.isOpen && !state.isClosing && state.choiceCount > 0;
}

export function reopenPendingLevelUpWhenIdle(
  modalStack: Pick<ModalStack, 'hasActiveSurface'>,
  levelUpModal: PendingLevelUpModal,
): boolean {
  if (modalStack.hasActiveSurface()) return false;
  return levelUpModal.reopenPending();
}
