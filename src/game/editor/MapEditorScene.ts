import Phaser from 'phaser';

import type { MapDirection } from '../content/maps/mapFormat';
import {
  getObjectArchetypeIds,
  getObjectVisualChoice,
  getObjectVisualChoices,
  isObjectArchetypeId,
  type ObjectArchetypeId,
} from '../content/objects/ObjectCatalog';
import {
  getTileDefinition,
  getTileIds,
  isWorldTileId,
  type WorldTileId,
} from '../content/terrain/TileCatalog';
import {
  getObjectAnchor,
  ObjectFactory,
  setObjectAnchor,
  setObjectDepthMode,
} from '../features/objects/ObjectFactory';
import { resolveExplicitDepth } from '../presentation/WorldDepth';
import {
  buildSourceAlphaMask,
  resolveWorldOcclusionRectangle,
  resolveWorldAlphaMaskRuns,
} from '../presentation/WorldOcclusion';
import {
  TerrainTransitionLayer,
  TerrainTransitionRenderer,
} from '../features/world/TerrainTransitionRenderer';
import { TileFactory } from '../features/world/TileFactory';
import type { LoadedMap } from '../infrastructure/maps/MapRepository';
import { getAsset } from '../infrastructure/assets/manifest';
import { AREAS } from '../world/Area';
import { connectionAt } from './MapConnections';
import { EDITOR_GEOMETRY_STYLES, EDITOR_SELECTION_STYLE } from './EditorGeometryStyles';
import { mountMapEditorInspector } from './MapEditorInspector';
import { mountMapEditorPanel, type ContentPreviewUrls } from './MapEditorPanel';
import { MapEditorState, type EditableMap, type EditableObjectInstance, type EditorTool } from './MapEditorState';
import { ObjectTemplateEditorState } from './ObjectTemplateEditorState';

interface MapEditorSceneData {
  loadedMap?: LoadedMap;
}

const TOKEN_CANDIDATES = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*';

interface TilePoint {
  readonly x: number;
  readonly y: number;
}

interface PaintDrag {
  readonly tileId: WorldTileId;
  readonly cells: Map<string, TilePoint>;
  readonly previews: Phaser.GameObjects.Image[];
  readonly hiddenTerrain: Map<string, Phaser.GameObjects.Image>;
  last: TilePoint;
}

interface ObjectStampDrag {
  readonly objectId: ObjectArchetypeId;
  readonly visualId: string;
  readonly cells: Map<string, TilePoint>;
  readonly previews: Phaser.GameObjects.Image[];
  last: TilePoint;
}

interface ObjectMoveDrag {
  readonly instanceId: string;
  readonly image: Phaser.GameObjects.Image;
  readonly startX: number;
  readonly startY: number;
  readonly pointerOffsetX: number;
  readonly pointerOffsetY: number;
  moved: boolean;
}

interface SafeZoneMove {
  readonly index: number;
  readonly w: number;
  readonly h: number;
  readonly offsetX: number;
  readonly offsetY: number;
  readonly startX: number;
  readonly startY: number;
  x: number;
  y: number;
}

/**
 * True while the user is editing DOM UI (dialog fields, selects, content
 * editable) — editor hotkeys and camera keys must not fire then, otherwise
 * typing in the New Map / Monster Spawns dialogs switches tools, and
 * Backspace can delete a selected object instead of editing text.
 */
function isUiEditingActive(target: EventTarget | null): boolean {
  if (document.querySelector('dialog[open]')) return true;
  if (!(target instanceof HTMLElement)) return false;
  return target instanceof HTMLInputElement
    || target instanceof HTMLTextAreaElement
    || target instanceof HTMLSelectElement
    || target.isContentEditable;
}

export class MapEditorScene extends Phaser.Scene {
  private loadedMap!: LoadedMap;
  private editor!: MapEditorState;
  private templateEditor!: ObjectTemplateEditorState;
  private collisionGroup!: Phaser.Physics.Arcade.StaticGroup;
  private renderedObjects: Phaser.GameObjects.GameObject[] = [];
  private overlayObjects: Phaser.GameObjects.GameObject[] = [];
  private renderedTerrain = new Map<string, Phaser.GameObjects.Image>();
  private renderedInstances = new Map<string, Phaser.GameObjects.Image>();
  private transitionLayer?: TerrainTransitionLayer;
  private unsubscribeState?: () => void;
  private unsubscribeTemplate?: () => void;
  private unmountPanel?: () => void;
  private unmountInspector?: () => void;
  private lastRevision = -1;
  private lastTemplateRevision = -1;
  private lastTemplateOverlaySettings = {
    showAllMatchingOverlays: false,
    showFrameOverlay: true,
    showColliderOverlay: true,
    showOcclusionOverlay: true,
  };
  private lastSelectedInstanceId?: string;
  private lastTool: EditorTool = 'pan';
  private panPointer?: { x: number; y: number };
  private paintDrag?: PaintDrag;
  private objectStampDrag?: ObjectStampDrag;
  private objectMoveDrag?: ObjectMoveDrag;
  private moveHandles?: Phaser.GameObjects.Graphics;
  private previewTileFactory!: TileFactory;
  private previewObjectFactory!: ObjectFactory;
  private cursorGhost?: Phaser.GameObjects.Image;
  private templatePreview?: Phaser.GameObjects.Image;
  private cursorGhostKey?: string;
  private eraseDragStart?: { x: number; y: number };
  private eraseDragMarker?: Phaser.GameObjects.Graphics;
  private safeZoneDragStart?: { x: number; y: number };
  private safeZoneDragRect?: { x: number; y: number; w: number; h: number };
  private safeZoneDragMarker?: Phaser.GameObjects.Graphics;
  private safeZoneMove?: SafeZoneMove;
  private cursors?: Phaser.Types.Input.Keyboard.CursorKeys;
  private wasd?: Record<'up' | 'down' | 'left' | 'right', Phaser.Input.Keyboard.Key>;

  constructor() {
    super('map-editor');
  }

  init(data: MapEditorSceneData): void {
    if (!data.loadedMap) throw new Error('MapEditorScene requires a loaded map');
    this.loadedMap = data.loadedMap;
  }

  create(): void {
    const initialTile = this.initialTileId();
    const query = new URLSearchParams(window.location.search);
    const requestedObjectId = query.get('templateObject');
    const requestedVisualId = query.get('templateVisual');
    const requestedObject = requestedObjectId && requestedVisualId && isObjectArchetypeId(requestedObjectId)
      ? getObjectVisualChoice(requestedObjectId, requestedVisualId)
      : undefined;
    const initialObject = requestedObject ?? getObjectVisualChoices()[0];
    this.editor = new MapEditorState(
      this.loadedMap.map,
      initialTile,
      initialObject.objectId,
      initialObject.visualId,
    );
    this.templateEditor = new ObjectTemplateEditorState(initialObject.objectId, initialObject.visualId);
    this.collisionGroup = this.physics.add.staticGroup();
    this.previewTileFactory = new TileFactory({
      scene: this,
      collisionTiles: this.collisionGroup,
      dimensions: this.loadedMap.dimensions,
      seed: this.areaSeed(),
      physicsEnabled: false,
    });
    this.previewObjectFactory = new ObjectFactory({
      scene: this,
      staticGroup: this.collisionGroup,
      physicsEnabled: false,
      animatedVisualsEnabled: false,
    });

    this.cameras.main.setBounds(0, 0, this.loadedMap.dimensions.width, this.loadedMap.dimensions.height);
    this.cameras.main.setZoom(0.8);
    this.cameras.main.centerOn(this.loadedMap.map.player.spawn.x, this.loadedMap.map.player.spawn.y);
    this.input.mouse?.disableContextMenu();

    const panel = document.querySelector<HTMLElement>('[data-map-editor-panel]');
    if (!panel) throw new Error('Missing map editor panel');
    const inspector = document.querySelector<HTMLElement>('[data-map-editor-inspector]');
    if (!inspector) throw new Error('Missing map editor inspector');
    const previews = this.buildContentPreviews();
    this.unmountPanel = mountMapEditorPanel(panel, this.editor, previews, this.templateEditor);
    this.unmountInspector = mountMapEditorInspector(
      inspector,
      this.templateEditor,
      { objects: previews.objects },
      this.editor,
    );
    this.unsubscribeState = this.editor.subscribe((state) => {
      const toolChanged = state.tool !== this.lastTool;
      const selectionChanged = state.selectedInstanceId !== this.lastSelectedInstanceId;
      this.lastTool = state.tool;
      this.lastSelectedInstanceId = state.selectedInstanceId;
      if (state.revision !== this.lastRevision) {
        this.lastRevision = state.revision;
        this.renderDocument();
      } else {
        if (toolChanged || selectionChanged) this.renderOverlays();
        this.renderSelectionMarker();
      }
    });
    this.lastTemplateRevision = this.templateEditor.value.revision;
    this.lastTemplateOverlaySettings = this.templateOverlaySettings();
    this.unsubscribeTemplate = this.templateEditor.subscribe((state) => {
      const previousOverlaySettings = this.lastTemplateOverlaySettings;
      const nextOverlaySettings = this.templateOverlaySettings();
      const overlaySettingsChanged = (
        state.showAllMatchingOverlays !== previousOverlaySettings.showAllMatchingOverlays
        || state.showFrameOverlay !== previousOverlaySettings.showFrameOverlay
        || state.showColliderOverlay !== previousOverlaySettings.showColliderOverlay
        || state.showOcclusionOverlay !== previousOverlaySettings.showOcclusionOverlay
      );
      this.lastTemplateOverlaySettings = nextOverlaySettings;
      if (state.revision === this.lastTemplateRevision) {
        if (overlaySettingsChanged && this.lastRevision >= 0) this.renderOverlays();
        return;
      }
      this.lastTemplateRevision = state.revision;
      if (this.lastRevision >= 0) this.renderDocument();
    });

    this.bindPointer();
    this.bindKeyboard();
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => this.destroyEditor());
  }

  update(_time: number, delta: number): void {
    if (!this.cursors || !this.wasd) return;
    if (isUiEditingActive(document.activeElement)) return;
    const speed = (650 * delta / 1000) / this.cameras.main.zoom;
    if (this.cursors.left.isDown || this.wasd.left.isDown) this.cameras.main.scrollX -= speed;
    if (this.cursors.right.isDown || this.wasd.right.isDown) this.cameras.main.scrollX += speed;
    if (this.cursors.up.isDown || this.wasd.up.isDown) this.cameras.main.scrollY -= speed;
    if (this.cursors.down.isDown || this.wasd.down.isDown) this.cameras.main.scrollY += speed;
  }

  private bindPointer(): void {
    this.input.on('pointerdown', (pointer: Phaser.Input.Pointer) => {
      const world = this.cameras.main.getWorldPoint(pointer.x, pointer.y);
      if (pointer.rightButtonDown()) {
        this.pickContentAt(world.x, world.y);
        return;
      }
      if (this.editor.value.tool === 'pan' || pointer.middleButtonDown()) {
        this.panPointer = { x: pointer.x, y: pointer.y };
        return;
      }
      if (this.editor.value.tool === 'terrain') {
        this.beginPaintDrag(world.x, world.y);
        return;
      }
      if (this.editor.value.tool === 'object') {
        this.beginObjectStampDrag(world.x, world.y);
        return;
      }
      if (this.editor.value.tool === 'select') {
        this.beginObjectMoveDrag(world.x, world.y);
        return;
      }
      if (this.editor.value.tool === 'erase') {
        this.eraseDragStart = { x: world.x, y: world.y };
        this.renderEraseDrag(world.x, world.y);
        return;
      }
      if (this.editor.value.tool === 'safe-zone') {
        const zoneIndex = this.safeZoneIndexAt(world.x, world.y);
        if (zoneIndex === undefined) this.beginSafeZoneDrag(world.x, world.y);
        else this.beginSafeZoneMove(zoneIndex, world.x, world.y);
        return;
      }
      this.applyTool(world.x, world.y);
    });
    this.input.on('pointermove', (pointer: Phaser.Input.Pointer) => {
      const worldPoint = this.cameras.main.getWorldPoint(pointer.x, pointer.y);
      this.updateCursorGhost(worldPoint.x, worldPoint.y);
      if (!pointer.isDown) return;
      if (this.panPointer) {
        const dx = pointer.x - this.panPointer.x;
        const dy = pointer.y - this.panPointer.y;
        this.cameras.main.scrollX -= dx / this.cameras.main.zoom;
        this.cameras.main.scrollY -= dy / this.cameras.main.zoom;
        this.panPointer = { x: pointer.x, y: pointer.y };
        return;
      }
      const world = worldPoint;
      if (this.paintDrag) {
        this.extendPaintDrag(world.x, world.y);
        return;
      }
      if (this.objectStampDrag) {
        this.extendObjectStampDrag(world.x, world.y);
        return;
      }
      if (this.objectMoveDrag) {
        this.updateObjectMoveDrag(world.x, world.y);
        return;
      }
      if (this.safeZoneMove) {
        this.updateSafeZoneMove(world.x, world.y);
        return;
      }
      if (this.editor.value.tool === 'erase' && this.eraseDragStart) {
        this.renderEraseDrag(world.x, world.y);
        return;
      }
      if (this.safeZoneDragStart) this.updateSafeZoneDrag(world.x, world.y);
    });
    this.input.on('pointerup', (pointer: Phaser.Input.Pointer) => {
      const world = this.cameras.main.getWorldPoint(pointer.x, pointer.y);
      if (this.paintDrag) this.finishPaintDrag();
      if (this.objectStampDrag) this.finishObjectStampDrag();
      if (this.objectMoveDrag) this.finishObjectMoveDrag();
      if (this.eraseDragStart) {
        this.finishEraseDrag(world.x, world.y);
      }
      if (this.safeZoneDragStart) this.finishSafeZoneDrag(world.x, world.y);
      if (this.safeZoneMove) this.finishSafeZoneMove();
      this.panPointer = undefined;
    });
    this.input.on('wheel', (_pointer: Phaser.Input.Pointer, _objects: unknown[], _dx: number, dy: number) => {
      const zoom = Phaser.Math.Clamp(this.cameras.main.zoom - dy * 0.001, 0.25, 2);
      this.cameras.main.setZoom(zoom);
      this.editor.notify(`Zoom ${Math.round(zoom * 100)}%`);
    });
  }

  private pickContentAt(worldX: number, worldY: number): void {
    const objectHit = this.movableObjectAt(worldX, worldY);
    if (objectHit) {
      const objectId = objectHit.object.objectId;
      if (!isObjectArchetypeId(objectId)) return;
      this.editor.setObject(objectId, objectHit.object.visualId);
      this.editor.selectInstance(objectHit.instanceId);
      this.templateEditor.select(objectId, objectHit.object.visualId);
      this.editor.notify(`Picked ${objectId} / ${objectHit.object.visualId}`);
      return;
    }

    const tile = this.tileAt(worldX, worldY);
    if (!tile) return;
    const layer = this.editor.value.map.layers[0];
    const row = layer?.rows[tile.y];
    const tileId = row ? layer.legend[row[tile.x]] : undefined;
    if (typeof tileId !== 'string' || !isWorldTileId(tileId)) return;
    this.editor.setTile(tileId);
    this.editor.selectInstance(undefined);
    this.editor.notify(`Picked ${tileId}`);
  }

  private bindKeyboard(): void {
    const keyboard = this.input.keyboard;
    if (!keyboard) return;
    this.cursors = keyboard.createCursorKeys();
    this.wasd = keyboard.addKeys({ up: 'W', down: 'S', left: 'A', right: 'D' }) as typeof this.wasd;
    const toolKeys: Readonly<Record<string, Parameters<MapEditorState['setTool']>[0]>> = {
      H: 'pan', B: 'terrain', O: 'object', V: 'select', X: 'erase', Z: 'safe-zone', P: 'spawn', I: 'entry', E: 'exit',
    };
    keyboard.on('keydown', (event: KeyboardEvent) => {
      if (isUiEditingActive(event.target)) return;
      if (event.ctrlKey && event.key.toLowerCase() === 's') {
        event.preventDefault();
        void this.editor.save();
        return;
      }
      if (event.ctrlKey && event.key.toLowerCase() === 'z') {
        event.preventDefault();
        this.editor.undo();
        return;
      }
      if (event.ctrlKey && event.key.toLowerCase() === 'y') {
        event.preventDefault();
        this.editor.redo();
        return;
      }
      if ((event.key === 'Delete' || event.key === 'Backspace') && this.editor.value.selectedInstanceId) {
        event.preventDefault();
        this.deleteSelectedObject();
        return;
      }
      if ((event.key === 'Delete' || event.key === 'Backspace') && this.editor.value.selectedSafeZoneIndex !== undefined) {
        event.preventDefault();
        this.deleteSafeZone(this.editor.value.selectedSafeZoneIndex);
        return;
      }
      const tool = toolKeys[event.key.toUpperCase()];
      if (tool) this.editor.setTool(tool);
    });
  }

  private applyTool(worldX: number, worldY: number): void {
    const { map, tool } = this.editor.value;
    const tileX = Math.floor(worldX / map.tileSize);
    const tileY = Math.floor(worldY / map.tileSize);
    if (tileX < 0 || tileY < 0 || tileX >= map.size.columns || tileY >= map.size.rows) return;
    const centerX = tileX * map.tileSize + map.tileSize / 2;
    const centerY = tileY * map.tileSize + map.tileSize / 2;

    switch (tool) {
      case 'terrain':
        this.editor.mutate(`Painted ${this.editor.value.tileId} at ${tileX}, ${tileY}`, (draft) => {
          this.setTerrain(draft, tileX, tileY, this.editor.value.tileId);
        });
        break;
      case 'erase': {
        const object = this.nearestObject(worldX, worldY, map.tileSize * 0.7);
        if (object) {
          this.editor.mutate(`Removed ${object.instanceId}`, (draft) => {
            draft.objects = draft.objects.filter((candidate) => candidate.instanceId !== object.instanceId);
          });
        } else {
          this.editor.mutate(`Cleared terrain at ${tileX}, ${tileY}`, (draft) => {
            this.setTerrain(draft, tileX, tileY, this.firstLegendTile(draft));
          });
        }
        break;
      }
      case 'select':
        break;
      case 'spawn':
        this.editor.mutate(`Moved player spawn to ${tileX}, ${tileY}`, (draft) => {
          draft.player.spawn = { x: centerX, y: centerY };
        });
        break;
      case 'entry':
        this.editor.mutate(`Set ${this.editor.value.direction} entry`, (draft) => {
          draft.player.entries[this.editor.value.direction] = { x: centerX, y: centerY };
        });
        break;
      case 'exit':
        this.placeExit(this.editor.value.direction);
        break;
      case 'safe-zone':
      case 'pan':
        break;
    }
  }

  private beginPaintDrag(worldX: number, worldY: number): void {
    const start = this.tileAt(worldX, worldY);
    if (!start) return;
    this.paintDrag = {
      tileId: this.editor.value.tileId,
      cells: new Map(),
      previews: [],
      hiddenTerrain: new Map(),
      last: start,
    };
    this.addPaintCell(start.x, start.y);
  }

  private extendPaintDrag(worldX: number, worldY: number): void {
    const drag = this.paintDrag;
    const next = this.tileAt(worldX, worldY);
    if (!drag || !next) return;
    this.visitTileLine(drag.last, next, (tileX, tileY) => this.addPaintCell(tileX, tileY));
    drag.last = next;
  }

  private addPaintCell(tileX: number, tileY: number): void {
    const drag = this.paintDrag;
    if (!drag) return;
    const key = `${tileX},${tileY}`;
    if (drag.cells.has(key)) return;
    drag.cells.set(key, { x: tileX, y: tileY });
    const existing = this.renderedTerrain.get(key);
    if (existing) {
      existing.setVisible(false);
      drag.hiddenTerrain.set(key, existing);
    }
    const preview = this.previewTileFactory.create(drag.tileId, tileX, tileY);
    preview.setDepth(resolveExplicitDepth('editor-drag-lift')).setAlpha(1);
    drag.previews.push(preview);
    this.editor.notify(`Painting ${drag.tileId} — ${drag.cells.size} tiles`);
  }

  private finishPaintDrag(): void {
    const drag = this.paintDrag;
    this.paintDrag = undefined;
    if (!drag) return;
    const changed = this.editor.mutate(`Painted ${drag.cells.size} tiles with ${drag.tileId}`, (draft) => {
      for (const cell of drag.cells.values()) this.setTerrain(draft, cell.x, cell.y, drag.tileId);
    });
    for (const preview of drag.previews) preview.destroy();
    if (!changed) {
      for (const terrain of drag.hiddenTerrain.values()) terrain.setVisible(true);
      this.editor.notify('Terrain already used the selected tile');
    }
  }

  private visitTileLine(start: TilePoint, end: TilePoint, visit: (x: number, y: number) => void): void {
    let x = start.x;
    let y = start.y;
    const dx = Math.abs(end.x - start.x);
    const stepX = start.x < end.x ? 1 : -1;
    const dy = -Math.abs(end.y - start.y);
    const stepY = start.y < end.y ? 1 : -1;
    let error = dx + dy;
    while (true) {
      visit(x, y);
      if (x === end.x && y === end.y) break;
      const doubled = error * 2;
      if (doubled >= dy) {
        error += dy;
        x += stepX;
      }
      if (doubled <= dx) {
        error += dx;
        y += stepY;
      }
    }
  }

  // ── Object stamping (left-drag places one object per crossed tile) ────────

  private beginObjectStampDrag(worldX: number, worldY: number): void {
    const start = this.tileAt(worldX, worldY);
    if (!start) return;
    this.objectStampDrag = {
      objectId: this.editor.value.objectId,
      visualId: this.editor.value.objectVisualId,
      cells: new Map(),
      previews: [],
      last: start,
    };
    this.addObjectStampCell(start.x, start.y);
  }

  private extendObjectStampDrag(worldX: number, worldY: number): void {
    const drag = this.objectStampDrag;
    const next = this.tileAt(worldX, worldY);
    if (!drag || !next) return;
    this.visitTileLine(drag.last, next, (tileX, tileY) => this.addObjectStampCell(tileX, tileY));
    drag.last = next;
  }

  private addObjectStampCell(tileX: number, tileY: number): void {
    const drag = this.objectStampDrag;
    if (!drag) return;
    const key = `${tileX},${tileY}`;
    if (drag.cells.has(key)) return;
    drag.cells.set(key, { x: tileX, y: tileY });
    const map = this.editor.value.map;
    const preview = this.previewObjectFactory.create(drag.objectId, {
      x: tileX * map.tileSize + map.tileSize / 2,
      y: (tileY + 1) * map.tileSize,
      visualId: drag.visualId,
      depthMode: 'explicit',
      depth: resolveExplicitDepth('editor-cursor'),
    });
    preview.setAlpha(0.65);
    drag.previews.push(preview);
    this.editor.notify(`Stamping ${drag.objectId} / ${drag.visualId} — ${drag.cells.size} positions`);
  }

  private finishObjectStampDrag(): void {
    const drag = this.objectStampDrag;
    this.objectStampDrag = undefined;
    if (!drag) return;
    const map = this.editor.value.map;
    this.editor.mutate(`Placed ${drag.cells.size} × ${drag.objectId} / ${drag.visualId}`, (draft) => {
      for (const cell of drag.cells.values()) {
        draft.objects.push({
          instanceId: this.createInstanceId(drag.objectId),
          objectId: drag.objectId,
          visualId: drag.visualId,
          x: cell.x * map.tileSize + map.tileSize / 2,
          y: (cell.y + 1) * map.tileSize,
        });
      }
    });
    for (const preview of drag.previews) preview.destroy();
  }

  private beginObjectMoveDrag(worldX: number, worldY: number): void {
    const hit = this.movableObjectAt(worldX, worldY);
    if (!hit) {
      this.editor.selectInstance(undefined);
      return;
    }
    this.objectMoveDrag = {
      instanceId: hit.instanceId,
      image: hit.image,
      startX: getObjectAnchor(hit.image)[0],
      startY: getObjectAnchor(hit.image)[1],
      pointerOffsetX: getObjectAnchor(hit.image)[0] - worldX,
      pointerOffsetY: getObjectAnchor(hit.image)[1] - worldY,
      moved: false,
    };
    setObjectDepthMode(hit.image, 'explicit', resolveExplicitDepth('editor-drag-lift'));
    hit.image.setAlpha(0.82);
    this.editor.selectInstance(hit.instanceId);
    this.editor.notify(`Dragging ${hit.instanceId} — release to place`);
  }

  private updateObjectMoveDrag(worldX: number, worldY: number): void {
    const drag = this.objectMoveDrag;
    if (!drag) return;
    const map = this.editor.value.map;
    const width = map.size.columns * map.tileSize;
    const height = map.size.rows * map.tileSize;
    const x = Phaser.Math.Clamp(worldX + drag.pointerOffsetX, 0, width);
    const y = Phaser.Math.Clamp(worldY + drag.pointerOffsetY, 1, height);
    setObjectAnchor(drag.image, x, y);
    drag.moved ||= Phaser.Math.Distance.Between(drag.startX, drag.startY, x, y) >= 2;
    this.drawMoveHandles();
    this.renderSelectionMarker();
  }

  private finishObjectMoveDrag(): void {
    const drag = this.objectMoveDrag;
    this.objectMoveDrag = undefined;
    if (!drag) return;
    const map = this.editor.value.map;
    const [anchorX, anchorY] = getObjectAnchor(drag.image);
    const tileX = Phaser.Math.Clamp(Math.floor(anchorX / map.tileSize), 0, map.size.columns - 1);
    const tileY = Phaser.Math.Clamp(Math.floor((anchorY - 1) / map.tileSize), 0, map.size.rows - 1);
    const targetX = tileX * map.tileSize + map.tileSize / 2;
    const targetY = (tileY + 1) * map.tileSize;
    if (!drag.moved) {
      setObjectAnchor(drag.image, drag.startX, drag.startY);
      setObjectDepthMode(drag.image, 'world-sorted');
      drag.image.setAlpha(1);
      this.drawMoveHandles();
      this.renderSelectionMarker();
      return;
    }
    const changed = this.editor.mutate(`Moved ${drag.instanceId}`, (draft) => {
      const object = draft.objects.find((candidate) => candidate.instanceId === drag.instanceId);
      if (!object) return;
      object.x = targetX;
      object.y = targetY;
    });
    if (!changed) {
      setObjectAnchor(drag.image, drag.startX, drag.startY);
      setObjectDepthMode(drag.image, 'world-sorted');
      drag.image.setAlpha(1);
      this.drawMoveHandles();
    }
    this.editor.selectInstance(drag.instanceId);
  }

  private movableObjectAt(worldX: number, worldY: number): { instanceId: string; image: Phaser.GameObjects.Image; object: EditableObjectInstance } | undefined {
    const objects = this.editor.value.map.objects;
    let hit: { instanceId: string; image: Phaser.GameObjects.Image; object: EditableObjectInstance } | undefined;
    let hitDepth = Number.NEGATIVE_INFINITY;
    for (let index = objects.length - 1; index >= 0; index -= 1) {
      const object = objects[index];
      const image = this.renderedInstances.get(object.instanceId);
      if (!image) continue;
      const bounds = image.getBounds();
      const padding = 5 / this.cameras.main.zoom;
      if (
        worldX >= bounds.x - padding
        && worldX <= bounds.right + padding
        && worldY >= bounds.y - padding
        && worldY <= bounds.bottom + padding
      ) {
        if (!hit || image.depth > hitDepth) {
          hit = { instanceId: object.instanceId, image, object };
          hitDepth = image.depth;
        }
      }
    }
    return hit;
  }

  // ── Cursor ghost (selected terrain/object follows the pointer) ────────────

  private updateCursorGhost(worldX: number, worldY: number): void {
    const { tool } = this.editor.value;
    const tile = this.tileAt(worldX, worldY);
    const dragActive = this.paintDrag !== undefined || this.objectStampDrag !== undefined;

    if (!tile || dragActive || (tool !== 'terrain' && tool !== 'object')) {
      this.cursorGhost?.setVisible(false);
      return;
    }

    const key = tool === 'terrain'
      ? `terrain:${this.editor.value.tileId}`
      : `object:${this.editor.value.objectId}:${this.editor.value.objectVisualId}`;

    let ghost = this.cursorGhost;
    if (this.cursorGhostKey !== key || !ghost) {
      ghost?.destroy();
      ghost = this.createCursorGhost(tool);
      this.cursorGhost = ghost;
      this.cursorGhostKey = key;
    }

    const map = this.editor.value.map;
    if (tool === 'terrain') {
      ghost.setPosition(tile.x * map.tileSize, tile.y * map.tileSize);
    } else {
      setObjectAnchor(
        ghost,
        tile.x * map.tileSize + map.tileSize / 2,
        (tile.y + 1) * map.tileSize,
      );
    }
    ghost.setVisible(true);
  }

  private createCursorGhost(tool: EditorTool): Phaser.GameObjects.Image {
    if (tool === 'terrain') {
      return this.previewTileFactory.create(this.editor.value.tileId, 0, 0)
        .setDepth(resolveExplicitDepth('editor-cursor'))
        .setAlpha(0.55);
    }
    return this.previewObjectFactory.create(this.editor.value.objectId, {
      x: 0,
      y: 0,
      visualId: this.editor.value.objectVisualId,
      depthMode: 'explicit',
      depth: resolveExplicitDepth('editor-cursor'),
    }).setAlpha(0.65);
  }

  private tileAt(worldX: number, worldY: number): TilePoint | undefined {
    const map = this.editor.value.map;
    const x = Math.floor(worldX / map.tileSize);
    const y = Math.floor(worldY / map.tileSize);
    if (x < 0 || y < 0 || x >= map.size.columns || y >= map.size.rows) return undefined;
    return { x, y };
  }

  private beginSafeZoneDrag(worldX: number, worldY: number): void {
    const map = this.editor.value.map;
    const tile = this.tileAt(worldX, worldY);
    if (!tile) return;
    this.safeZoneDragStart = {
      x: tile.x * map.tileSize,
      y: tile.y * map.tileSize,
    };
    this.safeZoneDragRect = {
      x: this.safeZoneDragStart.x,
      y: this.safeZoneDragStart.y,
      w: map.tileSize,
      h: map.tileSize,
    };
    this.renderSafeZoneDrag();
  }

  private updateSafeZoneDrag(worldX: number, worldY: number): void {
    const start = this.safeZoneDragStart;
    if (!start) return;
    const map = this.editor.value.map;
    const width = map.size.columns * map.tileSize;
    const height = map.size.rows * map.tileSize;
    const targetX = Phaser.Math.Clamp(worldX, 0, width);
    const targetY = Phaser.Math.Clamp(worldY, 0, height);
    const left = targetX >= start.x ? start.x : Math.max(0, targetX);
    const top = targetY >= start.y ? start.y : Math.max(0, targetY);
    this.safeZoneDragRect = {
      x: Math.floor(left / map.tileSize) * map.tileSize,
      y: Math.floor(top / map.tileSize) * map.tileSize,
      w: Math.max(map.tileSize, Math.ceil(Math.abs(targetX - start.x) / map.tileSize) * map.tileSize),
      h: Math.max(map.tileSize, Math.ceil(Math.abs(targetY - start.y) / map.tileSize) * map.tileSize),
    };
    this.safeZoneDragRect.w = Math.min(this.safeZoneDragRect.w, width - this.safeZoneDragRect.x);
    this.safeZoneDragRect.h = Math.min(this.safeZoneDragRect.h, height - this.safeZoneDragRect.y);
    this.renderSafeZoneDrag();
  }

  private renderSafeZoneDrag(): void {
    const rect = this.safeZoneDragRect;
    if (!rect) return;
    this.safeZoneDragMarker?.destroy();
    this.safeZoneDragMarker = this.add.graphics().setDepth(resolveExplicitDepth('editor-selection-marker', 1)).setName('editor-safe-zone-draft');
    this.safeZoneDragMarker.fillStyle(0x20ff63, 0.3).fillRect(rect.x, rect.y, rect.w, rect.h);
    this.safeZoneDragMarker.lineStyle(6, 0x65ff91, 1).strokeRect(rect.x, rect.y, rect.w, rect.h);
    this.editor.notify(`Safe zone ${rect.w} × ${rect.h} px`);
  }

  private finishSafeZoneDrag(worldX: number, worldY: number): void {
    if (!this.safeZoneDragStart) return;
    this.updateSafeZoneDrag(worldX, worldY);
    const rect = this.safeZoneDragRect;
    this.safeZoneDragStart = undefined;
    this.safeZoneDragRect = undefined;
    this.safeZoneDragMarker?.destroy();
    this.safeZoneDragMarker = undefined;
    if (!rect) return;
    this.editor.mutate(`Created monster safe zone (${rect.w} × ${rect.h})`, (draft) => {
      draft.enemySafeZones.push(rect);
    });
    this.editor.selectSafeZone(this.editor.value.map.enemySafeZones.length - 1);
  }

  private beginSafeZoneMove(index: number, worldX: number, worldY: number): void {
    const zone = this.editor.value.map.enemySafeZones[index];
    if (!zone) return;
    this.editor.selectSafeZone(index);
    this.safeZoneMove = {
      index,
      w: zone.w,
      h: zone.h,
      offsetX: worldX - zone.x,
      offsetY: worldY - zone.y,
      startX: zone.x,
      startY: zone.y,
      x: zone.x,
      y: zone.y,
    };
  }

  private updateSafeZoneMove(worldX: number, worldY: number): void {
    const move = this.safeZoneMove;
    if (!move) return;
    const map = this.editor.value.map;
    const width = map.size.columns * map.tileSize;
    const height = map.size.rows * map.tileSize;
    move.x = Phaser.Math.Clamp(worldX - move.offsetX, 0, width - move.w);
    move.y = Phaser.Math.Clamp(worldY - move.offsetY, 0, height - move.h);
    this.safeZoneDragMarker?.destroy();
    this.safeZoneDragMarker = this.add.graphics().setDepth(resolveExplicitDepth('editor-selection-marker', 2)).setName('editor-safe-zone-move');
    this.safeZoneDragMarker.fillStyle(0x20ff63, 0.34).fillRect(move.x, move.y, move.w, move.h);
    this.safeZoneDragMarker.lineStyle(7, 0xa0ffb9, 1).strokeRect(move.x, move.y, move.w, move.h);
    this.editor.notify(`Moving safe zone ${move.index + 1}`);
  }

  private finishSafeZoneMove(): void {
    const move = this.safeZoneMove;
    this.safeZoneMove = undefined;
    this.safeZoneDragMarker?.destroy();
    this.safeZoneDragMarker = undefined;
    if (!move) return;
    const moved = Phaser.Math.Distance.Between(move.startX, move.startY, move.x, move.y) >= 2;
    if (!moved) {
      this.editor.selectSafeZone(move.index);
      return;
    }
    this.editor.mutate(`Moved safe zone ${move.index + 1}`, (draft) => {
      const zone = draft.enemySafeZones[move.index];
      if (!zone) return;
      draft.enemySafeZones[move.index] = { ...zone, x: Math.round(move.x), y: Math.round(move.y) };
    });
    this.editor.selectSafeZone(move.index);
  }

  private deleteSafeZone(index: number): void {
    if (!this.editor.value.map.enemySafeZones[index]) return;
    this.editor.mutate(`Deleted safe zone ${index + 1}`, (draft) => {
      draft.enemySafeZones.splice(index, 1);
    });
    this.editor.selectSafeZone(undefined);
    this.editor.notify(`Deleted safe zone ${index + 1} — Ctrl+Z restores it`);
  }

  private placeExit(direction: MapDirection): void {
    const target = connectionAt(direction, this.editor.value.map)?.to;
    if (!target) {
      this.editor.notify(`Choose a ${direction} map in Map Connections first`);
      return;
    }
    this.editor.notify(`${direction} exit is connected to ${target}`);
  }

  private setTerrain(map: EditableMap, tileX: number, tileY: number, tileId: WorldTileId): void {
    const layer = map.layers[0];
    let token = Object.entries(layer.legend).find(([, value]) => value === tileId)?.[0];
    if (!token) {
      token = [...TOKEN_CANDIDATES].find((candidate) => !(candidate in layer.legend));
      if (!token) throw new Error('Terrain legend has no available token');
      layer.legend[token] = tileId;
    }
    const row = layer.rows[tileY];
    layer.rows[tileY] = `${row.slice(0, tileX)}${token}${row.slice(tileX + 1)}`;
  }

  private firstLegendTile(map: EditableMap): WorldTileId {
    const tileId = Object.values(map.layers[0].legend).find(isWorldTileId);
    return tileId ?? getTileIds()[0];
  }

  private nearestObject(x: number, y: number, radius: number): EditableObjectInstance | undefined {
    let nearest: EditableObjectInstance | undefined;
    let nearestDistance = radius;
    for (const object of this.editor.value.map.objects) {
      const distance = Phaser.Math.Distance.Between(x, y, object.x, object.y);
      if (distance <= nearestDistance) {
        nearest = object;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  private safeZoneIndexAt(x: number, y: number): number | undefined {
    const zones = this.editor.value.map.enemySafeZones;
    for (let index = zones.length - 1; index >= 0; index -= 1) {
      const zone = zones[index];
      if (x >= zone.x && x <= zone.x + zone.w && y >= zone.y && y <= zone.y + zone.h) return index;
    }
    return undefined;
  }

  private deleteSelectedObject(): void {
    const selectedId = this.editor.value.selectedInstanceId;
    if (!selectedId) return;
    this.editor.mutate(`Deleted ${selectedId}`, (draft) => {
      draft.objects = draft.objects.filter((object) => object.instanceId !== selectedId);
    });
    this.editor.selectInstance(undefined);
    this.editor.notify(`Deleted ${selectedId} — Ctrl+Z restores it`);
  }

  private renderEraseDrag(worldX: number, worldY: number): void {
    if (!this.eraseDragStart) return;
    this.eraseDragMarker?.destroy();
    const left = Math.min(this.eraseDragStart.x, worldX);
    const top = Math.min(this.eraseDragStart.y, worldY);
    const width = Math.abs(worldX - this.eraseDragStart.x);
    const height = Math.abs(worldY - this.eraseDragStart.y);
    this.eraseDragMarker = this.add.graphics().setDepth(resolveExplicitDepth('editor-selection-marker', 3)).setName('editor-erase-selection');
    this.eraseDragMarker.fillStyle(0xff5f56, 0.14).fillRect(left, top, width, height);
    this.eraseDragMarker.lineStyle(3, 0xff8b75, 0.95).strokeRect(left, top, width, height);
  }

  private finishEraseDrag(worldX: number, worldY: number): void {
    const start = this.eraseDragStart;
    this.eraseDragStart = undefined;
    this.eraseDragMarker?.destroy();
    this.eraseDragMarker = undefined;
    if (!start) return;

    const map = this.editor.value.map;
    const dragDistance = Phaser.Math.Distance.Between(start.x, start.y, worldX, worldY);
    if (dragDistance < map.tileSize * 0.2) {
      this.applyTool(start.x, start.y);
      return;
    }

    const padding = map.tileSize * 0.25;
    const left = Math.min(start.x, worldX) - padding;
    const right = Math.max(start.x, worldX) + padding;
    const top = Math.min(start.y, worldY) - padding;
    const bottom = Math.max(start.y, worldY) + padding;
    const instanceIds = new Set(
      map.objects
        .filter((object) => object.x >= left && object.x <= right && object.y >= top && object.y <= bottom)
        .map((object) => object.instanceId),
    );
    if (instanceIds.size === 0) {
      this.editor.notify('No objects inside erase selection');
      return;
    }
    this.editor.mutate(`Deleted ${instanceIds.size} objects`, (draft) => {
      draft.objects = draft.objects.filter((object) => !instanceIds.has(object.instanceId));
    });
  }

  private renderDocument(): void {
    this.transitionLayer?.destroy();
    this.transitionLayer = undefined;
    this.templatePreview?.destroy();
    this.templatePreview = undefined;
    for (const object of this.renderedObjects) object.destroy();
    this.renderedObjects = [];
    this.renderedTerrain.clear();
    this.renderedInstances.clear();
    const state = this.editor.value;
    const seed = this.areaSeed();
    const tileFactory = new TileFactory({
      scene: this,
      collisionTiles: this.collisionGroup,
      dimensions: this.loadedMap.dimensions,
      seed,
      physicsEnabled: false,
    });
    const objectFactory = new ObjectFactory({
      scene: this,
      staticGroup: this.collisionGroup,
      physicsEnabled: false,
      animatedVisualsEnabled: false,
    });

    const terrainGrid: WorldTileId[][] = [];
    const layer = state.map.layers[0];
    layer.rows.forEach((row, tileY) => {
      const targetRow: WorldTileId[] = [];
      for (let tileX = 0; tileX < row.length; tileX += 1) {
        const tileId = layer.legend[row[tileX]];
        if (isWorldTileId(tileId)) {
          const terrain = tileFactory.create(tileId, tileX, tileY);
          this.renderedTerrain.set(`${tileX},${tileY}`, terrain);
          this.renderedObjects.push(terrain);
          targetRow[tileX] = tileId;
        }
      }
      terrainGrid[tileY] = targetRow;
    });
    this.transitionLayer = new TerrainTransitionRenderer({
      scene: this,
      tileFactory,
      dimensions: this.loadedMap.dimensions,
      seed,
    }).render(terrainGrid);
    for (const object of state.map.objects) {
      if (!getObjectArchetypeIds().includes(object.objectId as ObjectArchetypeId)) continue;
      const image = objectFactory.create(object.objectId as ObjectArchetypeId, {
        x: object.x,
        y: object.y,
        visualId: object.visualId,
        sortId: object.instanceId,
        initialState: object.initialState,
      });
      image.setData('instanceId', object.instanceId);
      this.renderedInstances.set(object.instanceId, image);
      this.renderedObjects.push(image);
    }
    this.renderOverlays();
    this.renderSelectionMarker();
  }

  private renderOverlays(): void {
    for (const object of this.overlayObjects) object.destroy();
    this.overlayObjects = [];
    this.moveHandles = undefined;
    const map = this.editor.value.map;
    this.renderGrid(map);
    this.renderMapMarkers(map);
    this.renderTemplateOverlays();
    if (this.editor.value.tool === 'select') this.renderMoveHandles();
  }

  private renderTemplateOverlays(): void {
    const template = this.templateEditor.value;
    const selected = template.selected;
    this.templatePreview?.destroy();
    this.templatePreview = undefined;
    if (!selected || !template.draft) return;

    const resolved = getObjectVisualChoice(selected.objectId, selected.visualId);
    if (!resolved) return;

    const graphics = this.add.graphics().setDepth(resolveExplicitDepth('editor-template-overlay')).setName('editor-template-overlays');
    const asset = getAsset(resolved.assetId);
    const alphaMasks = new Map<string, ReturnType<typeof buildSourceAlphaMask>>();
    const drawGeometry = (image: Phaser.GameObjects.Image): void => {
      const [anchorX, anchorY] = getObjectAnchor(image);
      const bounds = image.getBounds();
      const frameX = bounds.x - resolved.visualOffset.x;
      const frameY = bounds.y - resolved.visualOffset.y;
      const drawOutlinedRect = (
        x: number,
        y: number,
        width: number,
        height: number,
        color: number,
        lineWidth: number,
      ): void => {
        graphics.lineStyle(lineWidth + 3, EDITOR_SELECTION_STYLE.shadow, 0.85).strokeRect(x, y, width, height);
        graphics.lineStyle(lineWidth, color, 0.98).strokeRect(x, y, width, height);
      };
      if (template.showFrameOverlay) {
        drawOutlinedRect(
          frameX,
          frameY,
          bounds.width,
          bounds.height,
          EDITOR_GEOMETRY_STYLES.frame.phaser,
          2,
        );
        graphics.lineStyle(2, EDITOR_GEOMETRY_STYLES.frame.phaser, 0.72);
        graphics.lineBetween(anchorX - 8, anchorY, anchorX + 8, anchorY);
        graphics.lineBetween(anchorX, anchorY - 8, anchorX, anchorY + 8);
        if (resolved.visualOffset.x !== 0 || resolved.visualOffset.y !== 0) {
          graphics.lineStyle(2, EDITOR_SELECTION_STYLE.phaser, 0.9).lineBetween(anchorX, anchorY, image.x, image.y);
        }
      }
      if (template.showColliderOverlay && resolved.physics !== null && resolved.collider) {
        const colliderX = frameX + resolved.collider.offsetX;
        const colliderY = frameY + resolved.collider.offsetY;
        graphics.fillStyle(EDITOR_GEOMETRY_STYLES.collider.phaser, 0.22).fillRect(
          colliderX,
          colliderY,
          resolved.collider.width,
          resolved.collider.height,
        );
        drawOutlinedRect(
          colliderX,
          colliderY,
          resolved.collider.width,
          resolved.collider.height,
          EDITOR_GEOMETRY_STYLES.collider.phaser,
          3,
        );
      }
      if (template.showOcclusionOverlay && template.draft?.occlusionBounds && template.frameDimensions) {
        const occlusionRectangle = resolveWorldOcclusionRectangle(
          image,
          template.frameDimensions,
          template.draft.occlusionBounds,
        );
        graphics.fillStyle(EDITOR_GEOMETRY_STYLES.occlusion.phaser, 0.08).fillRect(
          occlusionRectangle.x,
          occlusionRectangle.y,
          occlusionRectangle.width,
          occlusionRectangle.height,
        );
        drawOutlinedRect(
          occlusionRectangle.x,
          occlusionRectangle.y,
          occlusionRectangle.width,
          occlusionRectangle.height,
          EDITOR_GEOMETRY_STYLES.occlusion.phaser,
          2,
        );
        const frameName = String(image.frame.name);
        const sourceMask = alphaMasks.get(frameName) ?? buildSourceAlphaMask(
          template.frameDimensions,
          (x, y) => this.textures.getPixelAlpha(x, y, asset.runtime.textureKey, image.frame.name),
          template.draft.occlusionBounds,
        );
        alphaMasks.set(frameName, sourceMask);
        graphics.fillStyle(EDITOR_GEOMETRY_STYLES.occlusion.phaser, 0.2);
        for (const occlusion of resolveWorldAlphaMaskRuns(image, template.frameDimensions, sourceMask)) {
          graphics.fillRect(occlusion.x, occlusion.y, occlusion.width, occlusion.height);
        }
      }
    };
    const matchingObjects = this.editor.value.map.objects.filter((object) => (
      object.objectId === selected.objectId && object.visualId === selected.visualId
    ));
    const selectedInstanceId = this.editor.value.selectedInstanceId;
    const selectedMatch = matchingObjects.find((object) => object.instanceId === selectedInstanceId);
    const overlayTargets = template.showAllMatchingOverlays
      ? matchingObjects
      : selectedMatch ? [selectedMatch] : [];
    for (const object of overlayTargets) {
      const image = this.renderedInstances.get(object.instanceId);
      if (!image) continue;
      drawGeometry(image);
    }
    if (overlayTargets.length === 0) {
      const map = this.editor.value.map;
      const view = this.cameras.main.worldView;
      const anchorX = Phaser.Math.Clamp(view.centerX, map.tileSize / 2, map.size.columns * map.tileSize - map.tileSize / 2);
      const anchorY = Phaser.Math.Clamp(view.centerY, 1, map.size.rows * map.tileSize);
      this.templatePreview = this.previewObjectFactory.create(selected.objectId, {
        x: anchorX,
        y: anchorY,
        visualId: selected.visualId,
        depthMode: 'explicit',
        depth: resolveExplicitDepth('editor-template-overlay'),
      }).setAlpha(0.62);
      drawGeometry(this.templatePreview);
    }
    this.overlayObjects.push(graphics);
  }

  private renderMoveHandles(): void {
    this.moveHandles = this.add.graphics().setDepth(resolveExplicitDepth('editor-selection-marker')).setName('editor-move-handles');
    this.overlayObjects.push(this.moveHandles);
    this.drawMoveHandles();
  }

  private drawMoveHandles(): void {
    const graphics = this.moveHandles;
    if (!graphics || this.editor.value.tool !== 'select') return;
    graphics.clear();
    for (const [instanceId, image] of this.renderedInstances) {
      const bounds = image.getBounds();
      const selected = instanceId === this.editor.value.selectedInstanceId;
      const padding = selected ? 5 : 3;
      const color = selected ? 0xffe078 : 0x69e4b1;
      graphics.fillStyle(color, selected ? 0.14 : 0.055).fillRect(
        bounds.x - padding,
        bounds.y - padding,
        bounds.width + padding * 2,
        bounds.height + padding * 2,
      );
      graphics.lineStyle(selected ? 3 : 1, color, selected ? 1 : 0.62).strokeRect(
        bounds.x - padding,
        bounds.y - padding,
        bounds.width + padding * 2,
        bounds.height + padding * 2,
      );
      graphics.fillStyle(color, selected ? 1 : 0.75).fillCircle(
        bounds.centerX,
        bounds.y - padding,
        selected ? 5 : 3,
      );
    }
  }

  private renderGrid(map: EditableMap): void {
    const graphics = this.add.graphics().setDepth(resolveExplicitDepth('editor-template-overlay'));
    graphics.lineStyle(1, 0xf4cf7a, 0.13);
    const width = map.size.columns * map.tileSize;
    const height = map.size.rows * map.tileSize;
    for (let x = 0; x <= width; x += map.tileSize) graphics.lineBetween(x, 0, x, height);
    for (let y = 0; y <= height; y += map.tileSize) graphics.lineBetween(0, y, width, y);
    graphics.lineStyle(3, 0xf4cf7a, 0.8).strokeRect(0, 0, width, height);
    this.overlayObjects.push(graphics);
  }

  private renderMapMarkers(map: EditableMap): void {
    const graphics = this.add.graphics().setDepth(resolveExplicitDepth('editor-template-overlay', 1));
    graphics.fillStyle(0x62ff9b, 0.9).fillCircle(map.player.spawn.x, map.player.spawn.y, 12);
    graphics.lineStyle(3, 0x0a1b15, 1).strokeCircle(map.player.spawn.x, map.player.spawn.y, 12);
    for (const [direction, point] of Object.entries(map.player.entries)) {
      if (!point) continue;
      graphics.fillStyle(0x67d8ff, 0.9).fillCircle(point.x, point.y, 10);
      const label = this.add.text(point.x, point.y - 18, direction[0].toUpperCase(), {
        fontFamily: 'Trebuchet MS', fontSize: '13px', color: '#d9f8ff', backgroundColor: '#102b35', padding: { x: 4, y: 2 },
      }).setOrigin(0.5).setDepth(resolveExplicitDepth('editor-template-overlay', 2));
      this.overlayObjects.push(label);
    }
    for (const exit of map.exits) {
      graphics.fillStyle(0xffb84d, 0.2).fillRect(exit.zone.x, exit.zone.y, exit.zone.w, exit.zone.h);
      graphics.lineStyle(3, 0xffb84d, 0.9).strokeRect(exit.zone.x, exit.zone.y, exit.zone.w, exit.zone.h);
    }
    // Safe zones are only visible while the safe-zone tool is active, so
    // their bright rectangles do not clutter normal editing.
    if (this.editor.value.tool === 'safe-zone') {
      for (const [index, zone] of map.enemySafeZones.entries()) {
        graphics.fillStyle(0x20ff63, 0.24).fillRect(zone.x, zone.y, zone.w, zone.h);
        graphics.lineStyle(6, 0x65ff91, 1).strokeRect(zone.x, zone.y, zone.w, zone.h);
        const label = this.add.text(zone.x + zone.w / 2, zone.y + zone.h / 2, `SAFE ${index + 1}`, {
          fontFamily: 'Trebuchet MS', fontSize: '14px', color: '#effff3', backgroundColor: '#0b4a20', padding: { x: 6, y: 3 },
        }).setOrigin(0.5).setDepth(resolveExplicitDepth('editor-template-overlay', 2));
        this.overlayObjects.push(label);
      }
    }
    this.overlayObjects.push(graphics);
  }

  private renderSelectionMarker(): void {
    const existing = this.children.getByName('editor-selection-marker');
    existing?.destroy();
    const selectedZoneIndex = this.editor.value.selectedSafeZoneIndex;
    if (selectedZoneIndex !== undefined && this.editor.value.tool === 'safe-zone') {
      const zone = this.editor.value.map.enemySafeZones[selectedZoneIndex];
      if (!zone) return;
      const marker = this.add.graphics().setName('editor-selection-marker').setDepth(resolveExplicitDepth('editor-selection-marker'));
      marker.lineStyle(5, EDITOR_SELECTION_STYLE.shadow, 0.9).strokeRect(zone.x - 8, zone.y - 8, zone.w + 16, zone.h + 16);
      marker.lineStyle(3, EDITOR_SELECTION_STYLE.phaser, 1).strokeRect(zone.x - 8, zone.y - 8, zone.w + 16, zone.h + 16);
      marker.fillStyle(EDITOR_SELECTION_STYLE.shadow, 0.95).fillCircle(zone.x + zone.w, zone.y + zone.h, 8);
      marker.fillStyle(EDITOR_SELECTION_STYLE.phaser, 1).fillCircle(zone.x + zone.w, zone.y + zone.h, 5);
      return;
    }
    const selectedId = this.editor.value.selectedInstanceId;
    if (!selectedId) return;
    const image = this.renderedInstances.get(selectedId);
    if (!image) return;
    const bounds = image.getBounds();
    const marker = this.add.graphics().setName('editor-selection-marker').setDepth(resolveExplicitDepth('editor-selection-marker'));
    marker.lineStyle(5, EDITOR_SELECTION_STYLE.shadow, 0.9).strokeRect(
      bounds.x - 8,
      bounds.y - 8,
      bounds.width + 16,
      bounds.height + 16,
    );
    marker.lineStyle(3, EDITOR_SELECTION_STYLE.phaser, 1).strokeRect(
      bounds.x - 8,
      bounds.y - 8,
      bounds.width + 16,
      bounds.height + 16,
    );
    marker.fillStyle(EDITOR_SELECTION_STYLE.shadow, 0.95).fillCircle(bounds.centerX, bounds.y - 8, 8);
    marker.fillStyle(EDITOR_SELECTION_STYLE.phaser, 1).fillCircle(bounds.centerX, bounds.y - 8, 5);
  }

  private templateOverlaySettings(): {
    showAllMatchingOverlays: boolean;
    showFrameOverlay: boolean;
    showColliderOverlay: boolean;
    showOcclusionOverlay: boolean;
  } {
    const state = this.templateEditor.value;
    return {
      showAllMatchingOverlays: state.showAllMatchingOverlays,
      showFrameOverlay: state.showFrameOverlay,
      showColliderOverlay: state.showColliderOverlay,
      showOcclusionOverlay: state.showOcclusionOverlay,
    };
  }

  private initialTileId(): WorldTileId {
    const first = Object.values(this.loadedMap.map.layers[0].legend).find(isWorldTileId);
    return first ?? getTileIds()[0];
  }

  private areaSeed(): number {
    return Object.values(AREAS).find((candidate) => candidate.mapId === this.loadedMap.map.mapId)?.seed ?? 0;
  }

  private buildContentPreviews(): ContentPreviewUrls {
    const tiles: Record<string, string> = {};
    for (const tileId of getTileIds()) {
      const definition = getTileDefinition(tileId);
      const asset = getAsset(definition.visual.assetIds[0]);
      const frame = asset.source.kind === 'spritesheet' ? 0 : undefined;
      tiles[tileId] = this.createTexturePreview(asset.runtime.textureKey, frame);
    }

    const objects: Record<string, string> = {};
    for (const choice of getObjectVisualChoices()) {
      const asset = getAsset(choice.assetId);
      const frame = asset.source.kind === 'spritesheet' ? choice.frame : undefined;
      objects[choice.key] = this.createTexturePreview(asset.runtime.textureKey, frame);
    }
    return { tiles, objects };
  }

  private createTexturePreview(textureKey: string, frame?: number): string {
    const textureFrame = this.textures.getFrame(textureKey, frame);
    if (!textureFrame) return '';
    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 64;
    const context = canvas.getContext('2d');
    if (!context) return '';
    context.imageSmoothingEnabled = false;
    const source = textureFrame.source.image as CanvasImageSource;
    const sourceWidth = textureFrame.cutWidth;
    const sourceHeight = textureFrame.cutHeight;
    const scale = Math.min(56 / sourceWidth, 56 / sourceHeight);
    const width = Math.max(1, Math.round(sourceWidth * scale));
    const height = Math.max(1, Math.round(sourceHeight * scale));
    const x = Math.round((64 - width) / 2);
    const y = Math.round((64 - height) / 2);
    context.drawImage(
      source,
      textureFrame.cutX,
      textureFrame.cutY,
      sourceWidth,
      sourceHeight,
      x,
      y,
      width,
      height,
    );
    return canvas.toDataURL('image/png');
  }

  private createInstanceId(objectId: ObjectArchetypeId): string {
    return `${objectId.replaceAll('.', '-')}-${crypto.randomUUID().slice(0, 8)}`;
  }

  private destroyEditor(): void {
    this.transitionLayer?.destroy();
    this.eraseDragMarker?.destroy();
    this.safeZoneDragMarker?.destroy();
    for (const preview of this.paintDrag?.previews ?? []) preview.destroy();
    for (const preview of this.objectStampDrag?.previews ?? []) preview.destroy();
    this.cursorGhost?.destroy();
    this.templatePreview?.destroy();
    this.unsubscribeState?.();
    this.unsubscribeTemplate?.();
    this.unmountPanel?.();
    this.unmountInspector?.();
    this.renderedObjects = [];
    this.overlayObjects = [];
    this.renderedTerrain.clear();
    this.renderedInstances.clear();
  }
}
