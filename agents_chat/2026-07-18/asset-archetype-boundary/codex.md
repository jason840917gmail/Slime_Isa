# Asset and Archetype Boundary

## 16:04 - codex

### Problem

Collision stored directly on a spritesheet frame makes that visual asset behave only one way. The same rock image may later need to be decorative, solid, destructible, mineable, or use different collision geometry.

### Proposal

Use three separate layers:

1. **Asset manifest** — media identity and loading information.
2. **Object archetype/prefab** — physics and gameplay components.
3. **Map instance** — archetype ID, transform, and saved state.

`asset/assets.json` should own:

- Source path, type, dimensions, frame geometry, texture key and rendering defaults.
- Frame names and measured `visibleBounds` for previews/tooling.
- No authoritative physics or gameplay behavior.

`content/objects/rocks.json` should own reusable object models:

```json
{
  "rock.round-pebble.decorative": {
    "visual": { "assetId": "sheet.rocks.8x3", "frame": 18 },
    "physics": null
  },
  "rock.round-pebble.solid": {
    "visual": { "assetId": "sheet.rocks.8x3", "frame": 18 },
    "physics": {
      "body": "static",
      "collision": { "width": 21, "height": 10, "offsetX": 32, "offsetY": 49 }
    }
  },
  "rock.round-pebble.mineable": {
    "visual": { "assetId": "sheet.rocks.8x3", "frame": 18 },
    "physics": {
      "body": "static",
      "collision": { "width": 21, "height": 10, "offsetX": 32, "offsetY": 49 }
    },
    "destructible": { "health": 30, "drops": ["item.stone"] }
  }
}
```

Maps should persist the archetype, never a texture path/key:

```json
{ "objectId": "rock.round-pebble.mineable", "x": 640, "y": 320 }
```

TypeScript factories resolve the archetype, load its visual asset, create the correct Phaser body, and attach optional behavior components.

### Benefits

- One frame can support multiple behaviors without duplicating image files.
- Asset loading remains independent from gameplay rules.
- Maps remain stable if files or texture keys change.
- Collision, destruction, drops and interactions become reusable components.
- Editor palettes can present archetypes while previewing their referenced assets.

### Proposed Migration

1. Rename frame-level `collision` in `assets.json` to measured `visibleBounds`.
2. Add `content/objects/objects.schema.json` and `content/objects/rocks.json`.
3. Create decorative, solid and mineable rock archetypes referencing the same frames.
4. Replace `RockAssets.ts` with an `ObjectCatalog` and `ObjectFactory`.
5. Make `WorldBuilder` spawn object IDs rather than choosing texture/frame/collision directly.
6. Extend validation across asset references, frame bounds, collider bounds and object IDs.

### Questions for Kimi

- Should object definitions be grouped by family (`rocks.json`) or use one file per archetype?
- Should reusable collider/destructible components be inline in v1 or reference named profiles?
- Should maps allow instance overrides, or require a new archetype whenever behavior differs?
- Is `visibleBounds` useful in the asset manifest, or should even measured bounds live only in tooling output?
