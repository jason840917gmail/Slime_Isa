import Phaser from 'phaser';
import { Friend } from '../../Friend';
import { House } from '../../House';
import { TILE_SIZE, WORLD_HEIGHT, WORLD_TILES_X, WORLD_TILES_Y, WORLD_WIDTH } from '../../terrainNoise';
import { isTileCollidable, WORLD_TILE_RULES, type WorldTileId } from '../../worldTiles';

export interface HouseEntry {
  owner: 'player' | 'friend';
  house: House;
}

export interface HousePlacementContext {
  scene: Phaser.Scene;
  terrainGrid: WorldTileId[][];
  collisionTiles: Phaser.Physics.Arcade.StaticGroup;
  player: Phaser.Physics.Arcade.Sprite;
  friends: Phaser.Physics.Arcade.Group;
  shouldMovePlayerHome: boolean;
}

export function placeHouses(
  ctx: HousePlacementContext,
  playerCount = 1,
  friendCount = 3,
): { houses: HouseEntry[]; playerHouse?: House } {
  const candidates: Array<{ x: number; y: number }> = [];
  for (let tileY = 0; tileY < WORLD_TILES_Y; tileY += 1) {
    for (let tileX = 0; tileX < WORLD_TILES_X; tileX += 1) {
      const tileId = ctx.terrainGrid[tileY]?.[tileX];
      if (tileId && WORLD_TILE_RULES[tileId].allowsDecorations && !isTileCollidable(tileId)) {
        candidates.push({ x: tileX * TILE_SIZE + TILE_SIZE / 2, y: tileY * TILE_SIZE + TILE_SIZE / 2 });
      }
    }
  }

  candidates.sort((a, b) => {
    const distanceA = (a.x - WORLD_WIDTH / 2) ** 2 + (a.y - WORLD_HEIGHT / 2) ** 2;
    const distanceB = (b.x - WORLD_WIDTH / 2) ** 2 + (b.y - WORLD_HEIGHT / 2) ** 2;
    return distanceA - distanceB;
  });
  const homeCandidate = candidates.shift();
  Phaser.Utils.Array.Shuffle(candidates);
  if (homeCandidate) candidates.unshift(homeCandidate);

  const houses: HouseEntry[] = [];
  const friendHouses: House[] = [];
  let playerHouse: House | undefined;
  let index = 0;

  for (let i = 0; i < playerCount && index < candidates.length; i += 1, index += 1) {
    const position = candidates[index];
    const house = i === 0
      ? new House(ctx.scene, position.x, position.y, 'big-blue-house', 'bed')
      : new House(ctx.scene, position.x, position.y);
    if (i === 0) {
      playerHouse = house;
      if (ctx.shouldMovePlayerHome) {
        const door = house.getDoorPosition();
        ctx.player.setPosition(door.x, door.y + 18);
      }
    }
    houses.push({ owner: 'player', house });
    ctx.collisionTiles.add(house.sprite);
  }

  for (let i = 0; i < friendCount && index < candidates.length; i += 1, index += 1) {
    const position = candidates[index];
    const house = new House(ctx.scene, position.x, position.y);
    houses.push({ owner: 'friend', house });
    friendHouses.push(house);
    ctx.collisionTiles.add(house.sprite);
  }

  const friends = ctx.friends.getChildren() as Friend[];
  friendHouses.forEach((house, friendIndex) => {
    const friend = friends[friendIndex];
    if (!friend) return;
    friend.home = house;
    const door = house.getDoorPosition();
    friend.setPosition(door.x, door.y + 18);
  });

  return { houses, playerHouse };
}
