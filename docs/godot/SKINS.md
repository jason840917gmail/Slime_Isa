# Skins (roadmap 7.8)

The three Release 1 skins, built for real on 2026-10-17: **Heavy** (Pearl 1, Fatty One Eye),
**Silk** (Pearl 2, the Matron) and **Feral** (Pearl 3, the Crystal Colossus). Each dungeon's
Pearl is found inside it, before its boss, and the dungeon's second half teaches its skin
([the plan](../design/2026-10-17-pearl-mid-dungeon.md#the-skins-for-real-roadmap-78)). The rules
are the owner's ([Direction "The skins"](../story/01-direction.md#the-skins)):

- **Always on once won.** A skin is never put on, taken off or switched. Every won skin works at
  once and they stack; none has a downside (Heavy does not slow the slime). No keys: the Feral
  climb is a held interact. Skins cost no energy.
- **Contextual.** Each skin acts in its own places (its gate) and changes one move.
- **It shows while it works:** stony on a heavy plate, a grab or a Heavy Roll; silvery in a web,
  a web wall or a cut; furry with claws as it climbs or strikes. Otherwise the slime wears its
  **everyday look**, picked in the bag's Skins row (cosmetic only), else its own green goo: winning
  or lending a skin never changes it (owner, 2026-10-18: a skin shows only while its power works).
- **The Pearl grants its skin** and, the first time, shows the skin's
  short ceremony line (its name, big, and one line) over the slime, after the Pearl's card.

The Gulp's Stone and Silk forms no longer count as the Heavy and Silk checks. The forms themselves
stay until roadmap 7.11 removes them (the Swim form's mechanics stay for the later Swim skin);
nothing in the dungeons needs a form.

## The API

`game/player/skins/skin_state.gd` (class `SkinState`; preload it) is the one way to ask:

| Call | What it does |
|---|---|
| `SkinState.is_on(player, SkinState.HEAVY / SILK / FERAL)` | True once the skin is won or lent. `player` may be null (skins belong to the run). Every lock asks this |
| `SkinState.grant(id)` | A Pearl's grant: won for good, the ceremony line the first time (the look stays as it was). True when new |
| `SkinState.lend(id)` / `give_back(id)` | For this session only (dev powers, playground pedestals, `?skins=`); no save carries it |
| `SkinState.is_won(id)`, `on_ids()`, `order()` | Won for good (not lent); the skins on; every skin in `skins.order` |
| `SkinState.look()` / `set_look(id)` | The everyday look (`&""` = the goo) |
| `SkinState.show(player, id)` | A lock tells the slime its skin works now (player.gd `show_skin`) |
| `SkinState.definition(id)`, `display_name`, `look_index`, `color`, `setting(path, fallback)` | `skins.defs.<id>` and the skins' numbers |

player.gd keeps the old hooks, now on the skins: `presses_plates()` is the Heavy skin (heavy
plates, pressure plates, heavy blocks, a slam's Heavy impact on cracked ground), `crosses_webs()`
the Silk skin (every web rule). The Heavy Roll check is `game/fattys_lair/heavy_check.gd`
(`is_heavy_roll`: the Roll's bonk carries the `heavy` tag while the Heavy skin is on).

### The record

`RunState` keeps `story.skin_ids` (won and lent skins, in the order they came) and
`story.skin_look`, and `session_skin_ids` (the lent ones). `serialize` leaves the lent skins out,
and a lent look with them; `new_run` and `install` forget the lent list. A save from before
2026-10-17, whose Pearls set the story flags `skin.heavy`, `skin.silk` and `skin.feral`, wins those
skins when it loads. Signal: `skins_changed` {"skin_id", "reason": won, lent, returned or look}.

### Dev aids

- `?skins=heavy,silk,feral` (desktop `-- --skins=...`) lends those skins in any world, the last one
  (main.gd `lend_launch_skins`); the look stays the goo.
- `dungeon.devPowers.<world>` (game-constants.json) entries `skin.<id>` lend that skin to an F6 run
  of the world (main.gd `start_rework`); the look stays the goo.

## Looks

`game/player/skins/skin_look.gd` (owned by player.gd, real time) paints the Visual's material
(`game/player/gulp/form_skin.gdshader`, `skin` 4 Heavy, 5 Silk, 6 Feral, and `skin_amount`): first a
Gulp form's own skin, else a skin that works now (for `skins.lookShowMs` after the last
`SkinState.show`), else the everyday look, else the goo; a change fades out over `lookFadeOutMs`
and in over `lookFadeInMs`. With its painted texture (`asset/player/skins/<skin>-look.webp`, tiled
mirrored over the body, lit by the frame's own shading) the skin replaces its code pattern; the
Silk skin adds a drifting sheen. The shape weapons wear the look shown as their strike starts
(shape_visuals.gd). The Feral claws are `game/player/skins/feral_claws.gd`, a child of the body
made by the climb.

Who calls `SkinState.show`: heavy plates and pressure plates (the Heavy slime on them), the heavy
grab (pushing or pulling), the Heavy Roll (rolling, the bonk, what it breaks or shakes loose); the
floor webs (the Silk slime's feet in one), web walls (passing, cut), silk parcels (freed), web
barriers (crossed); the climb; the Spear's fast steps.

## Heavy

- **Its gate:** heavy plates (`object.heavy-plate`: only the Heavy slime or a heavy block sinks
  them; a light slime on one hears `refusal_text`, "It does not budge under you."), the old
  pressure plates (`object.pressure-plate`, Gloop Forest's iron hollow plate), and heavy blocks
  (`object.heavy-block`, `object.heavy-statue`, `heavy-ore-crate`: a held interact grabs, walking
  pushes or pulls; without the skin "Too heavy to move.").
- **The Heavy Roll:** every Roll with the skin on. Its bonk carries `heavy`, its screen shake is
  strong (`skins.heavy.rollBonkShakeMs` 420, `rollBonkShakeIntensity` 0.02, `rollBonkHitStopMs`
  90; a plain bonk keeps `character.player.movement.rollBonkShake*`), and its ground shake reaches
  `skins.heavy.looseRadiusPx` (200), heavy. It pushes no enemy away (a later upgrade).
- **What it breaks** (the look book: old, grey, dead or built things lying or leaning in the way):

| Object | Script | Notes |
|---|---|---|
| `object.plank-barricade`, `object.rotten-timbers`, `object.old-trunk`, `object.old-fence` | `game/scripts/plank_barricade.gd` | Wood: blocks as a wall, a Heavy Roll smashes it (a heap that no longer collides), `flag_id` keeps it smashed; anything else clinks with `refusal_text`. Exports `smash_text`, `smash_cue`, `splinter_rise` |
| `object.rubble-heap`, `object.loose-rock` | `game/scripts/rubble_heap.gd` | Rocks: the same, with pebbles (`rock_tint`) and `break_text`. Rubble heaps break under a Heavy Roll, no longer a Goo Bomb (owner, 2026-10-16); `breaks_by_blast` keeps the old blast heap, used only on the playground Bomb corner's islet until its cracked rock face (question 72) |
| `object.loose-prize` | `game/scripts/loose_prize.gd` | A prize caught up high (a coin pouch in a tree) `hang_height` over its root: a heavy shake within reach knocks it down, it pays `coins` and spills `contents`, `flag_id` keeps it taken; a plain bonk only makes it sway with `hint_text` |

Place a breakable across the way, its root on the ground line under it; a loose prize with its
root at the foot of the tree or wall it hangs on, where it lands. The Popworm and the Thorn Guard
listen to the same heavy shake (BESTIARY.md "Hooks").

## Silk

- Floor webs (painted on a `webs` WebLayer, `object.floor-web`, the Matron's patches) no longer slow
  the slime or stick a Roll; spit webs no longer root it; web barriers (`object.spider-web`) tear as
  it crosses them.
- Web walls (`object.web-wall`) are passed at `webs.wallPassMultiplier` (half speed).
- **The cut:** a shape's hit (the Spear in Release 1) cuts a web wall open for good and frees what
  is wrapped in silk (`object.silk-parcel`, the Matron's thread). The War Axe will cut webs without
  the skin (question 135).
- The rules and their numbers are [WEBS.md](WEBS.md)'s; the skin is `player.crosses_webs()`.

## Feral

- **The climb** (`game/player/skins/feral_climb.gd`, player-owned): at a climbable wall's start zone,
  facing along the climb, an interact press takes hold (or the wall's prompt, "Climb (hold)"). While
  the key stays held the slime climbs toward the far end at `skins.feral.climbSpeed` (150 px/s),
  swaying hand over hand; the movement key the other way climbs it back. Its body does not collide
  on the face and is drawn in front of it; claws show. At the far end it takes the level there
  (Elevation `track`) and the wall's `climbed` fires (a wall can lead out of the world:
  `exit_area_id`, `exit_marker`). Letting go midway, or a hit, drops it to the lower end over
  `skins.feral.dropMs` with a landing squash: no damage. Without the skin the wall is not offered,
  and pushing along it says `refusal_text` (at most every `skins.feral.refusalEveryMs`).
- **A wall that ends on the face** (`holds_at_top`; added by the dungeons for the Crystal Colossus's
  arena, [DUNGEONS.md](DUNGEONS.md#the-crystal-colossus-roadmap-124)): at the far end there is nothing
  to stand on, so the slime clings there (`hold_text` shows once each time it gets there) until it
  lets go or climbs back (feral_climb.gd `is_holding`).
- **The strike while clinging** (the plan's proposal, built by the dungeons on 2026-10-17 for the
  Colossus's claws): in the body-shapes mode an attack press while the slime climbs or clings (not
  while it drops) gives the current shape a press aimed along the face, left or right: the left or
  right movement key held, else toward the nearest standing enemy within `skins.feral.strikeSeekPx`
  (240), else the way the last one went (feral_climb.gd `strike_side`; player.gd `_climb_strike`). It
  strikes on the release as every press (the Spear at the Feral tempo, its hits through the shape
  controller as on the ground); the slime holds still on the face while the strike runs
  (`hold_still`), then climbs on. A hit still knocks it off. The classic game drops the press.
- **The Spear hits twice as fast:** while the skin is on, every Spear chain step runs its own
  timeline at `skins.feral.spearTempo` (2): wind-up, active window, recovery, cancel point, lunge
  and the finisher's rest take half as long (shape_controller.gd `_tempo`). The link window, the
  holds, the damage and the charged Lunge stay as they are.
- **Placing a climbable wall** (`object.climb-wall`, game/scenes/objects/climb-wall.tscn, script
  `game/scripts/climb_wall.gd`): put its root where the slime's feet stand at the wall's foot, about
  20 px below the face's foot line, and set `top` to where the slime's centre ends (on the ledge,
  about 40 px inside the rim). `art_size` sizes the roots' picture over the face; `grab_width` the
  zone across (default: the picture's width). To climb back down, place a second one on the lip
  facing down: its root about 20 px inside the rim, `top.y` > 0 ending about 30 px below the
  face's foot line, `show_art` off. A climbable wall never stands beside a heavy block or the
  root-rock wall style (questions 91 and 129). Painting roots on a layer is not built.

## The bag's Skins row

In the body-shapes mode the bag's band shows a Skins row beside the Shapes (inventory_screen.gd,
body_cards.gd `skin_card`): the goo and every skin on, with its icon (`asset/UI/skins/<skin>-icon.webp`).
A click picks the everyday look; its card says what the skin does and that it is always on. The row
hides until a skin is on. The bag pauses the game, as always.

## The Skins corner

The playground grew east by 20 columns (to 124) for it: `game/dev/corners/skins_corner.tscn`
(`skins_corner.gd`), x 6656 to 7936, `?map=playground&spawn=6800,1240`. A rework-mode testbed (the
classic playground drops it; its plateau stays painted). Three lanes, each with a skin pedestal
(`game/dev/corners/skin_pedestal.gd`: interact lends the skin for the session, again gives it back):

- **Heavy** (y 720 to 1200): a heavy plate, a heavy statue, a plank barricade, a loose rock, a
  rubble heap, an old fence, an old trunk, rotten timbers, a coin pouch in a tree.
- **Silk** (y 1330 to 1700): twelve floor webs, a web wall between stone walls hiding a silk parcel,
  a silk parcel in the open.
- **Feral** (y 1800 to 2500): a level-2 plateau painted on the playground's elevation (cells 110-117
  x 30-33) with a climbable wall up its face and one down from its lip, and a training dummy for the
  fast Spear.

None of its breakables keeps a flag: they come back with the world. The Heavy corner and the Webs
corner have a pedestal each too (their stone and silk essences went).

## Art

Generated with Magnific GPT 2.5 (`gpt-2-mini`, transparent background, the Lili creation as style
reference) on 2026-10-17; sources in `asset/Originals/skins/generated/`, packed by
`python scripts/art/pack-skin-art.py` ([TOOLING.md](../TOOLING.md)): the loose rock, the old trunk
and the old fence (each whole and broken, `asset/MAPS/props/heavy-skin/`), the coin pouch, the
three Skins row icons (`asset/UI/skins/`) and the three looks' textures (`asset/player/skins/`).
The claws are drawn by code. Pictures not imported yet load through `sheet_sprite.gd`
(`SheetSprite.load_picture`).

## Files

| File | What |
|---|---|
| `game/player/skins/skin_state.gd` | The API |
| `game/player/skins/skin_look.gd`, `feral_claws.gd` | The looks; the claws |
| `game/player/skins/feral_climb.gd`, `game/scripts/climb_wall.gd` | The climb; the climbable wall |
| `game/autoload/run_state.gd` | The record (`skin_ids`, `skin_look`, lending, the old flags) |
| `game/fattys_lair/heavy_check.gd`, `game/player/roll/player_roll.gd` | The Heavy Roll |
| `game/scripts/plank_barricade.gd`, `rubble_heap.gd`, `loose_prize.gd` | The Heavy Roll's locks |
| `game/scripts/pearl.gd` (`skin_id`) | The grant |
| `game/shapes/shape_controller.gd` (`_tempo`) | The Feral Spear |
| `game/ui/screens/inventory_screen.gd`, `game/ui/body_cards.gd` | The Skins row |
| `game/dev/corners/skins_corner.*`, `skin_pedestal.gd` | The playground corner |
| `tests/test_skins.gd` | The record, the grant, stacking and the look, the Heavy Roll and the prize, the climb, the Spear's tempo, the Skins row |

Numbers: game-constants.json `skins` (`order`, `defs`, `lookShowMs`, `lookFadeInMs`,
`lookFadeOutMs`, `ceremonyTextMs`, `heavy`, `feral`).

## Not built yet

- Roots painted on a layer (a climbable wall is a placed object).
- The Heavy Roll knocking the grey, leaning old tree over the river as a bridge (question 101).
- The Swim, Polar, Sand, Cloud and Lava skins (later releases); the Swim form stays as it is.
- Removing the Gulp forms, essences and Swallow (roadmap 7.11).
