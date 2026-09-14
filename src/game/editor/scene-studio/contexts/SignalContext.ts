import { handlersForScript, signalsForNode, type DescriptorRegistry } from '../../../content/scenes/propertyDescriptors';
import type { SceneNodeDocument } from '../../../content/scenes/types';

export interface CompatibleSignalConnection {
  readonly signal: string;
  readonly handler: string;
  readonly payload: string;
}

export function compatibleSignalConnections(source: SceneNodeDocument, target: SceneNodeDocument, registry: DescriptorRegistry): readonly CompatibleSignalConnection[] {
  const signals = signalsForNode(source.type, source.scriptId, registry);
  const handlers = handlersForScript(target.scriptId, registry);
  const compatible: CompatibleSignalConnection[] = [];
  for (const signal of signals.values()) for (const handler of handlers.values()) {
    if ((signal.payload ?? 'void') === (handler.payload ?? 'void')) compatible.push({ signal: signal.id, handler: handler.id, payload: signal.payload ?? 'void' });
  }
  return compatible;
}
