Godot Migration Plan
Create a new Godot project in a separate folder, for example:
godot/
  project.godot
  scenes/
  scripts/
  assets/
  data/
  autoload/
  export/
The existing Phaser/Vite game remains untouched.
Recommended Stack
- Engine: Godot 4.3 or newer
- Language: GDScript
- Game type: 2D
- Target: Android first
- Future target: iOS
- Art style: pixel art or hand-drawn sprites
- Version control: keep Godot project inside the same repo, but isolated from existing src/
- Static data format: custom .tres / .res Resources for slimes, abilities, levels, items
- Save format: versioned JSON in user:// for player progress and settings
- Placeholder strategy: procedural shapes, simple colors, and generated sounds from day one
Proposed Folder Structure
godot/
  project.godot
  scenes/
    player/
      PlayerSlime.tscn
    enemies/
      Enemy.tscn
    levels/
      Level.tscn
      TestLevel.tscn
    collectibles/
      Collectible.tscn
    ui/
      HUD.tscn
      TouchControls.tscn
      LoadingScreen.tscn
      DebugOverlay.tscn
      PauseMenu.tscn
      MainMenu.tscn
    world/
      House.tscn
      Interactable.tscn
  scripts/
    player/
      player_controller.gd
      player_stats.gd
    enemies/
      enemy_ai.gd
    animation/
      animation_state.gd
    systems/
      save_system.gd
      game_state.gd
      scene_loader.gd
      input_manager.gd
      audio_manager.gd
    ui/
      hud.gd
      touch_controls.gd
      debug_overlay.gd
    world/
      level_controller.gd
      collectible.gd
      interactable.gd
  assets/
    spritesheets/
      slime/
      enemies/
      collectibles/
      environment/
    sounds/
      sfx/
      music/
    tilemaps/
      terrain/
      props/
  data/
    slime_types/
      basic_slime.tres
    abilities/
      jump.tres
      roll.tres
      interact.tres
    levels/
      test_level.tres
    items/
      coin.tres
      berry.tres
  autoload/
    GameState.gd
    SaveSystem.gd
    InputManager.gd
    AudioManager.gd
    SceneLoader.gd
  export/
    android/
    ios/
Current Game Feature Mapping
Current Phaser Feature
WorldScene.ts
Player slime sprite/animations
Keyboard controls
Friends/NPCs
Berry collectibles
Coins
Shop UI
House interaction
Minimap
Procedural terrain
Core Architecture
Use Godot scenes as reusable building blocks.

Main scene flow:
Main.tscn
  GameRoot
    Level
    PlayerSlime
    CanvasLayer
      HUD
      TouchControls
      DebugOverlay
      PauseMenu

Main.tscn owns composition. It loads the level, reads the level spawn point, instantiates PlayerSlime, places the player, then wires player signals to level systems. Levels should not create the player directly. This avoids camera/input/UI dependencies needing to know about level internals.

Use autoload singletons for global systems:
GameState.gd
SaveSystem.gd
InputManager.gd
AudioManager.gd
SceneLoader.gd
Use signals instead of hard references where possible:
coin_collected(amount)
player_health_changed(value)
ability_used(ability_id)
level_completed(level_id)
This will make the game easier to grow later.
Player Plan
PlayerSlime.tscn:
PlayerSlime
  CharacterBody2D
    AnimatedSprite2D
    CollisionShape2D
    Area2D
      InteractionDetector
Responsibilities:
- Movement
- Slime animations
- Collision
- Ability input
- Interaction detection
- Mobile and keyboard input support through InputManager
Initial actions:
move_left
move_right
move_up
move_down
jump
roll
interact
ability_1
ability_2
pause

InputManager API:
- get_movement_vector() -> Vector2
- is_action_pressed(action: StringName) -> bool
- consume_action_just_pressed(action: StringName) -> bool
- set_virtual_movement_vector(vector: Vector2) -> void
- set_virtual_action(action: StringName, pressed: bool) -> void
- pulse_virtual_action(action: StringName) -> void
- clear_virtual_state() -> void

InputManager must merge physical keyboard/gamepad InputMap state and virtual touch state into one player-facing API. PlayerSlime should never read Input directly. Virtual joystick movement should be stored as a Vector2 instead of pretending joystick directions are native InputMap actions.

Touch Controls
Create TouchControls.tscn as a CanvasLayer or Control.
Recommended controls:
- Left side: virtual joystick
- Right side:
  - Jump
  - Roll / boost
  - Interact
  - Ability button
- Top-right:
  - Pause
The touch UI should write into the same InputManager state used by keyboard/gamepad. The player should not care whether input came from touch, keyboard, or controller.

Touch layout rules:
- Controls must respect display safe areas, including notches and rounded corners.
- Controls must scale and reposition for phone, tablet, and ultrawide aspect ratios.
- Left joystick should stay reachable by thumb, not simply pinned to the absolute screen corner.
- Right-side action cluster should have editable spacing and size.
- Debug overlay should expose the current virtual movement vector and pressed virtual actions.

Placeholder Visual Strategy
Do not wait for final art before testing gameplay.

Initial placeholders:
- Player: Polygon2D or generated capsule/blob shape with clear facing direction
- Enemies/NPCs: distinct colored shapes with labels if needed
- Collectibles: circles/stars using unique colors per item type
- Terrain: large colored Polygon2D shapes or TileMap blocks
- Interactables: simple houses/signs built from primitives
- UI icons: colored Button/TextureRect placeholders

These placeholders are allowed to ship through early prototypes. Replace them only after movement, interaction, camera, and mobile touch behavior are proven.

Level System
Start simple.
Level.tscn:
Level
  Node2D
    TileMapLayer / TileMap
    Props
    Collectibles
    Enemies
    SpawnPoints
      PlayerSpawn
    CameraBounds
Initial level goal:
- One test meadow level inspired by the current Phaser world
- Player spawn
- Collectible berries/coins
- Basic terrain collision
- One interactable object, such as a house or sign

Level responsibilities:
- Expose a PlayerSpawn node or method for Main.gd.
- Expose camera bounds for the player camera.
- Own static world geometry, collectibles, enemies, and interactables.
- Avoid directly depending on the player scene unless connected by Main.gd.

Camera Plan
Use a top-down Camera2D following PlayerSlime.

Initial camera requirements:
- Smooth follow enabled and tunable per level.
- Zoom configured for mobile readability.
- Camera limits set from the active level's CameraBounds.
- No camera movement outside authored level bounds.
- Debug overlay should show camera zoom and world position.

Later expansion:
- Multiple levels
- World map
- Procedural areas
- Biomes
- Dungeons
- NPC villages
Data-Driven Design
Use Godot Resources for static game data. Use JSON only for runtime player progress and settings.
Example data types:
SlimeTypeResource
  id
  display_name
  max_health
  speed
  sprite_sheet
  abilities
AbilityResource
  id
  display_name
  cooldown
  icon
  effect_type
LevelResource
  id
  display_name
  scene_path
  music
  recommended_level
This avoids hardcoding every slime, ability, and level in scripts.

Data boundaries:
- .tres/.res: slime definitions, abilities, items, level metadata, spawn tables, balance values
- JSON save: coins, berries, current level, player health, unlocked abilities, collected item IDs, settings
- Do not write mutable player progress back into .tres resources at runtime.

Save System
Use a versioned save file.
Example save data:
{
  "version": 1,
  "coins": 50,
  "current_level": "test_level",
  "player": {
    "slime_type": "basic_slime",
    "position": [100, 200],
    "unlocked_abilities": ["jump", "roll"]
  },
  "collected_items": [],
  "settings": {
    "music_volume": 0.8,
    "sfx_volume": 1.0
  }
}
Godot save path:
user://savegame.json
Save events:
- Collect coin/item
- Unlock ability
- Complete level
- Change settings
- App pause/background
Android Setup
Required setup:
- Godot Android export templates
- Android SDK
- Java JDK
- Debug keystore
- Package name, for example:
com.yourstudio.slimeisa
Android export settings:
- Orientation: likely landscape
- Touchscreen enabled
- Internet disabled unless needed
- Minimum SDK: choose Godot default unless there is a specific reason
- Texture compression: test ETC2 / ASTC depending on target devices
- Fullscreen enabled
- Hide navigation bar if desired
- Handle app pause/resume
Phase 1 Android validation:
- Install Android export templates.
- Confirm Android SDK and JDK paths in Godot editor settings.
- Create or verify a debug keystore.
- Export a debug APK from the project.
- Install and launch the APK on at least one physical Android device.
- Confirm touch controls, save path, pause/resume, fullscreen mode, and debug overlay visibility.

Android testing priorities:
- Low-end Android phone
- Mid-range Android phone
- Android tablet
- Different aspect ratios
- App background/resume
- Touch control responsiveness

Loading And Scene Transitions
Add a minimal SceneLoader pattern early, even before multiple levels exist.

Initial requirements:
- LoadingScreen.tscn can show a plain background, title, and status text.
- SceneLoader.gd owns scene transition calls.
- Main menu to test level and test level reload should use SceneLoader.
- Save/load should not be coupled to scene construction order.

Audio Placeholder System
AudioManager should not remain silent while gameplay is being tested.

Initial requirements:
- play_sfx(id: StringName) should route known sound IDs.
- Missing sounds should fail harmlessly with a debug warning only in development.
- Add placeholder click/pickup/error/ability sounds, either simple generated tones or tiny temporary audio files.
- Collectibles, ability use, UI buttons, and interactions should call AudioManager from the start.

Debug Tools
Mobile development needs on-device visibility.

Initial DebugOverlay requirements:
- Toggleable overlay for development builds.
- FPS display.
- Player world position.
- Current movement vector.
- Pressed/just-pressed action state.
- Current level ID.
- Camera zoom and camera limits.
- Save path/status messages.
- Optional collision visibility toggle if available in the running build.

iOS Later
iOS should be planned for but not prioritized now.
Requirements later:
- macOS machine
- Xcode
- Apple Developer account
- iOS export templates
- Bundle ID
- App icons
- Provisioning profiles
- TestFlight setup
Keep platform-specific code isolated so Android-first choices do not block iOS.
Phased Roadmap
Phase 1: Godot Foundation
- Create new Godot folder/project.
- Configure project settings.
- Add InputMap actions.
- Add Android export profile.
- Validate Android export templates, SDK, JDK, and debug keystore.
- Export and install a debug APK on a physical Android device.
- Create base folder structure.
- Add autoloads: GameState, SaveSystem, InputManager, AudioManager, SceneLoader.
- Add DebugOverlay.tscn and make it visible in development builds.
- Add LoadingScreen.tscn and route scene changes through SceneLoader.
Phase 2: Player Prototype
- Create PlayerSlime.tscn.
- Add CharacterBody2D movement.
- Add procedural placeholder slime sprite.
- Add idle/walk/roll/jump animation states.
- Add keyboard controls for desktop testing.
- Add touch joystick and buttons using InputManager's virtual input API.
- Show input vector/action state in DebugOverlay.
Phase 3: Test Level
- Create TestLevel.tscn.
- Add TileMap terrain.
- Add collision.
- Add player spawn.
- Main.gd should place PlayerSlime at the level's spawn point.
- Add camera following player with smoothing, zoom, and level bounds.
- Add basic HUD.
Phase 4: Collectibles And Economy
- Create Collectible.tscn.
- Add berry/coin pickup.
- Update HUD.
- Save collected coins.
- Add simple pickup effects/sound hooks.
- Add placeholder pickup sound through AudioManager.
Phase 5: Interactions
- Add Interactable.gd.
- Add house/sign interaction.
- Add interaction prompt.
- Connect mobile interact button.
- Prepare for shop/NPC interactions later.
Phase 6: Enemy/NPC Base
- Create Enemy.tscn.
- Add simple wandering AI.
- Add detection/chase behavior if needed.
- Keep AI modular so future enemy types can reuse it.
Phase 7: Save/Load
- Save coins, level, player state.
- Load save on startup.
- Add save versioning.
- Add reset save option for development.
Phase 8: Mobile Polish
- Tune touch controls.
- Refine safe-area handling already added in the prototype.
- Add pause/resume handling.
- Add Android haptics later if needed.
- Optimize sprites/textures.
- Test real devices.
Phase 9: Content Expansion
- Add slime types.
- Add abilities.
- Add more levels.
- Add enemies.
- Add shop.
- Add houses/NPCs.
- Replace placeholder sounds/music with final assets.
- Add progression.
Phase 10: Release Preparation
- App icon
- Splash screen
- Android signing key
- Store package name
- Privacy policy
- Build release APK/AAB
- Internal testing track on Google Play
- Crash/error logging strategy
Important Design Decisions To Make Before Building
1. Art style: pixel art or hand-drawn?
2. Orientation: landscape only, portrait only, or both?
3. Camera style: top-down like current game, side-view platformer, or hybrid?
4. World style: authored levels first or procedural world first?
5. Combat: peaceful exploration, enemy combat, or both?
6. Placeholder art direction: simple shapes, generated pixel placeholders, or rough hand-drawn temporary sprites?
7. Which Android device is the Phase 1 export validation target?
My Recommendation
Start with:
- Godot 4.3+
- GDScript
- Android landscape-first
- Top-down 2D movement, similar to the current Phaser game
- Data-driven slimes and abilities
- .tres Resources for static data, JSON for player saves
- One polished test level before procedural generation
- Touch controls from day one
- Android export validation from day one
- Debug overlay from day one
- Placeholder art and audio from day one
- Save system early, not later
