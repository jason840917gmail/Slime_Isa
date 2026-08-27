export function validateHarvestCapabilities(value, label = 'harvestCapabilities', resourceTags) {
  if (value === undefined) return [];
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return [`${label} must be an object`];

  const errors = [];
  for (const [targetTag, tier] of Object.entries(value)) {
    if (!targetTag.trim()) errors.push(`${label} target tag must be non-empty`);
    else if (targetTag !== targetTag.trim()) errors.push(`${label} target tag '${targetTag}' must not have surrounding whitespace`);
    else if (resourceTags && !resourceTags.has(targetTag)) errors.push(`${label} target tag '${targetTag}' is not configured; configured tags: ${[...resourceTags].join(', ')}`);
    if (!Number.isInteger(tier) || tier < 1) errors.push(`${label} '${targetTag}' must be an integer tier >= 1`);
  }
  return errors;
}
