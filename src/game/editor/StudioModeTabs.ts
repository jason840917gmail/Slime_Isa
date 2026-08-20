type StudioMode = 'characters' | 'projectiles' | 'weapons';

const MODES: readonly { id: StudioMode; label: string }[] = [
  { id: 'characters', label: 'CHARACTERS' },
  { id: 'projectiles', label: 'PROJECTILES' },
  { id: 'weapons', label: 'WEAPONS' },
];

export function ensureStudioModeTabs(
  container: HTMLDivElement,
  returnEditor: string,
  active: StudioMode,
): void {
  const actions = container.querySelector<HTMLElement>('.studio-topbar-actions');
  if (!actions || actions.querySelector('[data-studio-mode-tabs]')) return;
  const tabs = document.createElement('nav');
  tabs.className = 'studio-mode-tabs';
  tabs.dataset.studioModeTabs = 'true';
  tabs.setAttribute('aria-label', 'Studio mode');
  for (const mode of MODES) {
    const link = document.createElement('a');
    link.className = `studio-mode-tab${mode.id === active ? ' is-active' : ''}`;
    const query = new URLSearchParams({ studio: mode.id, ...(returnEditor ? { editor: returnEditor } : {}) });
    link.href = `?${query.toString()}`;
    link.textContent = mode.label;
    if (mode.id === active) link.setAttribute('aria-current', 'page');
    tabs.append(link);
  }
  actions.prepend(tabs);
}
