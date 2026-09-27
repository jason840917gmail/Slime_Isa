import { contentSha256 } from './contentHash.mjs';

export const sha256 = (value) => contentSha256(value);

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
      ...(output.contributions?.length ? { contributions: output.contributions } : {}),
    })).sort((left, right) => left.path.localeCompare(right.path)),
  };
}
