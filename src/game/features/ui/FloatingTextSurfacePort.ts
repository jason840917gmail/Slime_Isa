import type Phaser from 'phaser';

import type { JsonValue } from '../../content/scenes/types';
import type { FloatingTextColor, FloatingTextPresentationPort } from '../../ui/FloatingText';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';
import { projectWorldToScreen } from './projectWorldToScreen';

const POOL_SIZE = 24;
const COLORS: Readonly<Record<FloatingTextColor, string>> = {
  white: '#ffffff', yellow: '#ffdf8a', orange: '#ffad66', green: '#7be08a',
  red: '#ff6f88', cyan: '#72d8ff', blue: '#4a90e2',
};

interface FloatingEntry {
  readonly surfaceId: string;
  x: number;
  y: number;
  message: string;
  color: FloatingTextColor;
  big: boolean;
  startedAt: number;
  durationMs: number;
  lastSignature: string;
  lastModel: UiPresentationModel;
}

/** Owns up to 24 authored floating text instances and reuses them after expiry. */
export class FloatingTextSurfacePort implements UiSurfacePort, FloatingTextPresentationPort {
  private readonly entries = new Map<string, FloatingEntry>();
  private stopped = false;

  constructor(
    private readonly scene: Phaser.Scene,
    private readonly mount: (surfaceId: string) => void,
  ) {}

  spawn(x: number, y: number, message: string, color: FloatingTextColor, big: boolean, durationMs?: number): void {
    if (this.stopped) return;
    const now = this.scene.time.now;
    let entry = [...this.entries.values()].find((candidate) => now >= candidate.startedAt + candidate.durationMs);
    if (!entry) {
      if (this.entries.size >= POOL_SIZE) return;
      const surfaceId = `floating-text:${this.entries.size}`;
      entry = { surfaceId, x, y, message, color, big, startedAt: now,
        durationMs: durationMs ?? (big ? 900 : 700), lastSignature: '', lastModel: {} };
      this.entries.set(surfaceId, entry);
      try { this.mount(surfaceId); } catch (error) { this.entries.delete(surfaceId); throw error; }
      return;
    }
    entry.x = x;
    entry.y = y;
    entry.message = message;
    entry.color = color;
    entry.big = big;
    entry.startedAt = now;
    entry.durationMs = durationMs ?? (big ? 900 : 700);
    entry.lastSignature = '';
  }

  snapshot(surfaceId: string): UiPresentationModel {
    const entry = this.entries.get(surfaceId);
    if (!entry || this.stopped) return {};
    const elapsed = Math.max(0, this.scene.time.now - entry.startedAt);
    const progress = Math.min(1, elapsed / Math.max(1, entry.durationMs));
    const screen = projectWorldToScreen(this.scene.cameras.main, entry.x, entry.y - (entry.big ? 48 : 34) * progress);
    const width = entry.big ? 320 : 240;
    const height = entry.big ? 48 : 34;
    const left = Math.round(screen.x - width / 2);
    const top = Math.round(screen.y - height / 2);
    const visible = elapsed < entry.durationMs && screen.x > -width && screen.x < this.scene.scale.width + width
      && screen.y > -height && screen.y < this.scene.scale.height + height;
    const model = {
      message: entry.message,
      color: COLORS[entry.color],
      fontSize: entry.big ? 22 : 15,
      visible,
      opacity: visible ? Math.max(0, 1 - progress) : 0,
      scale: (entry.big ? 1.1 : 0.9) + progress * (entry.big ? 0.2 : 0.1),
      offsetMin: [left, top],
      offsetMax: [left + width, top + height],
    } satisfies Readonly<Record<string, JsonValue>>;
    const signature = JSON.stringify(model);
    if (signature === entry.lastSignature) return entry.lastModel;
    entry.lastSignature = signature;
    entry.lastModel = model;
    return model;
  }

  invoke(): void {}
  destroy(): void { this.stopped = true; this.entries.clear(); }
}
