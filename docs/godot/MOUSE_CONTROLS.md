# Controls: keys only

The game has one control scheme: **keys only**, no mouse in play. From 2026-10-06 to 2026-11-25 five
schemes could be switched with F2 to compare them (the keyboard scheme with the mouse, click to move
as in Diablo, right-click to move as in Dota, facing the pointer, and keys only). The owner picked keys
only (2026-10-19: "the winner so far is keys only"; 2026-11-25: "keys only stays, the other schemes
go"), and piece 5 of [the one-combat plan](../design/2026-11-25-weapons-beside-throws.md) removed the
other four, the F2 switch, the Settings window's **Mouse** button, the click routes and their tests.
The experiment's doc is archived in
[docs/archive/2026-11-25-mouse-control-schemes.md](../archive/2026-11-25-mouse-control-schemes.md).

A saved `control_scheme` in `user://settings.cfg` is read no more: every settings file plays keys only.

## The keys-only scheme

Asked by the owner on 2026-10-06: no mouse at all. The InputMap is rebound
([key_bindings.gd](../../godot/game/player/mouse/key_bindings.gd), applied by GameSettings
`apply_to_input` at start-up and on every settings change). The Controls list, the hints and the
prompts read the InputMap, so they show these keys by themselves ("Press W: Open chest").

One layout since 2026-11-25 (the one combat, owner: "S will stay as roll and D will be ability. Q suck
and W interact"; `KeyBindings.LAYOUT`):

| Action | Key | project.godot's binding (under the layout) |
|---|---|---|
| Walk | ↑ ← ↓ → | WASD or the arrows |
| Attack with the weapon (tap for the combo, hold for the charge; on a wall too) | A | left click |
| Roll (the `dodge` action) | S | Space |
| The ability chosen in the bag (`ability_use`) | D | F |
| The Gulp (suck, throw, swallow, spit: `eat`) | Q | Q |
| Interact (hold to pick up furniture) | W | right click |
| Next weapon (the weapon scroll; no key goes back) | E | the mouse wheel, and E |
| Bag (weapons, abilities and skins are chosen there), journal, map, zoom, pause | unchanged: B, J, M, = / -, Esc | |

Owner, 2026-10-08: every action of the planned HUD console has a letter
([HUD console mockup](../design/2026-10-07-hud-console-mockup.md#keys), roadmap 4.12): B opens the
bag (it was E), J the journal, and E is the weapon scroll.

Before 2026-11-25 three layouts were stacked: this one, the rework's (`REWORK_LAYOUT`: the ability on
S, the Roll on D) and the throw mode's (`THROW_LAYOUT`: Q the Gulp, S the Roll, A the ability, E the
ability carousel, the attack with no key). The rework's own input layer (`game/shapes/rework_input.gd`:
no number keys, the Roll on Space, the box ability on F) lies under this one, and each puts back only
what it changed (`KeyBindings.apply(false)` restores project.godot's bindings; the rework layer does
that around its own changes and applies the layout again).

What the mouse did, and what does it without it:

- **Aiming:** the weapon's strike, the charge and every aimed ability go the way the slime faces,
  which is the last direction it walked (8 ways; the weapons snap to their own directions). The Roll
  goes the way the held arrows point, else the way the slime faces. The Gulp sucks and throws where
  the slime faces (`player.gd` `get_gulp_aim`). The web aim help (`?aimhelp`) belongs to the throw
  rules, not to a scheme ([THROW_COMBAT.md](THROW_COMBAT.md)).
- **Teleport:** it always goes its full range the way the slime faces.
- **Choosing what to interact with:** the nearest target in reach wins, the one the slime faces
  helped (the interaction controller; the highest priority won until 2026-11-21). No pointer picks.
- **Placing furniture:** the bench's ghost stands 80 px in front of the slime, and walking moves
  it (`furniture_placement.gd` `_aim_point`). A places, E switches the variant, W or Esc cancels.
- **The interact badge** over the chosen target shows the interact key's letter (**W**) instead of
  the mouse glyph whenever `interact`'s first binding is a key (owner, 2026-10-20: "on coffers and
  interact remove the mouse icon"; `interaction_badge.gd`). The prompt reads "Press W: ...".
- **Windows** (bag, crafting, chest, journal, map, dialogue; owner, 2026-10-20: "I really
  shouldn't have to use the mouse"): the arrows **or W, A, S, D** move a selection cursor (a mint
  ring inside the cell, apart from the gold border of the selected one) between cells and
  buttons, Space or Enter presses, and Esc closes (B closes the bag). `game_window.gd` `_input`
  turns WASD into the `ui_*` arrows while the focus is in the window or the menu's tab strip, never
  in a text field. Dialogue also advances on W.
  - **Chest:** the first stack is selected and focused on open; moving selects; **Space takes the
    selected stack** and the selection moves to the stack now in its place. The opening status
    names the keys.
  - **Bag:** the selected item (the first at open) has the cursor; moving onto a bag cell selects
    it; **Space uses or holds it** (Use / Hold in hand / Place, the Primary button). Space on a
    belt slot holds that weapon; the belt is filled from a weapon's assignment buttons (move
    right to the details), so drag and drop isn't needed. In the rework mode, Space on a Shapes,
    Abilities or Skins cell chooses it (moving only shows its card). The titles, the band's help,
    the cards and the tabs' bubble name Space.
  - **Tabs:** move up past the window's top row to the tab strip and press Space (or B, J, M).
- **Mouse buttons and the wheel** do nothing in play (`player.gd` `_unhandled_input` drops every
  mouse event). Windows and menus still take clicks.

## Files

- [game/player/mouse/key_bindings.gd](../../godot/game/player/mouse/key_bindings.gd): the layout
  and the rebinding.
- `game/shell/game_settings.gd` `apply_to_input`; `game/shell/control_labels.gd` (the Controls list,
  `control_rows` / `rework_rows`); `game/hints/control_hints.gd` (the first-time hints).
- Tests: [tests/test_keys_only.gd](../../godot/tests/test_keys_only.gd) (the layout from the start,
  no F2 action or saved scheme, the arrows walk, A swings the way the slime faces and a click does
  nothing, W never uses a door).
