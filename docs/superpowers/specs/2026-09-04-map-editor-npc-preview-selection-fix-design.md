# Map Editor NPC Preview and Selected Wander-Area Fix

## Goal

Make the Level 1 Map Editor preview render both authored NPC placements, including Mossy Scout, while showing a wander area only for the currently selected NPC or explicitly selected NPC area.

## Current causes

- `MapEditorScene.createNpcEditorPreview` passes the NPC catalog definition ID to the preview adapter as though it were the character package ID. This is accidentally correct for Village Elder Plop, whose IDs match, but fails for Mossy Scout (`level-1-spider-giver` definition versus `mossy-scout` character package).
- `renderMapMarkers` only renders NPC wander areas while the `npc-area` tool is active, so selecting an NPC with the normal Select / Move tool does not reveal its personal area. When the tool is active, it renders every NPC area instead of only the selected owner’s area.

## Approved behavior

### NPC placement preview

NPC placement previews resolve through the placement choice’s `characterId`. The archetype’s NPC definition ID remains the catalog/quest identity and is not used to resolve character art. Both Level 1 NPC objects therefore render through the authored character packages, using the existing `NpcPlacementPreview` adapter and its existing frame/origin/scale behavior.

### Wander-area visibility

The editor derives the visible NPC area from the current selection:

- If a placed NPC is selected, show only that NPC’s personal wander area, if one exists.
- If an NPC wander area is explicitly selected, show that area as the selected area while its owner NPC remains selected. This is the authoritative selection when both IDs are present.
- If no NPC or NPC area is selected, show no NPC wander-area overlay.
- The area remains visible in the normal Select / Move tool so selecting the Elder or Mossy placement gives immediate visual feedback.
- The NPC Area tool remains the only tool that creates, moves, resizes, or deletes wander areas. Its editing mechanics and lavender styling remain unchanged.

The overlay resolver requires the selected area’s owner to match the current selected NPC. Selecting empty map space or another NPC hides the old area even if a stale area ID remains in editor state. Calling the existing `selectNpcWanderArea` API continues to establish the area’s owner NPC as the selected instance, so explicit area selection remains coherent without adding another persistent selection field. Selecting an NPC does not implicitly change the area-selection state used by delete and editing commands.

## Implementation boundary

Modify only the Map Editor preview argument and NPC area overlay-selection logic, plus focused regression coverage. Do not change NPC catalog IDs, authored map coordinates, runtime NPC behavior, area validation, or the ordinary object preview path.

## Verification

- Add a source-level or focused editor regression asserting that the Elder placement resolves through `village-elder-plop` and the Mossy placement resolves through `mossy-scout`, not `level-1-spider-giver`.
- Add a regression covering selected-only area visibility: selecting Elder shows exactly Elder’s area, selecting Mossy shows exactly Mossy’s area, and an empty/no selection shows none.
- Add a regression for explicit area selection through the NPC Area tool, confirming that only that owner’s area remains visible while the other NPC area is suppressed.
- Confirm both NPC sprites remain visible in Select / Move, NPC Area, NPC selection, area selection, and empty-selection states; only the selected owner’s area changes visibility.
- Confirm a stale explicit area ID cannot keep an overlay visible after deselecting its owner or selecting the other NPC.
- Run `pnpm test:map-editor`, `pnpm typecheck`, `pnpm objects:check`, and `pnpm maps:check`.
- Manually inspect Level 1 in the Map Editor: both NPC sprites appear on load; selecting Elder shows only Elder’s area; selecting Mossy shows only Mossy’s area; selecting empty space hides both areas; the NPC Area tool still edits the selected area.
