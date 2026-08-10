export type EditorGeometryKey = 'frame' | 'collider' | 'depth' | 'occlusion';

export interface EditorGeometryStyle {
  readonly label: string;
  readonly shortLabel: string;
  readonly css: string;
  readonly phaser: number;
}

export const EDITOR_GEOMETRY_STYLES: Readonly<Record<EditorGeometryKey, EditorGeometryStyle>> = {
  frame: {
    label: 'Visual frame',
    shortLabel: 'FRAME',
    css: '#ffd166',
    phaser: 0xffd166,
  },
  collider: {
    label: 'Collider',
    shortLabel: 'COLLIDER',
    css: '#ff4d5d',
    phaser: 0xff4d5d,
  },
  depth: {
    label: 'Depth bound',
    shortLabel: 'DEPTH',
    css: '#ff9f43',
    phaser: 0xff9f43,
  },
  occlusion: {
    label: 'Occlusion',
    shortLabel: 'OCCLUSION',
    css: '#38bdf8',
    phaser: 0x38bdf8,
  },
};

export const EDITOR_SELECTION_STYLE = {
  css: '#ffffff',
  phaser: 0xffffff,
  shadow: 0x111827,
} as const;
