# Handover: the Heavy grab's poses, text and hint (2026-10-19), for review

Read `AGENTS.md` first. Built by one side session on the owner's request; **nothing is committed**
and the test suite was **not run** (the owner's rule). Every edited script passes a `--check-only`
compile, and the behaviour was recorded in the running game (below). Never push.

## What the owner asked, and what was done

| Ask | Done | Owner |
|---|---|---|
| Its own pose while the Heavy slime pushes or pulls a heavy block (held W) | Push, pull and hold poses in all four directions, from new GPT 2.5 art on a new slime page (page 7) | Side view approved from a mockup (push A, pull B); the front and back views then built on his go-ahead; in-game captures sent, no verdict on them yet |
| The Heavy skin's description says holding W moves certain heavy objects | The bag's Skins card, the ceremony line and Pearl 1's card; the key comes from the bindings | Not commented |
| A hint on touching a movable heavy block, Heavy skin only, only while useful | "Hold W to push or pull" in the control hints pill | He reported "the hint is not working"; fixed (below) and re-recorded |

Magnific credits: 1,200 (12 GPT 2.5 images at 100).

## The changes, file by file

Several of these files also carry other sessions' uncommitted work (`player.gd`, `pearl.gd`,
`game-constants.json`, `TOOLING.md`, `BODY_SHAPES.md`, `docs/handover/README.md`): only the hunks named
here are this work. `git add -p` separates them.

**Poses**
- `godot/game/player/heavy_grab.gd`: `pose()` (line 114) returns `grab` (holding, the mouth latched),
  `push` or `pull`. Set in `step()` (lines 216, 235, 238): the move's direction while a cell move runs,
  else the walk key's direction past `startDelayMs`, also while the block knocks or (no skin) strains.
  The old latch look (a 6 % stretch toward the block and a 3 px lean, `LATCH_STRETCH`, `LATCH_LEAN_PX`)
  is removed; `_strain_look` (line 321) keeps only the strain's wobble. Header comment updated.
- `godot/game/scripts/player.gd` `_step_grab` (line 1762), this hunk only: plays the clip named by
  `_grab.pose()` in the facing's direction when the scene has it, else the old walk/idle.
- `godot/tools/build_player_clips.gd`: `GRAB_PAGE` (line 104) and `_shifted_clip` (line 395) build page
  7's clips with one `Visual:offset` key per frame (each frame's `shift` from the manifest), and a
  mirrored `pull-left` (the only side clip with a sideways shift). Header comment updated.
- `godot/game/characters/player_slime.tscn`: 10 new clips (`grab-`, `push-`, `pull-<down|up|side>`,
  `pull-left`), built by `build_player_clips.gd -- --only=push-,pull-,grab-`; 382 lines, insertions
  only.
- `scripts/characters/pack-slime-heavy-grab.py` (new): cuts the 2 x 2 sheets into poses (connected
  regions, so a snout over the sheet's middle stays whole), scales each sheet to page 1's idle area,
  places each pose where it meets the block (the side push's front and pull's snout at `FACE_X`, the
  back pull's snout at `BACK_TIP_Y` with at most `BACK_LEAN_MAX` of lean, the front pull's snout just
  past the feet) and writes `godot/asset/characters/256x256-tile_8x8-slime-v2-page-7.webp` and
  `asset/Originals/characters/slime-v2/page-7.json` (whole clips: frames, fps, loop, shifts).
- Art: `asset/Originals/characters/slime-v2/heavy-grab/` (12 sheets and a README with the prompts,
  picks and cost). The page's `.import` was made by the owner's open editor (its window was brought to
  the front once so it scanned); its settings match page 6's.
- `godot/tools/render_heavy_grab.gd` (new, + `.uid`): records the grab in the running game, windowed at
  1920 x 1080: a touch, the hold, a push and a pull from each side of a block, logging the pose, the
  clip, the slime's screen position and the control hint showing (`--map`, `--direct`, `--quick`,
  `--plain`; docs/TOOLING.md).

**Description**
- `godot/game/shell/control_labels.gd` `with_keys` (line 168): replaces `{<action>}` in a text with the
  action's main key label (mouse buttons in lower case; an unbound action reads "the <action> key").
- `godot/game/player/skins/skin_state.gd` `text(id, field)` (line 128); `ceremony_line` uses it.
- `godot/game/ui/body_cards.gd` `skin_card` (line 136) reads `SkinState.text`.
- `godot/game/data/game-constants.json` line 444, `skins.defs.heavy.line` only: "Heavy as stone: heavy
  plates sink, and holding {interact} pushes or pulls heavy blocks and statues."
- `godot/game/scripts/pearl.gd`: `card_line`'s default (line 53, Pearl 1's: no scene overrides it) names
  `{interact}`; the card's `line` and `how` go through `with_keys` (line 138); a `ControlLabels` preload.

**Hint**
- `godot/game/hints/control_hints.gd`: rework hint `heavy-grab`, text `with_keys("Hold {interact} to push
  or pull")` (line 259); relevant (line 299) while the Heavy skin is on and the slime holds a block or
  faces and touches one (`_heavy_block_at`, line 504: `HeavyGrab.block_in_reach`, the grab's own test);
  in `REWORK_HINT_IDS` right after `move` (line 95). Learned (`_learn_heavy_grab`, line 488) only once a
  block has moved in the grab both away from the slime and toward it (story flags `hint.heavy-grab.push`,
  `hint.heavy-grab.pull`, then `hint.heavy-grab`).
- **The owner's report and the fix:** the first version was learned the moment the first block moved
  and sat after `interact` in the order. Pressing W at once, the pill was still fading in (320 ms) when
  the push learned it, so it flashed and never came back in that run. Now it stays through the hold and
  the push, and goes after the first pull; `interact`'s hint can no longer take its place.

**Docs updated:** `docs/godot/SKINS.md` (API `SkinState.text`; Heavy: "Push and pull poses", "It says
so", "The touch hint"; Art; Files), `docs/godot/BODY_SHAPES.md` (the grab paragraph, the hints line),
`docs/TOOLING.md` (the packer, the clip builder's grab clips, the capture tool),
`docs/assets/slime-sheet-guide.md` (page 7), `asset/Originals/characters/slime-v2/README.md` (page 7
layout).

## How it was checked

- `--check-only` compiles of every edited script; a one-off headless check of `with_keys` ("Hold right
  click to push or pull" with the mouse binding, "holding W" with W, "the no such key" for an unknown
  action).
- In the running game (`tools/render_heavy_grab.gd`): the playground's Skins corner statue from all four
  sides, with and without the skin; the Weigh House (`--map=fatty-lair-c2-weigh-house --direct
  --block=800,352`) with a touch first and with W pressed at once. The logs show the clip switching
  `grab-` / `push-` / `pull-` (and `pull-left` facing left), the hint `heavy-grab` showing on touch,
  staying through the push and going after the pull. Captures: `output/heavy-grab-game/`,
  `output/heavy-grab-lair/` (ignored by git); the mockups `output/heavy-grab-mockup/`.

## For the reviewer: worth a close look

1. **Clip offsets.** The pull clips key `Visual:offset` per frame (the body drawn up to 60 texture px,
   about 17 units, away from the block). `player.gd` `_play_clip` puts the offset back to rest whenever a
   new clip starts; check no path leaves it shifted (a grab released by a hit, a teleport, death or a
   room change mid-pull), and that the StrikeRig, the skin look's shader and the hit flash are fine on
   page 7's texture.
2. **The front view.** With the block below the slime (the slime facing down) the tall statue and
   pedestal hide the slime almost completely, as they did before; only the squash and the lean peek out.
3. **The strain.** Without the skin the slime now shows the push or pull pose while it strains (with the
   wobble) instead of the latch stretch.
4. **Hint learning.** `_learn_heavy_grab` reads the block's `velocity` against the slime's facing while
   the block `is_moving()`. A block that can only be pushed (no room to pull) keeps the hint coming back
   on each touch until a pull: intended, but say if it should be learned sooner.
5. **`with_keys`** uses an action's first binding only; check the labels in every control scheme
   (keyboard, pointer, click and moba: "right click", since only the keys-only scheme rebinds the
   InputMap; keys only: "W"). The review found the click and moba schemes wrong here: see below.
6. **No tests were added.** Candidates: `test_skins.gd` (the card and ceremony texts through
   `SkinState.text`), a hint test (relevant only with the skin and touching; learned after push and
   pull), and the grab's `pose()` states.
7. **`player_slime.tscn`** was saved headlessly by `build_player_clips.gd` (insertions only); the
   owner's editor should reload it before any save there.

## After the review (2026-10-19, uncommitted, compile checks only)

- **Click scheme:** its right button (the use button) is caught before the input buffer, so a right
  click started the grab and let go on the next step; the hint "Hold right click to push or pull"
  never went away. `player.gd` `_step_grab` now holds the grab with `_use_button_down` too, as the
  Feral climb does.
- **Moba scheme:** its right button walks, so nothing holds the grab; `control_hints.gd`
  `is_relevant` (`heavy-grab`) no longer shows the hint there.
- **Mouth full:** the grab does not start with something in the mouth; the hint no longer shows then.
- Docs: `docs/godot/BODY_SHAPES.md` (the grab paragraph), `docs/godot/SKINS.md` ("The touch hint").

## Not done (by design or left for the owner)

- In the moba scheme the Heavy skin's card, its ceremony line and Pearl 1's card still say "holding
  right click", which does not grab there.

- The Feral Pearl's card still says "Hold the interact key" (`card_how` in `pearl-three.tscn`,
  `crystal-mine.tscn` and `dungeon-lab.tscn`); it could name the key with `{interact}` now.
- Sounds for push and pull are unchanged (the grab's placeholder cues).
- Not committed; the owner decides when.
