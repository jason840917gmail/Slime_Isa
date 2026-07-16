export interface DevToolsState {
  enabled: boolean;
  worldBounds: boolean;
  visualBounds: boolean;
  hitBoxes: boolean;
  interactionZones: boolean;
  attackBoxes: boolean;
}

type DevToolKey = keyof Omit<DevToolsState, 'enabled'>;

const TOGGLES: Array<{ key: DevToolKey; label: string; description: string }> = [
  { key: 'worldBounds', label: 'World bounds', description: 'World and camera extents' },
  { key: 'visualBounds', label: 'Visual bounds', description: 'Rendered sprite rectangles' },
  { key: 'hitBoxes', label: 'Hit boxes', description: 'Arcade physics bodies' },
  { key: 'interactionZones', label: 'Interaction zones', description: 'Doors, pickups, transitions' },
  { key: 'attackBoxes', label: 'Attack boxes', description: 'Active weapon hit areas' },
];

export const devToolsState: DevToolsState = {
  enabled: false,
  worldBounds: false,
  visualBounds: true,
  hitBoxes: true,
  interactionZones: true,
  attackBoxes: true,
};

export function createDevToolsPanel(): string {
  const rows = TOGGLES.map((toggle) => `
    <label class="dev-toggle-row">
      <input type="checkbox" data-dev-toggle="${toggle.key}" ${devToolsState[toggle.key] ? 'checked' : ''} />
      <span class="dev-checkbox" aria-hidden="true"></span>
      <span>
        <strong>${toggle.label}</strong>
        <small>${toggle.description}</small>
      </span>
    </label>
  `).join('');

  return `
    <aside class="development-panel" aria-label="Development tools">
      <header class="development-panel__header">
        <span class="dev-status-dot"></span>
        <div>
          <p>Debug Console</p>
          <h2>Development Tools</h2>
        </div>
      </header>
      <section class="dev-card">
        <h3>Runtime</h3>
        <button class="dev-runtime-button" type="button" data-dev-enabled="true">Enable Overlays</button>
        <p class="dev-note">Visible only in Vite dev mode.</p>
      </section>
      <section class="dev-card">
        <h3>Bounds</h3>
        ${rows}
      </section>
      <section class="dev-card dev-legend">
        <h3>Legend</h3>
        <p><span class="swatch swatch-world"></span> World/camera</p>
        <p><span class="swatch swatch-visual"></span> Visual bounds</p>
        <p><span class="swatch swatch-hit"></span> Physics hit boxes</p>
        <p><span class="swatch swatch-interaction"></span> Interactions</p>
        <p><span class="swatch swatch-attack"></span> Attacks</p>
      </section>
    </aside>
  `;
}

export function bindDevToolsPanel(root: ParentNode): void {
  const button = root.querySelector<HTMLButtonElement>('[data-dev-enabled]');

  const syncButton = () => {
    if (!button) return;
    button.textContent = devToolsState.enabled ? 'Disable Overlays' : 'Enable Overlays';
    button.classList.toggle('is-active', devToolsState.enabled);
  };

  button?.addEventListener('click', () => {
    devToolsState.enabled = !devToolsState.enabled;
    syncButton();
  });

  root.querySelectorAll<HTMLInputElement>('[data-dev-toggle]').forEach((input) => {
    const key = input.dataset.devToggle as DevToolKey | undefined;
    if (!key) return;
    input.checked = devToolsState[key];
    input.addEventListener('change', () => {
      devToolsState[key] = input.checked;
      if (input.checked && !devToolsState.enabled) {
        devToolsState.enabled = true;
        syncButton();
      }
    });
  });

  syncButton();
}
