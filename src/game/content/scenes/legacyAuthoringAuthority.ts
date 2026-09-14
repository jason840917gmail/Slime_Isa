interface MapAuthorityDocument {
  readonly bossCamps?: readonly { readonly id: string }[];
  readonly objects?: readonly { readonly instanceId: string }[];
}

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const record = value as Readonly<Record<string, unknown>>;
    return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${canonical(record[key])}`).join(',')}}`;
  }
  return JSON.stringify(value) ?? 'undefined';
}

function ownedRecord(map: MapAuthorityDocument, recordId: string): unknown {
  return map.bossCamps?.find((entry) => entry.id === recordId)
    ?? map.objects?.find((entry) => entry.instanceId === recordId);
}

export function changedSceneOwnedMapRecords(
  persisted: MapAuthorityDocument,
  submitted: MapAuthorityDocument,
  sceneOwnedRecordIds: ReadonlySet<string>,
): readonly string[] {
  return [...sceneOwnedRecordIds]
    .filter((recordId) => canonical(ownedRecord(submitted, recordId)) !== canonical(ownedRecord(persisted, recordId)))
    .sort();
}
