# Adding Game Assets

Game content has three layers. Never mix their responsibilities.

1. **Asset manifest:** file identity and loading.
2. **Object file:** reusable appearance, scale, collider, and behavior.
3. **Map instance:** object ID, exact visual ID, position, and mutable state.

## 1. Register the media

Put the source file under `asset/`, then register it in `asset/assets.json`.

```json
"sheet.trees.oak": {
  "source": {
    "kind": "spritesheet",
    "path": "MAPS/trees/oak.png",
    "frame": { "w": 128, "h": 170, "cols": 3, "rows": 1 },
    "expect": { "w": 384, "h": 170 }
  },
  "runtime": { "textureKey": "trees-oak" },
  "render": { "origin": [0.5, 1] },
  "frames": {
    "0": { "name": "oak-small" },
    "1": { "name": "oak-medium" },
    "2": { "name": "oak-large" }
  },
  "tags": ["object", "tree"],
  "status": "ready"
}
```

Add runtime media to the appropriate bundle, such as `boot`.

Manifest rules:

- Use stable dotted asset IDs.
- Paths are relative to `asset/`, use `/`, and match filename casing.
- Name spritesheets with their frame size and grid when practical, for example
  `128x128-tile_4x2-resource-piles.png`.
- Frame entries describe the sheet; they do not define game objects.
- Never put colliders, solidity, health, drops, damage, AI, or interactions here.
- Run `pnpm assets:check` after editing the manifest.

## 2. Create one file per object

Create a JSON file under a family directory such as `src/game/content/objects/trees/`. Its filename is the dotted object ID with dots replaced by hyphens.

Example: `tree.oak.solid` becomes `tree-oak-solid.json`.

```json
{
  "$schema": "../objects.schema.json",
  "objectId": "tree.oak.solid",
  "selection": "authored",
  "variants": [
    {
      "assetId": "sheet.trees.oak",
      "frames": [
        {
          "visualId": "oak-small",
          "frame": 0,
          "scale": 1,
          "collider": { "width": 30, "height": 40, "offsetX": 49, "offsetY": 125 }
        }
      ]
    }
  ],
  "physics": { "body": "static" },
  "tags": ["tree", "solid"]
}
```

Register the JSON import in `ObjectCatalog.ts`. This keeps object IDs available to TypeScript and lets `ObjectFactory` resolve the definition.

Object rules:

- The object file owns every collider and gameplay behavior.
- `scale` is an optional uniform visual multiplier. It defaults to `1`; the runtime applies it to the artwork and authored collider, depth, and occlusion geometry while preserving the map anchor.
- Every frame used by a solid object must define its collider.
- Decorative objects use `"physics": null` and define no colliders.
- Interactive objects may declare a stable `behavior` ID; the scene composition registers the matching behavior group.
- Multiple visuals may be declared in one object when they share behavior. Every frame needs a stable, unique `visualId`; map authors choose it explicitly.
- Create a new object file whenever behavior or boundaries differ.
- Run `pnpm objects:check` after adding or editing an object.

Current solid environment content includes `tree.world.solid` (46 explicitly selectable tree visuals) and `house.world.solid` (3 house visuals). They intentionally have no decorative/no-collision counterpart; create one only if that gameplay distinction is actually needed.

### Reusing one frame in different objects

Two objects may reference the same asset and frame while behaving differently. For example, `rock-amber-decorative.json` can contain:

```json
{
  "$schema": "../objects.schema.json",
  "objectId": "rock.amber.decorative",
  "selection": "authored",
  "variants": [{ "assetId": "sheet.rocks.8x3", "frames": [{ "visualId": "amber", "frame": 0 }] }],
  "physics": null,
  "tags": ["rock", "decorative"]
}
```

The separate `rock-amber-mineable.json` can use a different boundary and behavior:

```json
{
  "$schema": "../objects.schema.json",
  "objectId": "rock.amber.mineable",
  "selection": "authored",
  "variants": [{
    "assetId": "sheet.rocks.8x3",
    "frames": [{
      "visualId": "amber",
      "frame": 0,
      "collider": { "width": 42, "height": 16, "offsetX": 28, "offsetY": 59 }
    }]
  }],
  "physics": { "body": "static" },
  "destructible": { "health": 30, "drops": ["shard"] },
  "tags": ["rock", "solid", "mineable"]
}
```

## 3. Place object instances

Maps reference object and visual IDs—not asset IDs, paths, texture keys, frames, colliders, or scale. Scale is shared by every map instance using that visual template.

```json
{
  "instanceId": "tree-001",
  "objectId": "tree.oak.solid",
  "visualId": "oak-small",
  "x": 640,
  "y": 320,
  "initialState": { "health": 20 }
}
```

Only mutable per-instance state belongs here, such as remaining health, whether a chest is open, or whether an item was collected. Physics and behavior cannot be overridden by a map instance; create another object file instead.

At runtime, pass the object ID, visual ID, and placement coordinates to `ObjectFactory`. World-generation code must not know texture keys, frames, or collider values.

## Completion checklist

- Media file added under `asset/`.
- Loading-only manifest entry and bundle added.
- One JSON file created for each distinct object behavior/boundary set.
- Object registered in `ObjectCatalog.ts`.
- Maps reference only object IDs, visual IDs, positions, and mutable state.
- `pnpm check` passes.
