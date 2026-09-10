# Inventory Drop Search and Stacking Design

**Status:** Implemented and verified on 2026-09-10.

## Problem

Inventory drops currently inspect only a small fixed ring. When every candidate
is occupied, the drop fails while the inventory remains over the world message.
Compatible resource piles are also treated as blockers even though adding to
the existing stack is clearer than creating another pile.

## Placement

Search deterministic Chebyshev rings from radius two through the whole map.
Within each ring, prefer cells in the player's facing direction. Radius one is
excluded so the player's pickup body does not immediately recollect a landed
item.

Each inspected cell is one of:

- `open`: land at the cell's ground anchor;
- `compatible-stack`: land at the exact anchor of a dynamic pile containing
  the same item;
- `blocked`: continue searching.

Solid terrain, authored objects, and different-item collectibles are blocked.
Existing same-item inventory drops count as compatible even while launching,
so rapid drops converge on one destination. If the entire map has no open or
compatible cell, the operation safely rolls back.

## Landing merge

Every inventory action still creates a persistent incoming drop before the
shared world-drop animation begins. On landing, collectible registration checks
for an existing same-item dynamic pile at the same ground cell. If found, it
adds the incoming amount to that pile, persists the target owner's new amount,
sets the incoming owner to zero, and removes the redundant visual.

Only owner-backed resource and inventory piles merge. Static authored pickups
do not, which avoids changing their fixed quantity semantics. If the target is
collected before the incoming item lands, the incoming drop simply becomes the
new pile. Reloading during flight restores the incoming record settled, where
the same registration merge runs.

## Feedback

After the player presses an enabled Drop button, close the inventory whether
the transaction succeeds or safely rolls back. This exposes world feedback.
Drop-specific failure messages remain visible for approximately 1.8 seconds.

## Verification

- Placement expands beyond the initial ring and remains deterministic.
- Same-item dynamic piles are accepted; incompatible occupants remain blocked.
- Landing merges quantities and updates resource or inventory persistence.
- Interrupted/reloaded and rapid drops cannot lose quantity.
- A completely blocked map rolls inventory back and exposes the longer error.
- Existing collectible, persistence, content, typecheck, and build checks pass.
