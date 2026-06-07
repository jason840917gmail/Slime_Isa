import Phaser from 'phaser';
import { SLIME_ANIM_MAP, SLIME_ANIMS } from '../slimeAnimations';
import { Friend } from '../Friend';
import { House } from '../House';
import { TILE_SIZE, WORLD_TILES_X, WORLD_TILES_Y, WORLD_WIDTH, WORLD_HEIGHT, sample } from '../terrainNoise';
import {
  getTileBodyBounds,
  isTileCollidable,
  resolveWorldTile,
  WORLD_TILE_RULES,
  type WorldTileId,
} from '../worldTiles';
import { Minimap } from '../Minimap';
import { HUD } from '../HUD';
import { ShopUI } from '../ShopUI';

const WALK_SPEED = 230;
const BOOST_SPEED = 360;
const DEFAULT_ZOOM = 1;
const HOUSE_ZOOM = 1;

type Controls = Phaser.Types.Input.Keyboard.CursorKeys & {
  upAlt: Phaser.Input.Keyboard.Key;
  downAlt: Phaser.Input.Keyboard.Key;
  leftAlt: Phaser.Input.Keyboard.Key;
  rightAlt: Phaser.Input.Keyboard.Key;
  boost: Phaser.Input.Keyboard.Key;
  jump: Phaser.Input.Keyboard.Key;
  trick: Phaser.Input.Keyboard.Key;
  stretch: Phaser.Input.Keyboard.Key;
  squash: Phaser.Input.Keyboard.Key;
  teleport: Phaser.Input.Keyboard.Key;
  interact: Phaser.Input.Keyboard.Key;
};

export class WorldScene extends Phaser.Scene {
  private player!: Phaser.Physics.Arcade.Sprite;
  private collisionTiles!: Phaser.Physics.Arcade.StaticGroup;
  private friends!: Phaser.Physics.Arcade.Group;
  private controls!: Controls;
  private currentAnimation = 'slime-idle';
  private actionLocked = false;
  private terrainGrid: WorldTileId[][] = [];
  private coins = 50;
  private boostBonus = 0;
  private minimap!: Minimap;
  private hud!: HUD;
  private shopUI!: ShopUI;
  private shopTarget: Friend | null = null;
  private houses: Array<{ owner: 'player' | 'friend'; house: House }> = [];
  private playerHouse?: House;
  private insideHouse = false;
  private currentHouse: House | null = null;
  private houseUI?: Phaser.GameObjects.Container;
  private nearHouse: House | null = null;
  private enterPrompt?: Phaser.GameObjects.Text | null = null;
  private purpleFoods!: Phaser.Physics.Arcade.StaticGroup;
  private playerNameTag!: Phaser.GameObjects.Text;

  private fakeControls: Controls = {
    left: { isDown: false } as any,
    right: { isDown: false } as any,
    up: { isDown: false } as any,
    down: { isDown: false } as any,
    space: { isDown: false } as any,
    shift: { isDown: false } as any,
    upAlt: { isDown: false } as any,
    downAlt: { isDown: false } as any,
    leftAlt: { isDown: false } as any,
    rightAlt: { isDown: false } as any,
    boost: { isDown: false } as any,
    jump: { isDown: false } as any,
    trick: { isDown: false } as any,
    stretch: { isDown: false } as any,
    squash: { isDown: false } as any,
    teleport: { isDown: false } as any,
    interact: { isDown: false } as any,
  };

  constructor() {
    super('world');
    this.controls = this.fakeControls;
  }

  create(): void {
    // Phase 1: World entities (no cross-system side effects)
    this.createCollisionLayer();
    this.buildWorld();
    this.createSlimeAnimations();
    this.createPlayer();
    this.createFriends(84);
    this.placeHouses(1, Math.min(6, this.friends.getLength()));
    this.createPhysics();
    this.createCamera();

    // Phase 2: UI systems
    this.createMinimap();
    this.createHUD();
    this.createControls();
    this.createShopUI();
    this.createOverlay();

    // Phase 3: One-time cross-system sync
    this.hud.updateFriendCount(this.friends.getLength());

    this.scale.on('resize', this.handleResize, this);
  }

  update(): void {
    this.minimap.update(this.cameras.main, this.player, this.friends);

    if (this.player && this.playerNameTag) {
      this.playerNameTag.setPosition(this.player.x, this.player.y - 56);
    }

    this.updateHousePrompt();

    if (this.enterPrompt && this.player) {
      this.enterPrompt.setPosition(this.player.x, this.player.y - 40);
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
    const speed = wantsBoost ? BOOST_SPEED + this.boostBonus : WALK_SPEED;

    if (direction.lengthSq() > 0) {
      direction.normalize().scale(speed);
    }

    this.player.setVelocity(direction.x, direction.y);
    this.player.rotation = 0;

    if (direction.lengthSq() === 0) {
      this.player.setFlipX(false);
      this.playAnimation('slime-idle');
      return;
    }

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

  private updateHousePrompt(): void {
    if (!this.player || this.houses.length === 0) return;

    const THRESH = 96;
    let best: { house: House; d: number } | null = null;

    for (const e of this.houses) {
      const door = e.house.getDoorPosition();
      const d = Phaser.Math.Distance.Between(this.player.x, this.player.y, door.x, door.y);
      if (!best || d < best.d) {
        best = { house: e.house, d };
      }
    }

    if (best && best.d <= THRESH) {
      if (this.nearHouse !== best.house) {
        this.nearHouse = best.house;
        this.showEnterPrompt();
      }
    } else if (this.nearHouse) {
      this.nearHouse = null;
      this.hideEnterPrompt();
    }
  }

  private buildWorld(): void {
    this.terrainGrid = [];

    for (let tileY = 0; tileY < WORLD_TILES_Y; tileY += 1) {
      const row: WorldTileId[] = [];

      for (let tileX = 0; tileX < WORLD_TILES_X; tileX += 1) {
        const worldX = tileX * TILE_SIZE;
        const worldY = tileY * TILE_SIZE;
        const noise = sample(tileX, tileY);
        const tileId = resolveWorldTile(tileX, tileY);
        const tileRule = WORLD_TILE_RULES[tileId];

        row.push(tileId);
        this.createWorldTile(tileId, worldX, worldY);

        if (tileRule.allowsDecorations && noise > 0.62 && sample(tileX + 11, tileY - 7) > 0.5) {
          this.add
            .image(worldX + 42, worldY + 24, 'flower')
            .setDepth(2)
            .setScale(Phaser.Math.FloatBetween(0.9, 1.2));
        }

        if (tileRule.allowsDecorations && noise > 0.45 && sample(tileX + 5, tileY + 3) > 0.86) {
          const px = worldX + Phaser.Math.Between(20, 44);
          const py = worldY + Phaser.Math.Between(20, 44);
          this.spawnPurple(px, py);
        }

        if (tileRule.allowsDecorations && noise < 0.18 && sample(tileX - 5, tileY + 9) > 0.62) {
          this.add
            .image(worldX + 28, worldY + 34, 'stone')
            .setDepth(2)
            .setRotation(Phaser.Math.FloatBetween(-0.3, 0.3));
        }
      }

      this.terrainGrid.push(row);
    }

    this.physics.world.setBounds(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
  }

  private createCollisionLayer(): void {
    this.collisionTiles = this.physics.add.staticGroup();
    this.purpleFoods = this.physics.add.staticGroup();
  }

  private createSlimeAnimations(): void {
    for (const clip of SLIME_ANIMS) {
      this.makeAnimation(clip.key, clip.frames, clip.frameRate, clip.repeat);
    }
  }

  private createPlayer(): void {
    const spawnPoint = this.findSpawnPoint();

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
      this.physics.add.collider(this.player, this.friends as Phaser.Physics.Arcade.Group);
      this.physics.add.collider(this.friends, this.friends as Phaser.Physics.Arcade.Group);
    }
    if (this.purpleFoods) {
      this.physics.add.overlap(this.player, this.purpleFoods, this.collectPurple, undefined, this);
    }

    for (const entry of this.houses) {
      const zone = entry.house.doorZone;
      if (zone) {
        this.physics.add.overlap(this.player, zone, () => {
          this.nearHouse = entry.house;
          this.showEnterPrompt();
        }, undefined, this);
      }
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
        if (this.player) {
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

    this.coins += 5;
    this.hud.updateCoins(this.coins);
    this.hud.flashCoins(this);
  }

  private createMinimap(): void {
    this.minimap = new Minimap(this);
  }

  private createHUD(): void {
    this.hud = new HUD(this, this.coins, this.friends.getLength());
  }

  private createCamera(): void {
    this.cameras.main.setBounds(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
    this.cameras.main.startFollow(this.player, true, 0.08, 0.08);
    this.cameras.main.setZoom(DEFAULT_ZOOM);
    this.cameras.main.setRoundPixels(true);
  }

  private createControls(): void {
    const cursorKeys = this.input.keyboard?.createCursorKeys();
    const extraKeys = this.input.keyboard?.addKeys({
      upAlt: Phaser.Input.Keyboard.KeyCodes.I,
      downAlt: Phaser.Input.Keyboard.KeyCodes.K,
      leftAlt: Phaser.Input.Keyboard.KeyCodes.J,
      rightAlt: Phaser.Input.Keyboard.KeyCodes.L,
      boost: Phaser.Input.Keyboard.KeyCodes.Q,
      jump: Phaser.Input.Keyboard.KeyCodes.SPACE,
      trick: Phaser.Input.Keyboard.KeyCodes.E,
      stretch: Phaser.Input.Keyboard.KeyCodes.R,
      squash: Phaser.Input.Keyboard.KeyCodes.T,
      teleport: Phaser.Input.Keyboard.KeyCodes.Y,
      interact: Phaser.Input.Keyboard.KeyCodes.F,
    }) as Omit<Controls, keyof Phaser.Types.Input.Keyboard.CursorKeys> | undefined;

    if (!cursorKeys || !extraKeys) {
      throw new Error('Keyboard input is not available.');
    }

    this.controls = {
      ...cursorKeys,
      ...extraKeys,
    };

    this.input.keyboard?.on('keydown-W', () => {
      this.playActionAnimation('slime-eat');
    }, this);
  }

  private createOverlay(): void {
    const font = 'Aptos, Segoe UI Variable, sans-serif';

    this.add
      .text(24, 24, 'Explore the meadow', {
        fontFamily: font,
        fontSize: '24px',
        color: '#f2ffef',
        stroke: '#163033',
        strokeThickness: 5,
      })
      .setScrollFactor(0)
      .setDepth(50);

    this.add
      .text(24, 56, 'Arrows / IJKL move   Space jump   Q roll/boost', {
        fontFamily: font,
        fontSize: '16px',
        color: '#ccebd0',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(50);

    this.add
      .text(24, 82, 'E trick   R stretch   T squash   Y teleport', {
        fontFamily: font,
        fontSize: '16px',
        color: '#ccebd0',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(50);

    this.add
      .text(24, 108, 'Rock tiles are solid obstacles', {
        fontFamily: font,
        fontSize: '16px',
        color: '#ccebd0',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(50);
  }

  private createWorldTile(tileId: WorldTileId, worldX: number, worldY: number): void {
    const rule = WORLD_TILE_RULES[tileId];
    const bodyBounds = getTileBodyBounds(tileId, TILE_SIZE);

    if (!bodyBounds) {
      this.add.image(worldX, worldY, rule.texture).setOrigin(0);
      return;
    }

    const tile = this.collisionTiles.create(worldX + TILE_SIZE / 2, worldY + TILE_SIZE / 2, rule.texture) as Phaser.Physics.Arcade.Image;
    const body = tile.body as Phaser.Physics.Arcade.StaticBody;

    tile.setDepth(1);
    body.setSize(bodyBounds.width, bodyBounds.height);
    body.setOffset(bodyBounds.offsetX, bodyBounds.offsetY);
    tile.refreshBody();
  }

  private findSpawnPoint(): Phaser.Math.Vector2 {
    const startX = Math.floor(WORLD_TILES_X / 2);
    const startY = Math.floor(WORLD_TILES_Y / 2);
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
      if (this.insideHouse) {
        if (this.houseUI) {
          this.closeHouse();
        } else if (this.currentHouse) {
          this.showHouseUI(this.currentHouse);
        }

        return true;
      }

      if (this.tryEnterHouseNearby()) {
        return true;
      }

      if (this.trySleepNearby()) {
        return true;
      }

      this.tryOpenShopNearby();
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.jump)) {
      this.playActionAnimation('slime-hop');
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.boost) && direction.lengthSq() === 0) {
      this.playActionAnimation('slime-roll');
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.trick)) {
      this.playActionAnimation('slime-trick');
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.stretch)) {
      this.playActionAnimation('slime-stretch');
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.squash)) {
      this.playActionAnimation('slime-squash');
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.teleport)) {
      this.playActionAnimation('slime-teleport');
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
    this.shopUI.show(this.coins);
  }

  private tryEnterHouseNearby(): boolean {
    if (!this.player) return false;

    if (this.nearHouse) {
      this.openHouseInterior(this.nearHouse);
      return true;
    }

    if (!this.houses) return false;

    const entry = this.houses.find((h) => {
      const door = h.house.getDoorPosition();
      return Phaser.Math.Distance.Between(this.player.x, this.player.y, door.x, door.y) < 80;
    });

    if (entry) {
      this.openHouseInterior(entry.house);
      return true;
    }

    return false;
  }

  private openHouseInterior(house: House): void {
    if (!house || this.insideHouse) return;

    this.insideHouse = true;
    this.currentHouse = house;

    const cam = this.cameras.main;
    cam.stopFollow();
    cam.pan(house.sprite.x, house.sprite.y, 350, 'Power2');
    cam.zoomTo(HOUSE_ZOOM, 350);

    const door = house.getDoorPosition();
    this.player.setPosition(door.x, door.y + 12);

    this.showHouseUI(house);
  }

  private showHouseUI(house: House): void {
    if (this.houseUI) return;

    const cam = this.cameras.main;
    const cx = cam.width / 2;
    const cy = cam.height / 2;

    const container = this.add.container(cx, cy).setScrollFactor(0).setDepth(200);

    const bg = this.add.graphics();
    bg.fillStyle(0x071612, 0.96);
    bg.fillRoundedRect(-140, -80, 280, 160, 12);
    bg.lineStyle(2, 0x335c45, 0.6);
    bg.strokeRoundedRect(-140, -80, 280, 160, 12);
    container.add(bg);

    const font = 'Aptos, Segoe UI Variable, sans-serif';

    container.add(
      this.add
        .text(0, -52, 'House', {
          fontFamily: font,
          fontSize: '18px',
          color: '#ccebd0',
        })
        .setOrigin(0.5),
    );

    const sleepBtn = this.add
      .text(0, -8, 'Sleep', {
        fontFamily: font,
        fontSize: '16px',
        color: '#ffffff',
      })
      .setOrigin(0.5)
      .setInteractive({ useHandCursor: true })
      .on('pointerdown', () => {
        if (this.currentHouse) this.sleepAtBed(this.currentHouse);
      });

    container.add(sleepBtn);

    const leaveBtn = this.add
      .text(0, 44, 'Leave', {
        fontFamily: font,
        fontSize: '14px',
        color: '#ffd86b',
      })
      .setOrigin(0.5)
      .setInteractive({ useHandCursor: true })
      .on('pointerdown', () => this.closeHouse());

    container.add(leaveBtn);

    this.houseUI = container;
  }

  private closeHouse(): void {
    if (!this.insideHouse) return;

    if (this.houseUI) {
      this.houseUI.destroy();
      this.houseUI = undefined;
    }

    this.insideHouse = false;
    this.currentHouse = null;

    const cam = this.cameras.main;
    cam.pan(this.player.x, this.player.y, 350, 'Power2');
    cam.zoomTo(DEFAULT_ZOOM, 350);
    cam.startFollow(this.player, true, 0.08, 0.08);
  }

  private showEnterPrompt(): void {
    if (this.enterPrompt || !this.player) return;

    const t = this.add
      .text(this.player.x, this.player.y - 40, 'Press F to enter', {
        fontFamily: 'Aptos, Segoe UI Variable, sans-serif',
        fontSize: '14px',
        color: '#ffffff',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setOrigin(0.5)
      .setDepth(95)
      .setScrollFactor(0);

    this.enterPrompt = t;
  }

  private hideEnterPrompt(): void {
    if (!this.enterPrompt) return;
    this.enterPrompt.destroy();
    this.enterPrompt = undefined;
  }

  private trySleepNearby(): boolean {
    for (const entry of this.houses) {
      const bedPos = entry.house.getBedPosition();
      if (!bedPos) continue;

      if (Phaser.Math.Distance.Between(this.player.x, this.player.y, bedPos.x, bedPos.y) < 80) {
        this.sleepAtBed(entry.house);
        return true;
      }
    }

    return false;
  }

  private sleepAtBed(house: House): void {
    const bedPos = house.getBedPosition();
    if (!bedPos || this.actionLocked) return;

    this.actionLocked = true;
    this.player.setVelocity(0, 0);
    this.player.setPosition(bedPos.x, bedPos.y - 6);
    this.player.rotation = 0;
    this.playAnimation('slime-idle');

    const zzz = this.add
      .text(this.player.x, this.player.y - 26, 'Zzz...', {
        fontFamily: 'Aptos, Segoe UI Variable, sans-serif',
        fontSize: '18px',
        color: '#dfefff',
      })
      .setDepth(95)
      .setOrigin(0.5)
      .setScrollFactor(0);

    const follow = this.time.addEvent({
      delay: 50,
      loop: true,
      callback: () => {
        if (zzz && this.player) zzz.setPosition(this.player.x, this.player.y - 26);
      },
    });

    const sleepTime = 3000;
    this.time.delayedCall(sleepTime, () => {
      follow.remove(false);
      zzz.destroy();
      this.actionLocked = false;
      this.coins += 20;
      this.hud.updateCoins(this.coins);
      this.tweens.add({ targets: this.player, scale: 1.04, duration: 140, yoyo: true });
    }, [], this);
  }

  private createShopUI(): void {
    const x = this.cameras.main.width - 180;
    const y = 120;

    this.shopUI = new ShopUI(
      this,
      x,
      y,
      {
        onBuyBoost: () => {
          if (this.coins >= 25) {
            this.coins -= 25;
            this.boostBonus += 50;
            this.hud.updateCoins(this.coins);
          }
        },
        onBuyFriend: () => {
          if (this.coins >= 15) {
            this.coins -= 15;
            this.spawnFriend();
            this.hud.updateCoins(this.coins);
            this.hud.updateFriendCount(this.friends.getLength());
          }
        },
        onCoinsChanged: (coins: number) => {
          this.hud.updateCoins(coins);
        },
      },
    );
  }

  private handleResize(gameSize: Phaser.Structs.Size): void {
    this.cameras.main.setViewport(0, 0, gameSize.width, gameSize.height);

    if (this.shopUI) {
      this.shopUI.setPosition(gameSize.width - 180, 120);
    }
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
