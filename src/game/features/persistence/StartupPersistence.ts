import { saveSystem } from '../../core/SaveSystem';
import { peekRunNavigation } from '../world-navigation/AreaNavigation';

/**
 * Resolves browser recovery before Phaser builds the authored world. Explicit
 * load/reset/area handoffs already carry a complete run and skip this prompt.
 */
export async function prepareRunStartup(container: HTMLElement): Promise<void> {
  if (peekRunNavigation()) return;
  if (!saveSystem.hasSave()) {
    saveSystem.startNewRun();
    return;
  }

  await new Promise<void>((resolve) => {
    const backdrop = document.createElement('div');
    backdrop.className = 'dev-modal-backdrop';
    backdrop.innerHTML = `
      <section class="dev-modal startup-save-modal" role="dialog" aria-modal="true" aria-labelledby="startup-save-title" aria-describedby="startup-save-description">
        <header><p>Recovery available</p><h2 id="startup-save-title">Continue your last session?</h2></header>
        <p id="startup-save-description">Recovery protects progress after closing or refreshing the browser. Named saves are not changed by either choice.</p>
        <p class="dev-modal-status" data-startup-status hidden></p>
        <footer>
          <button type="button" class="dev-modal-button dev-modal-button--danger" data-startup-choice="new">Start New Run</button>
          <button type="button" class="dev-modal-button" data-startup-choice="continue">Continue Recovery</button>
        </footer>
      </section>
    `;
    container.appendChild(backdrop);

    const buttons = [...backdrop.querySelectorAll<HTMLButtonElement>('button')];
    const status = backdrop.querySelector<HTMLElement>('[data-startup-status]');
    const finish = (): void => {
      backdrop.remove();
      resolve();
    };
    const showFailure = (message: string): void => {
      if (status) {
        status.hidden = false;
        status.textContent = message;
      }
      buttons.forEach((button) => { button.disabled = false; });
    };

    backdrop.addEventListener('keydown', (event) => {
      if (event.key !== 'Tab' || buttons.length === 0) return;
      const first = buttons[0];
      const last = buttons[buttons.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    });

    backdrop.addEventListener('click', (event) => {
      const button = event.target instanceof HTMLElement
        ? event.target.closest<HTMLButtonElement>('[data-startup-choice]')
        : null;
      if (!button) return;
      buttons.forEach((candidate) => { candidate.disabled = true; });
      if (button.dataset.startupChoice === 'continue') {
        if (saveSystem.loadRecovery()) finish();
        else showFailure('Recovery could not be validated. Start a new run or load a named save after the game opens.');
        return;
      }
      saveSystem.discardRecoveryAndStartNewRun();
      finish();
    });

    buttons.at(-1)?.focus();
  });
}
