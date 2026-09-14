import { mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';

import { conversionReport, sha256 } from './ConversionReport.mjs';
import { loadContentWriteJournal } from './load-content-write-journal.mjs';
import { StableIdMap } from './StableIdMap.mjs';

function inside(parent, candidate) {
  const relative = path.relative(path.resolve(parent), path.resolve(candidate));
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

export const CONVERSION_FAMILY_ORDER = [
  'animation', 'visual', 'character', 'enemy', 'boss', 'weapon', 'projectile', 'effect', 'object', 'terrain', 'map', 'npc', 'ui',
];

function orderedFamilies(rows) {
  const present = new Set(rows.filter((unit) => unit.classification === 'convert').map((unit) => unit.family));
  return [
    ...CONVERSION_FAMILY_ORDER.filter((family) => present.delete(family)),
    ...[...present].sort(),
  ];
}

export class ConversionRunner {
  constructor({ repositoryRoot, ledger, adapters, outputRoot, stableIds = new StableIdMap(), validateWriteSet, journalFactory }) {
    this.repositoryRoot = repositoryRoot;
    this.ledger = ledger;
    this.adapters = adapters;
    this.outputRoot = outputRoot;
    this.stableIds = stableIds;
    this.validateWriteSet = validateWriteSet;
    this.journalFactory = journalFactory;
  }

  async run({ family = 'all', mode = 'dry-run', unitKeys } = {}) {
    if (!['dry-run', 'apply', 'check'].includes(mode)) throw new Error(`Unknown conversion mode '${mode}'`);
    const selectedKeys = unitKeys === undefined ? undefined : new Set(unitKeys);
    if (selectedKeys?.size === 0) throw new Error('Scene conversion unit selection cannot be empty');
    if (selectedKeys) {
      const knownKeys = new Set(this.ledger.rows.map((unit) => unit.key));
      const unknown = [...selectedKeys].filter((key) => !knownKeys.has(key)).sort();
      if (unknown.length > 0) throw new Error(`Unknown scene conversion units: ${unknown.join(', ')}`);
    }
    const eligibleRows = this.ledger.rows.filter((unit) => selectedKeys === undefined || selectedKeys.has(unit.key));
    const families = family === 'all' ? orderedFamilies(eligibleRows) : [family];
    const outputs = [];
    const units = [];
    for (const currentFamily of families) {
      const familyUnits = eligibleRows
        .filter((unit) => unit.family === currentFamily && unit.classification === 'convert' && unit.writerState !== 'scene')
        .sort((left, right) => left.key.localeCompare(right.key));
      if (familyUnits.length === 0) continue;
      const adapter = this.adapters[currentFamily];
      if (!adapter) throw new Error(`Missing scene conversion adapter '${currentFamily}'`);
      for (const unit of familyUnits) {
        const currentSource = await readFile(path.join(this.repositoryRoot, unit.oldSourcePath));
        if (unit.sourceHash && sha256(currentSource) !== unit.sourceHash) throw new Error(`Source hash changed for '${unit.key}'`);
      }
      units.push(...familyUnits);
      const converted = await adapter.convert({
        units: familyUnits,
        stableIds: this.stableIds,
        readSource: async (relativePath) => readFile(path.join(this.repositoryRoot, relativePath), 'utf8'),
      });
      outputs.push(...converted);
    }
    const paths = new Set();
    for (const output of outputs) {
      const normalized = output.path.replaceAll('\\', '/');
      if (normalized.startsWith('../') || path.isAbsolute(normalized)) throw new Error(`Unsafe conversion output '${output.path}'`);
      if (paths.has(normalized)) throw new Error(`Duplicate conversion output '${normalized}'`);
      paths.add(normalized);
      if (!output.content.endsWith('\n')) throw new Error(`Conversion output '${normalized}' is not canonically newline-terminated`);
      if (!Array.isArray(output.consumedFieldPaths) || !Array.isArray(output.intentionallyRetainedFields)) throw new Error(`Conversion output '${normalized}' must account for consumed and intentionally retained fields`);
      if (output.unaccountedFieldPaths !== undefined && !Array.isArray(output.unaccountedFieldPaths)) throw new Error(`Conversion output '${normalized}' has invalid unaccounted-field metadata`);
      if ((output.unaccountedFieldPaths ?? []).length > 0) throw new Error(`Conversion output '${normalized}' has unaccounted source fields: ${output.unaccountedFieldPaths.join(', ')}`);
      const unit = units.find((candidate) => candidate.key === output.unitKey);
      if (!unit) throw new Error(`Output '${normalized}' references unknown unit '${output.unitKey}'`);
    }
    for (const unit of units) if (!outputs.some((output) => output.unitKey === unit.key)) throw new Error(`Conversion unit '${unit.key}' produced no output`);
    if (!this.validateWriteSet) throw new Error('Scene conversion requires the canonical write-set validator');
    await this.validateWriteSet(outputs);
    if (mode === 'apply') {
      await mkdir(this.outputRoot, { recursive: true });
      const changed = [];
      for (const output of outputs) {
        const target = path.join(this.outputRoot, output.path);
        if (!inside(this.outputRoot, target) || path.resolve(target) === path.resolve(this.outputRoot)) throw new Error(`Unsafe conversion output '${output.path}'`);
        const current = await readFile(target).catch((error) => {
          if (error?.code === 'ENOENT') return undefined;
          throw error;
        });
        if (current !== undefined && current.toString('utf8') !== output.content) {
          throw new Error(`Conversion target changed at '${output.path}'; refusing to overwrite authored content`);
        }
        if (current === undefined) changed.push({ relativePath: output.path, content: output.content, expectedHash: null });
      }
      if (changed.length > 0) {
        const journal = this.journalFactory
          ? await this.journalFactory(this.outputRoot)
          : new (await loadContentWriteJournal()).ContentWriteJournal(this.outputRoot);
        await journal.recover();
        await journal.commit(changed);
      }
    } else if (mode === 'check') {
      for (const output of outputs) {
        const target = path.join(this.outputRoot, output.path);
        const current = await readFile(target, 'utf8').catch(() => undefined);
        if (current !== output.content) throw new Error(`Generated scene output differs at '${output.path}'`);
      }
    }
    return conversionReport(family, mode, units, outputs);
  }
}
