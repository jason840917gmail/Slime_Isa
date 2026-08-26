# Field Cartographer Map Editor

The map editor is available only through the Vite development server. Start it with:

```powershell
pnpm dev
```

Open an existing authored map:

```text
http://localhost:3000/?editor=level-1
http://localhost:3000/?editor=gloop-forest
http://localhost:3000/?editor=crystal-caverns
```

## Tools

The selected terrain tile or object visual follows the mouse cursor as a translucent preview, snapped to the tile under the pointer, so you always see what a click will place. Left-click-drag draws or stamps; middle-drag pans the map from any tool. Right-click picks the object or terrain under the cursor and activates the matching tool.

- **Pan (`H`)**: click-drag the canvas. Middle-drag also pans while another tool is active. Arrow keys or WASD move the camera; the mouse wheel zooms.
- **Paint (`B`)**: open a terrain group, select a miniature, then click-drag across map cells. Fast strokes are interpolated without gaps and one drag is one undo step.
- **Object (`O`)**: open an object group, select an exact visual miniature, then click or drag to stamp instances — one per crossed tile, committed as a single undoable stroke. The editor always places the chosen visual; it does not randomize variants.
- **Select / Move (`V`)**: every movable object receives a visible grab rectangle. Press inside a rectangle, drag the object, and release to snap it into the destination cell as one undoable move. Click without dragging to select it; press `Delete` or `Backspace` to remove the selection.
- **Erase (`X`)**: click to remove the nearest object or restore the first terrain type. Click-drag a rectangle to remove multiple objects in one undoable action. Safe zones are managed with the Monster Safe Zone tool instead.
- **Monster Safe Zone (`Z`)**: safe-zone rectangles are only visible while this tool is active, so they never clutter painting or object placement. Click-drag empty space to create a bright green, tile-aligned rectangle where enemies cannot spawn or enter. Left-click a zone to select it, left-drag it to move it, and press `Delete` to remove it. Safe zones work independently of a map's spawn configuration.
- **Enemy Area**: activates camp authoring. Choose circle or rectangle, drag a camp onto the map, then move it directly. A selected camp shows four corner handles for each perimeter; drag any corner to resize it while the stay/pursue containment rules and map bounds remain enforced. Use **Edit selected** to set its stay/pursue perimeters, enemy types, weights, per-type caps, respawn cooldown, and population cap, or **Delete selected** to remove the camp.
- **Player Spawn (`P`)**: places the default player spawn.
- **Entry Point (`I`)**: choose a direction and place that incoming entry point.
- **Exit Zone (`E`)**: choose a direction after assigning that edge in Map Connections. The physical boundary zone is generated automatically.

When a template is selected in the inspector, its canvas guides use a fixed visual legend: yellow is the visual frame and anchor, orange is the depth bound and its sorting edge, red is the collider, and blue is the occlusion scan region/reveal shape. The **Visual alignment** section includes a uniform scale multiplier; it preserves the map anchor and scales the artwork and its authored geometry together. The neutral white outline marks the selected object. The **Canvas boxes** controls can hide each guide independently or show the same guides on every matching instance. The depth bound is a separate source-frame rectangle; its lower edge controls front/behind sorting and does not change the map tile size.

## Connecting maps

The **Map Connections** section has North, East, South, and West dropdowns containing every existing authored map except the open document. Choose a map to connect that edge or choose **Not connected** to remove it. Connection changes support undo and redo.

Saving creates the opposite entry point and return exit in the target map, making the connection two-way. If that target edge already belongs to another map, saving stops with a conflict message instead of silently replacing it.

Use `Ctrl+Z` and `Ctrl+Y` for undo/redo and `Ctrl+S` to save. Saving persists the map without reloading the editor. The editor warns before leaving with unsaved work.

Safe zones are stored in map-level `enemySafeZones` as `{ x, y, w, h }`. They appear in bright green, are constrained to the map bounds, block respawning, and steer active monsters through the nearest rectangle edge. Older nested `spawns.safeZones` arrays remain supported when loading existing maps.

Enemy camps are stored in map-level `enemySpawnAreas`. Each area has an amber
`stayPerimeter` and containing cyan `pursuePerimeter`, both either circles or
rectangles. Areas are visible only with the Enemy Area tool. Runtime refills an
active camp from its own weighted roster and cooldown; leaving the pursue
perimeter makes its enemies return home instead of following the player across
the map. Maps without authored camps continue using the legacy random spawn
configuration until they are migrated.

## Saving and validation

Save is intentionally available only in development. The Vite endpoint:

1. Accepts a maximum 2 MB JSON payload.
2. Runs structural map validation.
3. Verifies terrain, object, enemy, connection, and target-map references.
4. Resolves the filename from the validated `mapId`; it never accepts a path from the browser.
5. Writes a temporary file and atomically renames it over the existing map.

After editing, run:

```powershell
pnpm maps:check
pnpm check
```

## Creating another map

Click **New map** beside the document selector, then choose:

- A unique kebab-case map ID.
- Columns, rows, and tile size.
- The base terrain used to fill the new ground layer.

Creation never overwrites an existing map. The editor writes the validated `<map-id>.map.json`, opens it immediately, and uses the same save workflow as every other authored map. Connect it through the Map Connections dropdowns to make it reachable. Maps without curated `Area.ts` metadata receive a deterministic name, seed, and meadow biome fallback until custom metadata is added.
