import Phaser from 'phaser';
import { gameEvents } from '../core/EventBus';
import { playerInventory, itemRegistry } from '../systems/Inventory';
import { RECIPES, canCraft, craft, type RecipeDef } from '../crafting/Crafting';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';
import { ModalStack, type ModalHandle } from './ModalStack';
import { createWeaponThumbnail } from './WeaponThumbnail';
import {
  clampOffset,
  ensureVisible,
  getCraftingLayout,
  moveSelection,
  ROW_GAP,
  visibleRange,
} from './CraftingLayout';

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';
const LIST_WIDTH = 620;
const LIST_HORIZONTAL_INSET = 16;
const COST_AREA_MIN_WIDTH = 84;
const COST_AREA_MAX_WIDTH = 112;
const COST_CHIP_HEIGHT = 24;
const COST_CHIP_GAP = 4;
const ROW_CORNER_RADIUS = 10;
const RESOURCE_ICON_SIZE = 22;
const FAILURE_FEEDBACK_DURATION = 180;

export interface CraftingUIContext {
  scene: Phaser.Scene;
  modalStack: ModalStack;
  onPausedChange: (paused: boolean) => void;
  onCrafted?: (recipe: RecipeDef) => void;
  /** Optional fixture for UI verification; production uses RECIPES. */
  recipes?: readonly RecipeDef[];
}

interface RecipeVisual {
  readonly row: Phaser.GameObjects.Container;
  readonly missingCosts: Phaser.GameObjects.GameObject[];
}

export class CraftingUI {
  private readonly ctx: CraftingUIContext;
  private readonly modalHandle: ModalHandle;
  private container?: Phaser.GameObjects.Container;
  private selectedIndex = 0;
  private scrollOffset = 0;
  private listBounds?: Phaser.Geom.Rectangle;
  private rowVisuals = new Map<number, RecipeVisual>();
  private openListenersAttached = false;

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
  }

  isOpen(): boolean {
    return !!this.container;
  }

  toggle(): void {
    if (this.container) this.close();
    else this.open();
  }

  private getRecipes(): readonly RecipeDef[] {
    return this.ctx.recipes ?? RECIPES;
  }

  private open(): void {
    this.build(true);
    this.attachOpenListeners();
    this.ctx.onPausedChange(true);
    this.modalHandle.open();
  }

  private refresh = (): void => {
    if (!this.container) return;
    this.rebuild(false);
  };

  private rebuild(animate: boolean): void {
    this.container?.destroy(true);
    this.container = undefined;
    this.listBounds = undefined;
    this.rowVisuals.clear();
    this.build(animate);
  }

  private build(animate: boolean): void {
    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    const recipes = this.getRecipes();
    const layout = getCraftingLayout(recipes.length, cam.height);
    const listWidth = Math.max(240, Math.min(LIST_WIDTH, cam.width - 2 * LIST_HORIZONTAL_INSET));

    this.selectedIndex = recipes.length > 0
      ? Phaser.Math.Clamp(this.selectedIndex, 0, recipes.length - 1)
      : 0;
    this.scrollOffset = clampOffset(this.scrollOffset, recipes.length, layout.capacityCount);

    const container = scene.add
      .container(cam.width / 2, cam.height / 2)
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(118));
    this.container = container;
    this.rowVisuals.clear();

    const modalShield = scene.add.zone(0, 0, cam.width, cam.height)
      .setOrigin(0.5)
      .setInteractive({ useHandCursor: false });
    modalShield.on('pointerdown', (
      _pointer: Phaser.Input.Pointer,
      _localX: number,
      _localY: number,
      event: Phaser.Types.Input.EventData,
    ) => event.stopPropagation());
    container.add(modalShield);

    this.listBounds = new Phaser.Geom.Rectangle(
      cam.width / 2 - listWidth / 2,
      cam.height / 2 - layout.listHeight / 2,
      listWidth,
      layout.listHeight,
    );

    const range = visibleRange(recipes.length, this.scrollOffset, layout.capacityCount);
    const firstRowY = layout.windowCount > 0
      ? -layout.listHeight / 2 + layout.rowHeight / 2
      : 0;
    for (let index = range.start; index < range.end; index += 1) {
      const rowIndex = index - range.start;
      this.drawRecipe(
        container,
        recipes[index],
        firstRowY + rowIndex * (layout.rowHeight + ROW_GAP),
        index,
        listWidth,
        layout.rowHeight,
      );
    }

    if (layout.maxOffset > 0) {
      container.add(scene.add.text(listWidth / 2 - 4, layout.listHeight / 2 + 12, 'scroll', {
        fontFamily: FONT,
        fontSize: '10px',
        color: '#9dc9b1',
      }).setOrigin(1, 0.5));
    }

    if (animate) {
      scene.tweens.add({ targets: container, alpha: { from: 0, to: 1 }, duration: 140 });
    }
  }

  private drawRecipe(
    container: Phaser.GameObjects.Container,
    recipe: RecipeDef,
    y: number,
    index: number,
    rowWidth: number,
    rowHeight: number,
  ): void {
    const scene = this.ctx.scene;
    const available = canCraft(recipe);
    const selected = index === this.selectedIndex;
    const row = scene.add.container(0, y);
    const card = scene.add.graphics();
    card.fillStyle(
      available ? 0x102a1f : 0x121a16,
      available ? 0.78 : 0.68,
    );
    card.fillRoundedRect(
      -rowWidth / 2,
      -rowHeight / 2,
      rowWidth,
      rowHeight,
      ROW_CORNER_RADIUS,
    );
    card.lineStyle(
      selected ? 3 : 1.5,
      selected ? 0xffdf8a : available ? 0x73e2b1 : 0x3b5c78,
      selected ? 1 : available ? 0.9 : 0.5,
    );
    card.strokeRoundedRect(
      -rowWidth / 2,
      -rowHeight / 2,
      rowWidth,
      rowHeight,
      ROW_CORNER_RADIUS,
    );
    row.add(card);

    const hitArea = scene.add.zone(0, 0, rowWidth, rowHeight)
      .setOrigin(0.5)
      .setInteractive({ useHandCursor: true });
    hitArea.on('pointerdown', (
      pointer: Phaser.Input.Pointer,
      _localX: number,
      _localY: number,
      event: Phaser.Types.Input.EventData,
    ) => {
      event.stopPropagation();
      if (pointer.button !== 0) return;
      this.handleRecipeClick(index);
    });
    hitArea.on('pointerover', () => row.setScale(1.01));
    hitArea.on('pointerout', () => row.setScale(1));
    row.add(hitArea);

    const left = -rowWidth / 2;
    const outputX = left + 31;
    const textX = left + 58;
    const costAreaWidth = Math.min(COST_AREA_MAX_WIDTH, Math.max(COST_AREA_MIN_WIDTH, rowWidth * 0.22));
    const costCenterX = rowWidth / 2 - costAreaWidth / 2 - 8;
    const textRight = costCenterX - costAreaWidth / 2 - 10;
    const textWidth = Math.max(92, textRight - textX);

    if (selected) {
      row.add(scene.add.text(left + 10, 0, '▶', {
        fontFamily: FONT,
        fontSize: '13px',
        color: '#ffdf8a',
        stroke: '#0b1020',
        strokeThickness: 3,
      }).setOrigin(0.5));
    }

    const outputDef = itemRegistry.get(recipe.output.itemId);
    if (outputDef) {
      if (outputDef.equipment?.weaponId) {
        const thumbnail = createWeaponThumbnail(scene, outputDef.equipment.weaponId, { x: outputX, y: 0, size: 38 });
        if (thumbnail) row.add(thumbnail);
      } else {
        const icon = outputDef.iconFrame === undefined
          ? scene.add.image(outputX, 0, outputDef.icon)
          : scene.add.image(outputX, 0, outputDef.icon, outputDef.iconFrame);
        row.add(icon.setDisplaySize(38, 38));
      }
    }

    row.add(scene.add.text(textX, -16, recipe.name, {
      fontFamily: FONT,
      fontSize: '15px',
      color: available ? '#f5f7ff' : '#8aa090',
      stroke: '#0b1020',
      strokeThickness: 3,
      wordWrap: { width: textWidth },
    }).setOrigin(0, 0.5));

    row.add(scene.add.text(textX, 10, recipe.description, {
      fontFamily: FONT,
      fontSize: '11px',
      color: available ? '#d7f6e9' : '#9db6a7',
      wordWrap: { width: textWidth },
      maxLines: 1,
    }).setOrigin(0, 0.5));

    const missingCosts: Phaser.GameObjects.GameObject[] = [];
    const costs = scene.add.container(costCenterX, 0);
    const stackCosts = rowWidth < 430 && recipe.ingredients.length > 1;
    const chipWidth = stackCosts
      ? costAreaWidth
      : recipe.ingredients.length > 1
        ? (costAreaWidth - COST_CHIP_GAP) / 2
        : Math.min(70, costAreaWidth);
    const chipStep = COST_CHIP_HEIGHT + COST_CHIP_GAP;

    recipe.ingredients.forEach((ingredient, ingredientIndex) => {
      const current = playerInventory.count(ingredient.itemId);
      const missing = current < ingredient.count;
      const chipX = stackCosts
        ? 0
        : (ingredientIndex - (recipe.ingredients.length - 1) / 2) * (chipWidth + COST_CHIP_GAP);
      const chipY = stackCosts
        ? (ingredientIndex - (recipe.ingredients.length - 1) / 2) * chipStep
        : 0;
      const def = itemRegistry.get(ingredient.itemId);
      if (def) {
        const icon = def.iconFrame === undefined
          ? scene.add.image(chipX - chipWidth / 2 + 13, chipY, def.icon)
          : scene.add.image(chipX - chipWidth / 2 + 13, chipY, def.icon, def.iconFrame);
        costs.add(icon.setDisplaySize(RESOURCE_ICON_SIZE, RESOURCE_ICON_SIZE));
        if (missing) missingCosts.push(icon);
      }
      const quantity = scene.add.text(chipX - chipWidth / 2 + 29, chipY, missing ? `${current}/${ingredient.count}` : `${ingredient.count}`, {
        fontFamily: FONT,
        fontSize: '11px',
        fontStyle: 'bold',
        color: missing ? '#ffaaa4' : '#ffd277',
      }).setOrigin(0, 0.5);
      costs.add(quantity);
      if (missing) missingCosts.push(quantity);
    });
    row.add(costs);

    container.add(row);
    this.rowVisuals.set(index, { row, missingCosts });
  }

  private handleRecipeClick(index: number): void {
    if (!this.container) return;
    const recipes = this.getRecipes();
    const recipe = recipes[index];
    if (!recipe) return;

    this.selectedIndex = index;
    const layout = getCraftingLayout(recipes.length, this.ctx.scene.cameras.main.height);
    this.scrollOffset = ensureVisible(index, this.scrollOffset, layout.capacityCount, recipes.length);
    this.rebuild(false);

    if (!canCraft(recipe)) {
      this.flashMissing(index);
      return;
    }

    if (craft(recipe)) this.ctx.onCrafted?.(recipe);
    else this.flashTransactionFailure(index);
  }

  private flashMissing(index: number): void {
    const visual = this.rowVisuals.get(index);
    if (!visual) return;
    const targets = visual.missingCosts.length > 0 ? visual.missingCosts : [visual.row];
    this.ctx.scene.tweens.add({
      targets,
      alpha: { from: 1, to: 0.25 },
      yoyo: true,
      duration: FAILURE_FEEDBACK_DURATION,
    });
  }

  private flashTransactionFailure(index: number): void {
    const visual = this.rowVisuals.get(index);
    if (!visual) return;
    this.ctx.scene.tweens.add({
      targets: visual.row,
      scaleX: { from: 1, to: 1.02 },
      scaleY: { from: 1, to: 1.02 },
      yoyo: true,
      duration: FAILURE_FEEDBACK_DURATION,
    });
  }

  private selectPrevious = (): void => {
    if (!this.container) return;
    const recipes = this.getRecipes();
    if (recipes.length === 0) return;
    this.selectedIndex = moveSelection(this.selectedIndex, -1, recipes.length);
    const layout = getCraftingLayout(recipes.length, this.ctx.scene.cameras.main.height);
    this.scrollOffset = ensureVisible(this.selectedIndex, this.scrollOffset, layout.capacityCount, recipes.length);
    this.rebuild(false);
  };

  private selectNext = (): void => {
    if (!this.container) return;
    const recipes = this.getRecipes();
    if (recipes.length === 0) return;
    this.selectedIndex = moveSelection(this.selectedIndex, 1, recipes.length);
    const layout = getCraftingLayout(recipes.length, this.ctx.scene.cameras.main.height);
    this.scrollOffset = ensureVisible(this.selectedIndex, this.scrollOffset, layout.capacityCount, recipes.length);
    this.rebuild(false);
  };

  private craftSelected = (): void => {
    if (!this.container) return;
    const recipes = this.getRecipes();
    const recipe = recipes[this.selectedIndex];
    if (!recipe) return;

    const layout = getCraftingLayout(recipes.length, this.ctx.scene.cameras.main.height);
    const nextOffset = ensureVisible(this.selectedIndex, this.scrollOffset, layout.capacityCount, recipes.length);
    if (nextOffset !== this.scrollOffset) {
      this.scrollOffset = nextOffset;
      this.rebuild(false);
    }

    if (!canCraft(recipe)) {
      this.flashMissing(this.selectedIndex);
      return;
    }
    if (craft(recipe)) this.ctx.onCrafted?.(recipe);
    else this.flashTransactionFailure(this.selectedIndex);
  };

  private handleCraftingWheel = (
    pointer: Phaser.Input.Pointer,
    _objects: unknown[],
    _deltaX: number,
    deltaY: number,
  ): void => {
    if (!this.container || !this.listBounds || deltaY === 0) return;
    if (!Phaser.Geom.Rectangle.Contains(this.listBounds, pointer.x, pointer.y)) return;

    const recipes = this.getRecipes();
    const layout = getCraftingLayout(recipes.length, this.ctx.scene.cameras.main.height);
    const nextOffset = clampOffset(this.scrollOffset + Math.sign(deltaY), recipes.length, layout.capacityCount);
    if (nextOffset === this.scrollOffset) return;
    this.scrollOffset = nextOffset;
    this.rebuild(false);
  };

  private handleResize = (): void => {
    if (this.container) this.rebuild(false);
  };

  private attachOpenListeners(): void {
    if (this.openListenersAttached) return;
    this.openListenersAttached = true;
    this.ctx.scene.input.on('wheel', this.handleCraftingWheel, this);
    this.ctx.scene.scale.on('resize', this.handleResize, this);
  }

  private detachOpenListeners(): void {
    if (!this.openListenersAttached) return;
    this.openListenersAttached = false;
    this.ctx.scene.input.off('wheel', this.handleCraftingWheel, this);
    this.ctx.scene.scale.off('resize', this.handleResize, this);
  }

  public close(): void {
    this.detachOpenListeners();
    const wasOpen = !!this.container;
    this.modalHandle.close();
    this.container?.destroy(true);
    this.container = undefined;
    this.listBounds = undefined;
    this.rowVisuals.clear();
    if (wasOpen) this.ctx.onPausedChange(false);
  }

  destroy(): void {
    const wasOpen = !!this.container;
    this.detachOpenListeners();
    gameEvents.off('inventory.changed', this.refresh, this);
    this.modalHandle.unregister();
    const kb = this.ctx.scene.input.keyboard;
    kb?.off('keydown-UP', this.selectPrevious, this);
    kb?.off('keydown-W', this.selectPrevious, this);
    kb?.off('keydown-DOWN', this.selectNext, this);
    kb?.off('keydown-S', this.selectNext, this);
    kb?.off('keydown-ENTER', this.craftSelected, this);
    this.container?.destroy(true);
    this.container = undefined;
    this.listBounds = undefined;
    this.rowVisuals.clear();
    if (wasOpen) this.ctx.onPausedChange(false);
  }
}
