import type { SceneDocument } from '../../content/scenes/types';

export const PREVIEW_CAPABILITIES = new Set(['presentation', 'resources', 'animation', 'audio-preview', 'diagnostics']);
export const FORBIDDEN_PREVIEW_CAPABILITIES = new Set(['gameplay', 'domain', 'persistence', 'save', 'inventory', 'quests', 'combat']);

export interface ScenePreviewHost {
  readonly dispose: () => void;
  readonly resourceCount?: () => number;
}

export interface ScenePreviewFactory {
  create(document: SceneDocument, capabilities: ReadonlySet<string>): ScenePreviewHost;
}

export interface PreviewMarker {
  readonly resourceId: string;
  readonly animationId: string;
  readonly eventId: string;
  readonly at: number;
}

export function isolatedPreviewDocument(document: SceneDocument): SceneDocument {
  const disabled = new Set(document.nodes.filter((node) => node.type === 'ScriptNode').map((node) => node.id));
  return {
    ...structuredClone(document),
    nodes: document.nodes.filter((node) => !disabled.has(node.id)).map((node) => structuredClone(node)),
    connections: (document.connections ?? []).filter((connection) => !disabled.has(connection.source.nodeId) && !disabled.has(connection.target.nodeId)).map((connection) => structuredClone(connection)),
  };
}

export function previewEventMarkers(document: SceneDocument): readonly PreviewMarker[] {
  const markers: PreviewMarker[] = [];
  for (const resource of document.subresources ?? []) {
    if (resource.kind !== 'animation-library') continue;
    for (const [animationId, animation] of Object.entries(resource.animations)) {
      if (animation === null || Array.isArray(animation) || typeof animation !== 'object') continue;
      const record = animation as Readonly<Record<string, unknown>>;
      const events = Array.isArray(record.events) ? record.events : [];
      for (const event of events) {
        if (event !== null && !Array.isArray(event) && typeof event === 'object' && typeof event.eventId === 'string' && typeof event.at === 'number') {
          markers.push({ resourceId: resource.resourceId, animationId, eventId: event.eventId, at: event.at });
        }
      }
    }
  }
  return markers;
}

export class ScenePreview {
  private host?: ScenePreviewHost;

  constructor(private readonly factory: ScenePreviewFactory) {}

  open(document: SceneDocument): void {
    this.close();
    this.host = this.factory.create(isolatedPreviewDocument(document), PREVIEW_CAPABILITIES);
  }

  close(): void {
    const active = this.host;
    this.host = undefined;
    active?.dispose();
  }

  get active(): boolean { return this.host !== undefined; }
  get resourceCount(): number { return this.host?.resourceCount?.() ?? 0; }
}
