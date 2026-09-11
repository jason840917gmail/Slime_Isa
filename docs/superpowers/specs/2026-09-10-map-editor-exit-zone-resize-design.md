# Map Editor Exit Zone Resize and Selection Design

## Status

Approved design for the Level 1 Map Studio exit-zone bug.

## Problem

Level 1 was resized from 24×18 tiles to 56×56 tiles. The resize logic scales
pixel coordinates but does not preserve an exit zone's relationship to the map
boundary. The existing east exit therefore remains around `x = 1504`, which
is inside the new 3584-pixel-wide map instead of on its east edge.

The editor compounds this in three ways:

- `exitDirection` only recognizes zones that span an entire boundary. The
  original Level 1 exit is a valid partial east-edge segment, so it is not
  considered a connection.
- `connectionAt` and `setConnection` cannot recover a stale interior zone,
  even though its reciprocal `entry` value identifies the intended cardinal
  direction.
- The overlay renderer draws every raw exit, but pointer handling has no exit
  hit test, selection state, or move operation. The visible rectangle is
  therefore neither represented by the connection controls nor editable on the
  canvas.

The authored map format remains unchanged: exits continue to store `{ zone,
to, entry }`, and cardinal direction remains derived rather than persisted as a
second field.

## Goals

1. Keep an existing exit on its original cardinal edge when map dimensions or
   tile size change.
2. Recognize both full-edge zones and partial edge segments as cardinal
   connections.
3. Recover already-stale Level 1 zones from their reciprocal entry direction.
4. Make existing exit zones selectable and movable along their edge in the
   `Select / Move` and `Exit Zone` tools.
5. Make the Map Connections controls and canvas overlays use the same
   connection interpretation.
6. Repair the current Level 1 duplicate east records without overwriting the
   user's unrelated map-size, terrain, or enemy-area changes.

## Non-goals

- No new exit IDs, direction fields, or schema version.
- No arbitrary interior exits or free-form exit-zone authoring.
- No reciprocal-map transaction changes; the existing map save contract stays
  intact.
- No changes to runtime transition behavior beyond receiving the repaired
  authored zone.
- No unrelated cleanup of the user's modified Gloop Forest, weapon files, or
  verification checklist.

## Design

### 1. Shared exit-direction and geometry helpers

Extend `src/game/editor/MapConnections.ts` with one consistent interpretation
of an exit's local cardinal direction. Expose two deliberately different
helpers:

- `edgeDirectionForZone(zone, map)` performs geometry-only classification for
  spatial diagnostics and edge attachment.
- `exitDirection(exit, map)` is the connection resolver. The authored
  reciprocal `entry` is authoritative: when it is a valid cardinal direction,
  return `OPPOSITE_DIRECTION[exit.entry]`, regardless of whether the rectangle
  is currently stale or touching a different boundary. If `entry` is invalid,
  return `undefined` for connection purposes. No caller may replace this with
  a geometry-first heuristic.

- Boundary contact uses a one-pixel tolerance: west/east contact means
  `x <= 1` / `x + w >= width - 1`, and north/south contact means
  `y <= 1` / `y + h >= height - 1`.
- Resolver precedence is explicit:

  | Zone geometry | Result |
  | --- | --- |
  | Full height, west contact only | west |
  | Full height, east contact only | east |
  | Full width, north contact only | north |
  | Full width, south contact only | south |
  | Not full-span, exactly one boundary contact | that boundary |
  | Any other multi-boundary case, including a partial rectangle touching a corner | unresolved |

  A zone spanning both dimensions is also unresolved for geometry diagnostics.
  Full-span checks happen before the exactly-one-boundary rule so full-edge
  zones touching two corners still have a deterministic spatial orientation.
- More formally, let `west`, `east`, `north`, and `south` be the four contact
  booleans above, `fullHeight = h >= height - 1`, and
  `fullWidth = w >= width - 1`. `edgeDirectionForZone` evaluates
  `fullHeight` first (west-only/east-only), then `fullWidth`
  (north-only/south-only), then the exactly-one-contact cases, and otherwise
  returns `undefined`. `exitDirection` does not call this geometry helper;
  its exact rule is `isMapDirection(exit.entry) ?
  OPPOSITE_DIRECTION[exit.entry] : undefined`.

`connectionAt`, the directional filtering used by `setConnection`, and the
Map Studio save endpoint in `vite.config.ts` (`connectionTarget` plus
reciprocal cleanup) must import and call the same `exitDirection` resolver from
`src/game/editor/MapConnections.ts`. `MapConnections.ts` remains Node-safe: it
contains only map types and pure functions, with no Phaser, DOM, or scene
imports. Replacing a connection therefore removes stale and duplicate records
for that direction before writing the canonical edge zone. This makes save-time
reciprocal updates use exactly the same semantics as the editor dropdown.

Save reciprocal cleanup is precise: when a previous target changes, remove
every exit in the previous target map whose resolved direction is reciprocal
and whose `to` equals the current map ID. When a next target is present, reject
any reciprocal-direction exit in that target map whose `to` is a different map;
then remove all reciprocal-direction exits whose `to` is the current map ID and
append one canonical reciprocal exit. This preserves the existing conflict
diagnostic while eliminating same-target duplicates.

`edgeExitZone` must derive an integer, contained lane:
`lane = max(1, min(32, floor(tileSize / 2)))`. Since map dimensions and tile
size are positive integers, the resulting full-edge rectangle is always
integer-valued and contained, including one-tile maps and odd tile sizes.

### 2. Resize and load repair in `MapEditorState`

Before changing the map dimensions, resolve each exit's old direction and
re-anchor its zone to the corresponding new boundary:

- Let `scale = nextTileSize / currentTileSize`, and first scale each zone
  coordinate and dimension with `round(value * scale)`, keeping every width
  and height at least one pixel.
- For west/east exits, first clamp the scaled fixed-axis thickness with
  `w = min(nextWidth, max(1, round(oldW * scale)))`, then clamp `h` to
  `min(nextHeight, max(1, round(oldH * scale)))`. Set `x` to `0` for west or
  `nextWidth - w` for east, and clamp `y` to `0..nextHeight - h`.
- For north/south exits, first clamp the scaled fixed-axis thickness with
  `h = min(nextHeight, max(1, round(oldH * scale)))`, then clamp `w` to
  `min(nextWidth, max(1, round(oldW * scale)))`. Set `y` to `0` for north or
  `nextHeight - h` for south, and clamp `x` to `0..nextWidth - w`.
- Keep the fixed coordinate on the new boundary.
- If the old zone covered the whole relevant perpendicular dimension (within
  the one-pixel tolerance), as evaluated against the old map dimensions before
  scaling, regenerate the full edge zone using `edgeExitZone`, including the
  new tile-size-derived lane width.
- For partial zones, clamp the scaled tangent dimension to the new map extent
  before clamping its tangent position. A segment always remains at least one
  pixel wide and high.
- Leave an exit unchanged except for normal scaling when no direction can be
  resolved.

The same repair helper runs against the cloned map when the editor loads with
`scale = 1`, so it reattaches legacy interior zones without writing to disk
automatically. Constructor ordering is explicit: clone the authored map, apply
the existing compatibility initialization and enemy-area normalization, capture
that result as the saved baseline, then apply exit repair. This keeps the
current behavior for optional-array initialization while ensuring only exit
repair marks the document dirty. If repair changed anything, the editor starts
dirty with a save-needed status; no synthetic undo entry is created. The first
user mutation records the repaired state normally, and undo does not silently
revert the automatic repair. A successful save replaces the baseline with the
repaired snapshot and clears dirty state. A failed save leaves both the
baseline and dirty state unchanged.

The current Level 1 authored file will also be repaired directly: retain the
original partial east segment, move it to the 56×56 east boundary, and remove
the duplicate east record with the same target and entry.

Exit repair must not alter objects, terrain, player spawn, player entries,
enemy zones, NPC areas, or spawn rules except for the existing resize scaling
already defined by the editor.

### 3. Exit selection and movement

Add `selectedExitIndex?: number` to `MapEditorState`, including selection
clearing when another content type is selected. Exit array index is the
in-memory identity because the map format has no exit ID and is intentionally
unchanged. Exit mutations validate that the selected index still exists and
that its `to`, `entry`, and complete original zone snapshot match the drag's
captured signature. The drag also captures the state's map revision and rejects
the update if any other mutation occurred before release. This prevents an
array-index reuse from editing a different duplicate. Undo/redo and connection
replacement clear exit selection. Add a mutation for updating one exit's zone.
The state readout and selection marker should identify the selected direction
and destination.

The captured revision is the existing `MapEditorState.revision` value. Every
successful `mutate`, resize, connection replacement, exit move, undo, and redo
increments it; no-op mutations, save attempts, and selection-only changes do
not. A stale exit release returns `false`, clears the exit selection, destroys
the draft, and reports that the map changed while the drag was active. The
automatic load repair leaves revision at zero and is guarded by the captured
zone snapshot rather than an undo entry.

In `MapEditorScene`:

- Add an `exitAt` hit test over the raw exit zones, using the recovered edge
  position after load repair. Iterate from the last exit to the first so
  overlapping exits have deterministic topmost-array-order behavior.
- In both `Select / Move` and `Exit Zone`, prioritize the topmost exit hit
  before object movement. An unresolved exit may be selected for diagnosis but
  cannot be moved; a resolved exit enters the move interaction. In `Exit
  Zone`, clicking empty map space retains the existing “choose a connection
  first” diagnostic. In `Select / Move`, an empty exit hit falls through to
  the existing object/empty-map behavior.
- Dragging moves only along the exit's cardinal edge. The fixed edge
  coordinate and zone size are preserved; the tangent coordinate is clamped to
  map bounds and snapped to the map tile size. At drag start, capture the
  pointer's tangent offset from the zone origin. On every move, set the tangent
  origin to `round((pointerTangent - grabOffset) / tileSize) * tileSize`, then
  clamp it to `0..mapExtent - zoneExtent`. This prevents a pointer grab from
  jumping the zone. The preview uses world coordinates from
  `cameras.main.getWorldPoint`, while the movement threshold is measured in
  screen-pointer pixels with
  `Math.hypot(pointer.x - startScreenX, pointer.y - startScreenY) >= 2`, so
  zoom does not change click-vs-drag behavior. Latch `thresholdCrossed = true`
  the first time the two-pixel displacement is reached; do not clear it if the
  pointer later returns closer to the start. On pointer release, commit only
  when `thresholdCrossed` is true and the final snapped zone differs from the
  original. The preview is scene-only graphics; if the threshold was never
  crossed, or Escape cancels the drag, destroy the preview and redraw the
  original zone. A click therefore selects the exit without dirtying it even
  when snapping would have changed a non-aligned preview.
- Commit one undoable mutation on pointer release. Full-edge zones have a zero
  tangent range and therefore remain selectable but do not move.
- Render a clear selection marker for the active exit while retaining the
  normal amber exit overlay.

The tool will not allow a connection zone to be dragged into the map interior,
which keeps the spatial editor and the connection dropdowns consistent.

### 4. Panel copy and diagnostics

Update the editor help/selection copy to explain that Map Connections chooses
the destination and Exit Zone moves the edge segment. When a stale exit is
recovered, show a concise save-needed status rather than silently implying
that the dropdown created a new link.

Unresolved exits remain visible as amber diagnostics but do not appear in a
directional connection dropdown and cannot be moved until their data is
corrected. This avoids inventing a cardinal direction for malformed content.

## Data flow

```text
authored map JSON
      │
      ▼
MapEditorState load repair ──► repaired in-memory edge zones
      │                                  │
      ├──────────────► Map Connections ◄─┘
      │                         │
      ▼                         ▼
canvas overlay/hit test   dropdown target selection
      │                         │
      └──────────► state mutation / undo / save
```

The resolver is the single source of truth for editor direction lookup,
connection replacement, resize re-anchoring, and exit hit-test movement.

## Error handling

- Invalid dimensions continue to be rejected before mutation.
- Exit segments are clamped so resizing cannot leave a repaired zone outside
  the map.
- An exit with an invalid or missing reciprocal entry is left untouched and is
  excluded from connection lookup, with a visible diagnostic status when the
  editor encounters it.
- Replacing a direction through the dropdown removes all resolvable exits for
  that direction, preventing stale duplicates from remaining hidden behind the
  new connection.
- Save validation remains authoritative. A validation rejection from
  `/__map-editor/save` occurs before temporary files are written and leaves
  persisted maps unchanged. Any HTTP, transport, or JSON-response failure
  leaves the in-memory map, `savedSnapshot`, dirty flag, undo stack, and redo
  stack unchanged; the user can correct the map or undo it. A successful save
  updates the source map and any reciprocal files returned by the existing
  endpoint, then replaces `savedSnapshot` with the source map's current
  serialization without clearing undo history. Multi-file rename atomicity is
  existing server infrastructure and is not expanded by this fix. If the
  transport fails after the request is sent, the client reports “save outcome
  unknown—reload before retry” and does not auto-retry; the user can reload to
  reconcile persisted reciprocal files before making another save attempt.

## Verification

Add focused map-editor tests for:

1. Full west/east/north/south edge zones.
2. Partial edge segments, including the original Level 1 east segment.
3. Stale interior zones recovered from `entry`.
4. Resize re-anchoring, scaling, clamping, and full-edge regeneration.
5. Directional replacement removing stale/duplicate exits.
6. Exit selection and tangent-only movement with undo behavior.
7. Invalid entries remaining unresolved.
8. Corner ambiguity and the one-pixel boundary tolerance.
9. Load-repair dirty status, saved-baseline behavior after existing constructor
   normalization, selection clearing, and failed-save preservation.
10. Level 1's repaired map containing one east record for the Gloop Forest
    target/entry pair.

Place the pure connection/resize/state coverage in
`scripts/tests/map-editor/exit-zones.test.mjs`; the existing `test:map-editor`
script already runs all files in that directory, so the focused command is
`pnpm test:map-editor`.

The focused cases must assert these concrete outcomes:

| Case | Expected result |
| --- | --- |
| 24×18, 64px tiles; `{ x: 1472, y: 512, w: 64, h: 128 }`, entry west | geometry and connection direction east |
| Resize that segment to 56×56, 64px tiles | `{ x: 3520, y: 512, w: 64, h: 128 }` |
| 56×56 stale `{ x: 1504, y: 0, w: 32, h: 1152 }`, entry west | geometry may see north contact, but connection direction is east from entry; repair to `{ x: 3552, y: 0, w: 32, h: 1152 }` |
| 24×18 full east edge resized to 56×56 | `{ x: 3552, y: 0, w: 32, h: 3584 }` |
| Shrink an east zone with `w = 128` to a 1×1 tile map | `w = 64`, `x = 0`, and all coordinates remain contained |
| `edgeExitZone('east', { columns: 1, rows: 1 }, 1)` | integer contained zone `{ x: 0, y: 0, w: 1, h: 1 }` |
| Partial zone touching east and north but not spanning a dimension | unresolved geometry diagnostic; valid entry still resolves the connection direction |
| Zone within one pixel of one boundary | classified as that boundary |
| Partial zone touching two boundaries without a full span | unresolved geometry |
| Edge zone with invalid `entry` | geometry helper may classify it, but `exitDirection` returns unresolved |
| Two overlapping exits | last array entry is selected; no random selection |
| Screen movement under two pixels with snapped preview changed | preview rolls back; no mutation and no dirty flag |
| Pointer crosses two screen pixels, returns below two, and releases changed | latched threshold still commits the changed snapped zone |
| Map revision changes during an exit drag | release is rejected and the captured exit remains unchanged |
| Save validation/HTTP/transport failure after automatic repair | map contents, baseline, dirty flag, undo stack, and redo stack remain unchanged |

The save-endpoint coverage must also verify that a repaired Level 1 east
connection creates/replaces only the reciprocal Gloop Forest west record and
that an invalid `entry` is not treated as a connection.

Run the focused tests plus:

```text
pnpm maps:check
pnpm typecheck
pnpm build
pnpm check
```

Manual acceptance in the running Map Studio:

1. Open Level 1 at 56×56 and confirm one east exit is on the outer east edge,
   not in the middle.
2. Confirm the east connection control reads Gloop Forest.
3. Drag the exit with `Select / Move` and confirm it slides vertically along
   the east edge, remains selected, and can be undone.
4. Resize the map again and confirm the exit remains edge-anchored.
5. Save, reload, and confirm the repaired zone and connection persist.
