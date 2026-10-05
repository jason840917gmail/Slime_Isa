# Adding Game Assets

Game content has three layers. Never mix their responsibilities.

1. **Asset manifest** (`asset/assets.json`): file identity and loading.
2. **Scene** (`src/game/content/scenes/authored/**/*.scene.json`): sprite, frame,
   scale, collision, depth/occlusion, animation, audio, and script data.
3. **Instance** in a world scene: which scene, where, and per-instance overrides.

## 1. Register the media

Put the runtime file under `asset/` (usually `asset/MAPS/<family>/`; source art
stays in `asset/Originals/`, which the manifest ignores), then add an entry to
`asset/assets.json`:

```json
"sheet.rocks.crystal-clusters.8x2": {
  "source": {
    "kind": "spritesheet",
    "path": "MAPS/rocks/128x128-tile_8x2-crystal-clusters.webp",
    "frame": { "w": 128, "h": 128, "cols": 8, "rows": 2, "count": 16 },
    "expect": { "w": 1024, "h": 256 }
  },
  "runtime": { "textureKey": "rocks-crystal-clusters-8x2" },
  "render": { "origin": [0.5, 0.97], "pixelArt": true },
  "tags": ["prop", "crystal", "cavern", "terrain-dressing"],
  "status": "ready"
}
```

Then add the ID to a load bundle. `boot`, `interiors`, `audio`, and `music` are
all loaded at startup by `ProceduralAssetScene`.

Manifest rules (schema: `asset/assets.schema.json`):

- Required fields are `source`, `runtime.textureKey`, and `status`
  (`draft`, `ready`, or `deprecated`). Optional: `frames` (per-index `name`),
  `render` (`origin`, `nativeSize`, `pixelArt`), `placement` (editor hints only),
  `tags`, `notes`.
- `source.kind` is one of `image`, `spritesheet`, `atlas`, `audio`, `tilemap`,
  `derived`, or `procedural`. `frame.count` marks a partly filled last row.
- Use stable dotted asset IDs and unique texture keys.
- Paths are relative to `asset/`, use `/`, and match filename casing.
- Name sheets with their frame size and grid, for example
  `128x128-tile_4x2-resource-piles.webp`.
- Never put colliders, solidity, health, drops, damage, AI, or interactions here.
- Run `pnpm assets:check`. It verifies paths, casing, `expect` dimensions, even
  frame division, unique texture keys, bundles, and fails on unregistered images
  and on stale per-world image lists. After adding or re-pointing art that
  worlds use, run `pnpm assets:worlds`: images only some worlds use then load
  when the player enters those worlds instead of at boot. Anything not in those
  lists loads at boot, so a stale list never leaves a texture missing.

## 2. Build a scene

Every placeable object, character, weapon, effect, and UI surface is a scene.
Create or duplicate one in Scene Studio (`pnpm dev`, then open
`http://localhost:3000/?studio=scenes`); it saves JSON under
`src/game/content/scenes/authored/`, and scene files there are discovered
automatically, so there is no catalog to register.

A static object is a `StaticBody2D` root with a `CollisionShape2D` and a
`Sprite2D`; a decoration without collision uses a `Node2D` root. The sprite
references the manifest through a scene-owned `sprite-sheet` subresource:

```json
{
  "version": 1,
  "sceneId": "object.crystal-cluster-wall.01",
  "rootNodeId": "body",
  "nodes": [
    { "id": "body", "name": "Body", "type": "StaticBody2D", "parentId": null, "order": 0,
      "properties": { "collisionLayer": 1, "collisionMask": 0, "position": [0, 0] } },
    { "id": "body-shape", "name": "BodyShape", "type": "CollisionShape2D", "parentId": "body", "order": 0,
      "properties": { "shape": { "resourceId": "crystal-cluster-wall.01.shape" }, "position": [0, -22] } },
    { "id": "visual", "name": "Visual", "type": "Sprite2D", "parentId": "body", "order": 1,
      "properties": {
        "texture": { "resourceId": "crystal-cluster-wall.01.sprite" }, "frame": 0,
        "origin": [0.5, 1], "scale": [1, 1], "visualOffset": [0, 0],
        "depthMode": "world-sorted", "depthBand": "world-entities",
        "occlusionBounds": { "width": 65, "height": 114, "offsetX": 31, "offsetY": 10 } } }
  ],
  "instances": [],
  "subresources": [
    { "version": 1, "resourceId": "crystal-cluster-wall.01.sprite", "kind": "sprite-sheet",
      "assetId": "sheet.rocks.crystal-clusters.8x2", "frameWidth": 128, "frameHeight": 128 },
    { "version": 1, "resourceId": "crystal-cluster-wall.01.shape", "kind": "collision-shape",
      "value": { "shape": "rectangle", "width": 48, "height": 44 } }
  ]
}
```

Scene rules:

- One scene per distinct visual/boundary. Reuse the same frame in two scenes
  when they need different collision or behavior.
- Behavior comes from a `ScriptNode` with a registered `scriptId`
  (`game.resource-node`, `game.collectible`, `game.chest`, `game.door`,
  `game.gate`, `game.npc`, ...; see `src/game/features/scripts/registrations.ts`).
  The node stores only the script ID and its data.
- Animations live in the scene's own `AnimationPlayer` library; sounds are
  `AudioStreamPlayer`/`AudioStreamPlayer2D` nodes (see `pnpm audio:wire`).
- Large families are generated rather than hand-built: interiors
  (`pnpm interiors:scenes`) and wall props
  (`python scripts/props/generate-wall-prop-scenes.py`). Re-running those tools
  overwrites the files they own.
- Run `pnpm scenes:check`.

The legacy object definitions in `src/game/content/objects/` (and
`ObjectCatalog.ts`) are a read-only compatibility validator for older map/save
data. New objects do not need an entry there.

## 3. Place instances

Open the world scene (`world.<map-id>`, file
`scenes/authored/worlds/<map-id>.scene.json`) in Scene Studio and add an
instance of the new scene. An instance stores the source `sceneId`, a stable
`instanceId`/`persistenceKey`, and property `overrides`, such as position, a
`visualOffset`/`scale` tweak, or script data like a collectible's quantity:

```json
{
  "instanceId": "l1-border-tree-001",
  "name": "l1-border-tree-001",
  "sceneId": "object.tree-forest-wall.pine-07",
  "parentNodeId": "gen-forest",
  "order": 0,
  "persistenceKey": "level-1.l1-border-tree-001",
  "overrides": [
    { "sourceInstancePath": [], "sourceNodeId": "body", "property": "position", "value": [32, 54] }
  ]
}
```

Instances never carry asset paths or texture keys. Run `pnpm scenes:check`
(world scenes are scenes). `pnpm maps:check` validates the separate map JSON in
`src/game/content/maps/` (terrain layers, spawns, exits, areas).

## Completion checklist

- Runtime file under `asset/`, source art under `asset/Originals/`.
- Manifest entry added to a bundle; `pnpm assets:check` passes.
- Scene created (Studio, generator, or JSON); `pnpm scenes:check` passes.
- Instances placed in the world scene; `pnpm scenes:check` passes again.
- `pnpm check` passes; the object looks and collides correctly in game.
