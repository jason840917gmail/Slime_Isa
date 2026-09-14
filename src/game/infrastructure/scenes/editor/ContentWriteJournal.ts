import { createHash, randomUUID } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';

export type ContentHash = string;

export interface ContentWrite {
  readonly relativePath: string;
  readonly content: string;
  readonly expectedHash: ContentHash | null;
}

export interface ContentWriteResult {
  readonly relativePath: string;
  readonly hash: ContentHash;
}

export interface ContentWriteJournalOptions {
  readonly journalRoot?: string;
  readonly transactionId?: () => string;
  readonly beforeReplace?: (relativePath: string, index: number) => void | Promise<void>;
}

interface JournalEntry {
  readonly relativePath: string;
  readonly existed: boolean;
  readonly originalHash: ContentHash | null;
  readonly backupName: string | null;
}

interface JournalManifest {
  readonly version: 1;
  readonly state: 'prepared' | 'committed';
  readonly entries: readonly JournalEntry[];
}

const HASH_PATTERN = /^[a-f0-9]{64}$/;
const MANIFEST_FILE = 'manifest.json';

export function contentHash(value: string | Uint8Array): ContentHash {
  return createHash('sha256').update(value).digest('hex');
}

function isInside(root: string, candidate: string): boolean {
  const relative = path.relative(root, candidate);
  return relative !== '' && !relative.startsWith('..') && !path.isAbsolute(relative);
}

function normalizeRelativePath(value: string): string {
  if (value.length === 0 || value.includes('\\') || path.isAbsolute(value)) {
    throw new Error(`Unsafe content path '${value}'`);
  }
  const normalized = path.posix.normalize(value);
  if (normalized === '.' || normalized.startsWith('../') || normalized.includes('/../')) {
    throw new Error(`Unsafe content path '${value}'`);
  }
  return normalized;
}

async function readExisting(target: string): Promise<Buffer | undefined> {
  try {
    return await fs.readFile(target);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return undefined;
    throw error;
  }
}

async function replaceFile(target: string, content: string | Uint8Array, suffix: string): Promise<void> {
  await fs.mkdir(path.dirname(target), { recursive: true });
  const temporary = `${target}.${suffix}.tmp`;
  try {
    await fs.writeFile(temporary, content);
    await fs.rename(temporary, target);
  } finally {
    await fs.rm(temporary, { force: true });
  }
}

async function writeManifest(transactionRoot: string, manifest: JournalManifest): Promise<void> {
  const target = path.join(transactionRoot, MANIFEST_FILE);
  const temporary = path.join(transactionRoot, `${MANIFEST_FILE}.tmp`);
  await fs.writeFile(temporary, JSON.stringify(manifest, null, 2), 'utf8');
  await fs.rename(temporary, target);
}

function parseManifest(value: unknown): JournalManifest {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid content journal manifest');
  const candidate = value as Partial<JournalManifest>;
  if (candidate.version !== 1 || !['prepared', 'committed'].includes(String(candidate.state)) || !Array.isArray(candidate.entries)) {
    throw new Error('Invalid content journal manifest');
  }
  for (const entry of candidate.entries) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) throw new Error('Invalid content journal entry');
    const item = entry as Partial<JournalEntry>;
    normalizeRelativePath(String(item.relativePath ?? ''));
    if (typeof item.existed !== 'boolean') throw new Error('Invalid content journal existence marker');
    if (item.originalHash !== null && (typeof item.originalHash !== 'string' || !HASH_PATTERN.test(item.originalHash))) {
      throw new Error('Invalid content journal original hash');
    }
    if (item.backupName !== null && (typeof item.backupName !== 'string' || !/^[0-9]+\.original$/.test(item.backupName))) {
      throw new Error('Invalid content journal backup name');
    }
  }
  return candidate as JournalManifest;
}

/**
 * Installs complete, prevalidated content write sets with hash preconditions and
 * exact-original rollback. This module is Node-only and is shared by the Vite
 * authoring endpoint and conversion tooling.
 */
export class ContentWriteJournal {
  readonly root: string;
  readonly journalRoot: string;
  readonly #transactionId: () => string;
  readonly #beforeReplace?: ContentWriteJournalOptions['beforeReplace'];

  constructor(root: string, options: ContentWriteJournalOptions = {}) {
    this.root = path.resolve(root);
    this.journalRoot = path.resolve(options.journalRoot ?? path.join(this.root, '.scene-studio-transactions'));
    if (!isInside(this.root, this.journalRoot)) throw new Error('Content journal must be inside its owned content root');
    this.#transactionId = options.transactionId ?? randomUUID;
    this.#beforeReplace = options.beforeReplace;
  }

  resolve(relativePath: string): string {
    const normalized = normalizeRelativePath(relativePath);
    const target = path.resolve(this.root, ...normalized.split('/'));
    if (!isInside(this.root, target) || isInside(this.journalRoot, target) || target === this.journalRoot) {
      throw new Error(`Unsafe content path '${relativePath}'`);
    }
    return target;
  }

  async recover(): Promise<void> {
    let directories;
    try {
      directories = await fs.readdir(this.journalRoot, { withFileTypes: true });
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') return;
      throw error;
    }
    for (const directory of directories.sort((left, right) => left.name.localeCompare(right.name))) {
      if (!directory.isDirectory()) continue;
      const transactionRoot = path.join(this.journalRoot, directory.name);
      let manifestSource: string;
      try {
        manifestSource = await fs.readFile(path.join(transactionRoot, MANIFEST_FILE), 'utf8');
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
        // Targets are not touched until the prepared manifest has been installed.
        await fs.rm(transactionRoot, { recursive: true, force: true });
        continue;
      }
      const manifest = parseManifest(JSON.parse(manifestSource));
      if (manifest.state === 'prepared') await this.#restore(transactionRoot, manifest);
      await fs.rm(transactionRoot, { recursive: true, force: true });
    }
  }

  async commit(writes: readonly ContentWrite[]): Promise<readonly ContentWriteResult[]> {
    if (writes.length === 0) throw new Error('A content transaction requires at least one file');
    const ordered = writes.map((write) => ({ ...write, relativePath: normalizeRelativePath(write.relativePath) }))
      .sort((left, right) => left.relativePath.localeCompare(right.relativePath));
    const unique = new Set<string>();
    for (const write of ordered) {
      if (unique.has(write.relativePath)) throw new Error(`Duplicate content path '${write.relativePath}'`);
      unique.add(write.relativePath);
      if (write.expectedHash !== null && !HASH_PATTERN.test(write.expectedHash)) {
        throw new Error(`Invalid expected hash for '${write.relativePath}'`);
      }
      this.resolve(write.relativePath);
    }

    const originals = await Promise.all(ordered.map(async (write) => {
      const value = await readExisting(this.resolve(write.relativePath));
      const actualHash = value === undefined ? null : contentHash(value);
      if (actualHash !== write.expectedHash) {
        throw new Error(`Content conflict for '${write.relativePath}': expected ${write.expectedHash ?? 'missing'}, found ${actualHash ?? 'missing'}`);
      }
      return value;
    }));

    await fs.mkdir(this.journalRoot, { recursive: true });
    const transactionRoot = path.join(this.journalRoot, this.#transactionId());
    if (!isInside(this.journalRoot, transactionRoot)) throw new Error('Invalid content transaction ID');
    await fs.mkdir(transactionRoot, { recursive: false });
    const entries: JournalEntry[] = [];
    try {
      for (let index = 0; index < ordered.length; index += 1) {
        const original = originals[index];
        const backupName = original === undefined ? null : `${index}.original`;
        if (backupName && original !== undefined) await fs.writeFile(path.join(transactionRoot, backupName), original);
        entries.push({
          relativePath: ordered[index].relativePath,
          existed: original !== undefined,
          originalHash: original === undefined ? null : contentHash(original),
          backupName,
        });
      }
      const prepared: JournalManifest = { version: 1, state: 'prepared', entries };
      await writeManifest(transactionRoot, prepared);

      for (let index = 0; index < ordered.length; index += 1) {
        const write = ordered[index];
        await this.#beforeReplace?.(write.relativePath, index);
        await replaceFile(this.resolve(write.relativePath), write.content, `${path.basename(transactionRoot)}.${index}`);
      }
      const committed: JournalManifest = { version: 1, state: 'committed', entries };
      await writeManifest(transactionRoot, committed);
      await fs.rm(transactionRoot, { recursive: true, force: true });
      return ordered.map((write) => ({ relativePath: write.relativePath, hash: contentHash(write.content) }));
    } catch (error) {
      const manifest: JournalManifest = { version: 1, state: 'prepared', entries };
      try {
        await this.#restore(transactionRoot, manifest);
        await fs.rm(transactionRoot, { recursive: true, force: true });
      } catch (restoreError) {
        throw new AggregateError([error, restoreError], 'Content transaction failed and rollback requires startup recovery');
      }
      throw error;
    }
  }

  async #restore(transactionRoot: string, manifest: JournalManifest): Promise<void> {
    for (const [index, entry] of [...manifest.entries].reverse().entries()) {
      const target = this.resolve(entry.relativePath);
      if (!entry.existed) {
        await fs.rm(target, { force: true });
        continue;
      }
      if (!entry.backupName) throw new Error(`Missing backup metadata for '${entry.relativePath}'`);
      const original = await fs.readFile(path.join(transactionRoot, entry.backupName));
      if (contentHash(original) !== entry.originalHash) throw new Error(`Corrupt backup for '${entry.relativePath}'`);
      await replaceFile(target, original, `restore.${index}`);
    }
  }
}
