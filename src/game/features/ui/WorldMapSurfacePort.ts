import type { JsonValue } from '../../content/scenes/types';
import { gameEvents } from '../../core/EventBus';
import { worldProgress } from '../progression/WorldProgress';
import { AREAS, type AreaId } from '../../world/Area';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

export interface WorldMapSurfaceOptions {
  readonly modalStack: ModalStack;
  readonly uiRoot: HTMLElement;
  readonly getCurrentArea: () => AreaId;
  readonly onPausedChange: (paused: boolean) => void;
}

/** World discovery and current-area presentation for the authored map modal. */
export class WorldMapSurfacePort implements UiSurfacePort {
  private readonly handle: ModalHandle;
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private readonly resizeObserver: ResizeObserver;
  private openValue = false;
  private stopped = false;

  constructor(private readonly options: WorldMapSurfaceOptions) {
    this.handle = options.modalStack.register('world-map', {
      isOpen: () => this.isOpen(), close: () => this.close(),
    });
    gameEvents.on('world.progress.changed', this.publish, this);
    document.addEventListener('keydown', this.handleMapShortcut, { capture: true });
    this.resizeObserver = new ResizeObserver(this.publish);
    this.resizeObserver.observe(options.uiRoot);
  }

  isOpen(): boolean { return this.openValue; }
  discover(areaId: AreaId): void { worldProgress.discoverArea(areaId); }
  toggle(): void { if (this.openValue) this.close(); else this.open(); }
  open(): void {
    if (this.openValue || this.stopped) return;
    this.discover(this.options.getCurrentArea());
    this.openValue = true;
    this.options.onPausedChange(true);
    this.handle.open();
    this.publish();
  }
  close(): void {
    if (!this.openValue) { this.handle.close(); return; }
    this.openValue = false;
    this.handle.close();
    this.options.onPausedChange(false);
    this.publish();
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'world-map-ui' || this.stopped) return {};
    const discovered = worldProgress.discovered();
    const current = this.options.getCurrentArea();
    const width = Math.min(620, Math.max(1, this.options.uiRoot.clientWidth - 32));
    const height = Math.min(340, Math.max(1, this.options.uiRoot.clientHeight - 32));
    const label = (id: AreaId): string => {
      const area = AREAS[id];
      if (!discovered.has(id)) return '?\nUnknown';
      return `${id === current ? '◉' : '●'}\n${area.name}${id === current ? '\nCurrent area' : ''}`;
    };
    return {
      open: this.openValue,
      offsetMin: [-Math.round(width / 2), -Math.round(height / 2)],
      offsetMax: [Math.round(width / 2), Math.round(height / 2)],
      icege: label('icege'),
      level1: label('level-1'),
      gloopForest: label('gloop-forest'),
      crystalCaverns: label('crystal-caverns'),
      levelGloop: discovered.has('level-1') && discovered.has('gloop-forest') ? '━━━━' : '',
      gloopCrystal: discovered.has('gloop-forest') && discovered.has('crystal-caverns') ? '━━━━' : '',
      summary: `${discovered.size} discovered · Areas stay marked as you travel`,
    };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== 'world-map-ui' || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(surfaceId: string, actionId: string, _payload?: JsonValue): void {
    if (surfaceId === 'world-map-ui' && actionId === 'close') this.close();
  }

  destroy(): void {
    if (this.stopped) return;
    this.close();
    this.stopped = true;
    gameEvents.off('world.progress.changed', this.publish, this);
    document.removeEventListener('keydown', this.handleMapShortcut, { capture: true });
    this.resizeObserver.disconnect();
    this.handle.unregister();
    this.listeners.clear();
  }

  private readonly handleMapShortcut = (event: KeyboardEvent): void => {
    if (event.key.toLowerCase() !== 'm' || event.repeat || event.ctrlKey || event.altKey || event.metaKey) return;
    if (!this.openValue && this.options.modalStack.hasActiveSurface()) return;
    if (!this.openValue && event.target instanceof HTMLElement && event.target.closest('input, textarea, select, [contenteditable]')) return;
    this.toggle();
    event.preventDefault();
    event.stopPropagation();
  };

  private readonly publish = (): void => {
    if (this.stopped) return;
    const model = this.snapshot('world-map-ui');
    for (const listener of this.listeners) listener(model);
  };
}
