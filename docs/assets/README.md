# Asset Creation And Integration

This is the starting point for creating new game art and making it available
to the game. Keep generated source art, sheet preparation, manifest metadata,
visual definitions, character/object content, and validation in this workflow.

## Recommended workflow

1. Read the [asset sheet and size contract](./asset-sheet-spec.md).
2. Choose the right art type guide:
   - [Animated character sheets](./slime-sheet-guide.md)
   - [Terrain, wall, and tile art](./terrain-tile-guide.md)
   - [Friends, houses, and building props](./friends-and-houses-guide.md)
3. Generate or commission the art using the [visual style guide](./visual-style-guide.md), the [Magnific MCP guide](./magnific-mcp-guide.md), or the [character animation video prompt](./character-animation-video-prompt.md).
4. Keep original or experimental output under `asset/Originals/` until it is ready. For generated video, extract a clean PNG sheet using the fixed camera, background, frame rate, and grid described by the prompt and art guide.
5. Register ready media and integrate it through [Adding Game Assets](./adding-assets.md).
6. For animated characters, continue with the [character sprites and visuals guide](./character-sprites-guide.md), then use Character Studio to create the character package and author clips, bodies, hitboxes, and gameplay fields.
7. Run the checks below before using the asset in a map or runtime feature.

## Which file owns what?

| Need | Source of truth |
| --- | --- |
| File path, dimensions, sheet grid, frame count, texture key, load bundle | `asset/assets.json` |
| Art style, generation constraints, and source preparation | This folder's generation guides |
| Character or object animation clips and visual transforms | `visual-set.json` |
| Character body, hitboxes, stats, AI, and drops | Character package `character.json` and owning runtime feature |
| Object collider, behavior, and reusable visual variants | Object JSON under `src/game/content/objects/` |
| Placement, position, and mutable instance state | Map JSON under `src/game/content/maps/` |

Do not put collision, solidity, health, damage, AI, or interactions in the
asset manifest. Do not put paths, texture keys, or collider definitions in a
map instance.

## Verification commands

Run the focused checks for the asset type, then the full project check:

```text
pnpm assets:check
pnpm visuals:check
pnpm characters:check
pnpm objects:check
pnpm maps:check
pnpm check
```

If the new asset is a projectile, enemy, weapon, or character, also run its
matching content check. Finish with a production build and a quick Studio or
game smoke test so frame alignment, loading, playback, and collision are
verified together.

## Guides in this folder

- [Adding Game Assets](./adding-assets.md) — register media, create reusable object definitions, and place map instances.
- [Asset Sheet And Size Guide](./asset-sheet-spec.md) — shared dimensions and when code changes are required.
- [Character Sprites And Animated Visuals](./character-sprites-guide.md) — manifest-to-runtime visual integration.
- [Slime Sheet Guide](./slime-sheet-guide.md) — animated character sheet format and frame layout.
- [Terrain And Tile Guide](./terrain-tile-guide.md) — terrain, obstacles, and small props.
- [Friends And Houses Guide](./friends-and-houses-guide.md) — NPC parts, buildings, and interaction props.
- [Visual Style Guide](./visual-style-guide.md) — project art direction and generation constraints.
- [Character Animation Video Prompt](./character-animation-video-prompt.md) — reusable prompt for extracting animation frames.
- [Character Animation Video Prompt Template](./character-animation-video-prompt-template.md) — fill-in template with idle, walk, attack, die, knockback, and direction presets.
- [Magnific MCP Guide](./magnific-mcp-guide.md) — image/video generation workflow and project placement.
- [Magnific MCP Login Fix](./magnific-mcp-login-fix.md) — recovery steps when the Magnific connector needs re-authentication.

## Related implementation plans

The operational guides live here. Deeper feature plans are organized under
[`docs/task/ideas/`](../task/ideas/README.md):

- [Character authoring development plan](../task/ideas/completed/character-authoring-development-plan.md)
- [Animated enemy roster design](../task/ideas/completed/2026-07-23-animated-worm-enemy-roster-design.md)
- [General visual animation system](../task/ideas/completed/general-visual-animation-system.md)
- [Visual set editor](../task/ideas/completed/visual-set-editor.md)
