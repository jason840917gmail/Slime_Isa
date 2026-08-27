import Phaser from 'phaser';
import { gameEvents } from '../core/EventBus';
import { playerInventory, itemRegistry } from '../systems/Inventory';
import { RECIPES, canCraft, craft, itemName, type RecipeDef } from '../crafting/Crafting';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';
import { ModalStack, type ModalHandle } from './ModalStack';
import { createWeaponThumbnail } from './WeaponThumbnail';

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';

export interface CraftingUIContext {
  scene: Phaser.Scene;
  modalStack: ModalStack;
  onPausedChange: (paused: boolean) => void;
  onCrafted?: (recipe: RecipeDef) => void;
}

export class CraftingUI {
  private ctx: CraftingUIContext;
  private readonly modalHandle: ModalHandle;
  private container?: Phaser.GameObjects.Container;
  private selectedIndex = 0;
  private clickRegions: Array<{ x: number; y: number; width: number; height: number; onClick: () => void }> = [];

  constructor(ctx: CraftingUIContext) {
    this.ctx = ctx;
    this.modalHandle = ctx.modalStack.register('crafting', {
      isOpen: () => this.isOpen(),
      close: () => this.close(),
    });
    gameEvents.on('inventory.changed', this.refresh, this);

    const kb = ctx.scene.input.keyboard;
    if (kb) {
      kb.on('keydown-UP', this.selectPrevious, this);
      kb.on('keydown-W', this.selectPrevious, this);
      kb.on('keydown-DOWN', this.selectNext, this);
      kb.on('keydown-S', this.selectNext, this);
      kb.on('keydown-ENTER', this.craftSelected, this);
    }
    ctx.scene.input.on('pointerdown', this.handlePointerDown, this);
  }

  isOpen(): boolean {
    return !!this.container;
  }

  toggle(): void {
    if (this.container) this.close();
    else this.open();
  }

  private open(): void {
    this.build(true);
    this.ctx.onPausedChange(true);
    this.modalHandle.open();
  }

  private refresh = (): void => {
    if (!this.container) return;
    this.container.destroy();
    this.container = undefined;
    this.build(false);
  };

  private build(animate: boolean): void {
    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    const panelW = 610;
    const panelH = 430;
    const container = scene.add.container(cam.width / 2, cam.height / 2).setScrollFactor(0).setDepth(resolveScreenUiDepth(118));
    this.container = container;
    this.clickRegions = [];

    container.add(scene.add.rectangle(0, 0, cam.width, cam.height, 0x080f20, 0.7).setOrigin(0.5));
    const bg = scene.add.graphics();
    bg.fillStyle(0x101a31, 0.98);
    bg.fillRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
    bg.lineStyle(2, 0x73e2b1, 0.85);
    bg.strokeRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
    container.add(bg);

    container.add(scene.add.text(-panelW / 2 + 24, -panelH / 2 + 28, 'Crafting', {
      fontFamily: FONT,
      fontSize: '22px',
      color: '#e7fff5',
      stroke: '#0b1020',
      strokeThickness: 5,
    }).setOrigin(0, 0.5));

    container.add(scene.add.text(panelW / 2 - 18, -panelH / 2 + 20, 'C / Esc to close', {
      fontFamily: FONT,
      fontSize: '12px',
      color: '#88c899',
    }).setOrigin(1, 0));

    container.add(scene.add.text(-panelW / 2 + 24, -panelH / 2 + 56, 'Up/Down or W/S selects a recipe. Enter crafts it. You can also click Craft.', {
      fontFamily: FONT,
      fontSize: '12px',
      color: '#88c899',
    }).setOrigin(0, 0.5));

    this.selectedIndex = Phaser.Math.Clamp(this.selectedIndex, 0, RECIPES.length - 1);
    let y = -118;
    for (let i = 0; i < RECIPES.length; i += 1) {
      this.drawRecipe(container, RECIPES[i], y, i);
      y += 96;
    }

    container.add(scene.add.text(-panelW / 2 + 24, panelH / 2 - 26, 'Tip: berries now become materials. Enemy drops unlock stronger recipes.', {
      fontFamily: FONT,
      fontSize: '12px',
      color: '#88c899',
    }).setOrigin(0, 0.5));

    if (animate) {
      scene.tweens.add({ targets: container, alpha: { from: 0, to: 1 }, scale: { from: 0.97, to: 1 }, duration: 140 });
    }
  }

  private drawRecipe(container: Phaser.GameObjects.Container, recipe: RecipeDef, y: number, index: number): void {
    const scene = this.ctx.scene;
    const available = canCraft(recipe);
    const selected = index === this.selectedIndex;
    const left = -270;

    const card = scene.add.graphics();
    card.fillStyle(available ? 0x102a1f : 0x121a16, 0.96);
    card.fillRoundedRect(left - 12, y - 34, 540, 78, 10);
    card.lineStyle(selected ? 3 : 1.5, selected ? 0xffdf8a : available ? 0x73e2b1 : 0x3b5c78, selected ? 1 : available ? 0.9 : 0.5);
    card.strokeRoundedRect(left - 12, y - 34, 540, 78, 10);
    container.add(card);

    this.addClickRegion(left - 20, y - 35, 540, 78, () => {
      this.selectedIndex = index;
      this.refresh();
    });

    if (selected) {
      container.add(scene.add.text(left - 30, y + 2, '▶', {
        fontFamily: FONT,
        fontSize: '18px',
        color: '#ffdf8a',
        stroke: '#0b1020',
        strokeThickness: 4,
      }).setOrigin(0.5));
    }

    const outputDef = itemRegistry.get(recipe.output.itemId);
    if (outputDef) {
      if (outputDef.equipment?.weaponId) {
        const thumbnail = createWeaponThumbnail(scene, outputDef.equipment.weaponId, { x: left + 20, y: y + 4, size: 36 });
        if (thumbnail) container.add(thumbnail);
      } else {
        const icon = scene.add.image(left + 20, y + 4, outputDef.icon).setDisplaySize(36, 36);
        if (outputDef.iconFrame !== undefined) icon.setFrame(outputDef.iconFrame);
        container.add(icon);
      }
    }

    container.add(scene.add.text(left + 50, y - 20, recipe.name, {
      fontFamily: FONT,
      fontSize: '15px',
      color: available ? '#f5f7ff' : '#8aa090',
      stroke: '#0b1020',
      strokeThickness: 3,
    }).setOrigin(0, 0.5));

    container.add(scene.add.text(left + 50, y + 2, recipe.description, {
      fontFamily: FONT,
      fontSize: '11px',
      color: '#d7f6e9',
      wordWrap: { width: 315 },
    }).setOrigin(0, 0.5));

    const costs = recipe.ingredients.map((i) => `${itemName(i.itemId)} ${playerInventory.count(i.itemId)}/${i.count}`).join('  ·  ');
    container.add(scene.add.text(left + 50, y + 24, costs, {
      fontFamily: FONT,
      fontSize: '11px',
      color: available ? '#ffd277' : '#b08080',
    }).setOrigin(0, 0.5));

    const buttonX = left + 440;
    const buttonY = y + 4;
    const buttonW = 96;
    const buttonH = 38;
    const buttonBg = scene.add.graphics();
    buttonBg.fillStyle(available ? 0x86f0c3 : 0x253552, available ? 1 : 0.65);
    buttonBg.fillRoundedRect(buttonX - buttonW / 2, buttonY - buttonH / 2, buttonW, buttonH, 8);
    buttonBg.lineStyle(1.5, available ? 0xe7fff5 : 0x4a6075, available ? 0.85 : 0.45);
    buttonBg.strokeRoundedRect(buttonX - buttonW / 2, buttonY - buttonH / 2, buttonW, buttonH, 8);
    container.add(buttonBg);

    const btn = scene.add.text(buttonX, buttonY, `Craft x${recipe.output.count}`, {
      fontFamily: FONT,
      fontSize: '13px',
      color: available ? '#101a31' : '#4a6075',
    }).setOrigin(0.5).setAlpha(available ? 1 : 0.75);
    container.add(btn);

    if (available) {
      this.addClickRegion(buttonX - buttonW / 2, buttonY - buttonH / 2, buttonW, buttonH, () => {
        this.selectedIndex = index;
        if (craft(recipe)) this.ctx.onCrafted?.(recipe);
      });
    }
  }

  private addClickRegion(x: number, y: number, width: number, height: number, onClick: () => void): void {
    this.clickRegions.push({ x, y, width, height, onClick });
  }

  private handlePointerDown = (pointer: Phaser.Input.Pointer): void => {
    if (!this.container) return;
    const localX = pointer.x - this.container.x;
    const localY = pointer.y - this.container.y;

    for (let i = this.clickRegions.length - 1; i >= 0; i -= 1) {
      const r = this.clickRegions[i];
      if (localX >= r.x && localX <= r.x + r.width && localY >= r.y && localY <= r.y + r.height) {
        r.onClick();
        return;
      }
    }
  };

  private selectPrevious = (): void => {
    if (!this.container) return;
    this.selectedIndex = (this.selectedIndex + RECIPES.length - 1) % RECIPES.length;
    this.refresh();
  };

  private selectNext = (): void => {
    if (!this.container) return;
    this.selectedIndex = (this.selectedIndex + 1) % RECIPES.length;
    this.refresh();
  };

  private craftSelected = (): void => {
    if (!this.container) return;
    const recipe = RECIPES[this.selectedIndex];
    if (recipe && craft(recipe)) this.ctx.onCrafted?.(recipe);
  };

  public close(): void {
    if (!this.container) {
      this.modalHandle.close();
      return;
    }
    this.modalHandle.close();
    this.container.destroy();
    this.container = undefined;
    this.ctx.onPausedChange(false);
  }

  destroy(): void {
    gameEvents.off('inventory.changed', this.refresh, this);
    this.modalHandle.unregister();
    const kb = this.ctx.scene.input.keyboard;
    kb?.off('keydown-UP', this.selectPrevious, this);
    kb?.off('keydown-W', this.selectPrevious, this);
    kb?.off('keydown-DOWN', this.selectNext, this);
    kb?.off('keydown-S', this.selectNext, this);
    kb?.off('keydown-ENTER', this.craftSelected, this);
    this.ctx.scene.input.off('pointerdown', this.handlePointerDown, this);
    const wasOpen = !!this.container;
    this.container?.destroy();
    this.container = undefined;
    if (wasOpen) this.ctx.onPausedChange(false);
  }
}
