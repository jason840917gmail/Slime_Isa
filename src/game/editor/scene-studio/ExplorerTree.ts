import type { SceneStudioContentSummary } from '../../infrastructure/scenes/editor/SceneStudioRepository';

/**
 * Project explorer tree built from each document's folder under the authored
 * content root. Files named `family--variant.*` are grouped under a family
 * node when a folder holds two or more of them, together with a base file
 * named exactly `family.*`, so large flat folders such as `objects/` stay
 * navigable without moving files on disk.
 */
export interface ExplorerFolder {
  /** Stable key: the folder path, plus `/family` for variant groups. */
  readonly key: string;
  readonly label: string;
  readonly family: boolean;
  readonly folders: readonly ExplorerFolder[];
  readonly items: readonly SceneStudioContentSummary[];
  /** Documents in this folder and every descendant. */
  readonly total: number;
}

interface MutableFolder {
  readonly key: string;
  readonly label: string;
  readonly family: boolean;
  readonly folders: Map<string, MutableFolder>;
  readonly items: SceneStudioContentSummary[];
}

const FAMILY_SEPARATOR = '--';

function fileName(relativePath: string): string {
  return relativePath.slice(relativePath.lastIndexOf('/') + 1);
}

const DOCUMENT_SUFFIX = /\.(?:scene|resource)\.json$/;

function familyName(relativePath: string): string | undefined {
  const name = fileName(relativePath);
  const separator = name.indexOf(FAMILY_SEPARATOR);
  return separator > 0 ? name.slice(0, separator) : undefined;
}

/** File name without the document suffix, e.g. `house-world-solid`. */
function baseName(relativePath: string): string {
  return fileName(relativePath).replace(DOCUMENT_SUFFIX, '');
}

function createFolder(key: string, label: string, family = false): MutableFolder {
  return { key, label, family, folders: new Map(), items: [] };
}

function groupFamilies(folder: MutableFolder): void {
  const families = new Map<string, SceneStudioContentSummary[]>();
  for (const item of folder.items) {
    const family = familyName(item.relativePath);
    if (family === undefined) continue;
    const members = families.get(family);
    if (members) members.push(item); else families.set(family, [item]);
  }
  for (const item of folder.items) {
    if (familyName(item.relativePath) === undefined) families.get(baseName(item.relativePath))?.push(item);
  }
  for (const [family, members] of families) {
    if (members.length < 2) continue;
    // A real subfolder with the same name keeps its key; the family nests inside it.
    const existing = folder.folders.get(family);
    const target = existing ?? createFolder(folder.key ? `${folder.key}/${family}` : family, family, true);
    target.items.push(...members);
    folder.folders.set(family, target);
    const grouped = new Set(members);
    for (let index = folder.items.length - 1; index >= 0; index -= 1) if (grouped.has(folder.items[index])) folder.items.splice(index, 1);
  }
  for (const child of folder.folders.values()) if (!child.family) groupFamilies(child);
}

function freeze(folder: MutableFolder): ExplorerFolder {
  const folders = [...folder.folders.values()].sort((left, right) => left.label.localeCompare(right.label)).map(freeze);
  // A family's base file (named exactly like the family) leads its variants.
  const rank = (item: SceneStudioContentSummary): number => folder.family && baseName(item.relativePath) === folder.label ? 0 : 1;
  const items = [...folder.items].sort((left, right) => rank(left) - rank(right) || fileName(left.relativePath).localeCompare(fileName(right.relativePath)));
  return {
    key: folder.key,
    label: folder.label,
    family: folder.family,
    folders,
    items,
    total: items.length + folders.reduce((sum, child) => sum + child.total, 0),
  };
}

export function buildExplorerTree(items: readonly SceneStudioContentSummary[]): ExplorerFolder {
  const root = createFolder('', '');
  for (const item of items) {
    let folder = root;
    for (const segment of item.relativePath.split('/').slice(0, -1)) {
      let child = folder.folders.get(segment);
      if (!child) {
        child = createFolder(folder.key ? `${folder.key}/${segment}` : segment, segment);
        folder.folders.set(segment, child);
      }
      folder = child;
    }
    folder.items.push(item);
  }
  groupFamilies(root);
  return freeze(root);
}

/** Keys of every folder containing the document, outermost first; empty when absent. */
export function explorerFolderKeysFor(root: ExplorerFolder, relativePath: string): readonly string[] {
  const search = (folder: ExplorerFolder, trail: readonly string[]): readonly string[] | undefined => {
    if (folder.items.some((item) => item.relativePath === relativePath)) return trail;
    for (const child of folder.folders) {
      const found = search(child, [...trail, child.key]);
      if (found) return found;
    }
    return undefined;
  };
  return search(root, []) ?? [];
}

export interface ExplorerRenderOptions {
  readonly isOpen: (key: string) => boolean;
  readonly isCurrent: (item: SceneStudioContentSummary) => boolean;
  readonly escape: (value: unknown) => string;
}

/**
 * Row label: the file name, since the enclosing folders already give its
 * place. Inside a family only the variant part is shown. The full ID and path
 * stay in the tooltip and remain searchable.
 */
function itemLabel(item: SceneStudioContentSummary, family: string | undefined): string {
  const base = baseName(item.relativePath);
  if (family === undefined || base === family) return base;
  return base.startsWith(`${family}${FAMILY_SEPARATOR}`) ? base.slice(family.length + FAMILY_SEPARATOR.length) : base;
}

function renderItem(item: SceneStudioContentSummary, family: string | undefined, options: ExplorerRenderOptions): string {
  const { escape } = options;
  const searchText = escape(`${item.id} ${item.relativePath}`.toLowerCase());
  const current = options.isCurrent(item) ? ' is-current' : '';
  const title = escape(`${item.id}\n${item.relativePath}`);
  const label = escape(itemLabel(item, family));
  return item.kind === 'scene'
    ? `<button type="button" data-scene-id="${escape(item.id)}" data-explorer-item="${searchText}" class="scene-explorer-item${current}" title="${title}"><span>◫</span><strong>${label}</strong></button>`
    : `<button type="button" data-resource-id="${escape(item.id)}" data-explorer-item="${searchText}" class="scene-explorer-item scene-resource-row${current}" title="${title}"><span>◈</span>${label}</button>`;
}

function renderFolder(folder: ExplorerFolder, options: ExplorerRenderOptions): string {
  const { escape } = options;
  const open = options.isOpen(folder.key);
  const children = [
    ...folder.folders.map((child) => renderFolder(child, options)),
    ...folder.items.map((item) => renderItem(item, folder.family ? folder.label : undefined, options)),
  ].join('');
  return `<div class="scene-explorer-folder${folder.family ? ' is-family' : ''}${open ? ' is-open' : ''}" data-explorer-folder="${escape(folder.key)}" data-explorer-total="${folder.total}">`
    + `<button type="button" class="scene-explorer-folder-toggle" data-explorer-folder-toggle="${escape(folder.key)}" aria-expanded="${open}" title="${escape(folder.key)}">`
    + `<span aria-hidden="true">▸</span><strong>${escape(folder.label)}</strong><em data-explorer-folder-count>${folder.total}</em></button>`
    + `<div class="scene-explorer-children" role="group" aria-label="${escape(folder.label)}">${children}</div></div>`;
}

/** Top-level folders and loose files of the tree, for placement inside the explorer nav. */
export function renderExplorerTree(root: ExplorerFolder, options: ExplorerRenderOptions): string {
  return [
    ...root.folders.map((folder) => renderFolder(folder, options)),
    ...root.items.map((item) => renderItem(item, undefined, options)),
  ].join('');
}
