import Phaser from 'phaser';

import { UI_THEME } from '../../presentation/theme';

/** Same attachment slot the player's name tag uses, so tags sort just above their owner. */
const NAME_TAG_ATTACHMENT_SLOT = 7;
const NAME_TAG_GAP_PX = 2;
const MARKER_GAP_PX = 18;
const MARKER_BOB_PX = 3;
const MARKER_BOB_PERIOD_MS = 900;

/** Quest state above an NPC: `!` has a quest for you, `?` is waiting on you, `…` wants a word. */
export type NpcQuestMarker = 'main-offer' | 'side-offer' | 'turn-in' | 'in-progress' | 'talk';

const MARKER_STYLE: Readonly<Record<NpcQuestMarker, { readonly symbol: string; readonly color: string; readonly size: number }>> = {
  'main-offer': { symbol: '!', color: '#ffd277', size: 30 },
  'side-offer': { symbol: '!', color: '#72d8ff', size: 26 },
  'turn-in': { symbol: '?', color: '#ffd277', size: 30 },
  'in-progress': { symbol: '?', color: '#a7bbd6', size: 24 },
  talk: { symbol: '…', color: '#f5f7ff', size: 24 },
};

export interface NpcNameTagAnchor {
  readonly label: string;
  isActive(): boolean;
  /** The NPC's visual; resolved lazily because presentation objects exist only while mounted. */
  sprite(): Phaser.GameObjects.Sprite;
}

interface NpcNameTag {
  readonly anchor: NpcNameTagAnchor;
  readonly text: Phaser.GameObjects.Text;
  marker?: Phaser.GameObjects.Text;
  markerKind?: NpcQuestMarker;
}

/** Floating display names above world NPCs, styled like the player's name tag. */
export class NpcNameTags {
  private readonly tags = new Map<string, NpcNameTag>();

  constructor(private readonly scene: Phaser.Scene) {}

  add(id: string, anchor: NpcNameTagAnchor): void {
    this.remove(id);
    const text = this.scene.add.text(0, 0, anchor.label, {
      fontFamily: UI_THEME.fontFamily,
      fontSize: '14px',
      color: UI_THEME.colors.text,
      stroke: UI_THEME.colors.shadow,
      strokeThickness: 4,
    }).setOrigin(0.5, 1);
    this.tags.set(id, { anchor, text });
    this.position({ anchor, text });
  }

  /** Shows, swaps, or clears (undefined) the quest marker floating above an NPC's name. */
  setMarker(id: string, kind: NpcQuestMarker | undefined): void {
    const tag = this.tags.get(id);
    if (!tag || tag.markerKind === kind) return;
    // A story variant can take the NPC out of the world while its quest state changes.
    if (!tag.anchor.isActive()) {
      this.remove(id);
      return;
    }
    tag.marker?.destroy();
    tag.marker = undefined;
    tag.markerKind = kind;
    if (!kind) return;
    const style = MARKER_STYLE[kind];
    tag.marker = this.scene.add.text(0, 0, style.symbol, {
      fontFamily: UI_THEME.fontFamily,
      fontSize: `${style.size}px`,
      fontStyle: 'bold',
      color: style.color,
      stroke: UI_THEME.colors.shadow,
      strokeThickness: 6,
    }).setOrigin(0.5, 1);
    this.scene.tweens.add({ targets: tag.marker, scale: { from: 0.4, to: 1 }, duration: 220, ease: 'Back.Out' });
    this.position(tag);
  }

  update(): void {
    for (const [id, tag] of this.tags) {
      if (tag.anchor.isActive()) this.position(tag);
      else this.remove(id);
    }
  }

  destroy(): void {
    for (const id of [...this.tags.keys()]) this.remove(id);
  }

  private position({ anchor, text, marker }: NpcNameTag): void {
    const sprite = anchor.sprite();
    text
      .setPosition(sprite.x, sprite.y - sprite.displayHeight * sprite.originY - NAME_TAG_GAP_PX)
      .setVisible(sprite.visible)
      .setDepth(sprite.depth + NAME_TAG_ATTACHMENT_SLOT);
    if (!marker) return;
    const bob = Math.sin((this.scene.time.now / MARKER_BOB_PERIOD_MS) * Math.PI * 2) * MARKER_BOB_PX;
    marker
      .setPosition(text.x, Math.round(text.y - MARKER_GAP_PX + bob))
      .setVisible(sprite.visible)
      .setDepth(text.depth);
  }

  private remove(id: string): void {
    const tag = this.tags.get(id);
    tag?.text.destroy();
    tag?.marker?.destroy();
    this.tags.delete(id);
  }
}
