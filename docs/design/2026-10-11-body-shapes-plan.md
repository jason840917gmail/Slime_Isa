# Body Shapes: the Rework Plan

*Status: a plan to discuss, on branch `exp/body-shapes` only. Nothing is built. Written
2026-10-11 from a survey of the code, five candidate designs, three judges, review passes and
three rounds of the owner's answers the same day. The Release 1 story, the dungeons and the quest
chain are in [2026-10-11-release-1-dungeons-plan.md](2026-10-11-release-1-dungeons-plan.md).*

The slime's weapons become **shapes of its own body**, like a symbiote: a spike, an axe, a
hammer. Crafted weapons, the axe and the pickaxe go away. The game leans toward adventure: every
boss lives in a dungeon, and secrets wait behind trees, rocks and webs for the shape that opens
them.

## 1. The plan in short

1. Three body shapes: **Spear** (pierce), **War Axe** (cut), **Hammer** (crush). The Attack key
   uses the current shape; E switches shapes.
2. **Spear:** taught by **Old Veteran Yoi** in a hidden maze cavern under Slimeshire, before any
   enemy. **War Axe:** found halfway through the Matron's dungeon (the Weaver Hollow).
   **Hammer:** later chapters; testable in the playground now.
3. **Every boss lives in a dungeon,** and its Pearl is inside: Fatty One Eye in **Fatty's Lair**
   (Chapter 1), the Matron in the **Weaver Hollow** (Chapter 2).
4. **Squash Slam** stays, taught by Fatty's Pearl, and gets stronger (a higher leap in place, a
   bigger and heavier landing). It does **not** break rocks.
5. **Rocks wait for the Hammer, trees for the Axe, thick webs for the Axe.** They hide
   "come back later" secrets.
6. **Q does the whole mouth:** hold to suck, hold 2 s to swallow an essence, quick release to
   throw, hold in a form to spit it out. No Swallow key.
7. **The Ability Box:** Squash Slam and every later gadget sit in a Zelda-style box and are used
   with **S**. The Roll is the only other ability with its own key, and it comes after Release 1.
8. Release 1 keys (keys-only scheme): **A W Q E S** (+ R to open the box). Crafting shrinks to
   2 recipes. Built grey-box first; no art credits until the owner likes the feel.

## 2. The owner's sketch (confirmed)

- **Spear:** a tapered spike, thick at the body and sharp at the tip, shoots straight out of the
  slime's front, with speed lines. Fast and narrow.
- **War Axe:** a goo haft grows out of the slime's side with a broad crescent axe head, and it
  sweeps down along a big arc. (The sketch drew a curved sword; on 2026-10-11 the owner made it a
  war axe, because a wide swing fits an axe better and an axe chops trees.)
- **Hammer:** a stalk grows out of the top of the slime, where the sprout is, with a big block
  head. It swings over the front and smashes the ground: crater, cracks, flying debris.

The slime never holds anything. Every shape comes out of the body.

## 3. The three shapes

### Shared rules

- **Attack key** (A in keys-only, left click with the mouse) uses the current shape.
- **Directions:** 8. Without a pointer the slime attacks the way it faces. With a pointer, the
  Axe and Hammer snap to the nearest of 8 directions; the Spear aims at the exact angle inside
  its 45° sector, so it never misses Fatty's small eye at a sector edge.
- **Tap = strike**, on the press, no energy. Presses chain into a **3-step combo** (the Hammer has 2): steps 1-2 hold the enemy in place, the last step launches it, and each enemy's reaction profile decides the rest. Steps come every 170-460 ms instead of today's 760-1300 ms. Full rules and numbers: the [combat feel plan](2026-10-11-combat-feel-plan.md).
- **Hold = charge**, for every shape **from the moment it is learned** (owner, 2026-10-11): no
  charge is a separate reward. A goo ring fills under the slime (the same ring as the mouth's);
  release when full. Charges cost energy.
- **Switching:** E (or the wheel), wrapping; instant between strikes, buffered 150 ms during one
  (as built: the press waits for the step's cancel point or the charge's end and never aborts a
  strike, BODY_SHAPES.md); a switch cancels a charge. The shape slot stays hidden until the second shape. No key goes back
  (owner rule, 2026-10-08).
- **Tags** are written on each shape. Every shape carries `weapon` (Tom's web tears). The Spear
  carries `spear` (Fatty's eye, spear switches). The Axe carries `cut` (thick webs, tethers,
  cocoons, trees). The Hammer carries `crush`. A wrong hit clinks.
- **Per-target modifiers are explicit:** Axe wood x1, stone x0; Hammer stone x1, iron x1.
- **Numbers** live in a new `shapes` block of `game-constants.json`.
- **Walls:** hits ignore walls and cliff levels today. The Spear gets a line check so it stops at
  walls (the check ignores water). A general "no hits across cliffs" rule is a separate change.

### The table (starting values for the grey box)

| | **Spear**: *pierce* | **War Axe**: *cut* | **Hammer**: *crush* |
|---|---|---|---|
| Role | Long reach, precise, fast | Wide arc, crowds | Heavy area hit, slow |
| Reach / area | A line 24-110 px, 14 px wide; hits all on the line; stops at walls | 140° arc, radius 60 | Circle r48, 48 px ahead; the slime stands still while it winds up |
| Chain (combat feel plan) | Jab, jab, lunging jab: contacts at 50, 220, 430 ms; 14 / 16 / 21 damage | Sweep, backswing (the same clip backwards), cleave: contacts at 80, 310, 620 ms; 18 / 21 / 27 | Thud, BOOM: contacts at 260, 740 ms; 36 / 54 plus a ring |
| Base damage (before the x1.2 attack multiplier) | 12 | 15 | 30 |
| Finisher launch | 420 along the aim (about 95 px on a light enemy) | 400 from the slime | 380 with a hop; ring r72 bounces |
| Breaks or opens | Fatty's eye, stone eyes and weaver's eyes (switches), Tom's fresh web, alarm bells that want a point | Plain and thick webs for good, tethers, cocoons, egg sacs, bushes, vines, **trees** (wood, and what hides behind them) | Stone and iron nodes, boulders, armour, heavy doors |
| Charge (hold, from the start) | **Lunge**: the spike grows to 170 px and the slime darts a short step along it, hitting every target on the line | **Spin**: 900 ms ring, release for a 360° cut of r72 | **Quake smash**: a longer wind-up, a ring of cracks around the head, more damage and area |
| Learned | Yoi, The Thorn Guard (Chapter 1) | Big chest, Edge Shrine, Weaver Hollow (Chapter 2) | Later chapters; the playground has it now |

## 4. Squash Slam, improved

Fatty's Pearl teaches it. It goes into the Ability Box and is used with S.

| | Today | New |
|---|---|---|
| Body | Stays in place; only stretches | **Stays in place.** Only the art rises 96 units. The code never moves the body, never starts a flight, never changes its height level, so it can never cross a wall, gate, hole or cliff (the reason the jump was removed) |
| Timeline | Wind-up 0-320 ms, impact 320, done 470 | Crouch 0-120, rise 120-320, hang 320-380, dive 380-460, impact 460, done 640 |
| Area | Circle r90 | Ground ellipse 140 x 96, only on the slime's own height level |
| Damage | 30 to everything | Inner half 40, outer ring 24; +25 % in the Stone form |
| Knockback | 320 | Inner 380, outer 300 |
| Energy / cooldown | 30 / 2.5 s | 35 / 2.5 s |
| Safety | Hits land; knockback moves the body | No hits from 140 to 440 ms (in the air); knockback ignored for the whole slam |
| What it breaks | Cracked ground in the Heavy form | Cracked ground in the Stone form (as built), worm drums, stuck hatches, egg sacs; trees shake (berries, a hidden prize on chosen trees). **Never stone, iron or boulders** (owner, 2026-10-11): `strike_area` keeps skipping resources |
| Feel | Shake 150 ms x 0.01, hit-stop 90 ms | Shake 240 ms x 0.014, hit-stop 110 ms; Stone form 260 ms x 0.018, 140 ms |
| Effects and sound | Ring; SlamWindup, SlamImpact | Shockwave ellipse, crack decal at the feet, pebbles and dust coloured by the ground, wobble within 200; new cues SlamRise, SlamDive, SlamImpactStone |
| Numbers | Literals in `ability_definitions.gd:36-37`, `slam_sequence.gd:15-17` | `game-constants.json`, `abilities.squashSlam` |

## 5. The mouth (Q)

**Rule** (owner, 2026-10-11, second version). **A press sucks**: one press of Q with an empty
mouth sucks for one second, whether Q is held or not. **A hold changes the body**: holding Q for
2 s swallows the essence in the mouth, or, with an empty mouth in a form, spits the form out. **A
tap empties the mouth**: a tap with something in the mouth throws it (a liftable) or spits it out
whole (an essence). What a press does depends on the mouth at the moment Q goes down; something
caught during a press waits for the next press.

New constants in `game-constants.json` `gulp`: `tapMs` 250, `suckBurstMs` 1000, `swallowHoldMs`
2000, `spitHoldMs` 2000, `ringCancelMs` 150, `ringRadiusPx` 30, all on `Services.now_ms()`.

| # | Mouth at the press | Form | Tap (released < 0.25 s) | Hold, 0.25-2 s | Held to 2 s |
|---|---|---|---|---|---|
| 1 | A liftable | Any | Throws it along the aim | Release still throws it | Release throws it; never spits the form |
| 2 | An essence (Swallow learned) | None, or another form | Spits it whole, 44 px ahead; it stays | A ring in the essence's colour and "Swallow Stone", with a rising throat sound; release cancels (the ring drains in 150 ms, the essence stays) | **Swallows** it. The old form's essence lands **whole** beside the slime and stays |
| 3 | An essence of the current form | That form | Spits it | "Already Stone" once; release keeps it | Nothing |
| 4 | An essence that cannot swim | Swim, over deep water | Spits it | "Swim back to the shallows first" once | Nothing |
| 5 | An essence (Swallow not learned) | Any | Spits it | No ring; release keeps it | "It won't go down yet" once (a hint pointing at Tom) |
| 6 | Empty | None | **A one-second suck burst** starts on the press; the first target in reach flies in (220 ms); nothing in reach = a puff of dust at the end | The same burst; holding changes nothing | Nothing more |
| 7 | Empty | A form | The same one-second burst | The burst goes on; if nothing has been caught by 0.25 s, the spit ring starts, "Spit out Stone". A catch cancels the ring | **Spits the form**: the essence lands whole 44 px ahead and stays ("Ptoo!") |
| 8 | Empty | Swim, over deep water | The same burst | "Swim back to the shallows first" once | No spit |

- **Cancels:** a hit (drop and pop as today), knockback, death, a door, sleep, focus loss, or a
  ceremony or window opening. A pull already in flight finishes.
- **While a burst or a ring runs:** no walking; attack, ability and roll presses are dropped. A
  short cooldown after a burst (tuned in the playground) stops Q being mashed.
- **Prompts:** "[Q] Suck" near a suckable thing; "[Q] Throw" with a liftable; "[Q] Spit out
  Hold [Q] Swallow" with an essence (only "[Q] Spit out" before Tom).
- Swallow stays a learned ability (`swallow`, from Tom) without a key or HUD slot. Its ceremony
  says "Hold Q with an essence in your mouth until the ring fills".
- New code: `mouth_hold.gd` (the state machine) and a code-drawn `goo_ring.gd`, shared with the
  Spin's charge ring.
- Today Q spits an essence on the *press* (`player.gd:1317-1326`), and a deliberate swap drops the
  old essence with the 3 s pop fade (`gulp_controller.gd:47-48`); both change.

## 6. The Ability Box and the keys

### The box (Zelda's item screen)

- **Sockets:** 8 in a 4 x 2 grid, fixed order: Squash Slam, Stretch Lash, Teleport, Glow, Goo
  Bombs, Goo Boomerang, Spore Powder, a spare. Release 1's story fills only the Slam; the
  playground fills the Slam, Lash and Teleport.
- **Never in the box:** shapes (E), the mouth and Swallow (Q), the Roll, forms, Goo Trail, the
  hidden jump (ledge drops still use its flight).
- **Where (owner idea, 2026-10-11): in the bag window**, not a screen of its own. The bag window
  (1000 x 640) has a 130 px band at the top for the 4-slot weapon belt, and the belt goes away
  with the body shapes. That band becomes two short rows: **Shapes** (Spear, Axe, Hammer; click
  one to make it current) and **Abilities** (the 8 sockets in one row; click one to put it on S).
  The details panel on the right shows the chosen one's card (line, energy cost, cooldown, key).
  B opens it, as today; a click on the HUD Ability slot opens it too. No extra key and no extra
  tab. Before the first bag, the window opens with the two rows and an empty bag area.
- **Choosing:** arrows or a click; the ability under the cursor goes on S at once; Esc or B
  closes.
- **Rules:** a newly learned box ability is selected by itself, and its ceremony names S. The
  choice is saved (`player.loadout.ability_id`). Cooldowns stay per ability. The Abilities row
  shows only learned sockets; empty ones stay hidden (no teasing silhouettes) until decided
  otherwise.
- **Gadgets with ammo** (bombs) need a count, which the ability system does not have yet; they get
  a small design when the first one is built.

### Keys only (the owner's preferred scheme)

| Action | Key | From |
|---|---|---|
| Walk | Arrows | Start |
| Attack with the shape (tap; hold to charge) | **A** | The Spear (Yoi) |
| Interact (hold for the second action) | **W** | Start |
| Mouth (section 5) | **Q** | Start; swallowing from Tom |
| Next shape | **E** | The second shape |
| Use the chosen ability | **S** | Squash Slam (Pearl 1) |
| Roll (hold to keep rolling) | **D** | Later, not Release 1 |
| Bag (with the Shapes and Abilities rows) / journal / map / pause / zoom / scheme | B / J / M / Esc / = - / F2 | Start (zoom off inside dungeons) |

Release 1 uses 5 gameplay keys (A W Q E S), all under the left hand. Today it is 8 (attack,
interact, Q, 1, 2, 3, 4, E).

### Mouse + keyboard

| Action | Key |
|---|---|
| Walk | WASD or arrows |
| Attack | Left click (Shift + hold for a charge in the click and moba schemes) |
| Interact | Right click |
| Mouth | Q |
| Next shape | E or wheel |
| Use the chosen ability | F |
| Choose the ability | B (the bag window), or click the HUD Ability slot |
| Roll | Space (later) |
| Bag / journal / map / pause / zoom / scheme | B / J / M / Esc / = - / F2 |

In the click and moba schemes an order on something the current shape cannot break is refused
with the hint, so the slime never swings forever.

### Input changes

- Delete `swallow` (1), `stretch_lash` (3), `squash_slam` (4) and `teleport` (5).
- Add `ability_use` (F; S in keys-only).
- Move `dodge` from 2 to Space (D in keys-only).
- `key_bindings.gd` LAYOUT gains `ability_use: [KEY_S]` and `dodge: [KEY_D]`.
- `ability_definitions.gd` `BAR_SLOTS` and `DISPATCH_ORDER` follow.
- Gamepad (later, its own workstream): left stick walks, X attack, A interact, LT held mouth, RB
  next shape, Y ability, B roll, Start pause, D-pad bag / journal / map.

## 7. Release 1 at a glance

Combat feel (combos, enemy reactions, juice): the [combat feel plan](2026-10-11-combat-feel-plan.md).
Full detail (play order, Yoi's Hideout, the dungeon framework, both dungeons, the quest chain,
materials, hearts, come-back secrets): the
[progression and dungeons plan](2026-10-11-release-1-dungeons-plan.md).

| Learned | Where | Opens |
|---|---|---|
| Mouth (Q suck and throw) | Start | Pots, bricks, the hideout's cover, bells and gongs hit by a thrown pot |
| 10-slot bag | Plop, accepting Slime Basics | Carrying things |
| **Spear** | Yoi, at the end of his water maze under Lili's yard | Attack; stone eyes; Fatty's eye; Tom's web |
| **Squash Slam** (box, S) | Pearl 1, Fatty's Lair | Worm drums, stuck hatches, cracked ground in the Stone form |
| Green key | Chest by Pearl 1 | The Verdant Gate, Chapter 2 |
| **Swallow** (hold Q) | Tom, Gloop Forest camp | Stone form (plates, cracked ground), Silk form (plain webs, the Weaver Hollow's web door) |
| 20-slot bag | Gloop Cavern (optional) | More slots |
| **War Axe** | Edge Shrine, halfway through the Weaver Hollow | Thick webs, tethers, cocoons, trees; E switches shapes |
| **Silk Reel** (a longer suck) | Pearl 2, the Matron | Sunny's basket, pots on islets, things behind bars |
| Heart quarters, boss hearts | 4 per region, 1 per boss | +20 max HP per heart; 180 after Chapter 2 |

**Later:** the Roll (own key D), the Hammer (rocks, boulders, armour), the Spear Lunge, Stretch
Lash, Teleport, Glow, Goo Bombs, the Heavy Gulp lift upgrades, the swim-essence enemy, Pip's Forge
(after the Hammer, its story rewritten), the Workshop, Sunny's basket (a come-back secret).

## 8. UI

1. **HUD console:** Shape slot (A; hidden until the second shape, shows the charge's cost),
   Ability slot (S; hidden while the box is empty; icon, key badge, energy-cost chip, cooldown
   sweep), Roll slot (D, once learned). The form badge stays on the energy orb.
2. **Goo ring** on the slime, drawn in code, for the mouth holds and the charges; a chime when
   full.
3. **Bag window:** the belt band becomes the Shapes and Abilities rows (section 6).
4. **Dungeon HUD:** small-key and big-key readout, minimap room fog (see the dungeons plan).
5. **Ceremony cards:** "New shape", "Pearl of the Wellspring (n of 8)", "Shape upgrade" later. The
   "New weapon" and "New tool" cards go.
6. **Bag:** the belt row and belt drag go (their band holds the Shapes and Abilities rows). The
   Crafting tab keeps the 2 recipes.
7. **Texts:** controls window, hints (switching at the second shape, charging, the mouth holds),
   refusal texts from the tags ("Cut it with an edge", "Too hard: something heavy could crush
   it"), the Gulp prompts, the cracked-ground creak hint, web hints. The crafting and "tools only
   work in hand" hints go.
8. **Dev aids:** `?shape=<id>`, `?shapes` (all three shapes, Slam, Lash, Teleport in the box)
   replace `?weapon` and `?arsenal`; dungeon options in the dungeons plan.
9. **UI art to make:** shape icons, box sockets and cards, the ring and chime, per-shape swing
   and switch sounds (they live in the weapon scenes and the EquipBlade / EquipTool / WrongTool
   cues today).

## 9. Art for the shapes

Dungeon art (doors, chests, switches, the Pearl, webs, new enemies, Yoi) is listed in the
dungeons plan. Everything starts grey-box.

### Body clips

New rows on new slime pages, same 256 px cells and baseline as pages 1-5.

| Shape | Drawn | Mirrored | Drawings per row | Notes |
|---|---|---|---|---|
| Spear | down, down-side, side, up-side, up | down-left, left, up-left | 4-8 | Short brace and push; the spike is an overlay |
| Axe | 5 | 3 | 4-8 | The haft grows from the side, the axe head sweeps down; backswing = same row backwards; the Spin charge reuses the ball spin frames plus a code smear |
| Hammer | 5 | 3 | 4-8 | Stalk from the top, head swings over and smashes; drawn last |
| Slam | Reuses today's slam poses | | | The higher rise is keyed offset; the landing is effects |

- 15 drawn rows: about 60 frames at 4 a row (one page), up to 120 at 8 (two pages, about +32 MB
  of video memory on web).
- Clip names `attack-<shape>-<dir>`; `build_player_clips.gd` extends its automatic `-left` mirror
  to the diagonals.
- **Source:** GPT 2.5 key poses (3-4 per row) with keyed offset, squash and skew on held drawings,
  as the slam does today. Seedance gave 0 usable attack takes out of 3. Every generation uses the
  turnaround as reference; each row is checked against the idle before the next. Two new diagonal
  start stills (down-side, up-side) come from `turnaround-e.png`. About 4-6k credits for the Spear
  and Axe, spent only after the grey-box playtest; the Hammer later.

### Effects: drawn or code

| Part | How |
|---|---|
| Spear spike | One painted strip (stump, shaft, tip), stretched and rotated in code like the Lash tendril |
| Axe head and arc | A painted strip (goo haft and crescent bit) plus a code-drawn smear (polygon with a reveal shader). The hit reaches 60 px; a head drawn inside a cell reaches about 36 |
| Hammer stalk and head | One painted head in 3 views on a stretched stalk strip |
| Floor crack | Reuse `boss-ground-crack-4x1.webp` as a decal |
| Dust, debris, sparks, shockwave | Existing: ParticleFx, `break_burst.gd`, the AbilityFx ring, GameFeel `slam` / `ground-crack` |

Overlays are painted in the slime's jelly green so `form_skin.gdshader` can re-skin them (a stone
hammer, a silk-wrapped axe); they must share the player's material settings (form, flash, waterline,
occlusion).

### Where mirroring fails

- **Light** comes from the upper left; a flipped row moves the shine to the upper right. More
  visible on diagonals, where a mirrored row sits next to an unmirrored one.
- **Face and sprout:** anything off-centre jumps sides. Keep attack faces symmetric on purpose.
- **Motion:** a mirrored sweep turns the other way. Fine for goo; a move that must always turn
  clockwise needs its own rows.
- **Keyed offsets** are not mirrored by `flip_h`; each diagonal needs its own built mirror clip.
- **Overlays** never need mirroring: they are rotated in code.
- **Related:** upward strikes must draw behind the slime (today the weapon is always in front),
  and diagonal attacks pop out of the 3-direction idle and walk. Accept the pop in the prototype;
  diagonal idle and walk rows (about 4) are a later cost.

## 10. What changes in code and data

Dungeon systems, worlds, quests and enemies: the dungeons plan, section 11. The shapes rework:

| Area | Files | Change |
|---|---|---|
| Weapon data | `data/weapons.json`, `game/inventory/weapon_catalog.gd` | Replaced by shape entries in `ability_definitions.gd` (`shape-spear`, `shape-axe`, `shape-hammer`, `axe-spin`) and a `shapes` block in `game-constants.json` |
| Weapon scenes | `scenes/weapons/*.tscn` (13), `scene_index.json` | Removed; new `scenes/shapes/{spear,axe,hammer}.tscn` with hitboxes facing right, rotated to the aim. The Goo Gauntlet is the template |
| Combat | `combat/player_combat.gd`, `scripts/weapon.gd`, `shared/directions.gd` | A resident shape controller instead of `equip()`; one rotated shape per span; explicit tags; 8-way snap; the Spear line check. Payload, crit, combo and hit feedback kept |
| Player | `scripts/player.gd` | Attack, switching, 8-way clip resolver, the Q state machine hook |
| Abilities | `player/abilities/ability_definitions.gd`, `slam_sequence.gd`, `ability_world.gd` | Shapes and their charges added; Silk Reel; the new Slam; literals to game constants; the box list; the hidden jump stays |
| Mouth | `player/gulp/*`, `gulp_hud.gd` | `mouth_hold.gd`, `goo_ring.gd`, the prompts, the swap rule |
| Belt | `player/weapon_loadout.gd`, `inventory_actions.gd`, `ui/screens/inventory_screen.gd`, `inventory_model.gd`, `item_cell.gd` | The belt goes; `wheel_stepper.gd` stays |
| Saves | `autoload/run_state.gd` | `equipment` becomes `loadout {shape_id, ability_id}`; shapes and charges are learned ability ids; dungeon state (dungeons plan). Schema 2; refusing older saves is new code. `weapon` leaves PERMANENT_ITEM_CATEGORIES |
| Crafting | `data/recipes.json`, `data/items.json`, `game/crafting/*`, `ui/screens/crafting_*`, `scripts/workbench.gd` | 13 recipes, the workbench, charcoal, iron bars, fangs, silk clumps deleted. `crafting_model.gd` and the service stay for 2 recipes |
| Stations | `scenes/objects/forge.tscn`, `workshop.tscn`, camp bench | Parked until after the Hammer; the camp bench goes |
| Bosses | `fatty-one-eye.tscn` (allowed spear ids), the Matron | Fatty checks the `spear` tag only; both move into dungeons (dungeons plan) |
| World objects | `resource-stone-node*.tscn`, `resource-iron-node.tscn`, `tom_web.gd`, webs | Refusal texts; webs cut by the Axe; thick webs |
| UI | `ui/weapon_hotbar.gd`, `ui/ability_bar.gd`, `ui/console/hud_console.gd`, `ui/screens/menu_tabs.gd`, `ui/ceremony/ability_ceremony.gd`, `hints/control_hints.gd`, `shell/control_labels.gd` | As in section 8 |
| Input | `project.godot`, `player/mouse/key_bindings.gd`, `click_orders.gd`, `pointer_targets.gd` | As in section 6; shape reach replaces weapon reach |
| Art and tools | `characters/player_slime.tscn`, `tools/build_player_clips.gd`, `scripts/characters/pack-slime-v2-page.py`, `tools/verify_scenes.gd` | New clips and pages; the verifier's play actor |
| Old art | `asset/MAPS/weapons/*.webp`, `weapon-player-*` icons | Kept unused until the direction is adopted |
| Dev | `game/main.gd`, `tests/run_tests.gd:188` | `?shape`, `?shapes`; tests start with the Spear learned |

**Saves:** a clean break on the branch (schema 2, its own save folder). That folder is a setting
in the shared `project.godot` and also separates `settings.cfg`; it goes in its own small,
announced commit. A migration is written only if the direction is adopted.

**Tests:** about 30 files need a planned rewrite pass: `test_combat`, `test_loadout`,
`test_crafting`, `test_world_objects`, `test_inventory`, `test_saves`, `test_ceremony`, the
chapter-flow tests, `test_boss`, `test_matron`, `test_tom`, `test_mouse_controls`,
`test_abilities`, `test_player_movement`, `test_ability_bar`, `test_gulp`, `test_world_puzzles`,
`test_control_hints`, `test_furniture`, `test_journal`, `test_quests`, `test_map`, `test_audio`,
`test_chest_window`. New tests: 8-way rotated hitboxes; the Spear passing Fatty; every shape on
Tom's web; Axe wood; the Slam never moving the body and never breaking rocks; the mouth table;
the box selection. None of them run until the owner asks.

**Docs** to rewrite in the same change: specs `combat`, `abilities`, `crafting`, `player`,
`world-objects`, `boss`, `matron`, `quests`, `audio`, `water`, `enemy`, `furniture`,
`interaction`, `journal-and-chest`, `shell` (and `world`, `map` after asking the atlas session);
new `docs/godot/DUNGEONS.md` and `specs/dungeon.md`; `ARCHITECTURE.md`, `CONVENTIONS.md`,
`MOUSE_CONTROLS.md`, `UI_THEME.md`; `GAME_GUIDELINES.md`, `GAME_ROADMAP.md`, the HUD mockup,
`AGENTS.md` launch options; story `01` to `06` and both chapter docs; `TOOLING.md`, the slime art
README.

## 11. Contradictions the build must fix

The dungeon-related ones are in the dungeons plan, section 13. For the shapes:

1. `01-direction.md` says weapons and tools are crafted and keeps a "Crafting time" row; its
   2026-10-08 rows say "Roll on key 2" and "Swallow before the iron hollow".
2. Stretch Lash is still the Matron's gift in the story docs and the roadmap (8.7, 5.9);
   `beyond-the-verdant-gate` still gives `stretch-lash` and `craft-reinforced-pickaxe`.
3. Chapters 1-2 are a crafting chain today; the Matron's offer says "An iron spear!" and needs
   `iron-gear`; `stone-tools` is the only `dodge` grant.
4. Rocks say "Requires a Pickaxe" / "Requires a Reinforced Pickaxe".
5. Weapon tags are guessed from ids and never carry both `spear` and `weapon`.
6. The quest service forgets an object opened before the quest; it ignores a refused reward; its
   header counts 14 quests, there are 15.
7. Keys: the docs put the Lash on 3 and the Slam on 4; `06-open-questions.md` says "Swallow (R;
   W in keys-only)"; `MOUSE_CONTROLS.md`'s first table says Space interacts and W swallows in
   keys-only, while the code binds W to interact.
8. `slam-hammer` shares the word "Slam" with Squash Slam; `chapter-3-crystal-caverns.md` makes
   the Hammer a Workshop recipe.
9. `matron.md` balances her against a basic sword and lists the wrong reward.
10. `03-world.md` says "Silk Armor"; Chapter 2 Beat 9 calls the Caverns exit sealed, but it is
    open since 2026-10-10 (and the Axe's web curtain will close it again until Chapter 2 ends).

## 12. Branch, coordination and phases

- **Branch:** `exp/body-shapes`, from `exp/mouse-controls` @ 858c8a78, in the worktree
  `D:/projects/Slime isa-shapes`. The main checkout stays on `exp/mouse-controls` for the open
  editor and the atlas session. To drop the rework: delete the branch and the worktree.
- **Godot:** open `D:/projects/Slime isa-shapes/godot/project.godot` as a second project. Its
  first open imports everything into its own cache (slow once). The godot-ai plugin's ports are
  editor settings shared by both editors, so run one editor at a time or expect the second one's
  bridge not to connect.
- **Packages:** `pnpm install` inside the worktree; never link `node_modules`.
- **Atlas session (agreed 2026-10-11):** it owns `world-map.json`, the atlas,
  `build_region_worlds.gd`, the 8 placeholder worlds, `world_map_window`, `WORLD_ATLAS.md` and the
  elevation work in progress (ramps, then stairs). This rework owns combat, player, abilities, UI,
  crafting, quests, weapon and object scenes, and the new interiors (the hideout, the dungeons).
  The new interiors and the changed markers (Fatty and Matron become dungeons; the Crystal seal
  needs the Axe) go into `world-map.json` by the atlas session's hand. Either side tells the
  other before touching `level-1`, `gloop-forest`, `crystal-caverns` or a shared file
  (`scene_index.json`, `project.godot`, `export_presets.cfg`, `AGENTS.md`, `TOOLING.md`,
  `ARCHITECTURE.md`, `CONVENTIONS.md`, `03-world.md`, `05-unlock-map.md`). `exp/mouse-controls` is
  merged into the branch from time to time; the elevation work must be committed and merged before
  the rework touches level-1, and dungeon stairs wait for the atlas session's stair work.

| Phase | What | Art credits | Gate |
|---|---|---|---|
| 0 | The owner answers the open questions | 0 | Yes |
| 1. Shapes grey box | Shape controller, Spear and Axe (Hammer for the playground) with rotated 8-way hitboxes, tags, the new Slam, in the playground behind `?shapes`, beside the old system. Code-drawn spike, arc, ring | 0 | The owner plays it and likes it more than the old weapons |
| 2. Mouth and box | The Q state machine, the goo ring, the Ability Box, the new keys, HUD slots | 0 | Playtest |
| 3. Yoi's Hideout | Secret cover and jingle, bell exports, the wooden gate, the maze world, Yoi (grey-box still), his quest | small (Yoi still) | Playtest from a new run |
| 4. Dungeon kit | Rooms, room camera, doors, keys, chests, room fights, Pearl, death at the entrance, the dungeon lab | 0 | The lab plays right |
| 5. Fatty's Lair | Grey box with existing enemies, then the Squint, Fatty's phase 2, Pearl 1 | 0 | Chapter 1 playable start to end |
| 6. Cut-over | Remove weapons, belt and recipes; the quest chain; schema 2; the tests rewrite; docs | 0 | Chapter 1 plays on the new system only |
| 7. Weaver Hollow | Grey box, the thick webs and tethers, the Axe chest, the Lurker, Broodlings, the Warden, the Matron rework, Pearl 2 and Silk Reel | 0 | Chapters 1-2 playable; the suite run once with the owner's OK |
| 8. Art | Diagonal stills, Spear and Axe key poses, strips; dungeon kit art; enemies; Yoi | ~4-6k plus the dungeon art | Art review in game |
| 9. Content and balance | Heart quarters, come-back secrets, the well cellar and smith's store, balance | small | Playtest |
| 10. Decide | Adopted: delete the old art and scenes, merge. Dropped: delete the branch | | The owner |
| Later | The Hammer in the story, the Roll, the Lash, the Forge, gamepad | | |

## 13. Open questions

**Answered on 2026-10-11:** the sketch reading; the Hammer comes later (playground now); Fatty
keeps teaching an improved Slam that breaks no rocks; the Spear comes from Yoi's hidden maze
cavern, found through Lili; no Roll in Chapter 1; the Lash moves later; trees and rocks stay
harvestable and hide secrets; thick webs guard secrets, and a web curtain closes the road to the
Crystal Caverns until the Axe; every boss in a dungeon with its Pearl inside; Q does the whole
mouth; the Ability Box on S, the Roll the only other key; Pip's Forge after the Hammer; Sunny's
basket becomes a come-back secret; the branch in its own worktree.

**Still open** (defaults in italics; more detail in the dungeons plan, section 12):

1. **Pearl 2 and the Roll:** *charges come with every shape, so Pearl 2 gives Silk Reel (a longer suck); the Roll comes in Chapter 6 on D* (see the [power curve](2026-10-11-world-power-curve.md)).
   Or every Pearl teaches a new move (two powers per dungeon; the power curve explains why not).
2. **Fatty's Lair item:** *none; a big key opens the boss door, and Fatty's phase-2 mud clods can
   be sucked and thrown back to daze him.* Or the first Heavy Gulp upgrade, found in the lair.
3. **Dungeon rules:** *a Zelda room camera (scroll, dark curtain, no zoom); small keys counted per
   dungeon, never bag items; one big key; the map in a chest; dying inside wakes at the entrance
   with keys and doors kept; room enemies come back, puzzles and ambushes stay done.*
4. **Mouth details:** *one long hold works (suck an essence and keep holding to swallow it); in a
   form, Q sucks for 0.25 s first, then becomes the spit ring; letting go before 2 s cancels; the
   slime stands still while the ring fills; the throw on release.*
5. **The key-item rule:** *"each region has one key item: it opens the region's dungeon or is
   found inside it, and the boss needs it" (Chapter 1: the Spear; Chapter 2: Swallow opens the
   Weaver Hollow, the Axe is found inside).*
6. **Hearts:** *four quarters per region (its caves and dungeons included) plus a full heart per
   boss: 180 max HP after Chapter 2.*
7. **Chapter 2 after Tom:** *The Sealed Hollow: the Stone form opens the iron hollow, and a war
   cache from Kiri (Yoi's old comrade, lore only) holds the dungeon map.* Or the Gloop Cavern on
   the main path.
8. **Pearl homecoming:** *each Pearl goes to Plop, who tells a piece of the story, until the
   Wellspring map exists.*
9. **Names:** answered: Lily the fisher becomes **Dora** (npc id `fisherman-slime` stays). The
   name appears in `npc-definitions.json`, `quests-chapter-1.json`, specs (interaction, quests,
   water, world), story docs, the roadmap, and the atlas session's `world-map.json` (its edit).
10. **The R key for the box:** *yes, R opens the box (taught only when it holds two abilities).*
    Or the box only from the menu tab.
11. **Saves on the branch:** *a clean break; migrate only if adopted.*
