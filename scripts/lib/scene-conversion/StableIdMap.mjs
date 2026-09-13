import { createHash } from 'node:crypto';

function safe(value) {
  return value.toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^[._-]+|[._-]+$/g, '');
}

export class StableIdMap {
  constructor(entries = {}) {
    this.entries = new Map(Object.entries(entries));
  }

  resolve(scope, sourceId) {
    const key = `${scope}:${sourceId}`;
    const existing = this.entries.get(key);
    if (existing) return existing;
    const base = safe(sourceId) || 'unnamed';
    const suffix = createHash('sha256').update(key).digest('hex').slice(0, 8);
    const generated = `${safe(scope)}.${base}.${suffix}`;
    this.entries.set(key, generated);
    return generated;
  }

  toJSON() {
    return Object.fromEntries([...this.entries].sort(([left], [right]) => left.localeCompare(right)));
  }
}
