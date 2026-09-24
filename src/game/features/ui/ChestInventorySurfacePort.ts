import type { JsonValue } from '../../content/scenes/types';
import { itemRegistry } from '../../systems/Inventory';
import type { ChestViewModel, ChestViewPort } from '../scripts/ChestScript';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';

export interface ChestInventorySurfaceOptions {
  readonly modalStack: ModalStack;
  readonly uiRoot: HTMLElement;
  readonly onPausedChange: (paused: boolean) => void;
  readonly getContents: (instanceId: string) => Readonly<Record<string, number>>;
}

/** Presents the active authored chest and delegates transfers to its ChestScript transaction. */
export class ChestInventorySurfacePort implements ChestViewPort, UiSurfacePort {
  private readonly modalHandle: ModalHandle;
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private readonly resizeObserver: ResizeObserver;
  private model?: ChestViewModel;
  private selectedItemId?: string;
  private status = 'Select a stack to inspect. Right-click or press Take Stack to collect it.';
  private stopped = false;

  constructor(private readonly options: ChestInventorySurfaceOptions) {
    this.modalHandle = options.modalStack.register('chest-inventory', {
      isOpen: () => this.isOpen(),
      close: () => this.finish(true),
    });
    this.resizeObserver = new ResizeObserver(this.publish);
    this.resizeObserver.observe(options.uiRoot);
  }

  isOpen(): boolean { return !!this.model; }

  open(model: ChestViewModel): void {
    if (this.stopped) return;
    if (this.model) this.finish(true);
    this.model = model;
    this.selectedItemId = this.entries()[0]?.[0];
    this.status = 'Select a stack to inspect. Right-click or press Take Stack to collect it.';
    this.options.onPausedChange(true);
    this.modalHandle.open();
    this.publish();
  }

  close(instanceId: string): void {
    if (this.model?.instanceId !== instanceId) return;
    this.finish(false);
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'chest-inventory-panel' || this.stopped) return {};
    const entries = this.entries();
    if (!entries.some(([id]) => id === this.selectedItemId)) this.selectedItemId = entries[0]?.[0];
    const selected = this.selectedItemId ? itemRegistry.get(this.selectedItemId) : undefined;
    const amount = entries.find(([id]) => id === this.selectedItemId)?.[1];
    const width = Math.min(920, Math.max(1, this.options.uiRoot.clientWidth - 32));
    const height = Math.min(620, Math.max(1, this.options.uiRoot.clientHeight - 32));
    return {
      open: !!this.model,
      offsetMin: [-Math.round(width / 2), -Math.round(height / 2)],
      offsetMax: [Math.round(width / 2), Math.round(height / 2)],
      items: entries.map(([id, count]) => {
        const item = itemRegistry.get(id);
        return {
          id,
          label: `${item?.name ?? id} ×${count}`,
          ...(item ? { metadata: { iconKey: item.icon, iconFrame: item.iconFrame ?? 0, shortcut: String(count) } } : {}),
        };
      }),
      selectedIndex: entries.findIndex(([id]) => id === this.selectedItemId),
      details: selected && amount ? [selected.name, `${selected.category.toUpperCase()} · ×${amount}`, '', selected.description,
        '', 'Take Stack transfers as much as your inventory can hold.'].join('\n')
        : entries.length ? 'Select an item' : 'The chest is empty.',
      status: this.status,
      takeDisabled: !this.selectedItemId,
    };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== 'chest-inventory-panel' || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(surfaceId: string, actionId: string, payload?: JsonValue): void {
    if (surfaceId !== 'chest-inventory-panel' || this.stopped) return;
    if (actionId === 'close') { this.finish(true); return; }
    if (!this.model) return;
    if (actionId === 'select-item' || actionId === 'take-selected-stack') {
      const index = selectionIndex(payload);
      const itemId = index === undefined ? undefined : this.entries()[index]?.[0];
      if (!itemId) return;
      this.selectedItemId = itemId;
      if (actionId === 'take-selected-stack') this.take(itemId);
      else this.publish();
    } else if (actionId === 'take-stack' && this.selectedItemId) this.take(this.selectedItemId);
  }

  destroy(): void {
    if (this.stopped) return;
    this.finish(true);
    this.stopped = true;
    this.resizeObserver.disconnect();
    this.modalHandle.unregister();
    this.listeners.clear();
  }

  private entries(): Array<[string, number]> {
    if (!this.model) return [];
    return Object.entries(this.options.getContents(this.model.instanceId)).filter(([, count]) => count > 0);
  }

  private take(itemId: string): void {
    if (!this.model) return;
    const moved = this.model.transferStack(itemId);
    this.status = moved > 0 ? `Moved ${moved} × ${itemRegistry.get(itemId)?.name ?? itemId}` : 'No inventory space for that item.';
    if (!this.entries().some(([id]) => id === itemId)) this.selectedItemId = this.entries()[0]?.[0];
    this.publish();
  }

  private finish(notifyScript: boolean): void {
    const model = this.model;
    if (!model) { this.modalHandle.close(); return; }
    this.model = undefined;
    this.selectedItemId = undefined;
    this.modalHandle.close();
    this.options.onPausedChange(false);
    this.publish();
    if (notifyScript) model.close();
  }

  private readonly publish = (): void => {
    if (this.stopped) return;
    const model = this.snapshot('chest-inventory-panel');
    for (const listener of this.listeners) listener(model);
  };
}

function selectionIndex(payload: JsonValue | undefined): number | undefined {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return undefined;
  const index = (payload as Readonly<Record<string, JsonValue>>).index;
  return typeof index === 'number' && Number.isSafeInteger(index) && index >= 0 ? index : undefined;
}
