import { handlersForNode, signalPayloadCompatible, signalsForNode, type DescriptorRegistry } from '../../../content/scenes/propertyDescriptors';
import type { SceneNodeDocument } from '../../../content/scenes/types';

export interface CompatibleSignalConnection {
  readonly signal: string;
  readonly handler: string;
  readonly payload: string;
}

export function compatibleSignalConnections(source: SceneNodeDocument, target: SceneNodeDocument, registry: DescriptorRegistry): readonly CompatibleSignalConnection[] {
  const signals = signalsForNode(source.type, source.scriptId, registry);
  const handlers = handlersForNode(target.type, target.scriptId, registry);
  const compatible: CompatibleSignalConnection[] = [];
  for (const signal of signals.values()) for (const handler of handlers.values()) {
    if (signalPayloadCompatible(signal, handler)) compatible.push({ signal: signal.id, handler: handler.id, payload: signal.payload ?? 'void' });
  }
  return compatible;
}
