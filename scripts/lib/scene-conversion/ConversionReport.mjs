import { createHash } from 'node:crypto';

export const sha256 = (value) => createHash('sha256').update(value).digest('hex');

export function conversionReport(family, mode, units, outputs) {
  return {
    version: 1,
    family,
    mode,
    units: units.map((unit) => unit.key).sort(),
    outputs: outputs.map((output) => ({
      unitKey: output.unitKey,
      path: output.path.replaceAll('\\', '/'),
      sha256: sha256(output.content),
      bytes: Buffer.byteLength(output.content),
      consumedFieldPaths: [...(output.consumedFieldPaths ?? [])].sort(),
      intentionallyRetainedFields: [...(output.intentionallyRetainedFields ?? [])].sort((left, right) => left.path.localeCompare(right.path)),
    })).sort((left, right) => left.path.localeCompare(right.path)),
  };
}
