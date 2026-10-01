import type Phaser from 'phaser';

import { DEPTH_BANDS } from '../../presentation/WorldDepth';
import { DisposableBag } from '../../shared/lifecycle/Disposable';

/**
 * Animated water drawn over the baked terrain (visual only). One shader quad
 * covers the tile layer; a low-resolution mask (one texel per tile, linearly
 * filtered) says where shallow and deep water are. The shader re-samples the
 * water ground textures with a moving refraction, crossing caustic layers,
 * sun glints and shoreline foam; deep water is darker and slower with broad
 * swells. Underwater life draws just above it with a blue tint (see
 * UNDERWATER_DEPTH).
 */

export type WaterKind = 'shallow' | 'deep';

export interface WaterSurfaceRequest {
  readonly scene: Phaser.Scene;
  readonly grid: readonly (readonly (string | undefined)[])[];
  readonly waterKind: (tileId: string) => WaterKind | undefined;
  readonly tileSize: number;
  /** Texture keys of the seamless water ground sheets. */
  readonly textures: Readonly<Record<WaterKind, string | undefined>>;
}

/**
 * Baked terrain chunks draw at ground-decals + 0.2, so the surface sits just
 * above them. Things seen under the water (fish, plants) draw just above the
 * surface at UNDERWATER_DEPTH, tinted and semi-transparent: below the nearly
 * opaque surface they would vanish.
 */
export const WATER_SURFACE_DEPTH = DEPTH_BANDS['ground-decals'] + 0.5;
export const UNDERWATER_DEPTH = DEPTH_BANDS['ground-decals'] + 0.6;
/** World size of one repeat of the water ground texture (the 19x19 sheet of 64 px tiles). */
const TEXTURE_PERIOD = 1216;
const TILE_TEXTURE_SIZE = 1024;

const FRAGMENT = `
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform float time;
uniform vec2 resolution;
uniform sampler2D iChannel0; // mask: r = shallow, g = deep (one texel per tile)
uniform sampler2D iChannel1; // shallow water texture (repeating)
uniform sampler2D iChannel2; // deep water texture (repeating)
uniform vec2 uGrid;
uniform float uTile;
uniform float uPeriod;
varying vec2 fragCoord;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
  vec2 i = floor(p); vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void main() {
  vec2 px = vec2(fragCoord.x, resolution.y - fragCoord.y);
  vec4 m = texture2D(iChannel0, (px / uTile) / uGrid);
  float wet = m.r + m.g;
  float edge = noise(px * 0.035) * 0.22 + noise(px * 0.09) * 0.1 - 0.16;
  float body = wet + edge;
  if (body < 0.3) discard;
  float deep = smoothstep(0.25, 0.85, m.g / max(wet, 0.001));
  float t = time;

  vec2 uv = px / uPeriod;
  vec2 wobble1 = vec2(sin(px.y * 0.034 + t * 1.25), cos(px.x * 0.029 + t * 1.05)) * 0.0055;
  vec2 wobble2 = vec2(sin((px.x + px.y) * 0.019 - t * 0.85), cos((px.x - px.y) * 0.017 + t * 0.7)) * 0.0045;

  // Shallow: two copies of the caustic texture drift across each other.
  vec3 s1 = texture2D(iChannel1, uv + vec2(t * 0.011, t * 0.006) + wobble1).rgb;
  vec3 s2 = texture2D(iChannel1, uv * 0.87 + vec2(-t * 0.008, t * 0.010) + wobble2 + 0.37).rgb;
  float caustic = max(0.0, min(luma(s1), luma(s2)) - 0.42) * 2.4;
  vec3 shallow = mix(s1, s2, 0.5) * 0.92 + vec3(0.75, 0.95, 1.0) * caustic;

  // Deep: slow, dark, broad swells.
  vec3 d1 = texture2D(iChannel2, uv * 0.72 + vec2(t * 0.004, t * 0.0025) + wobble1 * 0.7).rgb;
  vec3 d2 = texture2D(iChannel2, uv * 0.58 + vec2(-t * 0.003, t * 0.0045) + wobble2 * 0.7 + 0.61).rgb;
  float swell = sin(px.x * 0.0045 + px.y * 0.0031 - t * 0.55) * 0.5 + 0.5;
  vec3 deepColor = (d1 + d2) * 0.5 + vec3(0.02, 0.05, 0.09) * swell;

  vec3 color = mix(shallow, deepColor, deep);

  // Sun glints: a few soft four-point sparkles twinkling, mostly in shallow water.
  vec2 cell = floor(px / 9.0);
  float h = hash(cell);
  vec2 centre = (cell + 0.25 + 0.5 * vec2(hash(cell + 7.1), hash(cell + 3.7))) * 9.0;
  vec2 d = abs(px - centre);
  float star = max(0.0, 1.0 - length(d) / 2.2) + max(0.0, 1.0 - (d.x * 3.0 + d.y) / 4.5) * 0.5 + max(0.0, 1.0 - (d.y * 3.0 + d.x) / 4.5) * 0.5;
  float twinkle = pow(max(0.0, sin(t * 2.1 + h * 60.0)), 10.0);
  color += vec3(1.0, 0.98, 0.9) * step(0.985, h) * twinkle * star * (1.0 - deep * 0.75) * 0.85;

  // Foam lapping at the shore.
  float shore = 1.0 - smoothstep(0.5, 0.95, body);
  float lap = sin(t * 1.4 + noise(px * 0.02) * 6.2832) * 0.5 + 0.5;
  float foam = shore * smoothstep(0.55, 0.85, noise(px * 0.09 + vec2(t * 0.5, -t * 0.35)) * 0.7 + lap * 0.45);
  color = mix(color, vec3(0.93, 0.98, 1.0), foam * 0.6);

  float alpha = smoothstep(0.3, 0.62, body) * mix(0.82, 0.9, deep);
  gl_FragColor = vec4(color * alpha, alpha);
}
`;

/** Phaser's default Shader vertex program (kept here so this module needs no runtime Phaser import). */
const VERTEX = `
precision mediump float;
uniform mat4 uProjectionMatrix;
uniform mat4 uViewMatrix;
uniform vec2 uResolution;
attribute vec2 inPosition;
varying vec2 fragCoord;
varying vec2 outTexCoord;
void main () {
  gl_Position = uProjectionMatrix * uViewMatrix * vec4(inPosition, 1.0, 1.0);
  fragCoord = vec2(inPosition.x, uResolution.y - inPosition.y);
  outTexCoord = vec2(inPosition.x / uResolution.x, fragCoord.y / uResolution.y);
}
`;
const WEBGL_RENDERER = 2; // Phaser.WEBGL
const SCENE_SHUTDOWN = 'shutdown';

let nextId = 0;

/** Copies a (non-power-of-two) water sheet into a power-of-two canvas so it can repeat in WebGL1. */
function repeatableCopy(scene: Phaser.Scene, sourceKey: string, key: string): string | undefined {
  if (!scene.textures.exists(sourceKey)) return undefined;
  const source = scene.textures.get(sourceKey).getSourceImage() as CanvasImageSource;
  const canvas = document.createElement('canvas');
  canvas.width = TILE_TEXTURE_SIZE;
  canvas.height = TILE_TEXTURE_SIZE;
  const context = canvas.getContext('2d');
  if (!context) return undefined;
  context.imageSmoothingQuality = 'high';
  context.drawImage(source, 0, 0, TILE_TEXTURE_SIZE, TILE_TEXTURE_SIZE);
  scene.textures.addCanvas(key, canvas);
  return key;
}

export class WaterSurfaceLayer {
  private readonly shader?: Phaser.GameObjects.Shader;
  private readonly textureKeys: string[] = [];
  private readonly disposables = new DisposableBag();
  private destroyed = false;

  /** Returns undefined when the grid has no water or the renderer cannot run shaders. */
  static create(request: WaterSurfaceRequest): WaterSurfaceLayer | undefined {
    if (request.scene.sys.game.renderer.type !== WEBGL_RENDERER) return undefined;
    const hasWater = request.grid.some((row) => row.some((tileId) => tileId !== undefined && request.waterKind(tileId) !== undefined));
    return hasWater ? new WaterSurfaceLayer(request) : undefined;
  }

  private constructor(private readonly request: WaterSurfaceRequest) {
    const { scene, grid, tileSize } = request;
    const rows = grid.length;
    const columns = rows ? grid[0].length : 0;
    const id = nextId++;

    const mask = document.createElement('canvas');
    mask.width = columns;
    mask.height = rows;
    const context = mask.getContext('2d');
    if (!context) return;
    const pixels = context.createImageData(columns, rows);
    for (let y = 0; y < rows; y += 1) {
      for (let x = 0; x < columns; x += 1) {
        const tileId = grid[y][x];
        const kind = tileId === undefined ? undefined : request.waterKind(tileId);
        const offset = (y * columns + x) * 4;
        pixels.data[offset] = kind === 'shallow' ? 255 : 0;
        pixels.data[offset + 1] = kind === 'deep' ? 255 : 0;
        pixels.data[offset + 3] = 255;
      }
    }
    context.putImageData(pixels, 0, 0);
    const maskKey = `water-surface-mask-${id}`;
    scene.textures.addCanvas(maskKey, mask);
    this.textureKeys.push(maskKey);

    const shallowKey = request.textures.shallow && repeatableCopy(scene, request.textures.shallow, `water-surface-shallow-${id}`);
    const deepKey = request.textures.deep && repeatableCopy(scene, request.textures.deep, `water-surface-deep-${id}`);
    if (shallowKey) this.textureKeys.push(shallowKey);
    if (deepKey) this.textureKeys.push(deepKey);

    // Phaser's Shader reads only these fields of a BaseShader.
    const base = {
      key: `water-surface-${id}`,
      fragmentSrc: FRAGMENT,
      vertexSrc: VERTEX,
      uniforms: {
        uGrid: { type: '2f', value: { x: columns, y: rows } },
        uTile: { type: '1f', value: tileSize },
        uPeriod: { type: '1f', value: TEXTURE_PERIOD },
      },
    } as unknown as Phaser.Display.BaseShader;
    const shader = scene.add.shader(base, 0, 0, columns * tileSize, rows * tileSize).setOrigin(0).setDepth(WATER_SURFACE_DEPTH);
    const clamp = { wrapS: 'clamp_to_edge', wrapT: 'clamp_to_edge' };
    const repeat = { repeat: true };
    shader.setSampler2D('iChannel0', maskKey, 0, clamp);
    shader.setSampler2D('iChannel1', shallowKey ?? deepKey ?? maskKey, 1, repeat);
    shader.setSampler2D('iChannel2', deepKey ?? shallowKey ?? maskKey, 2, repeat);
    this.shader = shader;

    this.disposables.add(() => shader.destroy());
    const shutdown = (): void => this.destroy();
    scene.events.once(SCENE_SHUTDOWN, shutdown);
    this.disposables.add(() => scene.events.off(SCENE_SHUTDOWN, shutdown));
  }

  setOrigin(x: number, y: number): void { this.shader?.setPosition(x, y); }
  setVisible(visible: boolean): void { this.shader?.setVisible(visible); }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.disposables.dispose();
    for (const key of this.textureKeys) if (this.request.scene.textures.exists(key)) this.request.scene.textures.remove(key);
    this.textureKeys.length = 0;
  }
}
