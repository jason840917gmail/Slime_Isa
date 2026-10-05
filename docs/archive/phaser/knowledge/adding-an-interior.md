# Adding an Interior (a house you can enter)

How the Gloop Forest hut (roadmap 8.8) was added, as the recipe for the next
interior. An interior is a small world scene linked to an outdoor world by a
pair of doors.

## Pieces

| Piece | Gloop Forest hut |
|---|---|
| Interior world scene | `content/scenes/authored/worlds/gloop-hut.scene.json` (`world.gloop-hut`, 14 × 11 tiles, `cameraMode: fixed`) |
| Legacy map (save validation, new-run checks) | `content/maps/gloop-hut.map.json` (same `mapId`, size and spawn as the scene) |
| Outdoor door | nodes `hut-door` (position at the house's door step), `door-script` (`game.door`: `targetAreaId: gloop-hut`, `targetDoorId: house-door`), and a child named exactly `arrival` (where the slime appears when it comes out) |
| Indoor door | the same three nodes in the interior (`house-door` → `targetAreaId: gloop-forest`, `targetDoorId: hut-door`) |
| Bed | any instance of a bed scene (`game.bed`); sleeping in it stores `world.<mapId>.<instanceId>` as the respawn point |
| Room sound | a rule in `scripts/audio/wire-scene-audio.mjs` (the interior ambience bed), then `pnpm audio:wire` |

The outdoor house is any house prop; the door is a separate node in the
outdoor world, so the house scene itself needs no change. The hut reuses the
blue cottage already standing in Gloop Forest's camp.

## Steps

1. Write `content/maps/<id>.map.json` (copy an interior's and change `mapId`).
2. Register the map for conversion: add `map:<id>` to `sliceUnitKeys` in
   `scripts/convert-scenes.mjs`, run
   `node scripts/inventory-scene-conversion.mjs --sync`, then
   `node scripts/convert-scenes.mjs --unit map:<id> --apply`. This writes the
   bare world scene and its mapping report (`reports/worlds/<id>.mapping.json`)
   that `test:scene-integration` checks. Set the ledger row's `writerState` to
   `scene`, then `node scripts/rehash-scene-ledger.mjs` and
   `node scripts/reconcile-scene-ledger.mjs --write`.
3. Furnish the room in Scene Studio (`?studio=scenes&scene=world.<id>`): add
   instances of `object.interior-*` scenes, a bed, and the door nodes; save.
   The hut was instead copied from the Slime Home's furnished scene by a script
   (renamed IDs, one bed removed), because an agent cannot place furniture
   reliably by dragging in the Studio canvas headless. No Studio blocker was
   found; the Studio route has not been tried for this room yet.
4. Add the outdoor door nodes to the outdoor world (Studio or script). The
   arrival child must be named `arrival`.
5. Production worlds are listed in `scripts/tests/scene-content/discovery-plugin.test.mjs`
   (a dev-only world goes in `content/scenes/devOnlyWorlds.ts` instead), and a
   new map raises the map count in `scripts/tests/scene-integration/world-scenes.test.mjs`.
   A bed belongs in `scripts/tests/progression/respawn-destination.test.mjs`.
6. Run `pnpm assets:worlds`, `pnpm audio:wire`, then `pnpm typecheck`,
   `scenes:check`, `maps:check`, `audio:check`, `scene-ownership:check`,
   `test:scene-conversion`, `test:scene-integration`, `test:scene-content`,
   `test:progression`.

## Checked

Played headless on 2026-10-01: from Gloop Forest the hut door led into the
room, sleeping in its bed set the respawn point to `world.gloop-hut.west-bed`,
and the room's door led back out beside the cottage.
