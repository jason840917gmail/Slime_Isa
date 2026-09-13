import type { ResourceId } from '../identifiers';

export type JsonPrimitive = null | boolean | number | string;
export type JsonValue = JsonPrimitive | readonly JsonValue[] | { readonly [key: string]: JsonValue };

interface ResourceDocumentBase {
  readonly version: 1;
  readonly resourceId: ResourceId;
}

export interface TextureResourceDocument extends ResourceDocumentBase {
  readonly kind: 'texture';
  readonly assetId: string;
  readonly frame?: number;
}

export interface SpriteSheetResourceDocument extends ResourceDocumentBase {
  readonly kind: 'sprite-sheet';
  readonly assetId: string;
  readonly frameWidth: number;
  readonly frameHeight: number;
  readonly frameCount?: number;
}

export type CollisionShapeValue =
  | { readonly shape: 'rectangle'; readonly width: number; readonly height: number }
  | { readonly shape: 'circle'; readonly radius: number }
  | { readonly shape: 'ellipse'; readonly radiusX: number; readonly radiusY: number }
  | { readonly shape: 'sector'; readonly radius: number; readonly innerRadius?: number; readonly angleDegrees: number };

export interface CollisionShapeResourceDocument extends ResourceDocumentBase {
  readonly kind: 'collision-shape';
  readonly value: CollisionShapeValue;
}

export interface AnimationLibraryResourceDocument extends ResourceDocumentBase {
  readonly kind: 'animation-library';
  readonly animations: Readonly<Record<string, JsonValue>>;
}

export interface AudioResourceDocument extends ResourceDocumentBase {
  readonly kind: 'audio';
  readonly assetId: string;
}

export interface TileSetResourceDocument extends ResourceDocumentBase {
  readonly kind: 'tile-set';
  readonly tiles: Readonly<Record<string, JsonValue>>;
}

export interface TileDataResourceDocument extends ResourceDocumentBase {
  readonly kind: 'tile-data';
  readonly tileSet: ResourceId;
  readonly cells: readonly JsonValue[];
}

export interface FontResourceDocument extends ResourceDocumentBase {
  readonly kind: 'font';
  readonly assetId: string;
}

export interface ThemeResourceDocument extends ResourceDocumentBase {
  readonly kind: 'theme';
  readonly values: Readonly<Record<string, JsonValue>>;
}

export type SceneResourceDocument =
  | TextureResourceDocument
  | SpriteSheetResourceDocument
  | CollisionShapeResourceDocument
  | AnimationLibraryResourceDocument
  | AudioResourceDocument
  | TileSetResourceDocument
  | TileDataResourceDocument
  | FontResourceDocument
  | ThemeResourceDocument;

export interface ResourceReferenceDocument {
  readonly resourceId: ResourceId;
}
