import Phaser from 'phaser';
import { SLIME_ANIM_MAP, SLIME_ANIMS } from '../slimeAnimations';
import { Friend } from '../Friend';
import { House } from '../House';
import { TILE_SIZE, WORLD_TILES_X, WORLD_TILES_Y, WORLD_WIDTH, WORLD_HEIGHT, biomeSample } from '../terrainNoise';
import {
  getTileBodyBounds,
  isTileCollidable,
  resolveWorldTile,
  resolveWorldTileTexture,
  WORLD_TILE_RULES,
  type WorldTileId,
} from '../worldTiles';
import { Minimap } from '../Minimap';
import { HUD } from '../HUD';
import { ShopUI } from '../ShopUI';
import { ChatUI } from '../ChatUI';
import { gameState } from '../core/GameState';
import { gameEvents } from '../core/EventBus';
import { createControls, createFakeControls, type Controls, type InputBindings } from '../core/Input';
import { HouseSystem } from '../systems/HouseSystem';
import { HealthSystem, type DamageRequest } from '../systems/HealthSystem';
import { StatusEffectManager } from '../systems/StatusEffects';
import { getStats } from '../systems/PlayerStats';
import { AbilitySystem } from '../systems/AbilitySystem';
import { playerInventory, itemRegistry } from '../systems/Inventory';
import { floatingText } from '../ui/FloatingText';
import { HealthBar } from '../ui/HealthBar';
import { LevelUpModal } from '../ui/LevelUpModal';
import { InventoryUI } from '../ui/InventoryUI';
import { AbilityBar } from '../ui/AbilityBar';
import { Weapon } from '../combat/Weapon';
import { createGooGauntlet } from '../weapons/library/GooGauntlet';
import { ComboSystem } from '../combat/ComboSystem';
import { TargetDummy } from '../combat/TargetDummy';
import { hitboxPool, type HitboxConfig } from '../combat/Hitbox';
import { Enemy } from '../enemies/Enemy';
import { EnemySpawner } from '../enemies/EnemySpawner';
import { projectilePool } from '../enemies/Projectile';
import { SPAWN_TABLE_MEDIUM } from '../enemies/library/EnemyTypes';
import { AREAS, oppositeDirection, type AreaDef, type AreaId, type Direction } from '../world/Area';
import { BIOMES } from '../world/Biome';
import { showAreaTitleCard } from '../ui/AreaTitleCard';
import { WorldMapUI } from '../ui/WorldMapUI';
import { questTracker } from '../quests/QuestTracker';
import { QuestJournal } from '../ui/QuestJournal';
import { BLOBFATHER } from '../boss/BossDefs';
import { BossHealthBar } from '../ui/BossHealthBar';
import { CraftingUI } from '../ui/CraftingUI';
import { devToolsState } from '../devTools';

const WALK_SPEED = 230;
const BOOST_SPEED = 360;
const DEFAULT_ZOOM = 1;
const HOUSE_ZOOM = 1;
const PLAYER_HOUSE_SAFE_RADIUS = 540;
const EDGE_TRANSITION_SIZE = 32;
const EDGE_TRANSITION_GRACE_MS = 650;
const AREA_TRANSITION_HANDOFF_KEY = 'slime-isa:area-transition';
const BOSS_DEFEATED_KEY = 'slime-isa:defeated-bosses';
const DUNGEON_COMPLETED_KEY = 'slime-isa:dungeon-completed';
const CRYSTAL_TRIAL_ID = 'crystal-caverns-switch-trial';

interface WorldSceneData {
  areaId?: AreaId;
  entryEdge?: Direction;
}

export class WorldScene extends Phaser.Scene {
  private static sessionStarted = false;
  private player!: Phaser.Physics.Arcade.Sprite;
  private collisionTiles!: Phaser.Physics.Arcade.StaticGroup;
  private friends!: Phaser.Physics.Arcade.Group;
  private controls: Controls = createFakeControls();
  private currentAnimation = 'slime-idle';
  private actionLocked = false;
  private paused = false;
  private pauseSources = new Set<string>();
  private terrainGrid: WorldTileId[][] = [];
  private minimap!: Minimap;
  private hud!: HUD;
  private shopUI!: ShopUI;
  private shopTarget: Friend | null = null;
  private chatUI!: ChatUI;
  private houses: Array<{ owner: 'player' | 'friend'; house: House }> = [];
  private playerHouse?: House;
  private houseSystem!: HouseSystem;
  private inputBindings?: InputBindings;
  private purpleFoods!: Phaser.Physics.Arcade.StaticGroup;
  private grapeChips!: Phaser.Physics.Arcade.StaticGroup;
  private playerNameTag!: Phaser.GameObjects.Text;
  private healthSystem?: HealthSystem;
  private statusEffects?: StatusEffectManager;
  private healthBar?: HealthBar;
  private levelUpModal?: LevelUpModal;
  private inventoryUI?: InventoryUI;
  private worldMapUI?: WorldMapUI;
  private questJournal?: QuestJournal;
  private craftingUI?: CraftingUI;
  private abilitySystem?: AbilitySystem;
  private abilityBar?: AbilityBar;
  private facing = new Phaser.Math.Vector2(0, 1);
  private lastBedPos: Phaser.Math.Vector2 | null = null;
  private iFrameFlashActive = false;
  private weapon?: Weapon;
  private comboSystem?: ComboSystem;
  private combatTargets: Phaser.Physics.Arcade.Group | null = null;
  private dummies: TargetDummy[] = [];
  private enemySpawner?: EnemySpawner;
  private activeBoss?: Enemy;
  private bossHealthBar?: BossHealthBar;
  private dungeonSwitches?: Phaser.Physics.Arcade.StaticGroup;
  private dungeonChests?: Phaser.Physics.Arcade.StaticGroup;
  private dungeonSwitchStates: boolean[] = [];
  private dungeonChestOpened = false;
  private dungeonHintReadyAt = 0;
  private comboText?: Phaser.GameObjects.Text;
  private attacking = false;
  private dodgeInvulnUntil = 0;
  private currentArea: AreaDef = AREAS['meadow-crossing'];
  private entryEdge?: Direction;
  private transitioning = false;
  private transitionReadyAt = 0;
  private transitionZones: Phaser.GameObjects.Zone[] = [];
  private levelUpNoticeHandler?: (payload: { level: number }) => void;
  private questCompleteHandler?: (payload: { questId: string; title: string; rewards: { coins?: number; xp?: number } }) => void;
  private restoredFromAreaTransition = false;
  private respawnHomeOnLoad = false;
  private debugGraphics?: Phaser.GameObjects.Graphics;

  constructor() {
    super('world');
  }

  init(data: WorldSceneData = {}): void {
    const queryArea = new URLSearchParams(window.location.search).get('area') as AreaId | null;
    const queryEntry = new URLSearchParams(window.location.search).get('entry') as Direction | null;
    const queryRespawn = new URLSearchParams(window.location.search).get('respawn');
    const areaId = data.areaId ?? (queryArea && queryArea in AREAS ? queryArea : 'meadow-crossing');
    this.currentArea = AREAS[areaId];
    this.entryEdge = data.entryEdge ?? (queryEntry && this.isDirection(queryEntry) ? queryEntry : undefined);
    this.respawnHomeOnLoad = queryRespawn === 'home';
    this.transitioning = false;
    this.transitionReadyAt = this.time.now + EDGE_TRANSITION_GRACE_MS;
  }

  create(): void {
    this.resetSceneStateForAreaLoad();
    this.restoredFromAreaTransition = this.restoreAreaTransitionHandoff();

    // Reset persistent state once per browser session. Area transitions restart
    // this scene, so they must preserve HP, XP, coins, perks, and inventory.
    if (!WorldScene.sessionStarted && !this.restoredFromAreaTransition) {
      gameState.reset();
      WorldScene.sessionStarted = true;
    }

    // Phase 1: World entities (no cross-system side effects)
    this.createCollisionLayer();
    this.buildWorld();
    this.createSlimeAnimations();
    this.createPlayer();
    this.createFriends(this.friendCountForArea());
    this.placeHouses(this.currentArea.hasPlayerHome ? 1 : 0, this.currentArea.hasPlayerHome ? Math.min(6, this.friends.getLength()) : 0);
    this.createCrystalTrial();
    this.houseSystem = new HouseSystem({
      scene: this,
      getPlayer: () => this.player,
      getHouses: () => this.houses,
      isActionLocked: () => this.actionLocked,
      setActionLocked: (locked) => { this.actionLocked = locked; },
      playIdle: () => this.playAnimation('slime-idle'),
      defaultZoom: DEFAULT_ZOOM,
      houseZoom: HOUSE_ZOOM,
    });
    this.createPhysics();
    this.createCamera();

    // Phase 2: UI systems
    this.createMinimap();
    this.createHUD();
    this.createControls();
    this.createShopUI();
    this.createOverlay();
    this.createChatUI();

    // Phase 1 systems: health, status, level-up modal, inventory UI
    this.statusEffects = new StatusEffectManager();
    questTracker.start();
    this.healthSystem = new HealthSystem({
      scene: this,
      getPlayer: () => this.player,
      getStatus: () => this.statusEffects!,
      onHit: () => this.onPlayerHit(),
      onDeath: () => this.onPlayerDeath(),
    });
    this.healthBar = new HealthBar(this, this.player);
    this.abilitySystem = new AbilitySystem({
      scene: this,
      getPlayer: () => this.player,
      isActionLocked: () => this.actionLocked,
      setActionLocked: (locked) => { this.actionLocked = locked; },
      getFacing: () => this.facing,
      playAnimation: (key) => this.playAnimation(key),
      getTerrainGrid: () => this.terrainGrid,
      getCombatTargets: () => this.combatTargets,
    });
    this.levelUpModal = new LevelUpModal({
      scene: this,
      onPausedChange: (p) => { this.setSimulationPaused('levelup', p); },
    });
    this.inventoryUI = new InventoryUI({
      scene: this,
      onPausedChange: (p) => { this.setSimulationPaused('inventory', p); },
      onUseItem: (itemId) => this.useItem(itemId),
    });
    this.worldMapUI = new WorldMapUI({
      scene: this,
      getCurrentArea: () => this.currentArea.id,
      onPausedChange: (p) => { this.setSimulationPaused('worldmap', p); },
    });
    this.worldMapUI.discover(this.currentArea.id);
    this.questJournal = new QuestJournal({
      scene: this,
      onPausedChange: (p) => { this.setSimulationPaused('journal', p); },
    });
    this.craftingUI = new CraftingUI({
      scene: this,
      onPausedChange: (p) => { this.setSimulationPaused('crafting', p); },
      onCrafted: (recipe) => {
        floatingText.spawn(this, this.player.x, this.player.y - 44, `Crafted: ${recipe.name}`, 'green', true);
      },
    });
    this.abilityBar = new AbilityBar({
      scene: this,
      getAbilitySystem: () => this.abilitySystem,
    });

    // Phase 2: combat system
    this.createCombatSystem();

    this.bindHotkeys();
    this.bindDebugCheats();

    // Notify when an ability unlocks via level-up.
    this.levelUpNoticeHandler = (p) => {
      if (p.level === 2) {
        floatingText.spawn(this, this.player.x, this.player.y - 50, 'JUMP UNLOCKED!', 'green', true);
      } else if (p.level === 3) {
        floatingText.spawn(this, this.player.x, this.player.y - 50, 'SQUASH SLAM!', 'green', true);
      } else if (p.level === 4) {
        floatingText.spawn(this, this.player.x, this.player.y - 50, 'STRETCH LASH!', 'orange', true);
      } else if (p.level === 5) {
        floatingText.spawn(this, this.player.x, this.player.y - 50, 'TELEPORT UNLOCKED!', 'cyan', true);
      }
    };
    gameEvents.on('level.up', this.levelUpNoticeHandler);

    this.questCompleteHandler = (p) => {
      const reward = [`+${p.rewards.coins ?? 0}c`, `+${p.rewards.xp ?? 0} XP`].join('  ');
      floatingText.spawn(this, this.player.x, this.player.y - 70, `QUEST COMPLETE: ${p.title}`, 'yellow', true);
      floatingText.spawn(this, this.player.x, this.player.y - 48, reward, 'green', true);
    };
    gameEvents.on('quest.completed', this.questCompleteHandler);

    if (!this.restoredFromAreaTransition) {
      // Seed a couple of starter potions for playtesting once per fresh run.
      playerInventory.add('hp-potion', 3);
      playerInventory.add('energy-potion', 2);
    }

    // Record the bed position on sleep for respawn.
    gameEvents.on('house.sleep', () => {
      this.lastBedPos = new Phaser.Math.Vector2(this.player.x, this.player.y);
    });

    // Phase 3: One-time cross-system sync
    gameState.setTotalFriends(this.friends.getLength());

    this.scale.on('resize', this.handleResize, this);
    gameEvents.emit('area.enter', { areaId: this.currentArea.id });
    this.clearOneShotUrlParams();
    showAreaTitleCard(this, this.currentArea.name, BIOMES[this.currentArea.biome].titleColor);
  }

  private resetSceneStateForAreaLoad(): void {
    this.levelUpModal?.destroy();
    this.inventoryUI?.destroy();
    this.worldMapUI?.destroy();
    this.questJournal?.destroy();
    this.craftingUI?.destroy();
    this.enemySpawner?.destroy();
    this.bossHealthBar?.destroy();
    this.healthSystem?.destroy();
    if (this.levelUpNoticeHandler) {
      gameEvents.off('level.up', this.levelUpNoticeHandler);
      this.levelUpNoticeHandler = undefined;
    }
    if (this.questCompleteHandler) {
      gameEvents.off('quest.completed', this.questCompleteHandler);
      this.questCompleteHandler = undefined;
    }
    hitboxPool.clearScene(this);
    projectilePool.clearScene(this);

    this.houses = [];
    this.playerHouse = undefined;
    this.transitionZones.forEach((zone) => zone.destroy());
    this.transitionZones = [];
    this.dummies = [];
    this.combatTargets = null;
    this.activeBoss = undefined;
    this.bossHealthBar = undefined;
    this.dungeonSwitches = undefined;
    this.dungeonChests = undefined;
    this.dungeonSwitchStates = [];
    this.dungeonChestOpened = false;
    this.dungeonHintReadyAt = 0;
    this.shopTarget = null;
    this.worldMapUI = undefined;
    this.questJournal = undefined;
    this.craftingUI = undefined;
    this.pauseSources.clear();
    this.paused = false;
    this.actionLocked = false;
    this.attacking = false;
    this.dodgeInvulnUntil = 0;
  }

  private restoreAreaTransitionHandoff(): boolean {
    try {
      const raw = sessionStorage.getItem(AREA_TRANSITION_HANDOFF_KEY);
      if (!raw) return false;
      sessionStorage.removeItem(AREA_TRANSITION_HANDOFF_KEY);
      const parsed = JSON.parse(raw) as {
        gameState?: ReturnType<typeof gameState.serialize>;
        inventory?: ReturnType<typeof playerInventory.serialize>;
        respawnHome?: boolean;
      };
      if (parsed.gameState) gameState.load(parsed.gameState);
      if (parsed.inventory) playerInventory.load(parsed.inventory);
      if (parsed.respawnHome) this.respawnHomeOnLoad = true;
      WorldScene.sessionStarted = true;
      return true;
    } catch {
      return false;
    }
  }

  private clearOneShotUrlParams(): void {
    const url = new URL(window.location.href);
    if (!url.searchParams.has('entry') && !url.searchParams.has('respawn') && !url.searchParams.has('t')) return;
    url.searchParams.delete('entry');
    url.searchParams.delete('respawn');
    url.searchParams.delete('t');
    window.history.replaceState({}, '', url.toString());
  }

  private setSimulationPaused(source: string, paused: boolean): void {
    if (paused) {
      this.pauseSources.add(source);
    } else {
      this.pauseSources.delete(source);
    }

    const shouldPause = this.pauseSources.size > 0;
    if (this.paused === shouldPause) {
      if (shouldPause) this.stopMovingBodies();
      return;
    }

    this.paused = shouldPause;
    if (shouldPause) {
      this.stopMovingBodies();
      this.physics.world.pause();
    } else {
      this.physics.world.resume();
    }
  }

  private stopMovingBodies(): void {
    const stop = (child: Phaser.GameObjects.GameObject): void => {
      const body = (child as Phaser.GameObjects.GameObject & {
        body?: Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody;
      }).body;

      if (body instanceof Phaser.Physics.Arcade.Body) {
        body.setVelocity(0, 0);
      }
    };

    if (this.player?.body) this.player.setVelocity(0, 0);
    this.friends?.children.each((child) => {
      stop(child);
      return true;
    });
    this.combatTargets?.children.each((child) => {
      stop(child);
      return true;
    });
    projectilePool.enemyGroup(this).children.each((child) => {
      stop(child);
      return true;
    });
    projectilePool.playerGroup(this).children.each((child) => {
      stop(child);
      return true;
    });
  }

  update(_time: number, delta: number): void {
    this.updateDevToolsOverlay();

    if (this.paused) {
      this.player.setVelocity(0, 0);
      return;
    }

    this.minimap.update(this.cameras.main, this.player, this.friends, this.houses);

    if (this.player && this.playerNameTag) {
      this.playerNameTag.setPosition(this.player.x, this.player.y - 56);
    }

    this.houseSystem.update();
    this.statusEffects?.update(this.time.now, delta);
    this.healthSystem?.update(this.time.now);
    this.healthBar?.update();
    this.bossHealthBar?.update();
    this.abilityBar?.update();
    this.abilitySystem?.update();
    this.comboSystem?.update();
    this.enemySpawner?.update(this.time.now, delta);
    // Passive energy regen (scaled by Quick Recovery perk).
    if (!this.healthSystem?.isDead()) {
      const stats = getStats();
      const regen = (stats.energyRegenPerSec * delta) / 1000;
      if (regen > 0) gameState.regenEnergy(regen);
    }

    // Respawn override: if dead, skip input but still tick systems above.
    if (this.healthSystem?.isDead()) {
      this.player.setVelocity(0, 0);
      this.player.rotation = 0;
      return;
    }

    const direction = this.readDirection();

    if (this.actionLocked) {
      this.player.setVelocity(0, 0);
      this.player.rotation = 0;
      return;
    }

    if (this.handleActionInput(direction)) {
      return;
    }

    this.movePlayer(direction);
  }

  private updateDevToolsOverlay(): void {
    if (!import.meta.env.DEV) return;

    const g = this.debugGraphics ?? this.add.graphics().setDepth(1000).setScrollFactor(1);
    this.debugGraphics = g;
    g.clear();

    if (!devToolsState.enabled) {
      g.setVisible(false);
      return;
    }

    g.setVisible(true);

    if (devToolsState.worldBounds) this.drawWorldDebug(g);
    if (devToolsState.visualBounds) this.drawVisualBoundsDebug(g);
    if (devToolsState.hitBoxes) this.drawHitBoxesDebug(g);
    if (devToolsState.interactionZones) this.drawInteractionZonesDebug(g);
    if (devToolsState.attackBoxes) this.drawAttackBoxesDebug(g);
  }

  private drawWorldDebug(g: Phaser.GameObjects.Graphics): void {
    this.strokeRect(g, 0, 0, WORLD_WIDTH, WORLD_HEIGHT, 0xffe66d, 0.95, 3);
    const view = this.cameras.main.worldView;
    this.strokeRect(g, view.x, view.y, view.width, view.height, 0xffe66d, 0.6, 2);
  }

  private drawVisualBoundsDebug(g: Phaser.GameObjects.Graphics): void {
    this.drawGameObjectBounds(g, this.player, 0x55a7ff, 0.95);
    this.forGroupChildren(this.friends, (child) => this.drawGameObjectBounds(g, child, 0x55a7ff, 0.75));
    this.forGroupChildren(this.combatTargets, (child) => this.drawGameObjectBounds(g, child, 0x55a7ff, 0.85));
    this.forGroupChildren(this.purpleFoods, (child) => this.drawGameObjectBounds(g, child, 0x55a7ff, 0.55));
    this.forGroupChildren(this.grapeChips, (child) => this.drawGameObjectBounds(g, child, 0x55a7ff, 0.55));

    for (const entry of this.houses) {
      this.drawGameObjectBounds(g, entry.house.sprite, 0x55a7ff, 0.65);
    }
  }

  private drawHitBoxesDebug(g: Phaser.GameObjects.Graphics): void {
    this.drawBodyDebug(g, this.player.body, 0xff4d6d, 0.95);
    this.forGroupChildren(this.friends, (child) => this.drawBodyDebug(g, this.bodyOf(child), 0xff4d6d, 0.7));
    this.forGroupChildren(this.combatTargets, (child) => this.drawBodyDebug(g, this.bodyOf(child), 0xff4d6d, 0.9));
    this.forGroupChildren(this.collisionTiles, (child) => this.drawBodyDebug(g, this.bodyOf(child), 0xff4d6d, 0.35));
  }

  private drawInteractionZonesDebug(g: Phaser.GameObjects.Graphics): void {
    for (const entry of this.houses) {
      this.drawBodyDebug(g, this.bodyOf(entry.house.doorZone), 0x43f28f, 0.9);
    }

    for (const zone of this.transitionZones) {
      this.drawBodyDebug(g, this.bodyOf(zone), 0x43f28f, 0.85);
    }

    this.forGroupChildren(this.purpleFoods, (child) => this.drawBodyDebug(g, this.bodyOf(child), 0x43f28f, 0.75));
    this.forGroupChildren(this.grapeChips, (child) => this.drawBodyDebug(g, this.bodyOf(child), 0x43f28f, 0.75));
    this.forGroupChildren(this.dungeonSwitches, (child) => this.drawBodyDebug(g, this.bodyOf(child), 0x43f28f, 0.85));
    this.forGroupChildren(this.dungeonChests, (child) => this.drawBodyDebug(g, this.bodyOf(child), 0x43f28f, 0.85));
  }

  private drawAttackBoxesDebug(g: Phaser.GameObjects.Graphics): void {
    for (const config of hitboxPool.getActiveConfigs(this)) {
      this.drawAttackShape(g, config);
    }
  }

  private drawAttackShape(g: Phaser.GameObjects.Graphics, config: HitboxConfig): void {
    if (config.shape === 'sector') {
      const originX = config.originX ?? config.x;
      const originY = config.originY ?? config.y;
      const angle = config.angle ?? 0;
      const arcHalf = (config.arcWidth ?? Math.PI / 2) / 2;
      const innerRadius = config.innerRadius ?? 0;
      const outerRadius = config.outerRadius ?? Math.max(config.width, config.height) / 2;

      g.fillStyle(0xb685ff, 0.12);
      g.lineStyle(3, 0xb685ff, 0.95);
      g.beginPath();
      g.arc(originX, originY, outerRadius, angle - arcHalf, angle + arcHalf, false);
      if (innerRadius > 0) {
        g.arc(originX, originY, innerRadius, angle + arcHalf, angle - arcHalf, true);
      } else {
        g.lineTo(originX, originY);
      }
      g.closePath();
      g.fillPath();
      g.strokePath();
      this.strokeRect(g, config.x - config.width / 2, config.y - config.height / 2, config.width, config.height, 0xb685ff, 0.42, 1);
      return;
    }

    this.fillRect(g, config.x - config.width / 2, config.y - config.height / 2, config.width, config.height, 0xb685ff, 0.12);
    this.strokeRect(g, config.x - config.width / 2, config.y - config.height / 2, config.width, config.height, 0xb685ff, 0.95, 3);
  }

  private drawGameObjectBounds(g: Phaser.GameObjects.Graphics, object: Phaser.GameObjects.GameObject | null | undefined, color: number, alpha: number): void {
    const withBounds = object as (Phaser.GameObjects.GameObject & { getBounds?: () => Phaser.Geom.Rectangle; active?: boolean }) | null | undefined;
    if (!withBounds || withBounds.active === false || !withBounds.getBounds) return;

    const bounds = withBounds.getBounds();
    this.strokeRect(g, bounds.x, bounds.y, bounds.width, bounds.height, color, alpha, 2);
  }

  private drawBodyDebug(
    g: Phaser.GameObjects.Graphics,
    body: Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody | null | undefined,
    color: number,
    alpha: number,
  ): void {
    if (!body) return;
    this.fillRect(g, body.x, body.y, body.width, body.height, color, 0.06);
    this.strokeRect(g, body.x, body.y, body.width, body.height, color, alpha, 2);
  }

  private forGroupChildren(
    group: Phaser.GameObjects.Group | Phaser.Physics.Arcade.Group | Phaser.Physics.Arcade.StaticGroup | null | undefined,
    callback: (child: Phaser.GameObjects.GameObject) => void,
  ): void {
    if (!group) return;
    for (const child of group.getChildren()) callback(child);
  }

  private bodyOf(object: Phaser.GameObjects.GameObject | null | undefined): Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody | null {
    return ((object as Phaser.GameObjects.GameObject & {
      body?: Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody;
    } | null | undefined)?.body) ?? null;
  }

  private fillRect(g: Phaser.GameObjects.Graphics, x: number, y: number, width: number, height: number, color: number, alpha: number): void {
    g.fillStyle(color, alpha);
    g.fillRect(x, y, width, height);
  }

  private strokeRect(g: Phaser.GameObjects.Graphics, x: number, y: number, width: number, height: number, color: number, alpha: number, lineWidth: number): void {
    g.lineStyle(lineWidth, color, alpha);
    g.strokeRect(x, y, width, height);
  }

  private readDirection(): Phaser.Math.Vector2 {
    const direction = new Phaser.Math.Vector2(0, 0);

    if (this.controls.left.isDown || this.controls.leftAlt.isDown) {
      direction.x -= 1;
    }
    if (this.controls.right.isDown || this.controls.rightAlt.isDown) {
      direction.x += 1;
    }
    if (this.controls.up.isDown || this.controls.upAlt.isDown) {
      direction.y -= 1;
    }
    if (this.controls.down.isDown || this.controls.downAlt.isDown) {
      direction.y += 1;
    }

    return direction;
  }

  private movePlayer(direction: Phaser.Math.Vector2): void {
    const wantsBoost = this.controls.boost.isDown;
    const stats = getStats();
    const baseSpeed = wantsBoost ? BOOST_SPEED + gameState.boostBonus : stats.speed;
    const speedMult = this.statusEffects?.speedMultiplier ?? 1;

    if (this.statusEffects?.isRooted()) {
      this.player.setVelocity(0, 0);
      this.player.rotation = 0;
      this.playAnimation('slime-idle');
      return;
    }

    if (direction.lengthSq() > 0) {
      direction.normalize().scale(baseSpeed * speedMult);
    }

    this.player.setVelocity(direction.x, direction.y);
    this.player.rotation = 0;

    if (direction.lengthSq() === 0) {
      this.player.setFlipX(false);
      this.playAnimation('slime-idle');
      return;
    }

    // Track facing for abilities (jump/teleport).
    this.facing.set(direction.x, direction.y).normalize();

    if (Math.abs(direction.x) >= Math.abs(direction.y)) {
      this.player.setFlipX(direction.x > 0);
    } else {
      this.player.setFlipX(false);
    }

    if (wantsBoost) {
      this.playAnimation('slime-roll');
    } else if (Math.abs(direction.y) > Math.abs(direction.x)) {
      this.playAnimation(direction.y < 0 ? 'slime-stretch' : 'slime-hop');
    } else {
      this.playAnimation('slime-walk');
    }
  }

  private friendCountForArea(): number {
    if (this.currentArea.biome === 'meadow') return 84;
    if (this.currentArea.biome === 'gloop-forest') return 16;
    return 6;
  }

  private transitionTo(areaId: AreaId, entryEdge: Direction): void {
    this.transitioning = true;
    this.player.setVelocity(0, 0);
    this.navigateToArea(areaId, entryEdge, false);
  }

  private navigateToArea(areaId: AreaId, entryEdge?: Direction, respawnHome = false): void {
    try {
      sessionStorage.setItem(AREA_TRANSITION_HANDOFF_KEY, JSON.stringify({
        gameState: gameState.serialize(),
        inventory: playerInventory.serialize(),
        respawnHome,
      }));
    } catch {
      // If storage is unavailable, still transition; the area must not freeze.
    }

    const nextUrl = new URL(window.location.href);
    nextUrl.searchParams.set('area', areaId);
    if (entryEdge) {
      nextUrl.searchParams.set('entry', entryEdge);
    } else {
      nextUrl.searchParams.delete('entry');
    }
    if (respawnHome) {
      nextUrl.searchParams.set('respawn', 'home');
    } else {
      nextUrl.searchParams.delete('respawn');
    }
    nextUrl.searchParams.set('t', `${Date.now()}`);
    window.location.assign(nextUrl.toString());
  }

  private isDirection(value: string): value is Direction {
    return value === 'north' || value === 'east' || value === 'south' || value === 'west';
  }

  private buildWorld(): void {
    this.terrainGrid = [];

    for (let tileY = 0; tileY < WORLD_TILES_Y; tileY += 1) {
      const row: WorldTileId[] = [];

      for (let tileX = 0; tileX < WORLD_TILES_X; tileX += 1) {
        const worldX = tileX * TILE_SIZE;
        const worldY = tileY * TILE_SIZE;
        const tileId = resolveWorldTile(tileX, tileY, this.currentArea.biome, this.currentArea.seed);
        const tileRule = WORLD_TILE_RULES[tileId];
        const resourceNoise = biomeSample(tileX, tileY, this.currentArea.seed);

        row.push(tileId);
        this.createWorldTile(tileId, tileX, tileY, worldX, worldY);

        if (
          this.currentArea.biome === 'meadow'
          && tileRule.allowsDecorations
          && resourceNoise > 0.45
          && biomeSample(tileX + 5, tileY + 3, this.currentArea.seed) > 0.86
        ) {
          const px = worldX + Phaser.Math.Between(20, 44);
          const py = worldY + Phaser.Math.Between(20, 44);
          this.spawnPurple(px, py);
        }
      }

      this.terrainGrid.push(row);
    }

    this.physics.world.setBounds(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
  }

  private createCollisionLayer(): void {
    this.collisionTiles = this.physics.add.staticGroup();
    this.purpleFoods = this.physics.add.staticGroup();
    this.grapeChips = this.physics.add.staticGroup();
    this.dungeonSwitches = this.physics.add.staticGroup();
    this.dungeonChests = this.physics.add.staticGroup();
  }

  private createSlimeAnimations(): void {
    for (const clip of SLIME_ANIMS) {
      this.makeAnimation(clip.key, clip.frames, clip.frameRate, clip.repeat);
    }
  }

  private createPlayer(): void {
    const spawnPoint = this.findSpawnPoint(this.getEntryAnchor());

    this.player = this.physics.add.sprite(spawnPoint.x, spawnPoint.y, 'slime', 0);
    this.player.setScale(0.28);
    this.player.setCollideWorldBounds(true);
    this.player.setDepth(10);
    this.player.setSize(108, 80);
    this.player.setOffset(74, 140);
    this.playAnimation('slime-idle');

    this.playerNameTag = this.add
      .text(this.player.x, this.player.y - 56, 'bob', {
        fontFamily: 'Aptos, Segoe UI Variable, sans-serif',
        fontSize: '14px',
        color: '#ffffff',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setOrigin(0.5)
      .setDepth(11);
  }

  private createPhysics(): void {
    this.physics.add.collider(this.player, this.collisionTiles);
    if (this.friends) {
      this.physics.add.collider(this.friends, this.collisionTiles);
      this.physics.add.collider(this.friends, this.friends as Phaser.Physics.Arcade.Group);
    }
    if (this.purpleFoods) {
      this.physics.add.overlap(this.player, this.purpleFoods, this.collectPurple, undefined, this);
    }
    if (this.grapeChips) {
      this.physics.add.overlap(this.player, this.grapeChips, this.collectGrapeChips, undefined, this);
    }
    if (this.dungeonSwitches) {
      this.physics.add.overlap(this.player, this.dungeonSwitches, this.activateDungeonSwitch, undefined, this);
    }
    if (this.dungeonChests) {
      this.physics.add.overlap(this.player, this.dungeonChests, this.tryOpenDungeonChest, undefined, this);
    }

    for (const entry of this.houses) {
      const zone = entry.house.doorZone;
      if (zone) {
        this.physics.add.overlap(this.player, zone, () => {
          this.houseSystem.notifyNear(entry.house);
        }, undefined, this);
      }
    }

    this.createAreaTransitionZones();
  }

  private createAreaTransitionZones(): void {
    const zones: Array<{ direction: Direction; x: number; y: number; width: number; height: number }> = [
      { direction: 'west', x: EDGE_TRANSITION_SIZE / 2, y: WORLD_HEIGHT / 2, width: EDGE_TRANSITION_SIZE, height: WORLD_HEIGHT },
      { direction: 'east', x: WORLD_WIDTH - EDGE_TRANSITION_SIZE / 2, y: WORLD_HEIGHT / 2, width: EDGE_TRANSITION_SIZE, height: WORLD_HEIGHT },
      { direction: 'north', x: WORLD_WIDTH / 2, y: EDGE_TRANSITION_SIZE / 2, width: WORLD_WIDTH, height: EDGE_TRANSITION_SIZE },
      { direction: 'south', x: WORLD_WIDTH / 2, y: WORLD_HEIGHT - EDGE_TRANSITION_SIZE / 2, width: WORLD_WIDTH, height: EDGE_TRANSITION_SIZE },
    ];

    for (const z of zones) {
      const nextAreaId = this.currentArea.neighbors[z.direction];
      if (!nextAreaId) continue;

      const zone = this.add.zone(z.x, z.y, z.width, z.height).setOrigin(0.5);
      this.physics.add.existing(zone, true);
      this.transitionZones.push(zone);
      this.physics.add.overlap(this.player, zone, () => {
        if (this.transitioning || this.time.now < this.transitionReadyAt) return;
        this.transitionTo(nextAreaId, oppositeDirection(z.direction));
      });
    }
  }

  private placeHouses(playerCount = 1, friendCount = 3): void {
    const candidates: { x: number; y: number }[] = [];

    for (let tileY = 0; tileY < WORLD_TILES_Y; tileY += 1) {
      for (let tileX = 0; tileX < WORLD_TILES_X; tileX += 1) {
        const tileId = this.terrainGrid[tileY]?.[tileX];
        if (!tileId) continue;

        const rule = WORLD_TILE_RULES[tileId];
        if (rule.allowsDecorations && !isTileCollidable(tileId)) {
          candidates.push({ x: tileX * TILE_SIZE + TILE_SIZE / 2, y: tileY * TILE_SIZE + TILE_SIZE / 2 });
        }
      }
    }

    if (candidates.length > 0) {
      let bestIdx = -1;
      let bestDist = Infinity;

      for (let i = 0; i < candidates.length; i += 1) {
        const dx = candidates[i].x - WORLD_WIDTH / 2;
        const dy = candidates[i].y - WORLD_HEIGHT / 2;
        const d = dx * dx + dy * dy;
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }

      if (bestIdx > 0) {
        const chosen = candidates.splice(bestIdx, 1)[0];
        candidates.unshift(chosen);
      }
    }

    const playerHouseCandidate = candidates.shift();
    Phaser.Utils.Array.Shuffle(candidates);

    if (playerHouseCandidate) {
      candidates.unshift(playerHouseCandidate);
    }

    let idx = 0;

    for (let i = 0; i < playerCount && idx < candidates.length; i += 1, idx += 1) {
      const pos = candidates[idx];
      let h: House;

      if (i === 0) {
        h = new House(this, pos.x, pos.y, 'big-blue-house', 'bed');
        this.playerHouse = h;
        const door = h.getDoorPosition();
        if (this.player && (!this.entryEdge || this.respawnHomeOnLoad)) {
          this.player.setPosition(door.x, door.y + 18);
        }
      } else {
        h = new House(this, pos.x, pos.y);
      }

      this.houses.push({ owner: 'player', house: h });
      this.collisionTiles.add(h.sprite);
    }

    const friendHouses: House[] = [];

    for (let i = 0; i < friendCount && idx < candidates.length; i += 1, idx += 1) {
      const pos = candidates[idx];
      const h = new House(this, pos.x, pos.y);
      this.houses.push({ owner: 'friend', house: h });
      this.collisionTiles.add(h.sprite);
      friendHouses.push(h);
    }

    if (this.friends) {
      const fl = this.friends.getChildren() as Friend[];

      for (let i = 0; i < friendHouses.length && i < fl.length; i += 1) {
        const friend = fl[i];
        friend.home = friendHouses[i];
        const door = friend.home.getDoorPosition();
        friend.setPosition(door.x, door.y + 18);
      }

    }
  }

  private spawnPurple(x: number, y: number): void {
    if (!this.purpleFoods) return;

    const p = this.purpleFoods.create(x, y, 'purple-berry') as Phaser.Physics.Arcade.Image;
    p.setDepth(3);
    p.setOrigin(0.5, 0.5);
  }

  private collectPurple(_playerObj: any, purpleObj: any): void {
    const p = purpleObj as Phaser.Physics.Arcade.Image | null;
    if (!p || !p.active) return;

    this.playActionAnimation('slime-eat');

    p.destroy();

    gameState.addCoins(5);
    playerInventory.add('purple-berry-mat', 1);
    gameEvents.emit('player.collect', { kind: 'berry', value: 5 });
    this.hud.flashCoins(this);
  }

  private spawnGrapeChips(x: number, y: number): void {
    if (!this.grapeChips) return;

    const p = this.grapeChips.create(x, y, 'grape-chip') as Phaser.Physics.Arcade.Image;
    p.setDepth(3);
    p.setOrigin(0.5, 0.5);
    p.setRotation(Phaser.Math.FloatBetween(0, Math.PI * 2));
  }

  private collectGrapeChips(_playerObj: any, chipObj: any): void {
    const p = chipObj as Phaser.Physics.Arcade.Image | null;
    if (!p || !p.active) return;

    this.playActionAnimation('slime-eat');

    p.destroy();

    gameState.addCoins(12);
    gameEvents.emit('player.collect', { kind: 'chip', value: 12 });
    this.hud.flashCoins(this);
  }

  private createCrystalTrial(): void {
    if (this.currentArea.id !== 'crystal-caverns' || !this.dungeonSwitches || !this.dungeonChests) return;

    const completed = this.isDungeonCompleted(CRYSTAL_TRIAL_ID);
    this.dungeonChestOpened = completed;
    this.dungeonSwitchStates = [completed, completed];

    const center = this.findSpawnPoint(new Phaser.Math.Vector2(WORLD_WIDTH * 0.58, WORLD_HEIGHT * 0.48));
    const chestPos = this.findSpawnPoint(new Phaser.Math.Vector2(center.x, center.y - 130));
    const switchPositions = [
      this.findSpawnPoint(new Phaser.Math.Vector2(center.x - 170, center.y + 95)),
      this.findSpawnPoint(new Phaser.Math.Vector2(center.x + 170, center.y + 95)),
    ];

    const ring = this.add.graphics().setDepth(1.5);
    ring.lineStyle(3, 0x9cf0ff, 0.38);
    ring.strokeEllipse(center.x, center.y + 12, 520, 330);
    ring.lineStyle(1, 0x496d89, 0.5);
    ring.strokeEllipse(center.x, center.y + 12, 410, 250);

    this.add
      .text(center.x, center.y - 205, completed ? 'Crystal Trial Cleared' : 'Crystal Trial: wake both switches', {
        fontFamily: 'Aptos, Segoe UI Variable, sans-serif',
        fontSize: '18px',
        color: '#d8fbff',
        stroke: '#102033',
        strokeThickness: 4,
      })
      .setOrigin(0.5)
      .setDepth(6);

    switchPositions.forEach((pos, index) => {
      const switchSprite = this.dungeonSwitches!.create(
        pos.x,
        pos.y,
        completed ? 'crystal-switch-on' : 'crystal-switch-off',
      ) as Phaser.Physics.Arcade.Image;
      switchSprite.setDepth(4);
      switchSprite.setData('switchIndex', index);
      switchSprite.refreshBody();
    });

    const chest = this.dungeonChests.create(
      chestPos.x,
      chestPos.y,
      completed ? 'crystal-chest-open' : 'crystal-chest-closed',
    ) as Phaser.Physics.Arcade.Image;
    chest.setDepth(4);
    chest.refreshBody();
  }

  private activateDungeonSwitch(_playerObj: any, switchObj: any): void {
    if (this.currentArea.id !== 'crystal-caverns' || this.dungeonChestOpened) return;

    const switchSprite = switchObj as Phaser.Physics.Arcade.Image | null;
    const index = switchSprite?.getData('switchIndex') as number | undefined;
    if (!switchSprite || index === undefined || this.dungeonSwitchStates[index]) return;

    this.dungeonSwitchStates[index] = true;
    switchSprite.setTexture('crystal-switch-on');
    switchSprite.setTint(0xc9fbff);
    this.tweens.add({ targets: switchSprite, scale: 1.18, duration: 120, yoyo: true, onComplete: () => switchSprite.clearTint() });
    floatingText.spawn(this, switchSprite.x, switchSprite.y - 30, 'switch lit', 'cyan');

    if (this.dungeonSwitchStates.every(Boolean)) {
      const chest = this.dungeonChests?.getChildren()[0] as Phaser.Physics.Arcade.Image | undefined;
      if (chest) {
        this.tweens.add({ targets: chest, scale: 1.12, duration: 160, yoyo: true, repeat: 2 });
        floatingText.spawn(this, chest.x, chest.y - 42, 'CHEST UNSEALED', 'yellow', true);
      }
    }
  }

  private tryOpenDungeonChest(_playerObj: any, chestObj: any): void {
    if (this.currentArea.id !== 'crystal-caverns' || this.dungeonChestOpened) return;

    const chest = chestObj as Phaser.Physics.Arcade.Image | null;
    if (!chest) return;

    if (!this.dungeonSwitchStates.every(Boolean)) {
      if (this.time.now >= this.dungeonHintReadyAt) {
        this.dungeonHintReadyAt = this.time.now + 1400;
        floatingText.spawn(this, chest.x, chest.y - 42, 'Find both switches', 'cyan');
      }
      return;
    }

    this.dungeonChestOpened = true;
    this.markDungeonCompleted(CRYSTAL_TRIAL_ID);
    chest.setTexture('crystal-chest-open');
    this.cameras.main.shake(220, 0.006);

    gameState.addCoins(90);
    gameState.addXp(120);
    playerInventory.add('shard', 4);
    playerInventory.add('hp-potion', 1);
    this.hud.flashCoins(this);
    floatingText.spawn(this, chest.x, chest.y - 62, 'Crystal Cache Opened!', 'yellow', true);
    floatingText.spawn(this, chest.x, chest.y - 38, '+90c  +120 XP  +4 shards  +tonic', 'green', true);
  }

  private createMinimap(): void {
    this.minimap = new Minimap(this);
  }

  private createHUD(): void {
    this.hud = new HUD(this);
  }

  private createChatUI(): void {
    this.chatUI = new ChatUI(
      this,
      () => this.friends.getChildren() as Friend[],
      () => this.playerNameTag?.text ?? 'you',
      (open) => {
        this.actionLocked = open;
        if (open) {
          (this.player?.body as Phaser.Physics.Arcade.Body | undefined)?.setVelocity(0, 0);
        }
      },
    );
  }

  private createCamera(): void {
    this.physics.world.resume();
    this.cameras.main.resetFX();
    this.cameras.main.setBounds(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
    this.cameras.main.startFollow(this.player, true, 0.08, 0.08);
    this.cameras.main.setZoom(DEFAULT_ZOOM);
    this.cameras.main.setRoundPixels(true);
  }

  private createControls(): void {
    this.inputBindings = createControls(this, () => {
      this.playActionAnimation('slime-eat');
    });
    this.controls = this.inputBindings.controls;
  }

  private createOverlay(): void {
    const font = 'Aptos, Segoe UI Variable, sans-serif';
    const cam = this.cameras.main;
    const centerX = cam.width / 2;

    // Objective banner only. Full controls live in the HTML controls panel
    // (see config.ts) so they aren't duplicated on the canvas.
    this.add
      .text(centerX, 24, `Explore ${this.currentArea.name}`, {
        fontFamily: font,
        fontSize: '24px',
        color: '#f2ffef',
        stroke: '#163033',
        strokeThickness: 5,
      })
      .setOrigin(0.5, 0)
      .setScrollFactor(0)
      .setDepth(50);

    // Dev-only debug hint (kept small + dim; not gameplay controls).
    this.add
      .text(24, cam.height - 24, 'Debug: 1 dmg  2 xp  3 heal  4 coins  5 potion  6 burn  7 slow  8 dummy', {
        fontFamily: font,
        fontSize: '12px',
        color: '#6a8a78',
        stroke: '#163033',
        strokeThickness: 3,
      })
      .setOrigin(0, 1)
      .setScrollFactor(0)
      .setDepth(50);
  }

  private createWorldTile(tileId: WorldTileId, tileX: number, tileY: number, worldX: number, worldY: number): void {
    const textureKey = resolveWorldTileTexture(tileId, tileX, tileY, this.currentArea.seed);
    const bodyBounds = getTileBodyBounds(tileId, TILE_SIZE);

    if (!bodyBounds) {
      this.add.image(worldX, worldY, textureKey).setOrigin(0);
      return;
    }

    const tile = this.collisionTiles.create(worldX + TILE_SIZE / 2, worldY + TILE_SIZE / 2, textureKey) as Phaser.Physics.Arcade.Image;
    const body = tile.body as Phaser.Physics.Arcade.StaticBody;

    tile.setDepth(1);
    body.setSize(bodyBounds.width, bodyBounds.height);
    body.setOffset(bodyBounds.offsetX, bodyBounds.offsetY);
    tile.refreshBody();
  }

  private getEntryAnchor(): Phaser.Math.Vector2 | undefined {
    if (!this.entryEdge) return undefined;

    const centerX = Math.floor(WORLD_TILES_X / 2) * TILE_SIZE + TILE_SIZE / 2;
    const centerY = Math.floor(WORLD_TILES_Y / 2) * TILE_SIZE + TILE_SIZE / 2;
    const inset = TILE_SIZE * 4;

    switch (this.entryEdge) {
      case 'west': return new Phaser.Math.Vector2(inset, centerY);
      case 'east': return new Phaser.Math.Vector2(WORLD_WIDTH - inset, centerY);
      case 'north': return new Phaser.Math.Vector2(centerX, inset);
      case 'south': return new Phaser.Math.Vector2(centerX, WORLD_HEIGHT - inset);
    }
  }

  private findSpawnPoint(anchor?: Phaser.Math.Vector2): Phaser.Math.Vector2 {
    const startX = Math.floor((anchor?.x ?? WORLD_WIDTH / 2) / TILE_SIZE);
    const startY = Math.floor((anchor?.y ?? WORLD_HEIGHT / 2) / TILE_SIZE);
    const maxRadius = Math.max(WORLD_TILES_X, WORLD_TILES_Y);

    for (let radius = 0; radius < maxRadius; radius += 1) {
      for (let tileY = startY - radius; tileY <= startY + radius; tileY += 1) {
        for (let tileX = startX - radius; tileX <= startX + radius; tileX += 1) {
          if (!this.isWithinWorld(tileX, tileY) || this.isSolidTile(tileX, tileY)) {
            continue;
          }

          return new Phaser.Math.Vector2(
            tileX * TILE_SIZE + TILE_SIZE / 2,
            tileY * TILE_SIZE + TILE_SIZE / 2,
          );
        }
      }
    }

    return new Phaser.Math.Vector2(WORLD_WIDTH / 2, WORLD_HEIGHT / 2);
  }

  private isWithinWorld(tileX: number, tileY: number): boolean {
    return tileX >= 0 && tileX < WORLD_TILES_X && tileY >= 0 && tileY < WORLD_TILES_Y;
  }

  private isSolidTile(tileX: number, tileY: number): boolean {
    const tileId = this.terrainGrid[tileY]?.[tileX];
    return tileId ? isTileCollidable(tileId) : false;
  }

  private playAnimation(key: string): void {
    if (this.currentAnimation === key) {
      return;
    }

    this.currentAnimation = key;
    this.player.play(key, true);
  }

  private handleActionInput(direction: Phaser.Math.Vector2): boolean {
    if (Phaser.Input.Keyboard.JustDown(this.controls.interact)) {
      if (this.houseSystem.handleInteract()) {
        return true;
      }

      this.tryOpenShopNearby();
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.jump)) {
      this.abilitySystem?.tryJump(direction);
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.boost)) {
      this.tryDodge(direction);
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.trick)) {
      // Aim toward current movement direction if moving, else use facing.
      const moveDir = this.readDirection();
      this.tryAttack(moveDir.lengthSq() > 0 ? moveDir : undefined);
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.stretch)) {
      this.abilitySystem?.tryStretchLash();
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.squash)) {
      this.abilitySystem?.trySquashSlam();
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.teleport)) {
      this.abilitySystem?.tryTeleport(direction);
      return true;
    }

    return false;
  }

  private playActionAnimation(key: string): void {
    const clip = SLIME_ANIM_MAP[key];
    if (!clip) return;

    this.actionLocked = true;
    this.currentAnimation = key;
    this.player.setVelocity(0, 0);
    this.player.rotation = 0;
    this.player.play(key, true);

    const unlock = () => {
      this.actionLocked = false;
      this.currentAnimation = '';
      this.player.play('slime-idle', true);
    };

    if (clip.repeat === 0) {
      this.player.once(Phaser.Animations.Events.ANIMATION_COMPLETE_KEY + key, unlock);
      return;
    }

    const durationMs = Math.max(1, Math.round((clip.frames.length / clip.frameRate) * 1000));
    this.time.delayedCall(durationMs, unlock);
  }

  private createFriends(count = 3): void {
    this.friends = this.physics.add.group();

    for (let i = 0; i < count; i += 1) {
      this.spawnFriend();
    }
  }

  private spawnFriend(): Friend {
    const pos = this.findSpawnPoint();
    const friend = new Friend(this, pos.x, pos.y);
    this.friends.add(friend);
    return friend;
  }

  private tryOpenShopNearby(): void {
    if (!this.friends) return;

    const children = this.friends.getChildren() as Friend[];
    const near = children.find((f) => Phaser.Math.Distance.Between(this.player.x, this.player.y, f.x, f.y) < 80);

    if (near) {
      this.openShopForFriend(near);
      return;
    }

    this.hud.flashCoins(this);
  }

  private openShopForFriend(friend: Friend): void {
    this.shopTarget = friend;
    this.shopUI.show(gameState.coins);
  }

  private createShopUI(): void {
    // Bottom-left, away from the top-right controls panel and bottom-center
    // ability bar. The shop container is centered at (x,y) with width 280.
    const x = 160;
    const y = this.cameras.main.height - 210;

    this.shopUI = new ShopUI(
      this,
      x,
      y,
      {
        onBuyBoost: () => {
          if (gameState.spendCoins(25)) {
            gameState.addBoost(50);
          }
        },
        onBuyFriend: () => {
          if (gameState.spendCoins(15)) {
            this.spawnFriend();
            gameState.setTotalFriends(this.friends.getLength());
          }
        },
        onCoinsChanged: () => {
          // HUD is event-driven via GameState; kept for interface compatibility.
        },
      },
    );
  }

  private handleResize(gameSize: Phaser.Structs.Size): void {
    this.cameras.main.setViewport(0, 0, gameSize.width, gameSize.height);

    if (this.shopUI) {
      this.shopUI.setPosition(160, gameSize.height - 210);
    }
  }

  // ── Phase 1: health / damage / death / XP / items ──

  private onPlayerHit(): void {
    this.healthBar?.flash();
    floatingText.spawn(this, this.player.x, this.player.y - 30, `-${gameState.hp}`, 'red', true);
    // Red flash tween on the sprite.
    if (!this.iFrameFlashActive) {
      this.iFrameFlashActive = true;
      this.player.setTintFill(0xff5a5a);
      this.time.delayedCall(120, () => {
        this.player.clearTint();
        this.iFrameFlashActive = false;
      });
    }
  }

  private onPlayerDeath(): void {
    this.playAnimation('slime-idle');
    this.player.setVelocity(0, 0);
    this.player.rotation = 0;
    this.cameras.main.shake(400, 0.012);
    floatingText.spawn(this, this.player.x, this.player.y - 40, 'DEFEATED', 'red', true);

    // Respawn at last bed after a short delay.
    this.time.delayedCall(1400, () => this.respawnPlayer());
  }

  private respawnPlayer(): void {
    if (!this.healthSystem) return;

    if (this.currentArea.id !== 'meadow-crossing') {
      gameState.revive();
      this.statusEffects?.clear();
      this.navigateToArea('meadow-crossing', undefined, true);
      return;
    }

    const pos = this.lastBedPos ?? this.getPlayerHouseRespawnPoint() ?? this.findSpawnPoint();

    this.healthSystem.respawn();
    this.statusEffects?.clear();
    this.player.setPosition(pos.x, pos.y);
    this.player.clearTint();
    this.player.setAlpha(1);

    this.cameras.main.pan(pos.x, pos.y, 350, 'Power2');
    this.cameras.main.zoomTo(DEFAULT_ZOOM, 350);
    this.cameras.main.startFollow(this.player, true, 0.08, 0.08);

    floatingText.spawn(this, pos.x, pos.y - 40, 'Respawned', 'green', true);
  }

  private getPlayerHouseRespawnPoint(): Phaser.Math.Vector2 | null {
    if (!this.playerHouse) return null;
    const bed = this.playerHouse.getBedPosition();
    if (bed) return new Phaser.Math.Vector2(bed.x, bed.y - 8);
    const door = this.playerHouse.getDoorPosition();
    return new Phaser.Math.Vector2(door.x, door.y + 18);
  }

  private useItem(itemId: string): void {
    const def = itemRegistry.get(itemId);
    if (!def?.use) return;
    if (playerInventory.count(itemId) <= 0) return;

    if (def.use.healHp) {
      const healed = this.healthSystem?.heal(def.use.healHp) ?? 0;
      if (healed > 0) {
        floatingText.spawn(this, this.player.x, this.player.y - 30, `+${healed}`, 'green', true);
      }
    }
    if (def.use.healEnergy) {
      gameState.regenEnergy(def.use.healEnergy);
    }
    if (def.use.cureStatus) {
      for (const s of def.use.cureStatus) this.statusEffects?.remove(s);
    }

    playerInventory.remove(itemId, 1);
  }

  private spawnItemDropIcon(x: number, y: number, itemId: string, count: number, index: number, total: number): void {
    const item = itemRegistry.get(itemId);
    const texture = item?.icon;
    const label = item?.name ?? itemId;
    const offsetX = (index - (total - 1) / 2) * 30;

    if (texture && this.textures.exists(texture)) {
      const icon = this.add.image(x, y, texture).setDepth(24).setScale(1.35).setAlpha(0);
      this.tweens.add({
        targets: icon,
        x: x + offsetX,
        y: y - 34,
        alpha: { from: 0, to: 1 },
        scale: { from: 0.8, to: 1.55 },
        duration: 180,
        ease: 'Back.Out',
        onComplete: () => {
          this.tweens.add({
            targets: icon,
            y: y - 54,
            alpha: 0,
            duration: 650,
            ease: 'Sine.In',
            onComplete: () => icon.destroy(),
          });
        },
      });
    }

    floatingText.spawn(this, x + offsetX, y - 64, `+${count} ${label}`, 'green');
  }

  private bindHotkeys(): void {
    const kb = this.input.keyboard;
    if (!kb) return;

    // Tab = toggle inventory. Bind via keydown-TAB so we can preventDefault
    // before the browser moves focus.
    kb.on('keydown-TAB', (event: KeyboardEvent) => {
      event.preventDefault();
      if (this.levelUpModal?.isOpen()) return;
      this.inventoryUI?.toggle();
    });

    kb.on('keydown-M', () => {
      if (this.levelUpModal?.isOpen() || this.inventoryUI?.isOpen() || this.questJournal?.isOpen() || this.craftingUI?.isOpen()) return;
      this.worldMapUI?.toggle();
    });

    kb.on('keydown-U', () => {
      if (this.levelUpModal?.isOpen() || this.inventoryUI?.isOpen() || this.worldMapUI?.isOpen() || this.craftingUI?.isOpen()) return;
      this.questJournal?.toggle();
    });

    kb.on('keydown-C', () => {
      if (this.levelUpModal?.isOpen() || this.inventoryUI?.isOpen() || this.worldMapUI?.isOpen() || this.questJournal?.isOpen()) return;
      this.craftingUI?.toggle();
    });

    // Left-click = attack toward mouse pointer.
    this.input.on('pointerdown', (pointer: Phaser.Input.Pointer) => {
      if (pointer.leftButtonDown()) {
        const worldPoint = this.cameras.main.getWorldPoint(pointer.x, pointer.y);
        const aim = new Phaser.Math.Vector2(worldPoint.x - this.player.x, worldPoint.y - this.player.y);
        this.tryAttack(aim);
      }
    });
  }

  // ── Phase 2: combat ──

  private createCombatSystem(): void {
    // Combat targets group (enemies + dummies).
    this.combatTargets = this.physics.add.group();

    // Combo counter text (screen-space, above ability bar).
    this.comboText = this.add
      .text(this.cameras.main.width / 2, this.cameras.main.height - 130, '', {
        fontFamily: 'Aptos, Segoe UI Variable, sans-serif',
        fontSize: '20px',
        color: '#ffe680',
        stroke: '#0a1f15',
        strokeThickness: 4,
      })
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setDepth(55)
      .setAlpha(0);

    // Combo system with visual feedback.
    this.comboSystem = new ComboSystem(this, {
      onComboHit: (combo, mult) => {
        if (!this.comboText) return;
        this.comboText.setText(`${combo}x COMBO  ×${mult.toFixed(2)}`);
        this.comboText.setAlpha(1);
        this.tweens.add({
          targets: this.comboText,
          scale: { from: 1.2, to: 1 },
          duration: 150,
          ease: 'Back.Out',
        });
      },
      onComboReset: () => {
        if (this.comboText) this.comboText.setAlpha(0);
      },
      onComboFinish: (combo) => {
        floatingText.spawn(this, this.player.x, this.player.y - 60, `${combo}x FINISHER!`, 'yellow', true);
        this.cameras.main.shake(120, 0.008);
      },
    });

    // Starter weapon: Goo Gauntlet.
    this.weapon = createGooGauntlet({
      scene: this,
      getPlayer: () => this.player,
      getFacing: () => this.facing,
      getTargets: () => this.combatTargets,
      hitHandler: (target: Phaser.GameObjects.GameObject, damage: number, kx: number, ky: number, kStrength: number) => {
        const comboMult = this.comboSystem?.registerHit() ?? 1;
        const finalDmg = Math.round(damage * comboMult);
        if (target instanceof Enemy) {
          const hpBefore = target.hp;
          target.takeDamage(finalDmg, kx, ky, kStrength);
          this.applyLifeSteal(Math.max(0, hpBefore - target.hp));
        } else if (target instanceof TargetDummy) {
          target.takeDamage(finalDmg, kx, ky, kStrength);
        }
      },
      onAttackStart: () => {
        this.attacking = true;
        this.player.setVelocity(0, 0);
      },
      onAttackEnd: () => {
        this.attacking = false;
      },
      playAnimation: (key: string) => this.playAnimation(key),
    });

    // Enemy spawner.
    this.enemySpawner = new EnemySpawner({
      scene: this,
      getPlayer: () => this.player,
      maxPopulation: 16,
      spawnRadius: 500,
      despawnRadius: 800,
      minSpawnDistance: 200,
      spawnTable: SPAWN_TABLE_MEDIUM,
      worldWidth: WORLD_WIDTH,
      worldHeight: WORLD_HEIGHT,
      targetGroup: this.combatTargets,
      getSafeZones: () => this.getEnemySafeZones(),
      enemyContext: {
        getPlayer: () => this.player,
        onContactDamage: (_enemy, amount) => this.onEnemyContactDamage(amount),
        onDeath: (enemy) => this.onEnemyDeath(enemy),
        getSafeZones: () => this.getEnemySafeZones(),
        fireProjectile: (x, y, dx, dy, speed) => {
          projectilePool.fire(this, x, y, dx, dy, speed, 'enemy-projectile', 'enemy', 12);
        },
      },
    });

    // Seed initial enemies.
    this.enemySpawner.seed(8);
    this.spawnBlobfatherIfNeeded();

    // Spawn a couple of dummies near the player for practice.
    const px = this.player.x;
    const py = this.player.y;
    this.spawnDummy(px + 80, py + 20);

    // Collide combat targets with world + player so enemies can't pass through.
    if (this.combatTargets && this.collisionTiles) {
      this.physics.add.collider(this.combatTargets, this.collisionTiles);
    }
    if (this.combatTargets && this.player) {
      this.physics.add.collider(this.player, this.combatTargets);
    }

    // Enemy projectiles vs player.
    const enemyProjs = projectilePool.enemyGroup(this);
    this.physics.add.overlap(this.player, enemyProjs, (_p, proj) => {
      const sprite = proj as Phaser.Physics.Arcade.Image;
      const damage = 12;
      if (!this.isDodging()) {
        this.healthSystem?.applyDamage({ amount: damage, source: 'projectile' }, this.time.now);
      }
      floatingText.spawn(this, sprite.x, sprite.y - 10, 'hit', 'orange');
      sprite.setActive(false).setVisible(false).setVelocity(0, 0);
    });
  }

  private spawnBlobfatherIfNeeded(): void {
    if (!this.combatTargets) return;
    if (this.currentArea.id !== BLOBFATHER.areaId) return;
    if (this.isBossDefeated(BLOBFATHER.id)) return;

    const pos = this.findSpawnPoint(new Phaser.Math.Vector2(WORLD_WIDTH * 0.68, WORLD_HEIGHT * 0.5));
    const boss = new Enemy(this, pos.x, pos.y, BLOBFATHER.config, {
      getPlayer: () => this.player,
      onContactDamage: (_enemy, amount) => this.onEnemyContactDamage(amount),
      onDeath: (enemy) => this.onEnemyDeath(enemy),
      getSafeZones: () => this.getEnemySafeZones(),
    });

    this.combatTargets.add(boss);
    this.activeBoss = boss;
    this.bossHealthBar = new BossHealthBar(this, boss, BLOBFATHER.name);
    this.showBossIntro(BLOBFATHER.name);
  }

  private showBossIntro(name: string): void {
    this.cameras.main.shake(450, 0.01);
    const card = this.add.container(this.cameras.main.width / 2, 116).setScrollFactor(0).setDepth(240).setAlpha(0);
    const bg = this.add.graphics();
    bg.fillStyle(0x1f0808, 0.92);
    bg.fillRoundedRect(-210, -28, 420, 56, 14);
    bg.lineStyle(2, 0xff5a5a, 0.9);
    bg.strokeRoundedRect(-210, -28, 420, 56, 14);
    card.add(bg);
    card.add(this.add.text(0, 0, name, {
      fontFamily: 'Aptos, Segoe UI Variable, sans-serif',
      fontSize: '26px',
      color: '#ffe0d0',
      stroke: '#0a0505',
      strokeThickness: 6,
    }).setOrigin(0.5));
    this.tweens.add({ targets: card, alpha: 1, y: 132, duration: 280, yoyo: true, hold: 1200, onComplete: () => card.destroy() });
  }

  private getEnemySafeZones(): Array<{ x: number; y: number; radius: number }> {
    if (!this.playerHouse) return [];
    return [{ x: this.playerHouse.sprite.x, y: this.playerHouse.sprite.y, radius: PLAYER_HOUSE_SAFE_RADIUS }];
  }

  private isBossDefeated(bossId: string): boolean {
    try {
      const raw = localStorage.getItem(BOSS_DEFEATED_KEY);
      const defeated = raw ? JSON.parse(raw) as string[] : [];
      return defeated.includes(bossId);
    } catch {
      return false;
    }
  }

  private markBossDefeated(bossId: string): void {
    try {
      const raw = localStorage.getItem(BOSS_DEFEATED_KEY);
      const defeated = new Set(raw ? JSON.parse(raw) as string[] : []);
      defeated.add(bossId);
      localStorage.setItem(BOSS_DEFEATED_KEY, JSON.stringify([...defeated]));
    } catch {
      // Persistent defeat state is best-effort for now.
    }
  }

  private isDungeonCompleted(dungeonId: string): boolean {
    try {
      const raw = localStorage.getItem(DUNGEON_COMPLETED_KEY);
      const completed = raw ? JSON.parse(raw) as string[] : [];
      return completed.includes(dungeonId);
    } catch {
      return false;
    }
  }

  private markDungeonCompleted(dungeonId: string): void {
    try {
      const raw = localStorage.getItem(DUNGEON_COMPLETED_KEY);
      const completed = new Set(raw ? JSON.parse(raw) as string[] : []);
      completed.add(dungeonId);
      localStorage.setItem(DUNGEON_COMPLETED_KEY, JSON.stringify([...completed]));
    } catch {
      // Trial rewards should still work if persistent storage is unavailable.
    }
  }

  private applyLifeSteal(damageDealt: number): void {
    if (damageDealt <= 0 || !this.healthSystem) return;

    const stats = getStats();
    if (stats.lifeStealPct <= 0) return;

    const healed = this.healthSystem.heal(Math.ceil(damageDealt * stats.lifeStealPct));
    if (healed > 0) {
      floatingText.spawn(this, this.player.x, this.player.y - 36, `+${healed}`, 'green');
    }
  }

  private onEnemyContactDamage(amount: number): void {
    if (this.isDodging()) return;
    this.healthSystem?.applyDamage({ amount, source: 'enemy' }, this.time.now);
  }

  private onEnemyDeath(enemy: Enemy): void {
    // XP and coins are awarded immediately; item drops get distinct icon pops.
    const drop = enemy.config.drop;
    gameEvents.emit('enemy.died', { enemyId: enemy.enemyId, areaId: this.currentArea.id, kind: enemy.config.textureKey });

    if (enemy === this.activeBoss) {
      this.markBossDefeated(BLOBFATHER.id);
      this.bossHealthBar?.defeat();
      this.bossHealthBar = undefined;
      this.activeBoss = undefined;
      gameState.addCoins(BLOBFATHER.reward.coins);
      gameState.addXp(BLOBFATHER.reward.xp);
      this.cameras.main.shake(700, 0.018);
      floatingText.spawn(this, enemy.x, enemy.y - 70, `${BLOBFATHER.name} DEFEATED!`, 'yellow', true);
      floatingText.spawn(this, enemy.x, enemy.y - 46, `+${BLOBFATHER.reward.coins}c  +${BLOBFATHER.reward.xp} XP`, 'green', true);
    }

    if (drop.xp > 0) {
      gameState.addXp(drop.xp);
      floatingText.spawn(this, enemy.x, enemy.y - 36, `+${drop.xp} XP`, 'cyan');
    }

    if (drop.coins > 0) {
      gameState.addCoins(drop.coins);
      floatingText.spawn(this, enemy.x, enemy.y - 20, `+${drop.coins}c`, 'yellow');
    }

    const itemDrops = (drop.items ?? []).filter((itemDrop) => Math.random() < itemDrop.chance);
    for (let i = 0; i < itemDrops.length; i += 1) {
      const itemDrop = itemDrops[i];
      const count = itemDrop.count ?? 1;
      const added = playerInventory.add(itemDrop.itemId, count);
      if (added > 0) {
        this.spawnItemDropIcon(enemy.x, enemy.y, itemDrop.itemId, added, i, itemDrops.length);
      }
    }
  }

  private spawnDummy(x: number, y: number): void {
    if (!this.combatTargets) return;
    const dummy = new TargetDummy(this, x, y);
    this.combatTargets.add(dummy);
    this.dummies.push(dummy);
  }

  private tryAttack(aimDir?: Phaser.Math.Vector2): boolean {
    if (!this.weapon) return false;
    if (this.attacking) return false;
    if (this.actionLocked || this.paused) return false;
    if (this.healthSystem?.isDead()) return false;
    return this.weapon.attack(this.time.now, aimDir);
  }

  private tryDodge(direction: Phaser.Math.Vector2): boolean {
    // Roll with i-frames: brief invulnerability + dash in input direction.
    if (this.actionLocked || this.paused) return false;
    if (this.healthSystem?.isDead()) return false;

    const dir = direction.lengthSq() > 0
      ? direction.clone().normalize()
      : this.facing.clone().normalize();
    if (dir.lengthSq() === 0) dir.set(1, 0);

    this.dodgeInvulnUntil = this.time.now + 400;
    this.playActionAnimation('slime-roll');

    // Dash velocity.
    const dodgeSpeed = 420;
    this.player.setVelocity(dir.x * dodgeSpeed, dir.y * dodgeSpeed);

    // Dust particles at start.
    const dust = this.add.particles(this.player.x, this.player.y, 'xp-orb', {
      lifespan: 280,
      speed: { min: 10, max: 40 },
      scale: { start: 0.2, end: 0 },
      alpha: { start: 0.4, end: 0 },
      quantity: 6,
      emitting: false,
    }).setDepth(4);
    dust.emitParticle(6);
    this.time.delayedCall(300, () => dust.destroy());

    floatingText.spawn(this, this.player.x, this.player.y - 30, 'DODGE', 'cyan');
    return true;
  }

  private isDodging(): boolean {
    return this.time.now < this.dodgeInvulnUntil;
  }

  private bindDebugCheats(): void {
    const kb = this.input.keyboard;
    if (!kb) return;

    const guard = () => !this.paused && !this.healthSystem?.isDead();

    // [1] = debug damage 20 hp, [2] = give XP, [3] = heal full,
    // [4] = give coins, [5] = give potion, [6] = apply burn, [7] = apply slow.
    kb.on('keydown-ONE', () => {
      if (!guard()) return;
      if (this.isDodging()) {
        floatingText.spawn(this, this.player.x, this.player.y - 30, 'DODGED!', 'cyan', true);
        return;
      }
      const req: DamageRequest = { amount: 20, source: 'debug', knockStrength: 180 };
      const dx = this.player.x;
      req.knockX = dx > WORLD_WIDTH / 2 ? -1 : 1;
      req.knockY = 0;
      const dmg = this.healthSystem?.applyDamage(req, this.time.now) ?? 0;
      if (dmg > 0) {
        floatingText.spawn(this, this.player.x, this.player.y - 30, `-${dmg}`, 'red', true);
      }
    });

    kb.on('keydown-TWO', () => {
      if (!guard()) return;
      gameState.addXp(25);
      floatingText.spawn(this, this.player.x, this.player.y - 30, '+25 XP', 'cyan');
    });

    kb.on('keydown-THREE', () => {
      if (!guard()) return;
      this.healthSystem?.heal(gameState.maxHp);
      floatingText.spawn(this, this.player.x, this.player.y - 30, 'FULL HEAL', 'green', true);
    });

    kb.on('keydown-FOUR', () => {
      if (!guard()) return;
      gameState.addCoins(100);
    });

    kb.on('keydown-FIVE', () => {
      if (!guard()) return;
      playerInventory.add('hp-potion', 1);
      floatingText.spawn(this, this.player.x, this.player.y - 30, '+potion', 'green');
    });

    kb.on('keydown-SIX', () => {
      if (!guard()) return;
      this.statusEffects?.apply('burn');
      floatingText.spawn(this, this.player.x, this.player.y - 30, 'BURN!', 'orange');
    });

    kb.on('keydown-SEVEN', () => {
      if (!guard()) return;
      this.statusEffects?.apply('slow');
      floatingText.spawn(this, this.player.x, this.player.y - 30, 'SLOWED', 'cyan');
    });

    kb.on('keydown-EIGHT', () => {
      if (!guard()) return;
      this.spawnDummy(this.player.x + Phaser.Math.Between(60, 140), this.player.y + Phaser.Math.Between(-60, 60));
      floatingText.spawn(this, this.player.x, this.player.y - 30, '+dummy', 'white');
    });
  }

  private makeAnimation(key: string, frames: number[], frameRate: number, repeat = -1): void {
    if (this.anims.exists(key)) {
      return;
    }

    this.anims.create({
      key,
      frames: frames.map((frame) => ({ key: 'slime', frame })),
      frameRate,
      repeat,
    });
  }
}
