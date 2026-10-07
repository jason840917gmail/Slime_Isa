# Mouse control schemes (experiment)

Branch `exp/mouse-controls`, started 2026-10-06. The owner wants the mouse to matter more on PC, the
way it does in Diablo or Dota, or not at all. Five control schemes can be switched while playing,
so they can be compared side by side. The keyboard scheme is the original game and stays the
default.

| Scheme | Walk | Left click | Right click |
|---|---|---|---|
| `keyboard` (default) | WASD | swing toward the pointer | use the target in reach |
| `click` — Diablo | click the ground; hold to follow the pointer | **order** | **use**: what's under the pointer (walking there), else the target in reach |
| `moba` — Dota / LoL | right-click the ground; hold to follow | swing in place toward the pointer | **order** |
| `pointer` — face the pointer | **W** (or ↑) walks toward the pointer; A, S, D and clicks never move | swing toward the pointer | use the target in reach |
| `keys` — keys only | the **arrows**; **A** attacks, **W** interacts, **S** / **D** switch weapons | nothing | nothing |

**Switching:** press **F2** in game (`control_scheme_next`; the new scheme's name floats over the
slime), or use the **Mouse** button in Settings. The choice is saved with the other settings in
`user://settings.cfg` (`control_scheme`).

## What an order does

What the order button is pressed on decides what happens
([pointer_targets.gd](../../godot/game/player/mouse/pointer_targets.gd)), checked in this order:

1. **An enemy or a resource** (a tree, a rock: anything with a hurtbox in the `enemy` /
   `resource_node` groups, within `input.mouse.pickRadiusPx` of the pointer): the slime walks
   until a swing toward that side would reach the target's hurtbox
   (`WeaponScript.reaches`, a physics query with the weapon's own attack shapes), or until it is
   within `meleeFallbackPx`. Then it faces that side and swings. While the button is held it keeps
   swinging as fast as the weapon allows; once the button is up, the order ends after that swing.
   The cursor shows a cross and a red ring lies under the target.
2. **Something usable** (a door, a gate, a chest, an NPC, a bed, a bench, a restoration site or a
   Gulp spot, picked like the keyboard scheme's pointer pick but anywhere on screen,
   `InteractionController.target_at`): the slime walks there. The interaction controller keeps
   that target chosen (`set_preferred`) and uses it as soon as it is in reach. If the button is
   still held, a target with a hold action ("Hold: Pick up") does its hold action. The cursor
   shows a hand and a gold ring lies under the target.
3. **The ground:** the slime walks to the point. Holding the button keeps walking toward the
   pointer, re-planning the route every `followRepathMs`. A green ring marks the point.

Also:

- **Right click in the click scheme (owner, 2026-10-06):** it interacts, it never swings. On
  something usable under the pointer it walks there and uses it, like a left click. Otherwise it
  uses the target in reach, as the keyboard scheme's right click does, and holding it runs the
  target's hold action ("Hold: Pick up"). Shift + left click is the click scheme's swing in place.
- **Keys still work:** WASD, Space, 1–4, Q, the wheel and the rest do what they do in the keyboard
  scheme. A movement key ends the order.
- **Actions end the order:** dodge, lash, slam, teleport, eat, interact and a swing in place
  end the order. A jump does not: without movement keys it goes the way the slime is walking,
  and the walk goes on from where it lands.
- **Placing furniture** keeps the keyboard scheme's buttons: left click places, right click
  cancels.
- **Prompts and hints follow the scheme:** prompts read "Click: Open chest" in the click scheme
  and "Right-click: ..." in the moba scheme. The first-time hints and the Controls list follow the
  scheme too.

## The pointer scheme

Asked by the owner on 2026-10-06. The slime always faces the pointer, and only **W** (`move_up`,
so ↑ too) walks: forward, toward the pointer. A, S and D don't move it, nor does any click. The
left button swings toward the pointer and the right button uses the target in reach, as in the
keyboard scheme.

- **Facing:** every physics step the slime turns to the pointer (`player.gd` `_face_pointer`,
  from the aim origin), except while it rolls, is knocked back, swings or is busy with an
  ability: those set their own facing. Idle and walk clips follow it (down, up or side).
- **Walking:** W walks along the pointer's direction (`_movement_input`) at the normal speed
  (Shift sprints). The slime stops when the pointer is within the aim's dead zone (16 px), so it
  stands under the pointer instead of turning around over it. Before the pointer has ever been
  seen, W walks the way the slime faces.
- **Jump:** with W held, the jump goes toward the pointer. The dodge, lash and teleport aim at the
  pointer as in every scheme.

## The keys-only scheme

Asked by the owner on 2026-10-06: no mouse at all. While it is on, the InputMap is rebound
([key_bindings.gd](../../godot/game/player/mouse/key_bindings.gd), applied by GameSettings
`apply_to_input` at start-up and on every change). Every other scheme puts project.godot's
bindings back exactly. The Controls list, the hints and the prompts read the InputMap, so they
show the new keys by themselves ("Press W: Open chest").

| Action | Key | Was |
|---|---|---|
| Walk | ↑ ← ↓ → | WASD or the arrows |
| Attack | A | left click |
| Interact (hold to pick up furniture) | W | right click |
| Previous / next weapon | S / D | the mouse wheel |
| Sprint, jump, dodge, lash, slam, teleport, eat, bag, map, zoom, pause | unchanged: Shift, Space, 1, 2, 3, 4, Q, E, M, = / -, Esc | |

What needed the mouse, and what it does without it:

- **Aiming:** the swing, the dodge and the Stretch Lash go the way the slime faces, which is the
  last direction it walked: 8 ways, with the swing and the dodge snapped to 4. The pointer aims
  nothing in this scheme (`player.gd` `_pointer_aim`).
- **Teleport:** it always goes its full range the way the slime faces. With a mouse it stops at
  the pointer.
- **Choosing what to interact with:** the pointer no longer picks among several targets in
  reach. The highest priority wins, as with no mouse (the interaction controller).
- **Placing furniture:** the bench's ghost stands 80 px in front of the slime, and walking moves
  it (`furniture_placement.gd` `_aim_point`). A places, S / D switch the variant, W or Esc cancels.
- **The Gulp quick wheel** (hold Q): the arrows pick the slot.
- **Windows** (bag, crafting, chest, journal, map, dialogue): they already had keyboard focus.
  The arrows move between buttons, Enter or Space presses them, and Esc closes. Dialogue also
  advances on W. The bag's belt can be filled from its assignment buttons, so the drag and drop
  isn't needed. The chest takes a stack with its Take Stack button or the menu key.
- **Mouse buttons and the wheel** do nothing in play. Windows still take clicks.

## Walking: routes

[click_path.gd](../../godot/game/player/mouse/click_path.gd) finds the shortest way the slime can
walk. It searches with Lazy Theta*, an any-angle A*, over every ground level at once. The owner's
second round of feedback (2026-10-06) asked for three things, and this version does all three:
shortest routes, routes through any gap the slime fits, and routes that use stairs.

- **Cells:** the grid has `pathCellPx` (24) world px cells. A node is a cell on a level, standing
  at its spot: where the slime's body fits in that cell, using that level's collision. Collision
  is the body's own mask with the level's bit, so walls, props, deep water, NPCs, fences and that
  level's cliffs all block. Enemies are left out, because they move and an attack walks up to one
  anyway.
- **Narrow gaps:** when the body doesn't fit at a cell's centre, the centre is pushed out of what
  it overlaps, as long as it stays in the cell. So a gap as wide as the body is found wherever it
  lies against the grid. The planner uses the body grown by 0.5 px on every side, so a gap needs
  1 px of slack, and routes keep the real body clear of the walls and corners they pass.
- **Steps:** a step between two neighbouring centres is free, because the body's own size covers
  the move. Any other step is checked the way the follower walks it: straight at the next spot,
  sliding along whatever it hits and aiming again. That is how a gap's corners funnel the body in.
- **Straight lines:** each node also tries to reach its parent's parent in a straight line, when
  the body can sweep that line exactly, on one level, without stepping onto stairs of another
  level. So routes are straight lines that bend only at corners. The click itself is reached in a
  straight line when nothing is in the way.
- **Stairs:** stepping onto stairs gives the node the level of that stretch of stairs, just as a
  walking body changes level. Below the goal's level, the search's estimate goes through the
  nearest flight that climbs from that level. That points the search at the stairs without making
  routes any longer.
- **Drops:** from a rim the slime can drop over (`Elevation.ledge_below` and `drop_target`), a
  drop is a one-way step to its landing. Its cost is the distance the slime would walk in the time
  the push and the fall take. So a drop is taken when it's shorter than the stairs. The follower
  leans over the rim for the drop push time (the normal ledge drop) and walks on from the landing.
  Drops are only worked out near the rim and facing the goal, at most `MAX_DROP_CHECKS` per search,
  and cached.
- **Which level a click means:** the slime's own level where it can walk there (for example the
  strip behind a hill, seen from the north), else the ground seen at that point. An attack aims at
  the level its target walks on.
- **Budget:** a search stops after `pathMaxExpansions` nodes or `pathMaxMs` (30 ms). Re-plans while
  the button is held get `followMaxMs` (8 ms). A route that stops short walks to the explored node
  nearest the goal. If the budget ran out first, it plans the rest from there.
- **Walking it:** the follower ([click_orders.gd](../../godot/game/player/mouse/click_orders.gd))
  looks up to two waypoints ahead each step and goes straight there when it can. No progress for
  `stuckMs` re-plans around the waypoint it couldn't reach. Three fruitless re-plans in one place
  end the order, unless the button is held.

Measured in the tests: a gap 1.4 px wider than the slime takes about 1 ms to plan, a climb up the
park's stairs about 13 ms, and a drop off its rim about 3 ms.

Tuning is in `game-constants.json` under `input.mouse`.

## Files

- [game/player/mouse/](../../godot/game/player/mouse/): `control_scheme.gd` (the schemes and
  their buttons), `key_bindings.gd` (the keys-only scheme's InputMap), `click_orders.gd` (one
  order and its walking), `click_path.gd` (routes),
  `pointer_targets.gd` (what is under the pointer), `click_marker.gd` (the ground rings; a
  ground decal in the world's y-sorted root, like the Goo Trail).
- `game/scripts/player.gd`: `_capture_order_buttons`, `_issue_click_order` / `_issue_use`,
  `_run_click_order`, `_steer_click_order`, `_update_pointer_hover`, the pointer scheme's
  `_face_pointer` and `_movement_input`, and F2 (`_cycle_control_scheme`).
- `game/interaction/interaction_controller.gd`: `target_at`, `key_of`, `set_preferred`,
  `is_current`.
- `game/scripts/weapon.gd` / `game/combat/player_combat.gd`: `reaches(direction, area)`.
- Tests: [tests/test_mouse_controls.gd](../../godot/tests/test_mouse_controls.gd) (level-1:
  orders, gaps, the budget) and [tests/test_mouse_paths.gd](../../godot/tests/test_mouse_paths.gd)
  (the playground's Elevation Park: stairs and drops).

## Open questions for the playtest

- **Default:** should a mouse scheme become the default on PC? Keyboard stays the default for now,
  and the tests run in it.
- **Jump:** should Space jump toward the pointer in the mouse schemes (it follows the walk now)?
- **Dodge:** should dodge move to the right button or Space, ARPG style, with jump moving
  elsewhere?
- **Abilities:** should the four abilities move from 1–4 to Q/W/E/R in the moba scheme? Q is eat
  and E is the bag today.
- **Attack-move:** is an "A + click" attack-move (walk, and fight whatever comes in reach) worth
  adding?
