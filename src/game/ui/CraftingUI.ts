import Phaser from 'phaser';
import { gameEvents } from '../core/EventBus';
import { itemRegistry } from '../systems/Inventory';
import type { RecipeDef } from '../content/recipes/types';
import { RECIPES } from '../crafting/Crafting';
import {
  CraftingService,
  normalizeQuantity,
  type CraftFailureReason,
  type CraftQuote,
  type CraftSuccess,
} from '../crafting/CraftingService';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';
import { addUiSkin } from '../presentation/UiSkin';
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
const DISPLAY_FONT = 'Palatino Linotype, Book Antiqua, Georgia, serif';
const BODY_FONT = 'Segoe UI Variable, Segoe UI, Trebuchet MS, sans-serif';
const TEXT_IVORY = '#fff1c7';
const TEXT_GOLD = '#e8b85f';
const TEXT_AMBER = '#f6d77b';
const TEXT_MUTED = '#c8bb91';
const TEXT_WARNING = '#ff9d83';
const TEXT_SUCCESS = '#b8dfa6';
const PANEL_MAX_WIDTH = 1080;
const PANEL_GUTTER = 22;
const PANEL_BORDER_PADDING = {
  top: 50,
  right:100,
  bottom: 50,
  left: 170,
} as const;
const ROW_CORNER_RADIUS = 10;
const RESOURCE_ICON_SIZE = 30;
const COST_STACK_BREAKPOINT = 430;
const FAILURE_FEEDBACK_DURATION = 180;

interface QuantityInputBounds {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export interface CraftingUIContext {
  scene: Phaser.Scene;
  modalStack: ModalStack;
  craftingService: CraftingService;
  onPausedChange: (paused: boolean) => void;
  onCrafted?: (result: CraftSuccess) => void;
  /** Optional fixture for UI verification; production uses RECIPES. */
  recipes?: readonly RecipeDef[];
}

interface RecipeVisual {
  readonly row: Phaser.GameObjects.Container;
  readonly missingCosts: Phaser.GameObjects.GameObject[];
}

interface PanelLayout {
  readonly panelW: number;
  readonly panelH: number;
  readonly listX: number;
  readonly listY: number;
  readonly listWidth: number;
  readonly listHeight: number;
  readonly detailX: number;
  readonly detailWidth: number;
  readonly detailHeight: number;
  readonly detailY: number;
}

function reasonText(reason: CraftFailureReason): string {
  switch (reason) {
    case 'invalid-recipe': return 'This recipe is unavailable.';
    case 'not-learned': return 'Not learned yet — a quest will teach it.';
    case 'unique-owned': return 'You already have this item.';
    case 'missing-materials': return 'More materials are needed.';
    case 'inventory-full': return 'Make room in your inventory first.';
  }
}

export class CraftingUI {
  private readonly ctx: CraftingUIContext;
  private readonly modalHandle: ModalHandle;
  private container?: Phaser.GameObjects.Container;
  private detailContainer?: Phaser.GameObjects.Container;
  private craftButton?: Phaser.GameObjects.Graphics;
  private selectedIndex = 0;
  private selectedRecipeId?: string;
  private scrollOffset = 0;
  private panelLayout?: PanelLayout;
  private quantityInputBounds?: QuantityInputBounds;
  private quantityInput?: HTMLInputElement;
  private rowVisuals = new Map<number, RecipeVisual>();
  private quantityByRecipeId = new Map<string, number>();
  private failureMessage?: string;
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
      kb.on('keydown-ENTER', this.handleGlobalCraft, this);
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
    this.destroyQuantityInput();
    this.container?.destroy(true);
    this.container = undefined;
    this.detailContainer = undefined;
    this.craftButton = undefined;
    this.panelLayout = undefined;
    this.rowVisuals.clear();
    this.build(animate);
  }

  private build(animate: boolean): void {
    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    const recipes = this.getRecipes();
    this.synchronizeSelection(recipes);

    const layout = getCraftingLayout(recipes.length, cam.height);
    const panelW = Math.max(320, Math.min(PANEL_MAX_WIDTH, cam.width - 24));
    const contentWidth = panelW - PANEL_BORDER_PADDING.left - PANEL_BORDER_PADDING.right - PANEL_GUTTER;
    const listWidth = Math.max(300, Math.min(520, contentWidth * 0.55));
    const viewportListHeight = layout.listHeight;
    const panelH = Math.min(
      cam.height - 24,
      Math.max(560, viewportListHeight + PANEL_BORDER_PADDING.top + PANEL_BORDER_PADDING.bottom),
    );
    const detailWidth = Math.max(
      180,
      Math.min(280, contentWidth - listWidth),
    );
    const listX = -panelW / 2 + PANEL_BORDER_PADDING.left + listWidth / 2;
    const detailX = panelW / 2 - PANEL_BORDER_PADDING.right - detailWidth / 2;
    const contentHeight = panelH - PANEL_BORDER_PADDING.top - PANEL_BORDER_PADDING.bottom;
    const contentCenterY = -panelH / 2 + PANEL_BORDER_PADDING.top + contentHeight / 2;
    const listY = contentCenterY;
    const detailY = contentCenterY;
    const panelLayout: PanelLayout = {
      panelW,
      panelH,
      listX,
      listWidth,
      listHeight: viewportListHeight,
      listY,
      detailX,
      detailWidth,
      detailHeight: contentHeight,
      detailY,
    };
    this.panelLayout = panelLayout;

    const container = scene.add
      .container(cam.width / 2, cam.height / 2)
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(118));
    this.container = container;

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

    const skin = addUiSkin(scene, container, 'ui.backplate.crafting-detail-workbench', {
      x: 0,
      y: 0,
      width: panelW,
      height: panelH,
    });
    if (!skin) {
      const fallback = scene.add.graphics();
      fallback.fillStyle(0x101a31, 0.97);
      fallback.fillRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
      fallback.lineStyle(2, 0x73e2b1, 0.85);
      fallback.strokeRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
      fallback.lineStyle(1, 0x69c8a3, 0.42);
      fallback.lineBetween(0, -panelH / 2 + 24, 0, panelH / 2 - 24);
      container.add(fallback);
    }

    const range = visibleRange(recipes.length, this.scrollOffset, layout.capacityCount);
    const firstRowY = listY - viewportListHeight / 2 + layout.rowHeight / 2;
    for (let index = range.start; index < range.end; index += 1) {
      const rowIndex = index - range.start;
      this.drawRecipe(
        container,
        recipes[index],
        firstRowY + rowIndex * (layout.rowHeight + ROW_GAP),
        index,
        listX,
        listWidth,
        layout.rowHeight,
      );
    }

    if (layout.maxOffset > 0) {
      this.drawScrollControls(
        container,
        listX + listWidth / 2 + PANEL_GUTTER ,
        listY,
        this.scrollOffset > 0,
        this.scrollOffset < layout.maxOffset,
      );
    }

    this.renderDetails();
    if (animate) {
      scene.tweens.add({ targets: container, alpha: { from: 0, to: 1 }, duration: 140 });
    }
  }

  private renderDetails(): void {
    const scene = this.ctx.scene;
    const recipes = this.getRecipes();
    const layout = this.panelLayout;
    if (!this.container || !layout) return;

    this.detailContainer?.destroy(true);
    this.detailContainer = undefined;
    this.craftButton = undefined;

    const detail = scene.add.container(layout.detailX, layout.detailY);
    this.detailContainer = detail;
    this.container.add(detail);

    const recipe = this.getSelectedRecipe(recipes);
    if (!recipe) {
      detail.add(scene.add.text(0, 0, 'No recipes available', {
        fontFamily: DISPLAY_FONT,
        fontSize: '18px',
        fontStyle: 'bold',
        color: TEXT_IVORY,
      }).setOrigin(0.5));
      this.destroyQuantityInput();
      return;
    }

    const quantity = this.quantityFor(recipe);
    const quote = this.ctx.craftingService.quote(recipe, quantity);
    const width = layout.detailWidth;
    const height = layout.detailHeight;
    const horizontalPadding = width < 300 ? 16 : 20;
    const left = -width / 2 + horizontalPadding;
    const right = width / 2 - horizontalPadding;
    const top = -height / 2 + 18;
    const outputWellRadius = width < 300 ? 30 : 34;
    const outputCenterX = left + outputWellRadius + 4;
    const outputCenterY = top + 48;
    const outputWell = scene.add.graphics();
    outputWell.fillStyle(0x102b2b, 0.84);
    outputWell.fillCircle(outputCenterX, outputCenterY, outputWellRadius);
    outputWell.lineStyle(2, quote.status === 'ready' ? 0xd6aa54 : 0x7d7054, 0.78);
    outputWell.strokeCircle(outputCenterX, outputCenterY, outputWellRadius);
    detail.add(outputWell);
    this.addItemIcon(detail, quote.outputItemId, outputCenterX, outputCenterY, outputWellRadius * 1.55);

    const outputDef = itemRegistry.get(quote.outputItemId);
    const headerTextX = outputCenterX + outputWellRadius + 12;
    const title = scene.add.text(headerTextX, top + 18, outputDef?.name ?? recipe.name, {
      fontFamily: DISPLAY_FONT,
      fontSize: width < 300 ? '17px' : '20px',
      fontStyle: 'bold',
      color: TEXT_IVORY,
      stroke: '#1a140c',
      strokeThickness: 4,
      wordWrap: { width: Math.max(110, right - headerTextX) },
      maxLines: 2,
      lineSpacing: -2,
    }).setOrigin(0, 0);
    detail.add(title);

    const descriptionY = Math.max(top + 82, title.y + title.height + 7);
    const description = scene.add.text(left, descriptionY, recipe.description, {
      fontFamily: BODY_FONT,
      fontSize: '11px',
      color: TEXT_MUTED,
      wordWrap: { width: right - left },
      maxLines: 2,
      lineSpacing: 2,
    }).setOrigin(0, 0);
    detail.add(description);

    let contentY = descriptionY + description.height + 12;
    if (quote.stats.length > 0) {
      detail.add(scene.add.text(left, contentY, 'ITEM DETAILS', {
        fontFamily: DISPLAY_FONT,
        fontSize: '10px',
        fontStyle: 'bold',
        color: TEXT_GOLD,
        letterSpacing: 1,
      }).setOrigin(0, 0));
      contentY += 16;
      quote.stats.forEach((stat) => {
        detail.add(scene.add.text(left, contentY, stat.label, {
          fontFamily: BODY_FONT,
          fontSize: '12px',
          color: TEXT_MUTED,
        }).setOrigin(0, 0));
        detail.add(scene.add.text(right, contentY, stat.value, {
          fontFamily: DISPLAY_FONT,
          fontSize: '12px',
          fontStyle: 'bold',
          color: TEXT_AMBER,
        }).setOrigin(1, 0));
        contentY += 16;
      });
      contentY += 6;
    }
   
    detail.add(scene.add.text(left, contentY, 'MATERIALS NEEDED', {
      fontFamily: DISPLAY_FONT,
      fontSize: '10px',
      fontStyle: 'bold',
      color: TEXT_GOLD,
      letterSpacing: 1,
    }).setOrigin(0, 0));
    contentY += 18;

    quote.requirements.forEach((requirement) => {
      const def = itemRegistry.get(requirement.itemId);
      this.addItemIcon(detail, requirement.itemId, left + 14, contentY + 10, RESOURCE_ICON_SIZE - 2);
      detail.add(scene.add.text(left + 36, contentY + 2, def?.name ?? requirement.itemId, {
        fontFamily: BODY_FONT,
        fontSize: '12px',
        color: TEXT_IVORY,
        wordWrap: { width: Math.max(78, right - left - 112) },
      }).setOrigin(0, 0));
      detail.add(scene.add.text(right, contentY + 2, `${requirement.available} / ${requirement.required}`, {
        fontFamily: DISPLAY_FONT,
        fontSize: '12px',
        fontStyle: 'bold',
        color: requirement.missing > 0 ? TEXT_WARNING : TEXT_SUCCESS,
      }).setOrigin(1, 0));
      contentY += 30;
    });

    const actionHeight = 90;
    const actionTop = height / 2 - actionHeight - PANEL_BORDER_PADDING.bottom;
    const actionLeft = -width / 2 ;
    const actionWidth = width - 24;
    /*const actionBackground = scene.add.graphics();
    actionBackground.fillStyle(0x172a27, 0.72);
    actionBackground.fillRoundedRect(actionLeft, actionTop, actionWidth, actionHeight, 14);
    actionBackground.lineStyle(1, 0xc79a4b, 0.58);
    actionBackground.strokeRoundedRect(actionLeft, actionTop, actionWidth, actionHeight, 14);
    detail.add(actionBackground);*/

    const innerPadding = 12;
    const actionGap = 10;
    const buttonW = Math.max(112, Math.min(150, actionWidth * 0.46));
    const quantityWidth = Math.max(72, actionWidth - innerPadding * 2 - actionGap - buttonW);
    const quantityCenterX = actionLeft + innerPadding + quantityWidth / 2;
    const buttonX = actionLeft + actionWidth - innerPadding - buttonW / 2;
    const controlY = actionTop + 61;

    /*detail.add(scene.add.text(quantityCenterX, actionTop + 8, 'AMOUNT TO CRAFT', {
      fontFamily: DISPLAY_FONT,
      fontSize: '9px',
      fontStyle: 'bold',
      color: TEXT_GOLD,
      letterSpacing: 1,
      align: 'center',
      wordWrap: { width: quantityWidth },
    }).setOrigin(0.5, 0));*/
    detail.add(scene.add.text(quantityCenterX, actionTop + 25, `MAX ${quote.maxCraftable}`, {
      fontFamily: BODY_FONT,
      fontSize: '11px',
      color: TEXT_MUTED,
    }).setOrigin(0.5, 0));

    const inputLocalX = quantityCenterX;
    const inputWidth = Math.max(64, Math.min(84, quantityWidth - 4));
    const inputFrame = scene.add.graphics();
    inputFrame.fillStyle(0x10211f, 0.94);
    inputFrame.fillRoundedRect(inputLocalX - inputWidth / 2, controlY - 18, inputWidth, 36, 9);
    inputFrame.lineStyle(2, quote.status === 'ready' ? 0xe8b85f : 0x7d7054, 0.82);
    inputFrame.strokeRoundedRect(inputLocalX - inputWidth / 2, controlY - 18, inputWidth, 36, 9);
    detail.add(inputFrame);

    const buttonH = 48;
    const buttonY = controlY;
    const enabled = quote.status === 'ready';
    const buttonBackground = scene.add.graphics();
    const drawButton = (hover: boolean): void => {
      buttonBackground.clear();
      buttonBackground.fillStyle(enabled ? hover ? 0xfbe2a2 : 0xe8b85f : 0x625c49, enabled ? 0.98 : 0.78);
      buttonBackground.fillRoundedRect(buttonX - buttonW / 2, buttonY - buttonH / 2, buttonW, buttonH, 12);
      buttonBackground.lineStyle(2, enabled ? 0xffedbb : 0x8d8266, 0.92);
      buttonBackground.strokeRoundedRect(buttonX - buttonW / 2, buttonY - buttonH / 2, buttonW, buttonH, 12);
    };
    drawButton(false);
    this.craftButton = buttonBackground;

    const buttonZone = scene.add.zone(buttonX, buttonY, buttonW + 18, buttonH + 18)
      .setOrigin(0.5)
      .setInteractive({ useHandCursor: enabled });
    buttonZone.on('pointerdown', (
      pointer: Phaser.Input.Pointer,
      _localX: number,
      _localY: number,
      event: Phaser.Types.Input.EventData,
    ) => {
      event.stopPropagation();
      if (pointer.button !== 0) return;
      if (!enabled) {
        this.flashCraftButton();
        return;
      }
      this.craftSelected();
    });
    buttonZone.on('pointerover', () => drawButton(enabled));
    buttonZone.on('pointerout', () => drawButton(false));
    detail.add(buttonZone);
    detail.add(buttonBackground);
    detail.add(scene.add.text(buttonX, buttonY, 'CRAFT', {
      fontFamily: DISPLAY_FONT,
      fontSize: '17px',
      fontStyle: 'bold',
      color: enabled ? '#2b1b0e' : '#c8bb91',
      stroke: enabled ? '#f6df9f' : '#4e493b',
      strokeThickness: 1,
    }).setOrigin(0.5));

    const status = this.failureMessage ?? (quote.status === 'ready' ? '' : reasonText(quote.status));
    if (status) {
      detail.add(scene.add.text(0, actionTop - 14, status, {
        fontFamily: BODY_FONT,
        fontSize: '11px',
        fontStyle: 'bold',
        color: TEXT_WARNING,
        align: 'center',
        wordWrap: { width: width - 32 },
      }).setOrigin(0.5));
    }

    this.quantityInputBounds = {
      x: layout.detailX + inputLocalX,
      y: layout.detailY + controlY,
      width: inputWidth - 6,
      height: 32,
    };
    if (this.quantityInput) this.syncQuantityInputPosition();
    else this.createQuantityInput(recipe, quote);
  }

  private createQuantityInput(recipe: RecipeDef, quote: CraftQuote): void {
    const input = document.createElement('input');
    input.type = 'text';
    input.inputMode = 'numeric';
    input.autocomplete = 'off';
    input.spellcheck = false;
    input.maxLength = 7;
    input.setAttribute('aria-label', `Amount of ${recipe.name} to craft`);
    input.value = String(quote.requestedQuantity);
    input.style.cssText = [
      'position: fixed',
      'transform: translate(-50%, -50%)',
      'padding: 2px 8px',
      'font: bold 18px "Palatino Linotype", "Book Antiqua", Georgia, serif',
      'text-align: center',
      'border: 0',
      'background: transparent',
      `color: ${TEXT_IVORY}`,
      'outline: none',
      'z-index: 1100',
      'box-sizing: border-box',
    ].join(';');
    document.body.appendChild(input);
    this.quantityInput = input;
    input.addEventListener('input', this.handleQuantityInput);
    input.addEventListener('change', this.handleQuantityInput);
    input.addEventListener('blur', this.handleQuantityBlur);
    input.addEventListener('keydown', this.handleQuantityKeyDown);
    this.syncQuantityInputPosition();
  }

  private destroyQuantityInput(): void {
    if (!this.quantityInput) return;
    this.quantityInput.removeEventListener('input', this.handleQuantityInput);
    this.quantityInput.removeEventListener('change', this.handleQuantityInput);
    this.quantityInput.removeEventListener('blur', this.handleQuantityBlur);
    this.quantityInput.removeEventListener('keydown', this.handleQuantityKeyDown);
    this.quantityInput.remove();
    this.quantityInput = undefined;
    this.quantityInputBounds = undefined;
  }

  private syncQuantityInputPosition(): void {
    const input = this.quantityInput;
    const bounds = this.quantityInputBounds;
    const canvas = this.ctx.scene.game.canvas;
    if (!input || !bounds || !canvas) return;
    const rect = canvas.getBoundingClientRect();
    const cam = this.ctx.scene.cameras.main;
    const scaleX = rect.width / Math.max(1, cam.width);
    const scaleY = rect.height / Math.max(1, cam.height);
    input.style.left = `${rect.left + (cam.width / 2 + bounds.x) * scaleX}px`;
    input.style.top = `${rect.top + (cam.height / 2 + bounds.y) * scaleY}px`;
    input.style.width = `${bounds.width * scaleX}px`;
    input.style.height = `${bounds.height * scaleY}px`;
    input.style.fontSize = `${Math.max(14, 18 * Math.min(scaleX, scaleY))}px`;
  }

  private handleQuantityInput = (): void => {
    const recipe = this.getSelectedRecipe(this.getRecipes());
    const input = this.quantityInput;
    if (!recipe || !input) return;
    const quote = this.ctx.craftingService.quote(recipe, input.value);
    const normalized = normalizeQuantity(input.value, quote.maxCraftable);
    this.quantityByRecipeId.set(recipe.id, normalized);
    if (input.value.trim().length > 0 && input.value !== String(normalized)) input.value = String(normalized);
    this.failureMessage = undefined;
    this.renderDetails();
  };

  private handleQuantityBlur = (): void => {
    const recipe = this.getSelectedRecipe(this.getRecipes());
    if (!recipe || !this.quantityInput) return;
    const quote = this.ctx.craftingService.quote(recipe, this.quantityInput.value);
    const normalized = normalizeQuantity(this.quantityInput.value, quote.maxCraftable);
    this.quantityByRecipeId.set(recipe.id, normalized);
    this.quantityInput.value = String(normalized);
    this.renderDetails();
  };

  private handleQuantityKeyDown = (event: KeyboardEvent): void => {
    event.stopPropagation();
    if (event.key !== 'Enter') return;
    event.preventDefault();
    this.craftSelected(true);
  };

  private isQuantityInputFocused(): boolean {
    return !!this.quantityInput && document.activeElement === this.quantityInput;
  }

  private drawRecipe(
    container: Phaser.GameObjects.Container,
    recipe: RecipeDef,
    y: number,
    index: number,
    x: number,
    rowWidth: number,
    rowHeight: number,
  ): void {
    const scene = this.ctx.scene;
    const quote = this.ctx.craftingService.quote(recipe, 1);
    const available = quote.status === 'ready';
    const selected = index === this.selectedIndex;
    const row = scene.add.container(x, y);
    const card = scene.add.graphics();
    card.fillStyle(available ? 0x26352f : 0x242a27, available ? 0.58 : 0.48);
    card.fillRoundedRect(-rowWidth / 2, -rowHeight / 2, rowWidth, rowHeight, ROW_CORNER_RADIUS);
    card.lineStyle(
      selected ? 2 : 1,
      selected ? 0xf1c96e : available ? 0xa4874e : 0x68604b,
      selected ? 0.96 : available ? 0.66 : 0.52,
    );
    card.strokeRoundedRect(-rowWidth / 2, -rowHeight / 2, rowWidth, rowHeight, ROW_CORNER_RADIUS);
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
    const costWidth = Math.min(126, Math.max(84, rowWidth * 0.24));
    const costCenterX = rowWidth / 2 - costWidth / 2 - 8;
    const textWidth = Math.max(92, costCenterX - costWidth / 2 - 12 - textX);
    this.addItemIcon(row, recipe.output.itemId, outputX, 0, 38);

    row.add(scene.add.text(textX, 0, recipe.name, {
      fontFamily: DISPLAY_FONT,
      fontSize: '16px',
      fontStyle: 'bold',
      color: available ? TEXT_IVORY : '#938b72',
      stroke: '#1a140c',
      strokeThickness: 4,
      wordWrap: { width: textWidth },
    }).setOrigin(0, 0.5));

    const missingCosts: Phaser.GameObjects.GameObject[] = [];
    const costs = scene.add.container(costCenterX, 0);
    const stackCosts = rowWidth < COST_STACK_BREAKPOINT && recipe.ingredients.length > 1;
    const costItemWidth = stackCosts
      ? costWidth
      : recipe.ingredients.length > 1
        ? (costWidth - 4) / 2
        : Math.min(70, costWidth);
    const costStep = RESOURCE_ICON_SIZE + 4;
    recipe.ingredients.forEach((ingredient, ingredientIndex) => {
      const requirement = quote.requirements[ingredientIndex];
      const current = requirement?.available ?? 0;
      const missing = current < ingredient.count;
      const costX = stackCosts
        ? 0
        : (ingredientIndex - (recipe.ingredients.length - 1) / 2) * (costItemWidth + 4);
      const costY = stackCosts
        ? (ingredientIndex - (recipe.ingredients.length - 1) / 2) * costStep
        : 0;
     
      this.addItemIcon(costs, ingredient.itemId, costX - costItemWidth / 2 + 14, costY, RESOURCE_ICON_SIZE);
      const quantity = scene.add.text(costX - costItemWidth / 2 + 29, costY, `${ingredient.count}`, {
        fontFamily: DISPLAY_FONT,
        fontSize: '11px',
        fontStyle: 'bold',
        color: missing ? TEXT_WARNING : TEXT_AMBER,
      }).setOrigin(0, 0.5);
      costs.add(quantity);
      if (missing) missingCosts.push(quantity);
    });
    row.add(costs);
    container.add(row);
    this.rowVisuals.set(index, { row, missingCosts });
  }

  private addItemIcon(parent: Phaser.GameObjects.Container, itemId: string, x: number, y: number, size: number): void {
    const scene = this.ctx.scene;
    const def = itemRegistry.get(itemId);
    if (!def) return;
    if (def.equipment?.weaponId) {
      const thumbnail = createWeaponThumbnail(scene, def.equipment.weaponId, { x, y, size });
      if (thumbnail) parent.add(thumbnail);
      return;
    }
    const icon = def.iconFrame === undefined
      ? scene.add.image(x, y, def.icon)
      : scene.add.image(x, y, def.icon, def.iconFrame);
    parent.add(icon.setDisplaySize(size, size));
  }

  private drawScrollControls(
    container: Phaser.GameObjects.Container,
    x: number,
    centerY: number,
    canScrollUp: boolean,
    canScrollDown: boolean,
  ): void {
    const buttonHeight = 22;
    const buttonGap = 4;
    this.drawScrollButton(container, x, centerY - (buttonHeight + buttonGap) / 2, 'up', canScrollUp);
    this.drawScrollButton(container, x, centerY + (buttonHeight + buttonGap) / 2, 'down', canScrollDown);
  }

  private drawScrollButton(
    container: Phaser.GameObjects.Container,
    x: number,
    y: number,
    direction: 'up' | 'down',
    enabled: boolean,
  ): void {
    const scene = this.ctx.scene;
    const buttonWidth = PANEL_GUTTER;
    const buttonHeight = 22;
    const buttonBackground = scene.add.graphics();
    const arrow = direction === 'up'
      ? scene.add.triangle(x, y, 0, -6, -6, 5, 6, 5, 0xf1c96e)
      : scene.add.triangle(x, y, 0, 6, -6, -5, 6, -5, 0xf1c96e);
    const drawButton = (hover: boolean): void => {
      const arrowColor = enabled ? hover ? 0xffedb2 : 0xf1c96e : 0x716b5a;
      buttonBackground.clear();
      arrow.setFillStyle(arrowColor);
    };
    drawButton(false);

    const buttonZone = scene.add.zone(x, y, buttonWidth + 8, buttonHeight + 8)
      .setOrigin(0.5)
      .setInteractive({ useHandCursor: enabled });
    buttonZone.on('pointerdown', (
      pointer: Phaser.Input.Pointer,
      _localX: number,
      _localY: number,
      event: Phaser.Types.Input.EventData,
    ) => {
      event.stopPropagation();
      if (pointer.button !== 0 || !enabled) return;
      this.scrollRecipes(direction === 'up' ? -1 : 1);
    });
    buttonZone.on('pointerover', () => drawButton(true));
    buttonZone.on('pointerout', () => drawButton(false));
    container.add(buttonBackground);
    container.add(arrow);
    container.add(buttonZone);
  }

  private handleRecipeClick(index: number): void {
    const recipes = this.getRecipes();
    const recipe = recipes[index];
    if (!recipe) return;
    this.selectedIndex = index;
    this.selectedRecipeId = recipe.id;
    this.failureMessage = undefined;
    const layout = getCraftingLayout(recipes.length, this.ctx.scene.cameras.main.height);
    this.scrollOffset = ensureVisible(index, this.scrollOffset, layout.capacityCount, recipes.length);
    this.rebuild(false);
  }

  private craftSelected = (fromQuantityInput = false): void => {
    if (!this.container || this.isQuantityInputFocused() && !fromQuantityInput) return;
    const recipe = this.getSelectedRecipe(this.getRecipes());
    if (!recipe) return;
    const quantity = this.quantityFor(recipe);
    const result = this.ctx.craftingService.craft(recipe, quantity);
    if (result.ok) {
      this.failureMessage = undefined;
      this.ctx.onCrafted?.(result);
      return;
    }
    this.failureMessage = reasonText(result.reason);
    this.renderDetails();
    this.flashMissing(this.selectedIndex);
    this.flashCraftButton();
  };

  private handleGlobalCraft = (): void => {
    this.craftSelected();
  };

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

  private flashCraftButton(): void {
    if (!this.craftButton) return;
    this.ctx.scene.tweens.add({
      targets: this.craftButton,
      alpha: { from: 1, to: 0.45 },
      yoyo: true,
      duration: FAILURE_FEEDBACK_DURATION,
    });
  }

  private selectPrevious = (event?: KeyboardEvent): void => {
    if (!this.container || this.isQuantityInputFocused() || event?.target === this.quantityInput) return;
    const recipes = this.getRecipes();
    if (recipes.length === 0) return;
    this.selectedIndex = moveSelection(this.selectedIndex, -1, recipes.length);
    this.selectedRecipeId = recipes[this.selectedIndex]?.id;
    const layout = getCraftingLayout(recipes.length, this.ctx.scene.cameras.main.height);
    this.scrollOffset = ensureVisible(this.selectedIndex, this.scrollOffset, layout.capacityCount, recipes.length);
    this.failureMessage = undefined;
    this.rebuild(false);
  };

  private selectNext = (event?: KeyboardEvent): void => {
    if (!this.container || this.isQuantityInputFocused() || event?.target === this.quantityInput) return;
    const recipes = this.getRecipes();
    if (recipes.length === 0) return;
    this.selectedIndex = moveSelection(this.selectedIndex, 1, recipes.length);
    this.selectedRecipeId = recipes[this.selectedIndex]?.id;
    const layout = getCraftingLayout(recipes.length, this.ctx.scene.cameras.main.height);
    this.scrollOffset = ensureVisible(this.selectedIndex, this.scrollOffset, layout.capacityCount, recipes.length);
    this.failureMessage = undefined;
    this.rebuild(false);
  };

  private handleCraftingWheel = (
    _pointer: Phaser.Input.Pointer,
    _objects: unknown[],
    _deltaX: number,
    deltaY: number,
  ): void => {
    if (!this.container || deltaY === 0) return;
    this.scrollRecipes(Math.sign(deltaY));
  };

  private scrollRecipes(delta: number): void {
    if (!this.container || delta === 0) return;
    const recipes = this.getRecipes();
    const layout = getCraftingLayout(recipes.length, this.ctx.scene.cameras.main.height);
    const nextOffset = clampOffset(this.scrollOffset + delta, recipes.length, layout.capacityCount);
    if (nextOffset === this.scrollOffset) return;
    this.scrollOffset = nextOffset;
    this.rebuild(false);
  }

  private handleResize = (): void => {
    if (this.container) this.rebuild(false);
    else this.syncQuantityInputPosition();
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

  private synchronizeSelection(recipes: readonly RecipeDef[]): void {
    if (recipes.length === 0) {
      this.selectedIndex = 0;
      this.selectedRecipeId = undefined;
      return;
    }
    const selectedById = this.selectedRecipeId
      ? recipes.findIndex((recipe) => recipe.id === this.selectedRecipeId)
      : -1;
    this.selectedIndex = selectedById >= 0
      ? selectedById
      : Phaser.Math.Clamp(this.selectedIndex, 0, recipes.length - 1);
    this.selectedRecipeId = recipes[this.selectedIndex]?.id;
    const layout = getCraftingLayout(recipes.length, this.ctx.scene.cameras.main.height);
    this.scrollOffset = clampOffset(this.scrollOffset, recipes.length, layout.capacityCount);
  }

  private getSelectedRecipe(recipes: readonly RecipeDef[]): RecipeDef | undefined {
    if (this.selectedRecipeId) {
      const byId = recipes.find((recipe) => recipe.id === this.selectedRecipeId);
      if (byId) return byId;
    }
    return recipes[this.selectedIndex];
  }

  private quantityFor(recipe: RecipeDef): number {
    const probe = this.ctx.craftingService.quote(recipe, 1);
    const normalized = normalizeQuantity(this.quantityByRecipeId.get(recipe.id) ?? 1, probe.maxCraftable);
    this.quantityByRecipeId.set(recipe.id, normalized);
    return normalized;
  }

  public close(): void {
    this.detachOpenListeners();
    const wasOpen = !!this.container;
    this.modalHandle.close();
    this.destroyQuantityInput();
    this.container?.destroy(true);
    this.container = undefined;
    this.detailContainer = undefined;
    this.craftButton = undefined;
    this.panelLayout = undefined;
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
    kb?.off('keydown-ENTER', this.handleGlobalCraft, this);
    this.destroyQuantityInput();
    this.container?.destroy(true);
    this.container = undefined;
    this.detailContainer = undefined;
    this.craftButton = undefined;
    this.panelLayout = undefined;
    this.rowVisuals.clear();
    if (wasOpen) this.ctx.onPausedChange(false);
  }
}
