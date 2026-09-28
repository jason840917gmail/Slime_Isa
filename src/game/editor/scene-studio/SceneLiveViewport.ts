import type { CollisionShapeValue } from '../../content/scenes/resources/types';
import type { TileMapContext } from './contexts/TileMapContext';
import { SCENE_DRAG_TYPE } from './ExplorerTree';
import {
  frameCamera,
  panCamera,
  screenToWorld,
  worldToScreen,
  zoomCameraAt,
  type ComposedTransform,
  type ViewportCamera,
  type ViewportSize,
  type WorldRect,
} from './SceneViewport';

export interface LiveViewportMarker {
  readonly key: string;
  readonly label: string;
  readonly type: string;
  /** `boss` marks where a boss camp spawns its boss; its label is always shown. */
  readonly kind: 'node' | 'instance' | 'ui' | 'boss';
  readonly position: readonly [number, number];
  readonly rect?: WorldRect;
  readonly selected: boolean;
  readonly movable: boolean;
  /** Global rotation in radians; a selected rotatable marker shows a rotate handle. */
  readonly rotation?: number;
  readonly rotatable?: boolean;
}

export interface LiveViewportShape {
  readonly key: string;
  readonly transform: ComposedTransform;
  readonly value: CollisionShapeValue;
  readonly editable: boolean;
  /** A hitbox the animation timeline shows as active on the current frame. */
  readonly active?: boolean;
  /** World-area role, coloured like the in-game enemy/NPC boundary overlays. */
  readonly tone?: 'perimeter' | 'stay' | 'safe' | 'wander' | 'activation' | 'arena' | 'attack';
}

export interface LiveViewportTileLayer {
  readonly context: TileMapContext;
  readonly origin: readonly [number, number];
  readonly tileSize: number;
}

export interface LiveViewportModel {
  readonly ariaLabel: string;
  readonly footer: string;
  readonly status?: string;
  readonly statusTone?: 'info' | 'error';
  readonly markers: readonly LiveViewportMarker[];
  readonly selectionRect?: WorldRect;
  readonly shapes: readonly LiveViewportShape[];
  readonly tile?: LiveViewportTileLayer;
  /** Rendered display bounds keyed by selectable key, used for click-to-select on sprites. */
  readonly pickables: readonly { readonly key: string; readonly rect: WorldRect }[];
  readonly contentBounds?: WorldRect;
  readonly selectionBounds?: WorldRect;
  /** Occlusion/depth bounds and depth anchors of the selection, coloured like the in-game dev tools. */
  readonly boundsGuides?: readonly LiveViewportBoundsGuide[];
  /** Outline of the UI screen (1280×720) for Control scenes. */
  readonly screenRect?: WorldRect;
}

/**
 * An editable depth/occlusion guide. `key` is the composed node key; rect
 * guides carry a world rectangle, anchor guides a world point.
 */
export type LiveViewportBoundsGuide =
  | { readonly key: string; readonly property: string; readonly kind: 'occlusion' | 'depth'; readonly rect: WorldRect; readonly editable: boolean }
  | { readonly key: string; readonly property: string; readonly kind: 'anchor'; readonly point: readonly [number, number]; readonly editable: boolean };

type BoundsHandle = 'move' | 'nw' | 'ne' | 'sw' | 'se';

export interface LiveViewportHost {
  select(key: string): void;
  moveMarker(key: string, global: readonly [number, number]): void;
  /** Rotate-handle drag finished; `rotation` is the new global rotation in radians. */
  rotateMarker(key: string, rotation: number): void;
  paintCell(cell: { readonly x: number; readonly y: number }): void;
  editShape(key: string, value: CollisionShapeValue): void;
  /** A bounds guide drag finished: the new world rectangle, or the new anchor point. */
  editBounds(key: string, property: string, change: { readonly rect?: WorldRect; readonly point?: readonly [number, number] }): void;
  cameraChanged(camera: ViewportCamera): void;
  /** A scene dragged from the explorer was dropped at `global` world coordinates. */
  dropScene(sceneId: string, global: readonly [number, number]): void;
}

const EMPTY_MODEL: LiveViewportModel = { ariaLabel: '2D viewport', footer: '', markers: [], shapes: [], pickables: [] };
const CELL_BUTTON_MIN_PIXELS = 14;
const CELL_BUTTON_LIMIT = 2400;
const ROTATE_HANDLE_RADIUS = 46;

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character] ?? character);
}

type Drag =
  | { readonly kind: 'pan'; readonly pointerId: number; lastX: number; lastY: number; readonly startX: number; readonly startY: number; moved: boolean; readonly clickSelect: boolean }
  | { readonly kind: 'marker'; readonly pointerId: number; readonly key: string; readonly startX: number; readonly startY: number; readonly origin: readonly [number, number]; moved: boolean; current: readonly [number, number] }
  | { readonly kind: 'paint'; readonly pointerId: number; lastCell?: string }
  | { readonly kind: 'rotate'; readonly pointerId: number; readonly key: string; angle: number }
  | { readonly kind: 'shape'; readonly pointerId: number; readonly key: string; readonly handle: string; value: CollisionShapeValue }
  | { readonly kind: 'bounds'; readonly pointerId: number; readonly guide: LiveViewportBoundsGuide; readonly handle: BoundsHandle; readonly start: readonly [number, number]; rect?: WorldRect; point?: readonly [number, number]; moved: boolean };

/**
 * Persistent 2D viewport: hosts the embedded runtime canvas and an HTML/SVG
 * overlay for markers, selection, collision shapes and tile cells. It survives
 * Scene Studio re-renders so the canvas and camera are never rebuilt.
 */
export class SceneLiveViewport {
  readonly element: HTMLElement;
  private readonly stage: HTMLDivElement;
  private readonly overlay: HTMLDivElement;
  private readonly footerZoom: HTMLSpanElement;
  private readonly footerInfo: HTMLSpanElement;
  private readonly statusLine: HTMLDivElement;
  private model: LiveViewportModel = EMPTY_MODEL;
  private cameraValue: ViewportCamera = { centerX: 0, centerY: 0, zoom: 1 };
  private drag?: Drag;
  private spaceHeld = false;
  private hoverCell?: { x: number; y: number };
  private frameRequest?: number;
  private readonly abort = new AbortController();
  private lastSize: ViewportSize = { width: 0, height: 0 };
  private interactions = 0;

  /** Increments whenever the user moves the camera (wheel, pan, keys, toolbar). */
  get userCameraInteractions(): number { return this.interactions; }

  constructor(previewElement: HTMLElement | undefined, private readonly host: LiveViewportHost) {
    this.element = document.createElement('section');
    this.element.className = 'scene-viewport scene-live-viewport';
    this.element.setAttribute('aria-label', '2D viewport');
    this.element.innerHTML = `<header class="scene-viewport-toolbar" role="toolbar" aria-label="Viewport tools"><div><button type="button" data-view-action="frame-all" title="Frame all (F)">Frame all</button><button type="button" data-view-action="frame-selection" title="Frame selection (Shift+F)">Frame selection</button></div><div><button type="button" data-view-action="zoom-out" aria-label="Zoom out">−</button><button type="button" data-view-action="zoom-reset" aria-label="Actual size">1:1</button><button type="button" data-view-action="zoom-in" aria-label="Zoom in">+</button></div></header><div class="scene-viewport-stage" data-viewport-stage></div><div class="scene-viewport-status" role="note" hidden></div><footer><span data-viewport-zoom>ZOOM 100%</span><span data-viewport-info></span></footer>`;
    this.stage = this.element.querySelector<HTMLDivElement>('[data-viewport-stage]')!;
    this.statusLine = this.element.querySelector<HTMLDivElement>('.scene-viewport-status')!;
    this.footerZoom = this.element.querySelector<HTMLSpanElement>('[data-viewport-zoom]')!;
    this.footerInfo = this.element.querySelector<HTMLSpanElement>('[data-viewport-info]')!;
    if (previewElement) this.stage.append(previewElement);
    this.overlay = document.createElement('div');
    this.overlay.className = 'scene-viewport-overlay';
    this.overlay.tabIndex = 0;
    this.overlay.setAttribute('aria-label', 'Viewport canvas. Drag to pan, wheel to zoom, click to select.');
    this.stage.append(this.overlay);
    this.bind();
  }

  get camera(): ViewportCamera { return this.cameraValue; }

  get size(): ViewportSize {
    const rect = this.stage.getBoundingClientRect();
    return { width: rect.width || this.lastSize.width || 800, height: rect.height || this.lastSize.height || 600 };
  }

  /** Moves the persistent element into the freshly rendered slot. */
  attach(slot: Element | null): void {
    if (!slot) { this.element.remove(); return; }
    slot.replaceWith(this.element);
    const size = this.size;
    if (size.width !== this.lastSize.width || size.height !== this.lastSize.height) {
      this.lastSize = size;
      this.host.cameraChanged(this.cameraValue);
    }
    this.scheduleOverlay();
  }

  update(model: LiveViewportModel): void {
    this.model = model;
    this.element.setAttribute('aria-label', model.ariaLabel);
    this.footerInfo.textContent = model.footer;
    this.statusLine.hidden = !model.status;
    this.statusLine.textContent = model.status ?? '';
    this.statusLine.classList.toggle('is-error', model.statusTone === 'error');
    this.scheduleOverlay();
  }

  setCamera(camera: ViewportCamera): void {
    this.cameraValue = camera;
    this.footerZoom.textContent = `ZOOM ${(camera.zoom * 100).toFixed(0)}%`;
    this.host.cameraChanged(camera);
    this.scheduleOverlay();
  }

  frame(rect: WorldRect | undefined): void {
    if (!rect) return;
    this.setCamera(frameCamera(rect, this.size));
  }

  frameAll(): void { this.frame(this.model.contentBounds); }
  frameSelection(): void { this.frame(this.model.selectionBounds ?? this.model.contentBounds); }

  destroy(): void {
    this.abort.abort();
    if (this.frameRequest !== undefined) cancelAnimationFrame(this.frameRequest);
    this.element.remove();
  }

  /** Renders synchronously; used by tests and after structural changes. */
  renderOverlayNow(): void {
    if (this.frameRequest !== undefined) { cancelAnimationFrame(this.frameRequest); this.frameRequest = undefined; }
    this.renderOverlay();
  }

  private scheduleOverlay(): void {
    if (this.frameRequest !== undefined) return;
    this.frameRequest = requestAnimationFrame(() => { this.frameRequest = undefined; this.renderOverlay(); });
  }

  private toScreen(point: readonly [number, number]): readonly [number, number] { return worldToScreen(this.cameraValue, this.size, point); }

  private renderOverlay(): void {
    const size = this.size;
    this.lastSize = size;
    const camera = this.cameraValue;
    const zoom = camera.zoom;
    const parts: string[] = [];
    const svg: string[] = [];
    const rectPath = (rect: WorldRect, className: string): void => {
      const [x, y] = this.toScreen([rect.x, rect.y]);
      svg.push(`<rect class="${className}" x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${Math.max(1, rect.width * zoom).toFixed(1)}" height="${Math.max(1, rect.height * zoom).toFixed(1)}" />`);
    };
    // World origin axes.
    const [originX, originY] = this.toScreen([0, 0]);
    svg.push(`<line class="scene-axis" x1="0" y1="${originY.toFixed(1)}" x2="${size.width}" y2="${originY.toFixed(1)}" /><line class="scene-axis" x1="${originX.toFixed(1)}" y1="0" x2="${originX.toFixed(1)}" y2="${size.height}" />`);
    if (this.model.screenRect) rectPath(this.model.screenRect, 'scene-screen-rect');
    const tile = this.model.tile;
    if (tile) this.renderTileLayer(tile, parts, svg, size);
    if (this.model.selectionRect) rectPath(this.model.selectionRect, 'scene-selection-rect');
    for (const shape of this.model.shapes) svg.push(this.shapeSvg(shape));
    for (const guide of this.model.boundsGuides ?? []) this.renderBoundsGuide(guide, svg, parts);
    const showLabels = zoom >= 0.45;
    for (const marker of this.model.markers) {
      const position = this.drag?.kind === 'marker' && this.drag.key === marker.key ? this.drag.current : marker.position;
      if (marker.kind === 'ui' && marker.rect) {
        const [x, y] = this.toScreen([marker.rect.x, marker.rect.y]);
        parts.push(`<button type="button" class="scene-ui-layout-node${marker.selected ? ' is-selected' : ''}" style="left:${x.toFixed(1)}px;top:${y.toFixed(1)}px;width:${Math.max(5, marker.rect.width * zoom).toFixed(1)}px;height:${Math.max(5, marker.rect.height * zoom).toFixed(1)}px" data-viewport-key="${escapeHtml(marker.key)}" aria-label="Select ${escapeHtml(marker.label)}"><span>${escapeHtml(marker.label)}</span><small>${escapeHtml(marker.type)}</small></button>`);
        continue;
      }
      const [x, y] = this.toScreen(position);
      if (x < -40 || y < -40 || x > size.width + 40 || y > size.height + 40) continue;
      parts.push(`<button type="button" class="scene-viewport-node is-${marker.kind}${marker.selected ? ' is-selected' : ''}${marker.movable ? ' is-movable' : ''}${showLabels || marker.selected || marker.kind === 'boss' ? ' has-label' : ''}" style="left:${x.toFixed(1)}px;top:${y.toFixed(1)}px" data-viewport-key="${escapeHtml(marker.key)}" aria-label="Select ${escapeHtml(marker.label)}" title="${escapeHtml(marker.label)} · ${escapeHtml(marker.type)}"><i aria-hidden="true"></i><span>${escapeHtml(marker.label)}</span></button>`);
    }
    for (const shape of this.model.shapes) if (shape.editable) parts.push(...this.shapeHandles(shape));
    const rotatable = this.model.markers.find((marker) => marker.selected && marker.rotatable && marker.kind !== 'ui');
    if (rotatable) {
      const [x, y] = this.toScreen(this.drag?.kind === 'marker' && this.drag.key === rotatable.key ? this.drag.current : rotatable.position);
      const angle = this.drag?.kind === 'rotate' && this.drag.key === rotatable.key ? this.drag.angle : rotatable.rotation ?? 0;
      const hx = x + Math.cos(angle) * ROTATE_HANDLE_RADIUS;
      const hy = y + Math.sin(angle) * ROTATE_HANDLE_RADIUS;
      svg.push(`<circle class="scene-rotate-ring" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${ROTATE_HANDLE_RADIUS}" /><line class="scene-rotate-arm" x1="${x.toFixed(1)}" y1="${y.toFixed(1)}" x2="${hx.toFixed(1)}" y2="${hy.toFixed(1)}" />`);
      const degrees = Math.round(angle * 1800 / Math.PI) / 10;
      parts.push(`<button type="button" class="scene-rotate-handle" style="left:${hx.toFixed(1)}px;top:${hy.toFixed(1)}px" data-rotate-handle="${escapeHtml(rotatable.key)}" aria-label="Rotate ${escapeHtml(rotatable.label)}" title="Rotate ${escapeHtml(rotatable.label)} · ${degrees}° (Shift snaps to 15°)"></button>${this.drag?.kind === 'rotate' ? `<span class="scene-rotate-readout" style="left:${hx.toFixed(1)}px;top:${hy.toFixed(1)}px">${degrees}°</span>` : ''}`);
    }
    this.overlay.innerHTML = `<svg class="scene-overlay-svg" width="${size.width}" height="${size.height}" aria-hidden="true">${svg.join('')}</svg>${parts.join('')}`;
    this.overlay.classList.toggle('is-tile-mode', Boolean(tile));
    this.overlay.classList.toggle('is-compact', zoom < 0.5);
  }

  /** Current (possibly mid-drag) geometry of a guide. */
  private guideGeometry(guide: LiveViewportBoundsGuide): { readonly rect?: WorldRect; readonly point?: readonly [number, number] } {
    const drag = this.drag?.kind === 'bounds' && this.drag.guide.key === guide.key && this.drag.guide.property === guide.property ? this.drag : undefined;
    return guide.kind === 'anchor' ? { point: drag?.point ?? guide.point } : { rect: drag?.rect ?? guide.rect };
  }

  private renderBoundsGuide(guide: LiveViewportBoundsGuide, svg: string[], parts: string[]): void {
    const zoom = this.cameraValue.zoom;
    const label = guide.kind === 'occlusion' ? 'occlusion bounds' : guide.kind === 'depth' ? 'depth bounds' : 'depth anchor';
    const handle = (name: BoundsHandle, point: readonly [number, number]): string => {
      const [x, y] = this.toScreen(point);
      return `<span class="scene-bounds-handle is-${guide.kind} is-${name}" role="slider" aria-label="${name === 'move' ? 'Move' : 'Resize'} ${label}" title="${name === 'move' ? 'Drag to move' : 'Drag to resize'} ${label}" style="left:${x.toFixed(1)}px;top:${y.toFixed(1)}px" data-bounds-key="${escapeHtml(guide.key)}" data-bounds-property="${escapeHtml(guide.property)}" data-bounds-handle="${name}"></span>`;
    };
    const { rect, point } = this.guideGeometry(guide);
    if (point) {
      const [x, y] = this.toScreen(point);
      svg.push(`<g class="scene-bounds is-anchor"><line x1="${(x - 14).toFixed(1)}" y1="${y.toFixed(1)}" x2="${(x + 14).toFixed(1)}" y2="${y.toFixed(1)}" /><rect x="${(x - 5).toFixed(1)}" y="${(y - 5).toFixed(1)}" width="10" height="10" /></g>`);
      if (guide.editable) parts.push(handle('move', point));
      return;
    }
    if (!rect) return;
    const [x, y] = this.toScreen([rect.x, rect.y]);
    const width = Math.max(1, rect.width * zoom);
    const height = Math.max(1, rect.height * zoom);
    svg.push(`<g class="scene-bounds is-${guide.kind}"><rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${width.toFixed(1)}" height="${height.toFixed(1)}" />${guide.kind === 'depth' ? `<line class="scene-bounds-sort-line" x1="${x.toFixed(1)}" y1="${(y + height).toFixed(1)}" x2="${(x + width).toFixed(1)}" y2="${(y + height).toFixed(1)}" />` : ''}</g>`);
    if (!guide.editable) return;
    parts.push(
      handle('nw', [rect.x, rect.y]), handle('ne', [rect.x + rect.width, rect.y]),
      handle('sw', [rect.x, rect.y + rect.height]), handle('se', [rect.x + rect.width, rect.y + rect.height]),
      handle('move', [rect.x + rect.width / 2, rect.y + rect.height / 2]),
    );
  }

  private renderTileLayer(tile: LiveViewportTileLayer, parts: string[], svg: string[], size: ViewportSize): void {
    const { context, origin, tileSize } = tile;
    const zoom = this.cameraValue.zoom;
    const cellPixels = tileSize * zoom;
    const columns = context.document.columns;
    const rows = context.document.rows;
    const [left, top] = this.toScreen(origin);
    svg.push(`<rect class="scene-tile-bounds" x="${left.toFixed(1)}" y="${top.toFixed(1)}" width="${(columns * cellPixels).toFixed(1)}" height="${(rows * cellPixels).toFixed(1)}" />`);
    const region = context.effectiveRegion;
    if (context.showEffectiveRegion && region) {
      svg.push(`<rect class="scene-tile-effective" x="${(left + region.minX * cellPixels).toFixed(1)}" y="${(top + region.minY * cellPixels).toFixed(1)}" width="${((region.maxX - region.minX + 1) * cellPixels).toFixed(1)}" height="${((region.maxY - region.minY + 1) * cellPixels).toFixed(1)}" />`);
    }
    const minX = Math.max(0, Math.floor(-left / cellPixels));
    const minY = Math.max(0, Math.floor(-top / cellPixels));
    const maxX = Math.min(columns - 1, Math.floor((size.width - left) / cellPixels));
    const maxY = Math.min(rows - 1, Math.floor((size.height - top) / cellPixels));
    const visible = Math.max(0, maxX - minX + 1) * Math.max(0, maxY - minY + 1);
    const cells = new Map(context.cells.map((cell) => [`${cell.x},${cell.y}`, cell.tileId]));
    if (context.showCollision) {
      for (const cell of context.cells) {
        if (cell.x < minX || cell.x > maxX || cell.y < minY || cell.y > maxY || !context.isCollisionCell(cell)) continue;
        svg.push(`<rect class="scene-tile-collision" x="${(left + cell.x * cellPixels).toFixed(1)}" y="${(top + cell.y * cellPixels).toFixed(1)}" width="${cellPixels.toFixed(1)}" height="${cellPixels.toFixed(1)}" />`);
      }
    }
    if (this.hoverCell) {
      svg.push(`<rect class="scene-tile-hover" x="${(left + this.hoverCell.x * cellPixels).toFixed(1)}" y="${(top + this.hoverCell.y * cellPixels).toFixed(1)}" width="${(cellPixels * context.brushSize).toFixed(1)}" height="${(cellPixels * context.brushSize).toFixed(1)}" transform="translate(${(-Math.floor(context.brushSize / 2) * cellPixels).toFixed(1)} ${(-Math.floor(context.brushSize / 2) * cellPixels).toFixed(1)})" />`);
    }
    if (cellPixels < CELL_BUTTON_MIN_PIXELS || visible > CELL_BUTTON_LIMIT) return;
    for (let y = minY; y <= maxY; y += 1) {
      for (let x = minX; x <= maxX; x += 1) {
        const tileId = cells.get(`${x},${y}`);
        const collision = context.showCollision && context.isCollisionCell({ x, y });
        const effective = context.showEffectiveRegion && region && x >= region.minX && x <= region.maxX && y >= region.minY && y <= region.maxY;
        parts.push(`<button type="button" tabindex="-1" data-tile-x="${x}" data-tile-y="${y}" class="scene-tile-cell${tileId ? ' is-painted' : ''}${collision ? ' is-collision' : ''}${effective ? ' is-effective' : ''}" style="left:${(left + x * cellPixels).toFixed(1)}px;top:${(top + y * cellPixels).toFixed(1)}px;width:${cellPixels.toFixed(1)}px;height:${cellPixels.toFixed(1)}px" aria-label="Cell ${x},${y}${tileId ? ` ${escapeHtml(tileId)}` : ' empty'}"></button>`);
      }
    }
  }

  private shapeSvg(shape: LiveViewportShape): string {
    const [x, y] = this.toScreen(shape.transform.position);
    const value = this.drag?.kind === 'shape' && this.drag.key === shape.key ? this.drag.value : shape.value;
    const sx = shape.transform.scale[0] * this.cameraValue.zoom;
    const sy = shape.transform.scale[1] * this.cameraValue.zoom;
    const transform = `translate(${x.toFixed(1)} ${y.toFixed(1)}) rotate(${(shape.transform.rotation * 180 / Math.PI).toFixed(2)}) scale(${sx.toFixed(4)} ${sy.toFixed(4)})`;
    const className = `scene-shape${shape.editable ? ' is-editable' : ''}${shape.active ? ' is-active' : ''}${shape.tone ? ` is-area-${shape.tone}` : ''}`;
    if (value.shape === 'rectangle') return `<rect class="${className}" transform="${transform}" x="${-value.width / 2}" y="${-value.height / 2}" width="${value.width}" height="${value.height}" vector-effect="non-scaling-stroke" />`;
    if (value.shape === 'circle') return `<circle class="${className}" transform="${transform}" r="${value.radius}" vector-effect="non-scaling-stroke" />`;
    if (value.shape === 'ellipse') return `<ellipse class="${className}" transform="${transform}" rx="${value.radiusX}" ry="${value.radiusY}" vector-effect="non-scaling-stroke" />`;
    const start = value.angleRad - value.arcWidthRad / 2;
    const end = value.angleRad + value.arcWidthRad / 2;
    const point = (radius: number, angle: number): string => `${(Math.cos(angle) * radius).toFixed(2)} ${(Math.sin(angle) * radius).toFixed(2)}`;
    const large = value.arcWidthRad > Math.PI ? 1 : 0;
    return `<path class="${className}" transform="${transform}" vector-effect="non-scaling-stroke" d="M ${point(value.innerRadius, start)} L ${point(value.outerRadius, start)} A ${value.outerRadius} ${value.outerRadius} 0 ${large} 1 ${point(value.outerRadius, end)} L ${point(value.innerRadius, end)} A ${value.innerRadius} ${value.innerRadius} 0 ${large} 0 ${point(value.innerRadius, start)} Z" />`;
  }

  private shapeHandles(shape: LiveViewportShape): string[] {
    const value = this.drag?.kind === 'shape' && this.drag.key === shape.key ? this.drag.value : shape.value;
    const local: [string, number, number][] = value.shape === 'rectangle' ? [['corner', value.width / 2, value.height / 2]]
      : value.shape === 'circle' ? [['radius', value.radius, 0]]
        : value.shape === 'ellipse' ? [['radius-x', value.radiusX, 0], ['radius-y', 0, value.radiusY]]
          : [];
    return local.map(([handle, lx, ly]) => {
      const [x, y] = this.toScreen(this.localToGlobal(shape.transform, [lx, ly]));
      return `<span class="scene-shape-handle" role="slider" aria-label="Resize collision shape (${handle})" style="left:${x.toFixed(1)}px;top:${y.toFixed(1)}px" data-shape-key="${escapeHtml(shape.key)}" data-shape-handle="${handle}"></span>`;
    });
  }

  private localToGlobal(transform: ComposedTransform, point: readonly [number, number]): readonly [number, number] {
    const x = point[0] * transform.scale[0];
    const y = point[1] * transform.scale[1];
    const cosine = Math.cos(transform.rotation);
    const sine = Math.sin(transform.rotation);
    return [transform.position[0] + x * cosine - y * sine, transform.position[1] + x * sine + y * cosine];
  }

  private globalToLocal(transform: ComposedTransform, point: readonly [number, number]): readonly [number, number] {
    const dx = point[0] - transform.position[0];
    const dy = point[1] - transform.position[1];
    const cosine = Math.cos(-transform.rotation);
    const sine = Math.sin(-transform.rotation);
    return [(dx * cosine - dy * sine) / transform.scale[0], (dx * sine + dy * cosine) / transform.scale[1]];
  }

  private pointer(event: MouseEvent): readonly [number, number] {
    const rect = this.stage.getBoundingClientRect();
    return [event.clientX - rect.left, event.clientY - rect.top];
  }

  private cellAt(event: MouseEvent): { x: number; y: number } | undefined {
    const tile = this.model.tile;
    if (!tile) return undefined;
    const world = screenToWorld(this.cameraValue, this.size, this.pointer(event));
    const x = Math.floor((world[0] - tile.origin[0]) / tile.tileSize);
    const y = Math.floor((world[1] - tile.origin[1]) / tile.tileSize);
    if (x < 0 || y < 0 || x >= tile.context.document.columns || y >= tile.context.document.rows) return undefined;
    return { x, y };
  }

  private bind(): void {
    const signal = this.abort.signal;
    this.element.addEventListener('click', (event) => {
      const action = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-view-action]')?.dataset.viewAction : undefined;
      if (!action) return;
      event.stopPropagation();
      this.interactions += 1;
      const size = this.size;
      const center: [number, number] = [size.width / 2, size.height / 2];
      if (action === 'frame-all') this.frameAll();
      else if (action === 'frame-selection') this.frameSelection();
      else if (action === 'zoom-in') this.setCamera(zoomCameraAt(this.cameraValue, size, center, 1.25));
      else if (action === 'zoom-out') this.setCamera(zoomCameraAt(this.cameraValue, size, center, 0.8));
      else if (action === 'zoom-reset') this.setCamera({ ...this.cameraValue, zoom: 1 });
    }, { signal });
    this.overlay.addEventListener('wheel', (event) => {
      event.preventDefault();
      this.interactions += 1;
      const factor = Math.exp(-Math.max(-300, Math.min(300, event.deltaMode === 1 ? event.deltaY * 16 : event.deltaY)) * 0.0015);
      this.setCamera(zoomCameraAt(this.cameraValue, this.size, this.pointer(event), factor));
    }, { passive: false, signal });
    this.overlay.addEventListener('pointerdown', (event) => this.pointerDown(event), { signal });
    this.overlay.addEventListener('pointermove', (event) => this.pointerMove(event), { signal });
    this.overlay.addEventListener('pointerup', (event) => this.pointerUp(event), { signal });
    this.overlay.addEventListener('pointercancel', () => { this.drag = undefined; this.overlay.classList.remove('is-panning'); }, { signal });
    this.overlay.addEventListener('pointerleave', () => { if (this.hoverCell) { this.hoverCell = undefined; this.scheduleOverlay(); } }, { signal });
    // Scenes dragged from the explorer are instanced where they are dropped, like Godot.
    const carriesScene = (event: DragEvent): boolean => Boolean(event.dataTransfer?.types.includes(SCENE_DRAG_TYPE));
    this.stage.addEventListener('dragover', (event) => {
      if (!carriesScene(event)) return;
      event.preventDefault();
      event.dataTransfer!.dropEffect = 'copy';
      this.stage.classList.add('is-drop-target');
    }, { signal });
    this.stage.addEventListener('dragleave', (event) => {
      if (!(event.relatedTarget instanceof Node) || !this.stage.contains(event.relatedTarget)) this.stage.classList.remove('is-drop-target');
    }, { signal });
    this.stage.addEventListener('drop', (event) => {
      this.stage.classList.remove('is-drop-target');
      const sceneId = event.dataTransfer?.getData(SCENE_DRAG_TYPE);
      if (!sceneId) return;
      event.preventDefault();
      this.host.dropScene(sceneId, screenToWorld(this.cameraValue, this.size, this.pointer(event)));
    }, { signal });
    this.overlay.addEventListener('click', (event) => {
      // Keyboard activation of markers and cells (pointer paths are handled on pointerdown/up).
      if (event.detail !== 0) { event.stopPropagation(); return; }
      const target = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-viewport-key],[data-tile-x]') : null;
      event.stopPropagation();
      if (target?.dataset.viewportKey) this.host.select(target.dataset.viewportKey);
      else if (target?.dataset.tileX !== undefined) this.host.paintCell({ x: Number(target.dataset.tileX), y: Number(target.dataset.tileY) });
    }, { signal });
    this.overlay.addEventListener('keydown', (event) => {
      if (['f', 'F', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', '+', '=', '-'].includes(event.key)) this.interactions += 1;
      if (event.key === 'f' || event.key === 'F') { event.preventDefault(); if (event.shiftKey) this.frameSelection(); else this.frameAll(); return; }
      const step = 48 / this.cameraValue.zoom;
      const moves: Record<string, [number, number]> = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
      const move = moves[event.key];
      if (move) { event.preventDefault(); this.setCamera({ ...this.cameraValue, centerX: this.cameraValue.centerX + move[0], centerY: this.cameraValue.centerY + move[1] }); }
      else if (event.key === '+' || event.key === '=') this.setCamera(zoomCameraAt(this.cameraValue, this.size, [this.size.width / 2, this.size.height / 2], 1.25));
      else if (event.key === '-') this.setCamera(zoomCameraAt(this.cameraValue, this.size, [this.size.width / 2, this.size.height / 2], 0.8));
    }, { signal });
    window.addEventListener('keydown', (event) => {
      if (event.code === 'Space' && !(event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement || event.target instanceof HTMLSelectElement)) {
        if (this.element.isConnected && (event.target === this.overlay || event.target === document.body)) event.preventDefault();
        this.spaceHeld = true;
        this.overlay.classList.add('is-space-pan');
      }
    }, { signal });
    window.addEventListener('keyup', (event) => {
      if (event.code === 'Space') { this.spaceHeld = false; this.overlay.classList.remove('is-space-pan'); }
    }, { signal });
    new ResizeObserver(() => {
      const size = this.size;
      if (size.width === this.lastSize.width && size.height === this.lastSize.height) return;
      this.lastSize = size;
      this.host.cameraChanged(this.cameraValue);
      this.scheduleOverlay();
    }).observe(this.stage);
  }

  private pointerDown(event: PointerEvent): void {
    const target = event.target instanceof Element ? event.target : null;
    const handle = target?.closest<HTMLElement>('[data-shape-handle]');
    const markerElement = target?.closest<HTMLElement>('[data-viewport-key]');
    const panRequested = event.button === 1 || (event.button === 0 && this.spaceHeld);
    if (event.button !== 0 && !panRequested) return;
    this.overlay.focus({ preventScroll: true });
    this.overlay.setPointerCapture(event.pointerId);
    event.preventDefault();
    const rotateHandle = target?.closest<HTMLElement>('[data-rotate-handle]');
    if (!panRequested && rotateHandle?.dataset.rotateHandle) {
      const marker = this.model.markers.find((candidate) => candidate.key === rotateHandle.dataset.rotateHandle);
      if (marker) { this.drag = { kind: 'rotate', pointerId: event.pointerId, key: marker.key, angle: marker.rotation ?? 0 }; return; }
    }
    const boundsHandle = target?.closest<HTMLElement>('[data-bounds-handle]');
    if (!panRequested && boundsHandle) {
      const guide = (this.model.boundsGuides ?? []).find((candidate) => candidate.key === boundsHandle.dataset.boundsKey && candidate.property === boundsHandle.dataset.boundsProperty);
      if (guide?.editable) {
        this.drag = { kind: 'bounds', pointerId: event.pointerId, guide, handle: (boundsHandle.dataset.boundsHandle ?? 'move') as BoundsHandle, start: screenToWorld(this.cameraValue, this.size, this.pointer(event)), moved: false };
        return;
      }
    }
    if (!panRequested && handle) {
      const shape = this.model.shapes.find((candidate) => candidate.key === handle.dataset.shapeKey);
      if (shape) { this.drag = { kind: 'shape', pointerId: event.pointerId, key: shape.key, handle: handle.dataset.shapeHandle ?? '', value: shape.value }; return; }
    }
    if (!panRequested && this.model.tile && !markerElement?.classList.contains('is-selected')) {
      const cellButton = target?.closest<HTMLElement>('[data-tile-x]');
      const cell = cellButton ? { x: Number(cellButton.dataset.tileX), y: Number(cellButton.dataset.tileY) } : this.cellAt(event);
      if (cell) {
        this.drag = { kind: 'paint', pointerId: event.pointerId, lastCell: `${cell.x},${cell.y}` };
        this.host.paintCell(cell);
        return;
      }
    }
    if (!panRequested && markerElement?.dataset.viewportKey) {
      const marker = this.model.markers.find((candidate) => candidate.key === markerElement.dataset.viewportKey);
      if (marker) {
        const [x, y] = this.pointer(event);
        this.drag = { kind: 'marker', pointerId: event.pointerId, key: marker.key, startX: x, startY: y, origin: marker.position, moved: false, current: marker.position };
        if (!marker.selected) this.host.select(marker.key);
        return;
      }
    }
    const [x, y] = this.pointer(event);
    this.drag = { kind: 'pan', pointerId: event.pointerId, lastX: x, lastY: y, startX: x, startY: y, moved: false, clickSelect: !panRequested };
    this.overlay.classList.add('is-panning');
  }

  private pointerMove(event: PointerEvent): void {
    const drag = this.drag;
    if (!drag) {
      if (this.model.tile) {
        const cell = this.cellAt(event);
        if (cell?.x !== this.hoverCell?.x || cell?.y !== this.hoverCell?.y) { this.hoverCell = cell; this.scheduleOverlay(); }
      }
      return;
    }
    if (drag.pointerId !== event.pointerId) return;
    const [x, y] = this.pointer(event);
    if (drag.kind === 'pan') {
      if (Math.hypot(x - drag.startX, y - drag.startY) > 3) { if (!drag.moved) this.interactions += 1; drag.moved = true; }
      const camera = panCamera(this.cameraValue, x - drag.lastX, y - drag.lastY);
      drag.lastX = x; drag.lastY = y;
      this.setCamera(camera);
    } else if (drag.kind === 'marker') {
      const marker = this.model.markers.find((candidate) => candidate.key === drag.key);
      if (!marker?.movable) return;
      if (Math.hypot(x - drag.startX, y - drag.startY) > 3) drag.moved = true;
      if (!drag.moved) return;
      const zoom = this.cameraValue.zoom;
      drag.current = [Math.round(drag.origin[0] + (x - drag.startX) / zoom), Math.round(drag.origin[1] + (y - drag.startY) / zoom)];
      this.scheduleOverlay();
    } else if (drag.kind === 'rotate') {
      const marker = this.model.markers.find((candidate) => candidate.key === drag.key);
      if (!marker) return;
      const [cx, cy] = this.toScreen(marker.position);
      const raw = Math.atan2(y - cy, x - cx);
      const snap = Math.PI / 12;
      drag.angle = event.shiftKey ? Math.round(raw / snap) * snap : Math.round(raw * 10000) / 10000;
      this.scheduleOverlay();
    } else if (drag.kind === 'bounds') {
      const world = screenToWorld(this.cameraValue, this.size, [x, y]);
      const dx = Math.round(world[0] - drag.start[0]);
      const dy = Math.round(world[1] - drag.start[1]);
      drag.moved = drag.moved || dx !== 0 || dy !== 0;
      const guide = drag.guide;
      if (guide.kind === 'anchor') drag.point = [guide.point[0] + dx, guide.point[1] + dy];
      else {
        const { x: left, y: top, width, height } = guide.rect;
        let [x0, y0, x1, y1] = [left, top, left + width, top + height];
        if (drag.handle === 'move') { x0 += dx; x1 += dx; y0 += dy; y1 += dy; }
        if (drag.handle === 'nw' || drag.handle === 'sw') x0 = Math.min(x0 + dx, x1 - 1);
        if (drag.handle === 'ne' || drag.handle === 'se') x1 = Math.max(x1 + dx, x0 + 1);
        if (drag.handle === 'nw' || drag.handle === 'ne') y0 = Math.min(y0 + dy, y1 - 1);
        if (drag.handle === 'sw' || drag.handle === 'se') y1 = Math.max(y1 + dy, y0 + 1);
        drag.rect = { x: x0, y: y0, width: x1 - x0, height: y1 - y0 };
      }
      this.scheduleOverlay();
    } else if (drag.kind === 'paint') {
      const cell = this.cellAt(event);
      this.hoverCell = cell;
      if (!cell || `${cell.x},${cell.y}` === drag.lastCell) return;
      drag.lastCell = `${cell.x},${cell.y}`;
      this.host.paintCell(cell);
    } else {
      const shape = this.model.shapes.find((candidate) => candidate.key === drag.key);
      if (!shape) return;
      const local = this.globalToLocal(shape.transform, screenToWorld(this.cameraValue, this.size, [x, y]));
      const round = (value: number): number => Math.max(1, Math.round(Math.abs(value) * 2) / 2);
      const value = drag.value;
      drag.value = value.shape === 'rectangle' ? { ...value, width: round(local[0] * 2), height: round(local[1] * 2) }
        : value.shape === 'circle' ? { ...value, radius: round(Math.hypot(local[0], local[1])) }
          : value.shape === 'ellipse' ? (drag.handle === 'radius-x' ? { ...value, radiusX: round(local[0]) } : { ...value, radiusY: round(local[1]) })
            : value;
      this.scheduleOverlay();
    }
  }

  private pointerUp(event: PointerEvent): void {
    const drag = this.drag;
    if (!drag || drag.pointerId !== event.pointerId) return;
    this.drag = undefined;
    this.overlay.classList.remove('is-panning');
    if (this.overlay.hasPointerCapture(event.pointerId)) this.overlay.releasePointerCapture(event.pointerId);
    if (drag.kind === 'pan' && !drag.moved && drag.clickSelect) {
      const world = screenToWorld(this.cameraValue, this.size, this.pointer(event));
      const hits = this.model.pickables
        .filter(({ rect }) => world[0] >= rect.x && world[0] <= rect.x + rect.width && world[1] >= rect.y && world[1] <= rect.y + rect.height)
        .sort((left, right) => left.rect.width * left.rect.height - right.rect.width * right.rect.height);
      if (hits[0]) this.host.select(hits[0].key);
    } else if (drag.kind === 'marker' && drag.moved) {
      this.host.moveMarker(drag.key, drag.current);
    } else if (drag.kind === 'rotate') {
      this.host.rotateMarker(drag.key, drag.angle);
    } else if (drag.kind === 'shape') {
      this.host.editShape(drag.key, drag.value);
    } else if (drag.kind === 'bounds' && drag.moved) {
      this.host.editBounds(drag.guide.key, drag.guide.property, drag.guide.kind === 'anchor' ? { ...(drag.point ? { point: drag.point } : {}) } : { ...(drag.rect ? { rect: drag.rect } : {}) });
    }
    this.scheduleOverlay();
  }
}
