import Phaser from 'phaser';

import { UI_THEME } from '../../presentation/theme';

/** Same attachment slot the player's name tag uses, so tags sort just above their owner. */
const NAME_TAG_ATTACHMENT_SLOT = 7;
const NAME_TAG_GAP_PX = 2;

export interface NpcNameTagAnchor {
  readonly label: string;
  isActive(): boolean;
  /** The NPC's visual; resolved lazily because presentation objects exist only while mounted. */
  sprite(): Phaser.GameObjects.Sprite;
}

interface NpcNameTag {
  readonly anchor: NpcNameTagAnchor;
  readonly text: Phaser.GameObjects.Text;
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

  update(): void {
    for (const [id, tag] of this.tags) {
      if (tag.anchor.isActive()) this.position(tag);
      else this.remove(id);
    }
  }

  destroy(): void {
    for (const id of [...this.tags.keys()]) this.remove(id);
  }

  private position({ anchor, text }: NpcNameTag): void {
    const sprite = anchor.sprite();
    text
      .setPosition(sprite.x, sprite.y - sprite.displayHeight * sprite.originY - NAME_TAG_GAP_PX)
      .setVisible(sprite.visible)
      .setDepth(sprite.depth + NAME_TAG_ATTACHMENT_SLOT);
  }

  private remove(id: string): void {
    this.tags.get(id)?.text.destroy();
    this.tags.delete(id);
  }
}
