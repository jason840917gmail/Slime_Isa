import './character-studio.css';

import type { WeaponDefinition } from '../content/weapons/types';

interface WeaponCatalogEntry extends WeaponDefinition {
  readonly revision: string;
}

interface WeaponCatalogResponse {
  readonly version: 1;
  readonly revision: string;
  readonly weapons: readonly WeaponCatalogEntry[];
}

interface WeaponStudioState {
  readonly weapons: readonly WeaponCatalogEntry[];
  readonly selectedId: string;
  readonly draft?: WeaponDefinition;
  readonly revision?: string;
  readonly dirty: boolean;
  readonly saving: boolean;
  readonly notice?: string;
}

interface MutableWeaponScalingGroup {
  strength?: number;
  vitality?: number;
  agility?: number;
  intellect?: number;
}

interface MutableWeaponScaling {
  damage?: MutableWeaponScalingGroup;
  cooldown?: MutableWeaponScalingGroup;
  knockback?: MutableWeaponScalingGroup;
  reach?: MutableWeaponScalingGroup;
}

type Mutable<T> = { -readonly [Key in keyof T]: T[Key] };
type MutableWeaponDraft = Omit<Mutable<WeaponDefinition>, 'scaling'> & { scaling?: MutableWeaponScaling };

function escapeHtml(value: unknown): string {
  return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function field(label: string, path: string, value: unknown, unit: string, step = '0.01'): string {
  return `<label class="studio-field"><span>${label}<small>${unit}</small></span><input type="number" step="${step}" value="${escapeHtml(value)}" data-weapon-field="${path}" /></label>`;
}

function makeNewWeapon(): WeaponDefinition {
  return {
    version: 1,
    weaponId: 'new-weapon',
    displayName: 'New Weapon',
    category: 'melee',
    animKey: 'attack-1',
    baseDamage: 10,
    cooldownMs: 500,
    hitboxWidth: 32,
    hitboxHeight: 18,
    hitboxOffset: 24,
    hitboxDurationMs: 120,
    knockStrength: 120,
    scaling: { damage: { strength: 0.5 }, cooldown: { agility: 0.25 }, knockback: { strength: 0.25 } },
    vfxColor: 0x86f0c3,
    unlockLevel: 1,
    iconKey: 'weapon-generic',
    description: 'A reusable weapon definition.',
  };
}

function renderStudio(state: WeaponStudioState, returnEditor: string): string {
  const weapon = state.draft;
  const scaling = weapon?.scaling ?? {};
  return `<main class="character-studio weapon-studio" data-weapon-studio>
    <header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>WEAPON STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state${state.notice ? ' is-error' : ''}"><i></i>${escapeHtml(state.notice ?? (state.dirty ? 'Unsaved weapon' : 'Saved library'))}</span><button type="button" class="studio-button studio-button--save" data-action="save-weapon" ${!weapon || !state.dirty || state.saving ? 'disabled' : ''}>${state.saving ? 'SAVING…' : 'SAVE WEAPON'}</button></div></header>
    <div class="studio-layout"><aside class="studio-library"><div class="studio-panel-title"><div><span class="studio-kicker">Equipment library</span><h1>Weapons</h1></div><span class="studio-count">${String(state.weapons.length).padStart(2, '0')}</span></div><div class="studio-roster">${state.weapons.map((entry) => `<button type="button" class="studio-roster-item${entry.weaponId === state.selectedId ? ' is-active' : ''}" data-weapon-id="${escapeHtml(entry.weaponId)}"><span class="roster-glyph player">◆</span><span><strong>${escapeHtml(entry.displayName)}</strong><small>${entry.category.toUpperCase()} · ${escapeHtml(entry.weaponId)}</small></span><em>${entry.weaponId === state.selectedId ? 'OPEN' : ''}</em></button>`).join('')}</div><div class="studio-library-footer"><button type="button" class="studio-button studio-button--outline studio-button--create" data-action="new-weapon">NEW WEAPON</button><a class="studio-button studio-button--outline studio-button--navigation" href="?studio=characters&editor=${encodeURIComponent(returnEditor)}">↗ CHARACTER STUDIO</a></div></aside>
      <section class="studio-workbench">${weapon ? `<div class="studio-workbench-heading"><div><span class="studio-kicker">Reusable combat definition</span><h2>${escapeHtml(weapon.displayName)}</h2></div><div class="studio-workbench-meta"><span>WEAPON <b>${escapeHtml(weapon.weaponId)}</b></span><span>CATEGORY <b>${weapon.category.toUpperCase()}</b></span><span>BASE DAMAGE <b>${weapon.baseDamage}</b></span></div></div><section class="studio-inspector weapon-inspector"><div class="studio-inspector-scroll"><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Identity</span><strong>Equipment profile</strong></div><div class="studio-field-grid"><label class="studio-field"><span>Stable ID<small>lowercase</small></span><input type="text" value="${escapeHtml(weapon.weaponId)}" data-weapon-field="weaponId" /></label><label class="studio-field"><span>Display name<small>library label</small></span><input type="text" value="${escapeHtml(weapon.displayName)}" data-weapon-field="displayName" /></label></div><div class="studio-field-grid"><label class="studio-field"><span>Category<small>combat family</small></span><select data-weapon-field="category"><option value="melee" ${weapon.category === 'melee' ? 'selected' : ''}>Melee</option><option value="ranged" ${weapon.category === 'ranged' ? 'selected' : ''}>Ranged</option></select></label><label class="studio-field"><span>Character action<small>animation key</small></span><input type="text" value="${escapeHtml(weapon.animKey)}" data-weapon-field="animKey" /></label></div><label class="studio-field studio-field--wide"><span>Description<small>authoring note</small></span><input type="text" value="${escapeHtml(weapon.description)}" data-weapon-field="description" /></label></section><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Combat profile</span><strong>Base behavior</strong></div><div class="studio-field-grid">${field('Base damage', 'baseDamage', weapon.baseDamage, 'points')}${field('Cooldown', 'cooldownMs', weapon.cooldownMs, 'milliseconds')}${field('Hitbox width', 'hitboxWidth', weapon.hitboxWidth, 'world units')}${field('Hitbox height', 'hitboxHeight', weapon.hitboxHeight, 'world units')}${field('Hitbox offset', 'hitboxOffset', weapon.hitboxOffset, 'world units')}${field('Active duration', 'hitboxDurationMs', weapon.hitboxDurationMs, 'milliseconds')}${field('Knockback', 'knockStrength', weapon.knockStrength, 'world units/s')}${field('Unlock level', 'unlockLevel', weapon.unlockLevel, 'level', '1')}</div></section><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Attribute scaling</span><strong>Final value modifiers</strong></div><p class="studio-help">Coefficients resolve around attribute 10. Movement speed is intentionally not part of weapon scaling.</p><div class="studio-subheading">Damage</div><div class="studio-field-grid">${field('Strength', 'scaling.damage.strength', scaling.damage?.strength ?? 0, 'coefficient')}${field('Agility', 'scaling.damage.agility', scaling.damage?.agility ?? 0, 'coefficient')}${field('Intellect', 'scaling.damage.intellect', scaling.damage?.intellect ?? 0, 'coefficient')}</div><div class="studio-subheading">Cooldown</div><div class="studio-field-grid">${field('Agility', 'scaling.cooldown.agility', scaling.cooldown?.agility ?? 0, 'coefficient')}</div><div class="studio-subheading">Knockback</div><div class="studio-field-grid">${field('Strength', 'scaling.knockback.strength', scaling.knockback?.strength ?? 0, 'coefficient')}</div></section><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Presentation</span><strong>Weapon layer foundation</strong></div><p class="studio-help">Weapon art will render as a separate layer attached to the character. This keeps one character compatible with many weapons.</p><div class="studio-callout"><strong>Character action: ${escapeHtml(weapon.animKey)}</strong><span>Next layer: import weapon art, define attachment offsets, and author the weapon timeline independently.</span></div></section></div></section>` : '<section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>Select or create a weapon</h2><p>Weapons are reusable definitions. Characters and loadouts select them without duplicating character art.</p></section>'}</section></div>
  </main>`;
}

async function loadCatalog(): Promise<WeaponCatalogResponse> {
  const response = await fetch('/__character-studio/weapons');
  const payload = await response.json() as { ok: boolean; data?: WeaponCatalogResponse; error?: { message?: string } };
  if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Weapon catalog failed to load');
  return payload.data;
}

export function mountWeaponStudio(container: HTMLDivElement): () => void {
  container.classList.add('is-character-studio-host');
  const returnEditor = new URLSearchParams(window.location.search).get('editor') ?? 'meadow-crossing';
  let state: WeaponStudioState = { weapons: [], selectedId: '', dirty: false, saving: false };
  const render = (): void => { container.innerHTML = renderStudio(state, returnEditor); };
  const select = (weapon: WeaponDefinition, revision?: string): void => { state = { ...state, selectedId: weapon.weaponId, draft: clone(weapon), revision, dirty: false, notice: undefined }; render(); };
  const load = async (): Promise<void> => {
    try {
      const catalog = await loadCatalog();
      state = { ...state, weapons: catalog.weapons, selectedId: catalog.weapons[0]?.weaponId ?? '' };
      if (catalog.weapons[0]) select(catalog.weapons[0], catalog.weapons[0].revision); else render();
    } catch (error) { state = { ...state, notice: error instanceof Error ? error.message : String(error) }; render(); }
  };
  const updateDraft = (path: string, rawValue: string): void => {
    if (!state.draft) return;
    const draft = clone(state.draft) as MutableWeaponDraft;
    const numericPaths = new Set(['baseDamage', 'cooldownMs', 'hitboxWidth', 'hitboxHeight', 'hitboxOffset', 'hitboxDurationMs', 'knockStrength', 'unlockLevel', 'scaling.damage.strength', 'scaling.damage.agility', 'scaling.damage.intellect', 'scaling.cooldown.agility', 'scaling.knockback.strength']);
    const value = numericPaths.has(path) ? Number(rawValue) : rawValue;
    if (path.startsWith('scaling.')) {
      const [, group, attribute] = path.split('.') as ['', keyof MutableWeaponScaling, keyof MutableWeaponScalingGroup];
      draft.scaling ??= {};
      draft.scaling[group] ??= {};
      draft.scaling[group]![attribute] = Number(value);
    } else if (path === 'weaponId') draft.weaponId = String(value).trim().toLowerCase();
    else if (path === 'displayName') draft.displayName = String(value);
    else if (path === 'category') draft.category = value === 'ranged' ? 'ranged' : 'melee';
    else if (path === 'animKey') draft.animKey = String(value);
    else if (path === 'description') draft.description = String(value);
    else if (path === 'baseDamage') draft.baseDamage = Number(value);
    else if (path === 'cooldownMs') draft.cooldownMs = Number(value);
    else if (path === 'hitboxWidth') draft.hitboxWidth = Number(value);
    else if (path === 'hitboxHeight') draft.hitboxHeight = Number(value);
    else if (path === 'hitboxOffset') draft.hitboxOffset = Number(value);
    else if (path === 'hitboxDurationMs') draft.hitboxDurationMs = Number(value);
    else if (path === 'knockStrength') draft.knockStrength = Number(value);
    else if (path === 'unlockLevel') draft.unlockLevel = Number(value);
    state = { ...state, draft, selectedId: draft.weaponId, dirty: true, notice: undefined };
  };
  const save = async (): Promise<void> => {
    if (!state.draft || !state.dirty) return;
    state = { ...state, saving: true, notice: 'Saving weapon…' }; render();
    const isNew = !state.weapons.some((entry) => entry.weaponId === state.draft?.weaponId);
    try {
      const response = await fetch(`/__character-studio/weapon/${isNew ? 'create' : 'update'}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ weapon: state.draft, ...(isNew ? {} : { expectedRevision: state.revision }) }) });
      const payload = await response.json() as { ok: boolean; data?: { weapon: WeaponDefinition; revision: string }; error?: { message?: string } };
      if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Weapon save failed');
      const next = state.weapons.filter((entry) => entry.weaponId !== payload.data?.weapon.weaponId).concat({ ...payload.data.weapon, revision: payload.data.revision });
      state = { ...state, weapons: next, selectedId: payload.data.weapon.weaponId, draft: clone(payload.data.weapon), revision: payload.data.revision, dirty: false, saving: false, notice: 'Saved weapon' }; render();
    } catch (error) { state = { ...state, saving: false, notice: error instanceof Error ? error.message : String(error) }; render(); }
  };
  const onClick = (event: MouseEvent): void => {
    const target = event.target as HTMLElement;
    const weaponButton = target.closest<HTMLElement>('[data-weapon-id]');
    if (weaponButton) { const weapon = state.weapons.find((entry) => entry.weaponId === weaponButton.dataset.weaponId); if (weapon) select(weapon, weapon.revision); return; }
    const action = target.closest<HTMLElement>('[data-action]')?.dataset.action;
    if (action === 'new-weapon') { select(makeNewWeapon()); return; }
    if (action === 'save-weapon') void save();
  };
  const onInput = (event: Event): void => { const target = event.target as HTMLInputElement | HTMLSelectElement; const path = target.dataset.weaponField; if (!path) return; updateDraft(path, target.value); if (target instanceof HTMLSelectElement) render(); };
  container.addEventListener('click', onClick); container.addEventListener('input', onInput); container.addEventListener('change', onInput); render(); void load();
  return () => { container.removeEventListener('click', onClick); container.removeEventListener('input', onInput); container.removeEventListener('change', onInput); container.classList.remove('is-character-studio-host'); };
}
