# Global map and map joining

## Status

Open — the current world-map UI exists, but this idea covers a fuller world
map that explains connected authored maps and supports a player-facing travel
view.

## Goal

Give players and level designers one stable view of the connected world. The
map should show discovered areas, their links, the current area, and the
player's position without merging separate map files into one oversized scene.

## Proposed scope

- Read the map graph from authored map connections and stable area IDs.
- Show undiscovered areas as silhouettes and discovered areas with their names,
  biome colors, exits, and completion markers.
- Keep the editor's map view focused on one document while offering a link to
  neighboring map documents.
- Make the player-mode world map open and close without changing the active
  scene, pausing simulation while it is visible.
- Preserve exact map-local coordinates when crossing an authored connection.

## Open decisions

1. Whether travel is always performed by walking to an exit or whether the
   world map may fast-travel to previously discovered areas.
2. Where discovery and completion state is persisted in the save model.
3. How locked exits, quest gates, and one-way connections are presented.
4. Whether the map uses hand-authored panel artwork or generated graph geometry.

## Acceptance criteria

- Every production map appears once in the graph with stable neighboring links.
- A player can identify the current area and all discovered exits.
- Opening and closing the map never loses player position or scene state.
- Editor and runtime use the same connection source of truth.
