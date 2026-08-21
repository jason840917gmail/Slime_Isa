import type { AnimationPackageCatalogEntry } from '../content/animations/types';

export interface StudioWeaponLibraryEntry {
  readonly weaponId: string;
  readonly displayName: string;
  readonly description: string;
  readonly category: string;
  readonly version: number;
}

export interface StudioLibraryTreeOptions {
  readonly weapons: readonly StudioWeaponLibraryEntry[];
  readonly animations: readonly AnimationPackageCatalogEntry[];
  readonly search: string;
  readonly expandedFolders: ReadonlySet<string>;
  readonly selectedWeaponId?: string;
  readonly selectedAnimationId?: string;
  readonly footerHtml: string;
}

interface AnimationFolderNode {
  readonly name: string;
  readonly path: string;
  readonly folders: Map<string, AnimationFolderNode>;
  readonly entries: { readonly label: string; readonly entry: AnimationPackageCatalogEntry }[];
}

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
  })[character] ?? character);
}

function chevronIcon(): string {
  return '<svg class="studio-tree-chevron" viewBox="0 0 12 12" aria-hidden="true"><path d="M4 2.5 8 6l-4 3.5"/></svg>';
}

function folderIcon(): string {
  return '<svg class="studio-tree-folder-icon" viewBox="0 0 18 16" aria-hidden="true"><path class="folder-back" d="M1.5 3.5c0-.8.6-1.5 1.5-1.5h4l1.7 2H15c.8 0 1.5.7 1.5 1.5v7.8c0 .9-.6 1.5-1.5 1.5H3c-.9 0-1.5-.6-1.5-1.5Z"/><path class="folder-front" d="M2 7h14l-1.3 6.4c-.2.8-.7 1.3-1.5 1.3H3c-.8 0-1.4-.6-1.5-1.4Z"/></svg>';
}

function weaponIcon(): string {
  return '<svg class="studio-tree-file-icon studio-tree-file-icon--weapon" viewBox="0 0 16 16" aria-hidden="true"><path d="m11.8 1.7 2.5-.7-.7 2.5-7 7-1.8-1.8Z"/><path d="m4.1 8.8 3.1 3.1M2.2 10.8l3 3M1.4 14.6l3.8-.8-3-3Z"/></svg>';
}

function animationIcon(): string {
  return '<svg class="studio-tree-file-icon studio-tree-file-icon--animation" viewBox="0 0 16 16" aria-hidden="true"><rect x="2" y="2.5" width="12" height="11" rx="1.5"/><path d="M5 2.5v11M11 2.5v11M2 6h3M11 6h3M2 10h3M11 10h3"/><path class="studio-tree-play" d="m7 6 3 2-3 2Z"/></svg>';
}

function createAnimationTree(entries: readonly AnimationPackageCatalogEntry[]): AnimationFolderNode {
  const root: AnimationFolderNode = { name: 'ANIMATIONS', path: 'animations', folders: new Map(), entries: [] };
  for (const entry of entries) {
    const segments = (entry.folderPath || entry.packagePath.replace(/\/animation\.json$/, ''))
      .split('/')
      .filter(Boolean);
    const label = segments.pop() ?? entry.animationId;
    let node = root;
    for (const segment of segments) {
      const path = `${node.path}/${segment}`;
      let child = node.folders.get(segment);
      if (!child) {
        child = { name: segment, path, folders: new Map(), entries: [] };
        node.folders.set(segment, child);
      }
      node = child;
    }
    node.entries.push({ label, entry });
  }
  return root;
}

function folderContainsSelection(node: AnimationFolderNode, selectedAnimationId: string | undefined): boolean {
  if (!selectedAnimationId) return false;
  if (node.entries.some(({ entry }) => entry.animationId === selectedAnimationId)) return true;
  return [...node.folders.values()].some((child) => folderContainsSelection(child, selectedAnimationId));
}

function renderAnimationFolder(
  node: AnimationFolderNode,
  options: StudioLibraryTreeOptions,
  depth: number,
): string {
  const forcedOpen = Boolean(options.search.trim()) || folderContainsSelection(node, options.selectedAnimationId);
  const open = forcedOpen || options.expandedFolders.has(node.path);
  const folders = [...node.folders.values()]
    .sort((left, right) => left.name.localeCompare(right.name))
    .map((child) => renderAnimationFolder(child, options, depth + 1))
    .join('');
  const entries = [...node.entries]
    .sort((left, right) => left.label.localeCompare(right.label))
    .map(({ label, entry }) => `<button type="button" class="studio-tree-item studio-tree-file${entry.animationId === options.selectedAnimationId ? ' is-active' : ''}" style="--tree-depth:${depth + 1}" data-animation-id="${escapeHtml(entry.animationId)}" title="${escapeHtml(entry.displayName)} · ${escapeHtml(entry.animationId)}">${animationIcon()}<span class="studio-tree-file-copy"><strong>${escapeHtml(label)}</strong><small>${escapeHtml(entry.displayName)}</small></span><em>${entry.animation.loop ? 'LOOP' : 'ONCE'}</em></button>`)
    .join('');
  return `<details class="studio-tree-folder" data-library-folder="${escapeHtml(node.path)}" ${open ? 'open' : ''}><summary class="studio-tree-folder-row" style="--tree-depth:${depth}">${chevronIcon()}${folderIcon()}<span>${escapeHtml(node.name)}</span></summary>${folders}${entries}</details>`;
}

function renderWeapons(options: StudioLibraryTreeOptions): string {
  const open = Boolean(options.search.trim()) || options.expandedFolders.has('weapons') || Boolean(options.selectedWeaponId);
  const entries = [...options.weapons]
    .sort((left, right) => left.displayName.localeCompare(right.displayName))
    .map((weapon) => `<button type="button" class="studio-tree-item studio-tree-file${weapon.weaponId === options.selectedWeaponId ? ' is-active' : ''}" style="--tree-depth:1" data-weapon-id="${escapeHtml(weapon.weaponId)}" title="${escapeHtml(weapon.description)}">${weaponIcon()}<span class="studio-tree-file-copy"><strong>${escapeHtml(weapon.displayName)}</strong><small>${escapeHtml(weapon.weaponId)}</small></span><em>V${weapon.version}</em></button>`)
    .join('');
  return `<details class="studio-tree-folder studio-tree-root" data-library-folder="weapons" ${open ? 'open' : ''}><summary class="studio-tree-folder-row studio-library-root-label" style="--tree-depth:0">${chevronIcon()}${folderIcon()}<span>WEAPONS</span></summary>${entries}</details>`;
}

export function renderStudioLibraryTree(options: StudioLibraryTreeOptions): string {
  const search = options.search.trim().toLowerCase();
  const weapons = options.weapons.filter((weapon) => !search || [weapon.weaponId, weapon.displayName, weapon.description]
    .some((value) => value.toLowerCase().includes(search)));
  const animations = options.animations.filter((entry) => !search || [entry.animationId, entry.displayName, entry.description, entry.packagePath]
    .some((value) => value.toLowerCase().includes(search)));
  const filteredOptions = { ...options, weapons, animations };
  return `<aside class="studio-library studio-library--tree"><div class="studio-panel-title"><div><span class="studio-kicker">Shared content</span><h1>Explorer</h1></div><span class="studio-count">${String(weapons.length + animations.length).padStart(2, '0')}</span></div><label class="studio-library-search"><span class="sr-only">Search weapons and animations</span><input type="search" placeholder="Search files…" value="${escapeHtml(options.search)}" data-studio-library-search /></label><div class="studio-roster studio-tree" role="tree">${renderWeapons(filteredOptions)}${renderAnimationFolder(createAnimationTree(animations), filteredOptions, 0)}</div><div class="studio-library-footer">${options.footerHtml}</div></aside>`;
}
