import type { JsonValue } from '../../content/scenes/types';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

export const CHEST_WORLD_SERVICE = 'world.chest-transaction';
export const CHEST_GUARD_SERVICE = 'world.chest-guard';
export const CHEST_VIEW_SERVICE = 'ui.chest-view';

export interface ChestWorldPort {
  ensureInitialized(mapId: string, instanceId: string, contents: Readonly<Record<string, number>>): void;
  getRemaining(mapId: string, instanceId: string): Readonly<Record<string, number>>;
  transferStack(mapId: string, instanceId: string, itemId: string): number;
}

export interface ChestGuardPort {
  isLocked(instanceId: string): boolean;
}

export interface ChestViewModel {
  readonly mapId: string;
  readonly instanceId: string;
  readonly contents: Readonly<Record<string, number>>;
  readonly transferStack: (itemId: string) => number;
  readonly close: () => void;
}

export interface ChestViewPort {
  open(model: ChestViewModel): void;
  close(instanceId: string): void;
}

function recordOfPositiveIntegers(value: JsonValue | undefined): Readonly<Record<string, number>> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(Object.entries(value).filter((entry): entry is [string, number] => (
    Number.isSafeInteger(entry[1]) && Number(entry[1]) > 0
  )));
}

export class ChestScript extends ScriptNode {
  readonly mapId: string;
  readonly instanceId: string;
  private world?: ChestWorldPort;
  private guard?: ChestGuardPort;
  private view?: ChestViewPort;

  constructor(context: NodeConstructionContext) {
    if (!context.scriptId) throw new Error('ChestScript requires a registered script identity.');
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: context.scriptId, exportedProperties: context.properties });
    this.mapId = typeof context.properties.mapId === 'string' ? context.properties.mapId : '';
    this.instanceId = typeof context.properties.instanceId === 'string' ? context.properties.instanceId : '';
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.world = this.service<ChestWorldPort>(CHEST_WORLD_SERVICE);
    this.guard = this.service<ChestGuardPort>(CHEST_GUARD_SERVICE);
    this.view = this.service<ChestViewPort>(CHEST_VIEW_SERVICE);
    this.world.ensureInitialized(this.mapId, this.instanceId, recordOfPositiveIntegers(this.exportedProperties.initialContents));
    this.entryDisposables.add(() => this.view?.close(this.instanceId));
  }

  get remaining(): Readonly<Record<string, number>> {
    return this.world?.getRemaining(this.mapId, this.instanceId) ?? {};
  }

  get empty(): boolean {
    return Object.keys(this.remaining).length === 0;
  }

  requestOpen(): 'opened' | 'guarded' {
    if (this.guard?.isLocked(this.instanceId)) {
      this.getSignal<{ instanceId: string }>('guard_blocked')?.emit({ instanceId: this.instanceId });
      return 'guarded';
    }
    const model: ChestViewModel = {
      mapId: this.mapId,
      instanceId: this.instanceId,
      contents: this.remaining,
      transferStack: (itemId) => this.transferStack(itemId),
      close: () => this.close(),
    };
    this.getSignal<ChestViewModel>('open_requested')?.emit(model);
    this.view?.open(model);
    return 'opened';
  }

  transferStack(itemId: string): number {
    const moved = this.world?.transferStack(this.mapId, this.instanceId, itemId) ?? 0;
    if (moved > 0) this.getSignal<{ itemId: string; moved: number }>('stack_transferred')?.emit({ itemId, moved });
    return moved;
  }

  close(): void {
    this.view?.close(this.instanceId);
    this.getSignal<{ instanceId: string }>('closed')?.emit({ instanceId: this.instanceId });
  }
}

