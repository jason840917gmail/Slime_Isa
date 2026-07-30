import { getObjectVisualChoices, type ObjectVisualChoice } from '../content/objects/ObjectCatalog';
import { getTileDefinition, getTileIds } from '../content/terrain/TileCatalog';
import { getAuthoredMapIds } from '../infrastructure/maps/MapRepository';
import { ENEMY_CONFIGS } from '../enemies/library/EnemyTypes';
import type { MapEnemyAreaPerimeter, MapEnemyAreaShape } from '../content/maps/mapFormat';
import { ObjectTemplateEditorState } from './ObjectTemplateEditorState';
import type { EditorTool, MapEditorState } from './MapEditorState';
import { connectionAt, MAP_DIRECTIONS } from './MapConnections';

const TOOLS: ReadonlyArray<{ id: EditorTool; key: string; label: string }> = [
  { id: 'pan', key: 'H', label: 'Pan' },
  { id: 'terrain', key: 'B', label: 'Paint' },
  { id: 'object', key: 'O', label: 'Object' },
  { id: 'select', key: 'V', label: 'Select / Move' },
  { id: 'erase', key: 'X', label: 'Erase / Box Delete' },
  { id: 'safe-zone', key: 'Z', label: 'Monster Safe Zone' },
  { id: 'enemy-area', key: 'M', label: 'Enemy Area' },
  { id: 'spawn', key: 'P', label: 'Player Spawn' },
  { id: 'entry', key: 'I', label: 'Entry Point' },
  { id: 'exit', key: 'E', label: 'Exit Zone' },
];

export interface ContentPreviewUrls {
  readonly tiles: Readonly<Record<string, string>>;
  readonly objects: Readonly<Record<string, string>>;
}

function titleFromId(id: string): string {
  return id.split(/[.-]/).map((part) => `${part[0]?.toUpperCase() ?? ''}${part.slice(1)}`).join(' ');
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    "'": '&#39;',
    '"': '&quot;',
  })[character] ?? character);
}

function terrainGroup(tileId: string): string {
  if (tileId.startsWith('grass-')) return 'Grass';
  if (tileId.startsWith('amberleaf-')) return 'Amberleaf';
  if (tileId.startsWith('frozen-')) return 'Frozen';
  if (tileId.startsWith('sanddessert-')) return 'Sand Dessert';
  if (tileId.includes('water')) return 'Water';
  if (tileId.startsWith('forest-') || tileId === 'tree-wall') return 'Forest';
  if (tileId.startsWith('cavern-') || tileId.startsWith('crystal-')) return 'Crystal Cavern';
  return 'Walls';
}

function objectGroup(objectId: string): string {
  if (objectId.startsWith('collectible.')) return 'Collectibles';
  if (objectId === 'decoration.world.floor') return 'Floor Decorations';
  if (objectId === 'decoration.world.solid') return 'Solid Decorations';
  if (objectId.startsWith('tree.')) return 'Solid Trees';
  if (objectId.startsWith('house.')) return 'Solid Houses';
  if (objectId.startsWith('wall.')) return 'Stone Walls';
  if (objectId.includes('mineable')) return 'Mineable Rocks';
  if (objectId.includes('decorative')) return 'Decorative Rocks';
  if (objectId.includes('solid')) return 'Solid Rocks';
  return 'Other Objects';
}

function renderGroups(items: ReadonlyArray<{ readonly group: string; readonly html: string }>): string {
  const groups = new Map<string, string[]>();
  for (const item of items) {
    const entries = groups.get(item.group) ?? [];
    entries.push(item.html);
    groups.set(item.group, entries);
  }
  return [...groups].map(([label, entries], index) => (
    `<details class="editor-palette-group" ${index === 0 ? 'open' : ''}>
      <summary><span>${label}</span><small>${entries.length}</small></summary>
      <div class="editor-palette-group-items">${entries.join('')}</div>
    </details>`
  )).join('');
}

function renderObjectArtworkGroup(choices: readonly ObjectVisualChoice[], previews: ContentPreviewUrls): string {
  const first = choices[0];
  if (!first) return '';
  const siblingRows = choices.map((choice) => `
    <button class="editor-palette-sibling" type="button" data-object="${escapeHtml(choice.objectId)}" data-visual="${escapeHtml(choice.visualId)}" title="${escapeHtml(choice.visualId)}">
      <span>${escapeHtml(choice.displayName === choice.visualId ? titleFromId(choice.visualId) : choice.displayName)}</span>
      <small>${escapeHtml(choice.visualId)} · ${choice.physics ? `Collider ${choice.collider?.width ?? '?'} × ${choice.collider?.height ?? '?'}` : 'No physics'}</small>
    </button>`).join('');
  return `<div class="editor-palette-artwork">
    <button class="editor-palette-item" type="button" data-object="${escapeHtml(first.objectId)}" data-visual="${escapeHtml(first.visualId)}" title="${escapeHtml(first.visualId)}">
      <span class="editor-palette-preview"><img src="${escapeHtml(previews.objects[first.key] ?? '')}" alt="" /></span>
      <span class="editor-palette-copy"><strong>${escapeHtml(titleFromId(first.objectId))}</strong><small>${escapeHtml(first.assetId)} · frame ${first.frame} · ${choices.length} template${choices.length === 1 ? '' : 's'}</small></span>
    </button>
    <div class="editor-palette-siblings">${siblingRows}</div>
  </div>`;
}

export function mountMapEditorPanel(
  host: HTMLElement,
  editor: MapEditorState,
  previews: ContentPreviewUrls,
  templateEditor: ObjectTemplateEditorState,
): () => void {
  const mapIds = getAuthoredMapIds();
  const enemyTypes = Object.keys(ENEMY_CONFIGS);
  const tileButtons = renderGroups(getTileIds().map((tileId) => {
    const tags = getTileDefinition(tileId).tags.join(' / ');
    return {
      group: terrainGroup(tileId),
      html: `<button class="editor-palette-item" type="button" data-tile="${tileId}">
        <span class="editor-palette-preview"><img src="${previews.tiles[tileId]}" alt="" /></span>
        <span class="editor-palette-copy"><strong>${titleFromId(tileId)}</strong><small>${tags}</small></span>
      </button>`,
    };
  }));
  const objectArtworkGroups = new Map<string, ObjectVisualChoice[]>();
  for (const choice of getObjectVisualChoices()) {
    const key = `${choice.assetId}::${choice.frame}`;
    const group = objectArtworkGroups.get(key) ?? [];
    group.push(choice);
    objectArtworkGroups.set(key, group);
  }
  const objectButtons = renderGroups([...objectArtworkGroups.values()].map((choices) => ({
    group: objectGroup(choices[0].objectId),
    html: renderObjectArtworkGroup(choices, previews),
  })));

  host.innerHTML = `
    <header class="map-editor-header">
      <div class="map-editor-mark" aria-hidden="true">M</div>
      <div><p>Slime Isa / Worldworks</p><h1>Field Cartographer</h1></div>
      <nav class="editor-header-actions" aria-label="Editor navigation">
        <a class="editor-nav-link editor-nav-link--studio" href="?studio=characters&amp;editor=${encodeURIComponent(editor.value.map.mapId)}" data-testid="character-studio-link">Character Studio</a>
        <a class="editor-nav-link editor-game-link" href="?area=${editor.value.map.mapId}">Play map</a>
      </nav>
    </header>
    <section class="editor-map-strip">
      <label for="editor-map-select">Document</label>
      <select id="editor-map-select" data-testid="map-select">
        ${mapIds.map((id) => `<option value="${id}">${titleFromId(id)}</option>`).join('')}
      </select>
      <button class="editor-new-map" type="button" data-command="new-map" data-testid="new-map-button">New map</button>
      <span class="editor-dirty" data-editor-dirty>Saved</span>
    </section>
    <section class="editor-actions" aria-label="Document actions">
      <button type="button" data-command="undo" data-testid="undo-button">Undo <kbd>Ctrl Z</kbd></button>
      <button type="button" data-command="redo" data-testid="redo-button">Redo <kbd>Ctrl Y</kbd></button>
      <button class="editor-save" type="button" data-command="save" data-testid="save-button">Save map <kbd>Ctrl S</kbd></button>
    </section>
    <section class="editor-section">
      <div class="editor-section-title"><span>01</span><h2>Tools</h2></div>
      <div class="editor-tool-grid">
        ${TOOLS.map((tool) => `<button type="button" data-tool="${tool.id}" data-testid="tool-${tool.id}">
          <kbd>${tool.key}</kbd><span>${tool.label}</span>
        </button>`).join('')}
      </div>
      <p class="editor-help">Enemy Area draws a camp on the map. Amber is the stay perimeter; cyan is the pursue perimeter. Click an existing camp to move it, or edit its rules below.</p>
    </section>
    <section class="editor-section editor-enemy-area-section">
      <div class="editor-section-title"><span>02</span><h2>Enemy Areas</h2></div>
      <label class="editor-area-shape-field">New area shape<select data-enemy-area-shape>
        <option value="rectangle">Rectangle</option>
        <option value="circle">Circle</option>
      </select></label>
      <div class="editor-area-actions">
        <strong data-enemy-area-count>0 authored camps</strong>
        <button type="button" data-command="monster-settings" data-testid="monster-settings-button">Map defaults</button>
        <button type="button" data-command="edit-enemy-area" data-testid="edit-enemy-area-button">Edit selected</button>
      </div>
      <p class="editor-help">Each camp gets its own monster roster, respawn cooldown, and population cap. Enemies return to amber when the player leaves cyan.</p>
    </section>
    <section class="editor-section">
      <div class="editor-section-title"><span>03</span><h2>Direction</h2></div>
      <div class="editor-direction-grid">
        ${['north', 'east', 'south', 'west'].map((direction) => (
          `<button type="button" data-direction="${direction}">${direction}</button>`
        )).join('')}
      </div>
      <p class="editor-help">Used by entry and exit tools.</p>
    </section>
    <section class="editor-section editor-connections-section">
      <div class="editor-section-title"><span>04</span><h2>Map Connections</h2></div>
      <div class="editor-connections-grid">
        ${MAP_DIRECTIONS.map((direction) => `<label data-connection-label="${direction}">
          <span>${direction}</span>
          <select data-connection-direction="${direction}" aria-label="${titleFromId(direction)} connected map">
            <option value="">Not connected</option>
            ${mapIds
              .filter((mapId) => mapId !== editor.value.map.mapId)
              .map((mapId) => `<option value="${mapId}">${titleFromId(mapId)}</option>`)
              .join('')}
          </select>
        </label>`).join('')}
      </div>
      <p class="editor-help">Connections are two-way. Saving also creates the matching entry and return exit in the linked map.</p>
    </section>
    <section class="editor-section editor-palette-section">
      <div class="editor-section-title"><span>05</span><h2>Terrain Content</h2></div>
      <div class="editor-palette" data-editor-terrain>${tileButtons}</div>
    </section>
    <section class="editor-section editor-palette-section">
      <div class="editor-section-title"><span>06</span><h2>Object Content</h2></div>
      <div class="editor-palette" data-editor-objects>${objectButtons}</div>
    </section>
    <footer class="editor-status" aria-live="polite">
      <span class="editor-status-light"></span>
      <div><strong data-editor-status>Ready</strong><small data-editor-selection>No object selected</small></div>
    </footer>
    <dialog class="editor-new-map-dialog" data-new-map-dialog>
      <form data-new-map-form>
        <header><p>New authored document</p><h2>Survey a new map</h2></header>
        <label>Map ID<input name="mapId" required pattern="[a-z0-9]+(-[a-z0-9]+)*" placeholder="misty-highlands" /></label>
        <div class="editor-new-map-grid">
          <label>Columns<input name="columns" type="number" min="1" max="256" value="54" required /></label>
          <label>Rows<input name="rows" type="number" min="1" max="256" value="54" required /></label>
          <label>Tile size<input name="tileSize" type="number" min="16" max="256" step="8" value="64" required /></label>
        </div>
        <label>Base terrain<select name="tileId" required>
          ${getTileIds().map((tileId) => `<option value="${tileId}">${titleFromId(tileId)}</option>`).join('')}
        </select></label>
        <p class="editor-new-map-error" data-new-map-error></p>
        <footer>
          <button type="button" data-command="cancel-new-map">Cancel</button>
          <button class="editor-create-map" type="submit">Create map</button>
        </footer>
      </form>
    </dialog>
    <dialog class="editor-new-map-dialog editor-monster-dialog editor-enemy-area-dialog" data-enemy-area-dialog>
      <form data-enemy-area-form>
        <header><p>Enemy camp authoring</p><h2>Edit enemy area</h2></header>
        <label>Area ID<input name="id" readonly /></label>
        <label>Shape<select name="shape">
          <option value="rectangle">Rectangle</option>
          <option value="circle">Circle</option>
        </select></label>
        <div class="editor-area-perimeter-grid" data-area-rectangle-fields>
          <fieldset><legend>Stay perimeter / amber</legend>
            <label>X<input name="stayX" type="number" step="1" /></label>
            <label>Y<input name="stayY" type="number" step="1" /></label>
            <label>Width<input name="stayW" type="number" min="1" step="1" /></label>
            <label>Height<input name="stayH" type="number" min="1" step="1" /></label>
          </fieldset>
          <fieldset><legend>Pursue perimeter / cyan</legend>
            <label>X<input name="pursueX" type="number" step="1" /></label>
            <label>Y<input name="pursueY" type="number" step="1" /></label>
            <label>Width<input name="pursueW" type="number" min="1" step="1" /></label>
            <label>Height<input name="pursueH" type="number" min="1" step="1" /></label>
          </fieldset>
        </div>
        <div class="editor-area-perimeter-grid" data-area-circle-fields>
          <fieldset><legend>Stay perimeter / amber</legend>
            <label>Center X<input name="stayCX" type="number" step="1" /></label>
            <label>Center Y<input name="stayCY" type="number" step="1" /></label>
            <label>Radius<input name="stayR" type="number" min="1" step="1" /></label>
          </fieldset>
          <fieldset><legend>Pursue perimeter / cyan</legend>
            <label>Center X<input name="pursueCX" type="number" step="1" /></label>
            <label>Center Y<input name="pursueCY" type="number" step="1" /></label>
            <label>Radius<input name="pursueR" type="number" min="1" step="1" /></label>
          </fieldset>
        </div>
        <div class="editor-monster-list" aria-label="Enemy area roster">
          ${enemyTypes.map((type) => `<div class="editor-monster-row" data-area-enemy-row="${type}">
            <label><input name="area-enemy-${type}" type="checkbox" /><strong>${titleFromId(type)}</strong></label>
            <label>Weight<input name="area-weight-${type}" type="number" min="1" max="1000" step="1" value="10" /></label>
            <label>Max alive<input name="area-max-${type}" type="number" min="1" max="100" step="1" placeholder="Any" /></label>
          </div>`).join('')}
        </div>
        <div class="editor-monster-rules">
          <label>Respawn cooldown (ms)<input name="intervalMs" type="number" min="100" step="1" value="1500" required /></label>
          <label>Population cap<input name="maxPopulation" type="number" min="1" step="1" value="8" required /></label>
        </div>
        <p class="editor-new-map-error" data-enemy-area-error></p>
        <footer>
          <button type="button" data-command="cancel-enemy-area">Cancel</button>
          <button class="editor-create-map" type="submit">Apply area rules</button>
        </footer>
      </form>
    </dialog>
    <dialog class="editor-new-map-dialog editor-monster-dialog" data-monster-dialog>
      <form data-monster-form>
        <header><p>Encounter rules</p><h2>Monster spawning</h2></header>
        <label class="editor-monster-toggle">
          <input name="enabled" type="checkbox" />
          <span><strong>Enable monster spawning</strong><small>Safe zones remain available when spawning is disabled.</small></span>
        </label>
        <div class="editor-monster-list" aria-label="Monster spawn table">
          ${enemyTypes.map((type) => `<div class="editor-monster-row" data-enemy-row="${type}">
            <label><input name="enemy-${type}" type="checkbox" /><strong>${titleFromId(type)}</strong></label>
            <label>Weight<input name="weight-${type}" type="number" min="1" max="1000" value="10" /></label>
            <label>Max alive<input name="max-${type}" type="number" min="1" max="100" placeholder="Any" /></label>
          </div>`).join('')}
        </div>
        <div class="editor-monster-rules">
          <label>Min distance<input name="radiusMin" type="number" min="0" value="200" required /></label>
          <label>Max distance<input name="radiusMax" type="number" min="1" value="500" required /></label>
          <label>Interval (ms)<input name="intervalMs" type="number" min="100" value="1500" required /></label>
          <label>Population cap<input name="maxPopulation" type="number" min="1" value="16" required /></label>
        </div>
        <p class="editor-new-map-error" data-monster-error></p>
        <footer>
          <button type="button" data-command="cancel-monsters">Cancel</button>
          <button class="editor-create-map" type="submit">Apply monster rules</button>
        </footer>
      </form>
    </dialog>
  `;

  const mapSelect = host.querySelector<HTMLSelectElement>('#editor-map-select');
  const newMapDialog = host.querySelector<HTMLDialogElement>('[data-new-map-dialog]');
  const newMapForm = host.querySelector<HTMLFormElement>('[data-new-map-form]');
  const enemyAreaDialog = host.querySelector<HTMLDialogElement>('[data-enemy-area-dialog]');
  const enemyAreaForm = host.querySelector<HTMLFormElement>('[data-enemy-area-form]');
  const enemyAreaShape = host.querySelector<HTMLSelectElement>('[data-enemy-area-shape]');
  const monsterDialog = host.querySelector<HTMLDialogElement>('[data-monster-dialog]');
  const monsterForm = host.querySelector<HTMLFormElement>('[data-monster-form]');
  if (mapSelect) mapSelect.value = editor.value.map.mapId;

  const clickHandler = (event: MouseEvent): void => {
    const target = (event.target as HTMLElement).closest<HTMLElement>('button');
    if (!target) return;
    const tool = target.dataset.tool as EditorTool | undefined;
    if (tool) editor.setTool(tool);
    if (target.dataset.tile) editor.setTile(target.dataset.tile as Parameters<typeof editor.setTile>[0]);
    if (target.dataset.object && target.dataset.visual) {
      const objectId = target.dataset.object as Parameters<typeof editor.setObject>[0];
      const visualId = target.dataset.visual;
      if (!templateEditor.select(objectId, visualId)) {
        if (!window.confirm('Discard the unsaved template draft and select another template?')) return;
        templateEditor.discardAndSelect(objectId, visualId);
      }
      editor.setObject(objectId, visualId);
    }
    if (target.dataset.direction) editor.setDirection(target.dataset.direction as Parameters<typeof editor.setDirection>[0]);
    if (target.dataset.command === 'undo') editor.undo();
    if (target.dataset.command === 'redo') editor.redo();
    if (target.dataset.command === 'save') void editor.save();
    if (target.dataset.command === 'new-map') newMapDialog?.showModal();
    if (target.dataset.command === 'cancel-new-map') newMapDialog?.close();
    if (target.dataset.command === 'edit-enemy-area') {
      if (!editor.value.selectedEnemyAreaId) {
        editor.notify('Select an enemy area first');
      } else {
        populateEnemyAreaForm();
        enemyAreaDialog?.showModal();
      }
    }
    if (target.dataset.command === 'cancel-enemy-area') enemyAreaDialog?.close();
    if (target.dataset.command === 'monster-settings') {
      populateMonsterForm();
      monsterDialog?.showModal();
    }
    if (target.dataset.command === 'cancel-monsters') monsterDialog?.close();
  };
  host.addEventListener('click', clickHandler);

  const changeHandler = (): void => {
    const mapId = mapSelect?.value;
    if (mapId && mapId !== editor.value.map.mapId) window.location.assign(`?editor=${encodeURIComponent(mapId)}`);
  };
  mapSelect?.addEventListener('change', changeHandler);

  enemyAreaShape?.addEventListener('change', () => {
    editor.setEnemyAreaShape(enemyAreaShape.value as MapEnemyAreaShape);
  });

  const connectionChangeHandler = (event: Event): void => {
    const select = (event.target as HTMLElement).closest<HTMLSelectElement>('[data-connection-direction]');
    if (!select) return;
    editor.setConnection(
      select.dataset.connectionDirection as Parameters<typeof editor.setConnection>[0],
      select.value || undefined,
    );
  };
  host.addEventListener('change', connectionChangeHandler);

  const createMapHandler = async (event: SubmitEvent): Promise<void> => {
    event.preventDefault();
    if (!newMapForm) return;
    const submit = newMapForm.querySelector<HTMLButtonElement>('[type="submit"]');
    const error = newMapForm.querySelector<HTMLElement>('[data-new-map-error]');
    const values = new FormData(newMapForm);
    if (submit) submit.disabled = true;
    if (error) error.textContent = '';
    try {
      const response = await fetch('/__map-editor/create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mapId: values.get('mapId'),
          columns: Number(values.get('columns')),
          rows: Number(values.get('rows')),
          tileSize: Number(values.get('tileSize')),
          tileId: values.get('tileId'),
        }),
      });
      const result = await response.json() as { ok?: boolean; error?: string; mapId?: string };
      if (!response.ok || !result.ok || !result.mapId) throw new Error(result.error ?? 'Map creation failed');
      window.location.assign(`?editor=${encodeURIComponent(result.mapId)}`);
    } catch (cause) {
      if (error) error.textContent = cause instanceof Error ? cause.message : String(cause);
      if (submit) submit.disabled = false;
    }
  };
  newMapForm?.addEventListener('submit', createMapHandler);

  const setInputValue = (name: string, value: number | string): void => {
    const input = enemyAreaForm?.elements.namedItem(name) as HTMLInputElement | HTMLSelectElement | null;
    if (input) input.value = String(typeof value === 'number' ? Math.round(value) : value);
  };

  const setPerimeterFormValues = (prefix: 'stay' | 'pursue', perimeter: MapEnemyAreaPerimeter): void => {
    if (perimeter.shape === 'circle') {
      setInputValue(`${prefix}CX`, perimeter.x);
      setInputValue(`${prefix}CY`, perimeter.y);
      setInputValue(`${prefix}R`, perimeter.radius);
      return;
    }
    setInputValue(`${prefix}X`, perimeter.x);
    setInputValue(`${prefix}Y`, perimeter.y);
    setInputValue(`${prefix}W`, perimeter.w);
    setInputValue(`${prefix}H`, perimeter.h);
  };

  const syncEnemyAreaShapeFields = (shape: MapEnemyAreaShape): void => {
    enemyAreaForm?.querySelector<HTMLElement>('[data-area-rectangle-fields]')?.classList.toggle('is-hidden', shape !== 'rectangle');
    enemyAreaForm?.querySelector<HTMLElement>('[data-area-circle-fields]')?.classList.toggle('is-hidden', shape !== 'circle');
  };

  const populateEnemyAreaForm = (): void => {
    if (!enemyAreaForm) return;
    const area = editor.value.map.enemySpawnAreas.find((candidate) => candidate.id === editor.value.selectedEnemyAreaId);
    if (!area) return;
    const shape = area.stayPerimeter.shape;
    const shapeInput = enemyAreaForm.elements.namedItem('shape') as HTMLSelectElement | null;
    if (shapeInput) shapeInput.value = shape;
    setInputValue('id', area.id);
    setPerimeterFormValues('stay', area.stayPerimeter);
    setPerimeterFormValues('pursue', area.pursuePerimeter);
    const configured = new Map(area.enemies.map((enemy) => [enemy.type, enemy]));
    for (const type of enemyTypes) {
      const entry = configured.get(type);
      const checked = enemyAreaForm.elements.namedItem(`area-enemy-${type}`) as HTMLInputElement | null;
      const weight = enemyAreaForm.elements.namedItem(`area-weight-${type}`) as HTMLInputElement | null;
      const maxAlive = enemyAreaForm.elements.namedItem(`area-max-${type}`) as HTMLInputElement | null;
      if (checked) checked.checked = entry !== undefined;
      if (weight) weight.value = String(Math.round(entry?.weight ?? 10));
      if (maxAlive) maxAlive.value = entry?.maxAlive === undefined ? '' : String(Math.round(entry.maxAlive));
    }
    setInputValue('intervalMs', area.intervalMs);
    setInputValue('maxPopulation', area.maxPopulation);
    const error = enemyAreaForm.querySelector<HTMLElement>('[data-enemy-area-error]');
    if (error) error.textContent = '';
    syncEnemyAreaShapeFields(shape);
  };

  const enemyAreaShapeChangeHandler = (): void => {
    const shape = (enemyAreaForm?.elements.namedItem('shape') as HTMLSelectElement | null)?.value as MapEnemyAreaShape | undefined;
    if (shape) syncEnemyAreaShapeFields(shape);
  };
  const enemyAreaShapeField = enemyAreaForm?.elements.namedItem('shape') as HTMLSelectElement | null;
  enemyAreaShapeField?.addEventListener('change', enemyAreaShapeChangeHandler);

  const readNumber = (values: FormData, name: string): number => Math.round(Number(values.get(name)));
  const readEnemyAreaPerimeter = (values: FormData, prefix: 'stay' | 'pursue', shape: MapEnemyAreaShape): MapEnemyAreaPerimeter => (
    shape === 'circle'
      ? { shape, x: readNumber(values, `${prefix}CX`), y: readNumber(values, `${prefix}CY`), radius: readNumber(values, `${prefix}R`) }
      : { shape, x: readNumber(values, `${prefix}X`), y: readNumber(values, `${prefix}Y`), w: readNumber(values, `${prefix}W`), h: readNumber(values, `${prefix}H`) }
  );

  const enemyAreaSubmitHandler = (event: SubmitEvent): void => {
    event.preventDefault();
    if (!enemyAreaForm) return;
    const areaId = editor.value.selectedEnemyAreaId;
    const current = editor.value.map.enemySpawnAreas.find((area) => area.id === areaId);
    if (!areaId || !current) return;
    const values = new FormData(enemyAreaForm);
    const error = enemyAreaForm.querySelector<HTMLElement>('[data-enemy-area-error]');
    const shape = values.get('shape') as MapEnemyAreaShape;
    const enemies = enemyTypes.flatMap((type) => {
      if (values.get(`area-enemy-${type}`) !== 'on') return [];
      const maxAlive = readNumber(values, `area-max-${type}`);
      return [{
        type,
        weight: readNumber(values, `area-weight-${type}`),
        ...(maxAlive > 0 ? { maxAlive } : {}),
      }];
    });
    if (enemies.length === 0) {
      if (error) error.textContent = 'Select at least one enemy type.';
      return;
    }
    const stayPerimeter = readEnemyAreaPerimeter(values, 'stay', shape);
    const pursuePerimeter = readEnemyAreaPerimeter(values, 'pursue', shape);
    if (shape === 'circle') {
      if (stayPerimeter.shape !== 'circle' || pursuePerimeter.shape !== 'circle'
        || stayPerimeter.radius <= 0 || pursuePerimeter.radius <= 0
        || Math.hypot(stayPerimeter.x - pursuePerimeter.x, stayPerimeter.y - pursuePerimeter.y) + stayPerimeter.radius > pursuePerimeter.radius) {
        if (error) error.textContent = 'The cyan pursue circle must contain the amber stay circle.';
        return;
      }
    } else if (stayPerimeter.shape !== 'rectangle' || pursuePerimeter.shape !== 'rectangle'
      || stayPerimeter.w <= 0 || stayPerimeter.h <= 0 || pursuePerimeter.w <= 0 || pursuePerimeter.h <= 0
      || stayPerimeter.x < pursuePerimeter.x || stayPerimeter.y < pursuePerimeter.y
      || stayPerimeter.x + stayPerimeter.w > pursuePerimeter.x + pursuePerimeter.w
      || stayPerimeter.y + stayPerimeter.h > pursuePerimeter.y + pursuePerimeter.h) {
      if (error) error.textContent = 'The cyan pursue rectangle must contain the amber stay rectangle.';
      return;
    }
    editor.updateEnemySpawnArea(areaId, {
      id: current.id,
      stayPerimeter,
      pursuePerimeter,
      enemies,
      intervalMs: readNumber(values, 'intervalMs'),
      maxPopulation: readNumber(values, 'maxPopulation'),
    });
    enemyAreaDialog?.close();
  };
  enemyAreaForm?.addEventListener('submit', enemyAreaSubmitHandler);

  const populateMonsterForm = (): void => {
    if (!monsterForm) return;
    const spawns = editor.value.map.spawns;
    const defaults = new Map([
      ['worm-brawler', { weight: 50 }],
      ['worm-swordsman', { weight: 30 }],
      ['worm-archer', { weight: 20 }],
    ]);
    const configured = new Map((spawns?.enemies ?? []).map((enemy) => [enemy.type, enemy]));
    const enabled = monsterForm.elements.namedItem('enabled') as HTMLInputElement | null;
    if (enabled) enabled.checked = spawns !== undefined;
    for (const type of enemyTypes) {
      const entry = configured.get(type) ?? (!spawns ? defaults.get(type) : undefined);
      const checked = monsterForm.elements.namedItem(`enemy-${type}`) as HTMLInputElement | null;
      const weight = monsterForm.elements.namedItem(`weight-${type}`) as HTMLInputElement | null;
      const maxAlive = monsterForm.elements.namedItem(`max-${type}`) as HTMLInputElement | null;
      const entryMaxAlive = entry && 'maxAlive' in entry ? entry.maxAlive : undefined;
      if (checked) checked.checked = entry !== undefined;
      if (weight) weight.value = String(entry?.weight ?? 10);
      if (maxAlive) maxAlive.value = entryMaxAlive === undefined ? '' : String(entryMaxAlive);
    }
    const values: Array<[string, number]> = [
      ['radiusMin', spawns?.radius.min ?? 200],
      ['radiusMax', spawns?.radius.max ?? 500],
      ['intervalMs', spawns?.intervalMs ?? 1500],
      ['maxPopulation', spawns?.maxPopulation ?? 16],
    ];
    for (const [name, value] of values) {
      const input = monsterForm.elements.namedItem(name) as HTMLInputElement | null;
      if (input) input.value = String(value);
    }
    const error = monsterForm.querySelector<HTMLElement>('[data-monster-error]');
    if (error) error.textContent = '';
  };

  const monsterSubmitHandler = (event: SubmitEvent): void => {
    event.preventDefault();
    if (!monsterForm) return;
    const values = new FormData(monsterForm);
    const error = monsterForm.querySelector<HTMLElement>('[data-monster-error]');
    if (values.get('enabled') !== 'on') {
      editor.setSpawns(undefined);
      monsterDialog?.close();
      return;
    }
    const enemies = enemyTypes.flatMap((type) => {
      if (values.get(`enemy-${type}`) !== 'on') return [];
      const maxAlive = Number(values.get(`max-${type}`));
      return [{
        type,
        weight: Number(values.get(`weight-${type}`)),
        ...(maxAlive > 0 ? { maxAlive } : {}),
      }];
    });
    const radiusMin = Number(values.get('radiusMin'));
    const radiusMax = Number(values.get('radiusMax'));
    if (enemies.length === 0) {
      if (error) error.textContent = 'Select at least one monster type.';
      return;
    }
    if (radiusMin < 0 || radiusMax <= radiusMin) {
      if (error) error.textContent = 'Maximum distance must be greater than minimum distance.';
      return;
    }
    editor.setSpawns({
      enemies,
      radius: { min: radiusMin, max: radiusMax },
      intervalMs: Number(values.get('intervalMs')),
      maxPopulation: Number(values.get('maxPopulation')),
      safeZones: [],
    });
    monsterDialog?.close();
  };
  monsterForm?.addEventListener('submit', monsterSubmitHandler);

  const beforeUnloadHandler = (event: BeforeUnloadEvent): void => {
    if (!editor.value.dirty && !templateEditor.value.dirty) return;
    event.preventDefault();
  };
  window.addEventListener('beforeunload', beforeUnloadHandler);

  const unsubscribe = editor.subscribe((state) => {
    host.querySelectorAll<HTMLElement>('[data-tool]').forEach((button) => {
      button.classList.toggle('is-active', button.dataset.tool === state.tool);
    });
    const shapeSelect = host.querySelector<HTMLSelectElement>('[data-enemy-area-shape]');
    if (shapeSelect) shapeSelect.value = state.enemyAreaShape;
    const areaCount = host.querySelector<HTMLElement>('[data-enemy-area-count]');
    if (areaCount) {
      const count = state.map.enemySpawnAreas.length;
      areaCount.textContent = `${count} authored camp${count === 1 ? '' : 's'}`;
    }
    const editArea = host.querySelector<HTMLButtonElement>('[data-command="edit-enemy-area"]');
    if (editArea) editArea.disabled = !state.selectedEnemyAreaId;
    host.querySelectorAll<HTMLElement>('[data-tile]').forEach((button) => {
      button.classList.toggle('is-active', button.dataset.tile === state.tileId);
    });
    host.querySelectorAll<HTMLElement>('[data-object]').forEach((button) => {
      button.classList.toggle(
        'is-active',
        button.dataset.object === state.objectId && button.dataset.visual === state.objectVisualId,
      );
    });
    host.querySelectorAll<HTMLElement>('[data-direction]').forEach((button) => {
      button.classList.toggle('is-active', button.dataset.direction === state.direction);
    });
    host.querySelectorAll<HTMLSelectElement>('[data-connection-direction]').forEach((select) => {
      const direction = select.dataset.connectionDirection as Parameters<typeof connectionAt>[0];
      select.value = connectionAt(direction, state.map)?.to ?? '';
      select.closest('label')?.classList.toggle('is-connected', select.value !== '');
    });
    const undo = host.querySelector<HTMLButtonElement>('[data-command="undo"]');
    const redo = host.querySelector<HTMLButtonElement>('[data-command="redo"]');
    const save = host.querySelector<HTMLButtonElement>('[data-command="save"]');
    if (undo) undo.disabled = !state.canUndo;
    if (redo) redo.disabled = !state.canRedo;
    if (save) save.disabled = state.saving || !state.dirty;
    const dirty = host.querySelector<HTMLElement>('[data-editor-dirty]');
    if (dirty) {
      dirty.textContent = state.dirty ? 'Unsaved' : 'Saved';
      dirty.classList.toggle('is-dirty', state.dirty);
    }
    const status = host.querySelector<HTMLElement>('[data-editor-status]');
    if (status) status.textContent = state.status;
    const selection = host.querySelector<HTMLElement>('[data-editor-selection]');
    if (selection) {
      const safeZoneCount = state.map.enemySafeZones.length;
      selection.textContent = state.selectedInstanceId
        ?? (state.selectedSafeZoneIndex !== undefined ? `Safe zone ${state.selectedSafeZoneIndex + 1} selected` : undefined)
        ?? (state.selectedEnemyAreaId ? `Enemy area ${state.selectedEnemyAreaId} selected` : undefined)
        ?? `${state.map.objects.length} objects / ${safeZoneCount} safe zones / ${state.map.enemySpawnAreas.length} enemy areas / ${state.map.size.columns}x${state.map.size.rows}`;
    }
  });

  const unsubscribeTemplate = templateEditor.subscribe((state) => {
    host.querySelectorAll<HTMLElement>('[data-object]').forEach((button) => {
      button.classList.toggle(
        'is-template-active',
        button.dataset.object === state.selected?.objectId && button.dataset.visual === state.selected?.visualId,
      );
    });
  });

  return () => {
    unsubscribe();
    unsubscribeTemplate();
    host.removeEventListener('click', clickHandler);
    mapSelect?.removeEventListener('change', changeHandler);
    host.removeEventListener('change', connectionChangeHandler);
    newMapForm?.removeEventListener('submit', createMapHandler);
    enemyAreaForm?.removeEventListener('submit', enemyAreaSubmitHandler);
    enemyAreaShapeField?.removeEventListener('change', enemyAreaShapeChangeHandler);
    monsterForm?.removeEventListener('submit', monsterSubmitHandler);
    window.removeEventListener('beforeunload', beforeUnloadHandler);
    host.innerHTML = '';
  };
}
