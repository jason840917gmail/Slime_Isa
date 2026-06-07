Old Game Parity Implementation Plan

Goal
Make the Godot mobile version first match the old Phaser game mechanically and visually before adding more mobile-specific content. The current Godot version is a prototype; the target is parity with the old Slime Open World experience.

Reference Source Files
- src/game/scenes/WorldScene.ts
- src/game/Friend.ts
- src/game/House.ts
- src/game/HUD.ts
- src/game/Minimap.ts
- src/game/ShopUI.ts
- src/game/worldTiles.ts
- src/game/terrainNoise.ts
- src/game/slimeAnimations.ts
- src/game/scenes/BootScene.ts

Target Features
- Procedural 54x54 tile meadow world.
- Grass, water, and rock-wall terrain using the old noise rules.
- Dense decorative flowers, stones, and purple berry pickups.
- Real slime sprite sheet and old animation set.
- Player name tag: bob.
- Movement, jump, roll/boost, trick, stretch, squash, teleport, and eat.
- 84 wandering friends with random faces, colors, ears, and simple collision.
- Player house and friend houses.
- Door prompt, house UI, bed/sleep flow, and coin reward.
- Purple berry pickup economy.
- Friend shop: buy boost and spawn friend.
- HUD with old title/instructions, coins, and friend count.
- Bottom-left minimap with player/friend dots and camera viewport.
- Camera bounds and zoom close to the Phaser version.

Phase 1: World Visual Parity
- Port terrainNoise.ts constants and sample() behavior into Godot.
- Port worldTiles.ts tile resolution rules.
- Generate a 54x54 world with 64px cells.
- Generate procedural textures equivalent to BootScene.createTerrainTextures().
- Spawn grass-a, grass-b, water, and rock-wall tiles.
- Add collision only for rock-wall tiles.
- Spawn flowers, stones, and purple berries using the old noise thresholds.
- Set world/camera bounds to 3456x3456.
- Reduce camera zoom from prototype close-up to an old-game readable zoom.

Phase 2: Real Slime Parity
- Bring asset/slime_normalized.png into MobileVersion assets.
- Replace the Polygon2D player placeholder with AnimatedSprite2D using an 8x8, 256px frame sheet.
- Port animation clips: slime-idle, slime-walk, slime-hop, slime-squash, slime-stretch, slime-roll, slime-trick, slime-teleport, slime-eat.
- Match old movement constants: walk 230, boost 360, boost bonus starts at 0.
- Add action locking for one-shot animations.
- Add bob name tag above the player.

Phase 3: Player Actions
- Keep PlayerSlime reading only from InputManager.
- Map physical and virtual input to the old actions.
- Movement while boost is held plays roll.
- Pressing roll while idle plays a one-shot roll animation.
- Jump plays hop.
- Trick, stretch, squash, and teleport play their old animation clips.
- Pickup plays eat.

Phase 4: Friends
- Create Friend.tscn and friend.gd.
- Spawn 84 friends at valid non-solid world tiles.
- Wander to random nearby targets.
- Randomly change face, color, and ears on timers.
- Collide with rock walls, player, and other friends where practical.
- Add friend count to HUD and minimap.

Phase 5: Houses And Interaction
- Create reusable House.tscn and house.gd parity behavior.
- Place one player house near the player and up to six friend houses.
- Assign friend homes and place the first friends near their doors.
- Add door zones and bed zones.
- Show enter prompt near doors.
- Enter house: stop camera follow, pan/zoom to house, and show House UI.
- Sleep: lock player, show Zzz..., wait, reward 20 coins, then unlock.
- Leave: resume camera follow.

Phase 6: Pickups And Economy
- Spawn purple berry pickups from procedural terrain.
- On pickup: play slime-eat, remove pickup, add 5 coins, flash HUD, play pickup sound, and save.
- Keep initial coins at 50 to match the old game.

Phase 7: Shop
- Create ShopUI.tscn and shop_ui.gd.
- Interact near a friend to open shop.
- Boost +50 speed costs 25 coins.
- Spawn Friend costs 15 coins.
- Update HUD immediately after purchases.

Phase 8: HUD And Minimap
- Recreate old HUD title/instructions in the top-left.
- Show Coins and Friends counts.
- Hide debug overlay by default; keep F3 toggle.
- Add bottom-left minimap with a dark background, green border, player dot, friend dots, and viewport rectangle.

Phase 9: Mobile Adaptation
- Make touch controls semi-transparent and less visually dominant.
- Respect safe areas and common phone/tablet aspect ratios.
- Keep old-game readability while tuning mobile zoom/control positions.
- Keep debug tools available but not visible in normal play.

Implementation Order
1. Terrain/world generation.
2. Real slime sprite and animation setup.
3. Player actions and action locking.
4. Friends.
5. Houses and interaction.
6. Pickups and economy.
7. Shop.
8. HUD and minimap.
9. Mobile layout polish.
