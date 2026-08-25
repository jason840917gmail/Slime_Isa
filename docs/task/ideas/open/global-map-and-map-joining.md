# Shared world map and Map Studio graph

## Status

Open — the runtime has a node-based discovered-area popup and Map Studio can
edit cardinal connections with dropdowns. This task upgrades both surfaces
without creating a second connection model.

## Goal

Give players a useful representation of the full discovered world and give
designers a visual graph for previewing, arranging, opening, and connecting all
authored maps.

## Shared graph contract

- Authored map exits and stable map/area IDs remain the connection source of
  truth. The player map and Map Studio graph are projections of that data.
- A separate layout record may store graph-card positions and presentation
  metadata, but it must never redefine gameplay neighbors.
- The first implementation supports reciprocal cardinal links only:
  north ↔ south and east ↔ west. One-way and non-cardinal travel remain an
  explicit future extension.
- Creating, replacing, or deleting a visual connection updates both map
  documents transactionally and validates target entry points.
- Broken references, duplicate directional exits, self-links, and mismatched
  reciprocal links are rejected before save.

## Map Studio organizer

- Show every authored map once as a draggable card with name, biome, dimensions,
  validation status, and a generated thumbnail preview.
- Allow cards to be arranged freely without changing map-local coordinates.
- Expose north, east, south, and west connector ports on each card.
- Drag from a port to a compatible target port to create or replace a connection;
  show the reciprocal edge before confirmation.
- Select an edge to inspect or delete it. Double-click or use **Open map** to
  enter the existing single-map editor.
- Keep the current connection dropdowns as an accessible and compact fallback;
  both surfaces call the same connection command.

## Player world map

- Replace the small abstract popup with a responsive full-screen world view
  generated from the same graph and saved layout.
- Show the current area, player location within that area, discovered exits,
  biome identity, locks, and useful completion markers.
- Undiscovered areas appear only as silhouettes when adjacency has been learned;
  completely unknown branches remain hidden.
- Opening the map pauses simulation and closing it restores the same local
  player and scene state.
- Walking through authored exits remains the default travel rule. Fast travel
  is deferred until its unlock and safety rules are designed.

## Implementation slices

1. Extract a validated, read-only world-graph projection from authored maps.
2. Add persisted presentation layout independent from gameplay links.
3. Build Map Studio cards, previews, arrangement, and shared edge commands.
4. Add transactional reciprocal connection editing and clear diagnostics.
5. Rebuild the player world map from the shared projection.
6. Add discovery, lock, completion, resize, save/load, and transition tests.

## Acceptance criteria

- Every production map appears exactly once in Map Studio’s graph.
- Visual connectors and existing dropdowns edit the same authored exits.
- A cardinal connection is reciprocal, valid, and saved atomically.
- Rearranging graph cards never moves content inside a map.
- The player map clearly identifies the current area and discovered travel
  choices without exposing fully unknown content.
- Editor, validator, and runtime derive neighbors from the same source of truth.
- Opening and closing either map surface does not lose gameplay or editor state.
