type StudioMode = 'characters' | 'projectiles' | 'weapons';
type StudioNavigationMode = StudioMode | 'map';

const MODES: readonly { id: StudioNavigationMode; label: string }[] = [
  { id: 'characters', label: 'CHARACTERS' },
  { id: 'projectiles', label: 'PROJECTILES' },
  { id: 'weapons', label: 'WEAPONS' },
  { id: 'map', label: 'MAP STUDIO' },
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
  tabs.setAttribute('aria-label', 'Studio navigation');
  for (const mode of MODES) {
    const link = document.createElement('a');
    const isActive = mode.id !== 'map' && mode.id === active;
    link.className = `studio-mode-tab${mode.id === 'map' ? ' studio-mode-tab--map' : ''}${isActive ? ' is-active' : ''}`;
    const query = mode.id === 'map'
      ? new URLSearchParams(returnEditor ? { editor: returnEditor } : {})
      : new URLSearchParams({ studio: mode.id, ...(returnEditor ? { editor: returnEditor } : {}) });
    link.href = `?${query.toString()}`;
    link.textContent = mode.label;
    if (isActive) link.setAttribute('aria-current', 'page');
    if (mode.id === 'map') link.dataset.testid = 'map-studio-link';
    tabs.append(link);
  }
  actions.prepend(tabs);
}
