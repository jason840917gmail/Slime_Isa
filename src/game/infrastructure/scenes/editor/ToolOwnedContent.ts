import { promises as fs } from 'node:fs';
import path from 'node:path';

/**
 * Explains why a content path (relative to the authored content root) must stay
 * where it is, or resolves undefined when Scene Studio may move it.
 */
export type ContentMoveGuard = (relativePath: string) => Promise<string | undefined>;

/** Folders whose files a generator rewrites and prunes; anything moved in or out would be lost or duplicated. */
const GENERATED_FOLDERS: readonly { readonly prefix: string; readonly owner: string }[] = [
  { prefix: 'objects/interiors/', owner: 'pnpm interiors:scenes' },
];

const LEDGER_PATH = 'scripts/migrations/universal-scene-conversion-ledger.json';
const AUTHORED_PREFIX = 'src/game/content/scenes/authored/';

interface LedgerRow {
  readonly key?: unknown;
  readonly outputs?: readonly { readonly path?: unknown }[];
}

/**
 * Default guard for the dev server: generated interior scenes and every
 * conversion output recorded in the scene conversion ledger live at fixed
 * paths that tooling and checks read back, so they cannot be moved.
 */
export function toolOwnedContentGuard(repositoryRoot = process.cwd()): ContentMoveGuard {
  return async (relativePath) => {
    for (const { prefix, owner } of GENERATED_FOLDERS) {
      if (relativePath.startsWith(prefix)) return `'${relativePath}' is inside ${prefix.slice(0, -1)}, which ${owner} regenerates; it cannot be moved in or out`;
    }
    let source: string;
    try { source = await fs.readFile(path.join(repositoryRoot, LEDGER_PATH), 'utf8'); } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') return undefined;
      throw error;
    }
    const ledger = JSON.parse(source) as { readonly rows?: readonly LedgerRow[] };
    const owned = `${AUTHORED_PREFIX}${relativePath}`;
    const row = ledger.rows?.find((candidate) => candidate.outputs?.some((output) => output.path === owned));
    return row ? `'${relativePath}' is a conversion output of '${String(row.key)}' and must stay at its recorded path` : undefined;
  };
}
