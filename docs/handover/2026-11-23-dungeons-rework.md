# Handover: the rework of dungeons 2 and 3 (stopped 2026-11-23, 23:41; step 1's fix round run 2026-11-24)

Where the work stands, for the session that picks it up. The owner's brief, the audit, the new maps
and both boss fights are in [the plan](../design/2026-11-23-dungeons-2-3-rework.md); its three
sketches are in `docs/design/dungeons-rework/` (redrawn by `output/dungeon-rework/*.py`).

**How he wants it run:** one session plans, sketches and reviews; builder agents build; he is shown
only finished work (real art, full motion, sounds). Tests run only when he asks.

## Decided today

- **Step 1 approved** ("yes we can start step 1"): the knock target, the ram and the runaway cart
  in a lab world.
- **No heart quarter inside a dungeon** (they are outside-world secrets). Written into the level
  design guide, DUNGEONS.md "Chests", the game guidelines, the roadmap (5.3), the unlock map and the
  decisions archive. The built Hollow still has one in the Pillar room (`weaver-hollow-pillar-heart`
  in `rooms/weaver-hollow-boughs/B6-the-pillar.tscn`): left in place, it goes with the rebuild.
- **Accepted as proposed on 2026-11-24** ("Yes, start step 2"; they waited until then) (the plan's "The owner's calls" 1, 2, 3, 5, 6): both dungeons as room worlds
  with the interior walls; the Hollow's big key on the rafters; the Ram Cellar in place of R3's drop
  gate, key 1 on the hub's gallery and the compass in R2; the Mine's key 2 on the shaft's ledge and
  M7's cart; the two boss exams. Step 2 started on 2026-11-24.

## Step 1: built, first pass

One builder agent, about 75 minutes. All of it is uncommitted, with the rest of the working tree.

| Piece | Files |
|---|---|
| Knock target | `godot/game/dungeon/knock_target.gd`, `scenes/objects/dungeon/knock-target.tscn` |
| Ram, bricked arch | `godot/game/dungeon/ram.gd`, `bricked_arch.gd`, their scenes |
| Runaway cart, rail gate | `godot/game/crystal_mine/ram_cart.gd`, `rail_gate.gd`, their scenes |
| Shared | `godot/game/dungeon/mechanism_strike.gd` (what a moving part does to what it sweeps), `mechanism_debris.gd` |
| Lab world | `godot/game/dev/mechanisms/mechanism-lab.tscn` (F6 on it; built by `tools/build_mechanism_lab.gd`, `--force` overwrites hand edits) |
| Films | `tools/film_mechanisms.gd`, `scripts/godot/film-mechanisms.sh`; eight films in `output/mechanisms/<name>/` (strip.png, film.gif) |
| Art | sources and prompts `asset/Originals/dungeon-kit/mechanisms/`, packer `scripts/art/pack-mechanism-art.py`, runtime `godot/asset/MAPS/objects/mechanisms/` |
| Sound | ten cues as round 15 of the sound picker (22 takes), players added to `godot/game/scenes/audio/global.tscn` |
| Data, docs, tests | `dungeon.knockTarget`, `.ram`, `.ramCart`, `.burst` in `game-constants.json`; DUNGEONS.md "Mechanisms"; `tests/test_mechanisms.gd` (14 tests, compiled, never run) |

**Checked by the reviewer:** the eight films, frame by frame for four of them; `mechanism_strike.gd`
and the ram's cycle read in full; the other scripts scanned for rule breaches (none found); every
new script compiles (`--check-only`, 23:41).

**Credits:** 358 Magnific credits spent of the 800 allowed for step 1 (six image sheets 240, sounds
115, one background removal 3).

## The fix round that was stopped

Sent to the builder at 23:39 and stopped two minutes later, before it changed any file. **Run on
2026-11-24** by a builder session: see [The fix round, done](#the-fix-round-done-2026-11-24) below.
The list as it was given:

1. **The slime and the ram:** the log draws over a slime it has knocked. Knock the slime across
   the lane, clear of its two cells, before the head arrives. Refilm `ram-slime`.
2. **Armour:** a Thorn Guard took 15 of the ram's 60 and barely moved. A mechanism's hit on an enemy
   should be true damage, and a heavy enemy should still travel two cells or more. Refilm
   `ram-enemies`.
3. **The rope** between a target and its mechanism is a plain thin line: draw a real rope (two-tone,
   a shadow, pinned by floor eyelets, sagging when slack, a whip when knocked); the cart's haul
   chain thicker.
4. **The cart seen from the front** has no moving part while it rolls: rattle, jostling ore, sparks
   at both wheels.
5. **Films missing:** `target-blast`, `target-roll`, `arch-refuse`, `gate-refuse`, `ram-south`,
   `ram-west`, `cart-hook` (the cart stopping against a node with `on_mechanism_hit`, the ram
   swinging on through one).
6. **Small:** the refusal lines' throttle uses real time in `bricked_arch.gd` and `rail_gate.gd`
   (make it as `key_door.gd` does it, or say why); the lab's Worm Swordsman showed 8 health, not 90
   (find out why); name the weakest of the ten cues.

## The fix round, done (2026-11-24)

Everything is uncommitted, with the rest of the working tree. Every touched script passes
`--check-only`; `tests/test_mechanisms.gd` is updated and compiles (not run). DUNGEONS.md
"Mechanisms" (a new subsection, [A mechanism's blow on an enemy](../godot/DUNGEONS.md#a-mechanisms-blow-on-an-enemy)),
BODY_SHAPES.md (the hit's two new fields) and AGENTS.md's film list say what is true now.

1. **The ram and the slime** (`mechanism_strike.gd` `shove_slime`, `ram.gd` `_shove`): the slime on
   a ram's lane is shoved across it, to the side its feet stand on (down or right from the middle
   line), far enough to stand 16 units past the lane's edge, at 1800 units/s, as soon as the head
   would reach it in that time: out of the lane before the head arrives, the log passing beside it.
   True damage 12 as before; i-frames and a Roll refuse it (then the log passes over it). The slime
   is also always knocked aside in the shared sweep (the cart's rule), as the fallback.
   `ram.slimeKnockSpeed`, `slimeClearPx`, `slimeBodyPx` are new numbers.
2. **Armour:** a mechanism's blow on an enemy is true damage (`true_damage`: no part, phase or
   knockdown multiplier), lands through a phase's shield on the ground (`true_blow`, also past the
   wake guard and the phase's armor; never a boss, never a phase off the ground) and moves the body
   at least `hit.resistFloor` (0.6) of the knock (`resist_floor`). Code: `hit_reaction.gd`
   (`blow_lands`, the gate, steps 2 and 3 of `decide`), `enemy_reactions.gd` (`damage_scale`,
   `blow_lands`, `_resist`), `patterned_enemy.gd` (its shield check). **What was wrong in the first
   film:** the Thorn Guard was asleep, so every hit clinked; its 15 was the bowl damage of the
   brawler flung into it, and after that bowl its wake guard turned the ram's blow into armor.
   **Unmovable, reported and not forced:** a sleeping or waking Thorn Guard is rooted by design
   (`thorn_guard.gd` `_slides_when_stunned`): the ram now cracks it for 60 and it does not budge.
   The full lists (19 enemies with `knockbackScale` 0, 17 always rooted while stunned, 4 rooted in
   some phases) are in DUNGEONS.md. The film stages the guard awake (put in its march by the tool).
3. **The rope** (`knock_target.gd`): two twisted strands, an outline, a shine, a soft shadow; iron
   eyelets (a plate and a ring it runs through) at the foot, at each rope point and along a straight
   run; taut when armed, loose curves between pins when slack, a whip along it when knocked (and a
   small one at the snap upright). It now hangs down the back of the disc to a foot beside and just
   behind the post, no longer across the target's face. **The haul chain**
   (`ram_cart.gd`): 12-unit links, oval and edge-on in turn, outlined, with a shine and a shadow.
4. **The cart from the front** (`ram_cart.gd`): the picture cut at the rim into the ore heap and the
   bin; the bin jolts on each sleeper joint and rocks to alternate sides, the heap jostles a moment
   later, two loose stones hop on the hard jolts, sparks fly at both wheels.
5. **Films:** all 15 filmed again with the round's code (`output/mechanisms/<name>/`: strip.png,
   film.gif, film-slow.gif, film.json with notes), each looked at frame by frame:

   | Film | What it shows | Still weak |
   |---|---|---|
   | `ram-slime` | two swings: the slime on the middle line halfway down (shoved 120 south), then north of the line near the far end (shoved 90 north); 12 damage each; its feet 56 and 50 units outside the lane when the head reached its spot; the log never on it | the shove starts with the head about 70 units off, and the hurt pause (3 frames) freezes that gap: a hard shove, not a touch |
   | `ram-enemies` | Brawler 55 and Spider 40 killed and flung about 200 units; the Thorn Guard (put in its march by the tool) takes the true 60, knocked down, slides 147 units (2.3 cells) | asleep, the guard would not move (rooted by design) |
   | `ram-south`, `ram-west` | lane B's ram moved and turned by the tool: the log on end swinging south, from the side swinging west; a Worm Brawler on the lane struck (55) and flung 200; `ram-south` at `--zoom=1.1` (the gantry's top to the lane's end is taller than a screen) | staged by moving the lab's ram, not placed in the lab |
   | `target-blast` | the Goo Bomb cast and spat beside the target, the slime backs off; the blast trips it, it spins, the ram swings; the rope goes slack in curves | the knock's whip is hidden under the blast |
   | `target-roll` | a Roll into the post: a clink, the line, the target stays armed, the ram ready | the target's rock from a tap is small |
   | `arch-refuse` | the Spear, a pot and a Goo Bomb against the bricks: three lines, the arch stands | the lines fade within a few frames in the film: floating text runs on real time and the film renders slower than real time (in play they last 2.2 s) |
   | `gate-refuse` | the Spear, a pot thrown along the rails, a Goo Bomb: three lines, the gate stands | as above |
   | `cart-hook` | a standing dummy (the hook probe with the training dummy's picture) on the second cart's rails: the cart stops against it (one `cart` call, no damage); then on lane B's lane: the log swings through it (one `ram` call) | (fixed in the second round: the cart now stops with its front on the hurtbox's edge) the log passes behind the dummy (depth order), not visibly against it |
   | `cart-gate` | the front view rolling: the bin jolts and rocks on the sleepers, the heap shifts, sparks at both wheels; the gate bursts, the cart stays at its buffer | the two loose stones are hard to tell from the heap at game size |
   | `cart-return` | the haul chain (big links, readable) and the counterweight hauling the cart home; the target rearms | — |
   | `ram-arch`, `target-arrow`, `target-refuse`, `cart-enemy` | as in the first pass, with the new rope (eyelets at `a-target`'s two corners) | `cart-enemy`'s Worm Swordsman has 8 health (below), so it dies at once |
6. **Small:** the refusal lines' throttle stays on real time, as the kit's doors do it
   (`dungeon_door.gd` `say`, which `key_door.gd` uses, also uses `Time.get_ticks_msec()`): it only
   spaces a floating line, presentation; said so in both scripts and DUNGEONS.md. **The Worm
   Swordsman's 8 health** is not the lab's fault: `game/scenes/characters/worm-swordsman.tscn` says
   `max_health = 8.0` since the editor re-save of commit `88499375` (2026-10-06; it was 90), and the
   game reads a placed enemy's health from its scene (`enemy-types.json`'s `maxHp` 90 is read only by
   the bestiary pens). Every Worm Swordsman in the game has 8 health. Not fixed here (an existing
   scene, outside this round). **The weakest cue: `CartRoll`** (`cart-roll.wav`): the only loop, it
   plays through every run, yet it is the quietest take (RMS -26 dB, 7 dB under the others), half
   of its 2.25 s sits below -30 dB, and it has almost no low end (1 % under 200 Hz): ticks and hiss
   rather than a heavy ore cart. Next weakest: `ram-windup-2` and `ram-ratchet-2`/`-3` end cut off
   at a loud point (their last 50 ms at -21 to -24 dB: a click at the end).

Also found and fixed on the way (the refusal films showed it): a thrown thing broke on the rail
gate and the arch as on a wall and never met their hurtboxes, so a throw never said their line (their
own bodies hid their hurtboxes from the throw's line test, and the hurtboxes stopped short of the
bodies). Both now name their body (`get_body()`, as the knock target does) and their hurtboxes reach
past it (`rail-gate.tscn` 132 x 76, `bricked-arch.tscn` 84 x 74). And a Goo Bomb laid against the
arch's bricks did not reach it (its blast point sat 34 units up the doorway): it is now the bricks'
middle. From the side, the gate's posts still stop a throw as a wall does.

The first builder (agent `aebdb7157b620d10a`, in the session of 2026-11-23) was not used.

## The second fix round (2026-11-24)

The review accepted the fix round with four follow-ups; done, uncommitted, every touched script
compiles, the tests updated and compiled (not run).

1. **Invulnerable by design stays invulnerable:** `EnemyReactions.invulnerable_by_design(enemy)`
   (the enemy answers `is_invulnerable()` true) makes a mechanism's blow clink, in `blow_lands`
   (the patterned shield) and in `can_receive` (any gate). Only the Prism Eye answers it (with
   `pattern.invulnerable`). The other `_shields` users checked: none is invulnerable by an owner's
   rule except two a blow cannot hurt anyway (the Gloomling has no hurtbox; the Carnivore Plant,
   "only fire kills them", zeroes a thrown-class hit, which a blow is, and dozes off). Test
   `test_a_mechanism_clinks_on_an_enemy_invulnerable_by_design`.
2. **True damage keeps the gate's 0:** `damage_scale` asks the gate first and skips only the three
   multipliers. The `noSleep` rule is kept (every `noSleep` phase that has a shield is one where the
   body is out of reach: underground, in the air, in a pipe, behind crates) and described truly in
   the code and DUNGEONS.md, the Bulwark's charge and skid named as marked but unshielded.
3. **The cart stops at contact:** a hooked node is found ahead, the cart rolls on until its front
   (`CONTACT_SIDE` 42, `CONTACT_FRONT` 8) touches the hurtbox's near edge, and the hook call, the
   bump, dust and sparks come at that touch; the ore falls back round the cart (`ram_cart.gd`; the
   sweep defers the call: `MechanismStrike.sweep(..., defer_hooks)`, `call_hook`, `area_rect`). The
   film's dummy got a hurtbox as wide as its arms (the probe's new `size`). `cart-hook` refilmed:
   its front 0.0 units from the hurtbox, the call at the bump.
4. **Sound:** `CartRoll` redone as option "b" (two five-second looping takes, 50 Magnific credits;
   a 3.3 s loop cut from the first, levelled, crossfaded), played at -19 dB (`CUE_TARGET_DB` in
   `stage-round.py`), the player at -1.0 dB instead of -8.2; the tails of `ram-windup-2`,
   `ram-ratchet-2` and `-3` faded (60, 40 ms curved). Round 15's manifest and picks, `cues.mjs`,
   `urls.json`, the packed copies and audio spec §17 updated. Still unheard by anyone: judged by
   measurement only.

Left as the review said: the Worm Swordsman's 8 health (the owner's scene) and the shove's lead.

## Step 2: boss look sheets (2026-11-24)

Art only, for the owner's yes on each boss's look before any frames or fight are built. Nothing under
`godot/` was touched; nothing is packed.

- **The sheets:** `output/boss-rework/matron-look.png` and `output/boss-rework/colossus-look.png`,
  made by `output/boss-rework/make_look_sheets.py` (kept beside them; `output/` is git-ignored, so
  they stay local). Each has the design large, every pose labelled at 1.5x game size with the slime
  beside it at the same scale, and a true-size panel (1 : 1 game pixels on 64-unit floor cells). The
  bosses are sized as in the game today: the Matron about 190 px wide, her cocoon about 130, the
  Colossus about 180 tall; the slime 51.
- **The Matron:** her design (a crimson crown and collar edged in gold, the web-marked abdomen with
  three egg sacs, six red eyes, venom on her fangs), then hanging idle, spitting, the dive, caught by
  the ram, on her back kicking, climbing back up, spinning a cocoon, beaten (an extra), and the
  cocoon whole and torn (her crown's points and spines show through the silk).
- **The Colossus:** his design with the three plates marked L, C, R as in the plan's sketch, then
  walking toward you, to the side, away, the stomp raised, a plate brittle (orange), a plate burst
  (rose quartz under it), clinging to the wall, on his back. At 1 : 1 his three plates can still be
  counted.
- **Sources and prompts:** `asset/Originals/dungeon-kit/bosses/matron/` and `.../colossus/` (a
  README in each). Every first take was used except the Colossus's design (takes A and B came with
  a heart-shaped chest plate, kept as `-rejected`) and his "on his back" in the second pose sheet (a
  jumble, retaken alone).
- **Credits:** 400 Magnific credits of the 600 allowed (ten generations at 40).
- **Weakest:** the Matron caught by the ram (she tilts more than she flies: the flight is the code's
  job); the Colossus walking to the side (his far shoulder plate shows as a smaller second plate);
  the Colossus clinging to the wall still wears both shoulder plates, though in the fight he climbs
  with two plates gone (the plates will be layers over his body, as the plan says).
- **The owner's yes (2026-11-24):** "i like both keep going". Both looks approved; the frames and
  sounds come next, in the same art session, with 1,200 Magnific credits for them (his pick).

### The frames and sounds (2026-11-24, same session)

Art and sound only, still nothing under `godot/` and nothing packed. 1,150 of the 1,200 credits:
23 image sheets (920) and 22 sound takes (230).

- **The Matron:** nine animations of four frames each in
  `asset/Originals/dungeon-kit/bosses/matron/frames/`: hanging idle, the spit, the dive, caught by
  the ram, on her back kicking (retaken: the first take was not upside down), climbing, spinning
  her cocoon, the cocoon knocked down / straining / torn on the ground (its first frame not used),
  dropping out of the cocoon and dazed. The cocoon's breathing and swing stay in code
  (`matron_cocoon_look.gd` does them already).
- **The Colossus:** six animations (three walks, the stomp with a stagger, leap and cling, the fall
  and on his back), each drawn twice: with his plates and as a plate-less edit (rose quartz in the
  sockets), plus a sheet of burst shards. `scripts/art/boss_frames.py` turns each pair into a bare
  body per frame and a layer per plate (L, C, R), so any plate can be cold, hot or gone on any frame;
  how, and the plates' naming per view, in `.../colossus/README.md`.
- **Previews** (git-ignored, `output/boss-rework/frames/`): `matron-showcase.gif` and
  `colossus-showcase.gif` (every animation playing at once at game size, sent to the owner; the
  Colossus's breastplate going cold, hot, bursting), the `-contact.png` sheets (every frame), a GIF
  per animation. `python scripts/art/boss_frames.py preview|contact|showcase` rebuilds them.
- **Sounds:** Sound Picker round 16 (`scripts/audio/picker/round-16-make.py`, takes in
  `temp/sound-round-16/`), published to the
  [Sound Picker](https://claude.ai/artifact/RDDoJKEVByiJCSsRvzwLHZ) page for the owner's picks: the
  Matron's hiss (2 options), shriek (2), landing (1); the Colossus's stomp (2), roar (1), a plate
  bursting (2), a cold plate clanging (1). Two takes each. Not staged: `stage-round.py --picks` with
  his picks once the fights play them (it writes the players into `global.tscn`).
  `prep-takes.py` keeps takes already written: delete `temp/sound-round-16/takes/` before re-running
  it after a manifest change.
- **For the fight builder:** pack the frames from `boss_frames.py` (its `frames_of` and
  `armour_frames` give the lined-up frames at one scale per boss); the Matron's cells were 384 px at
  `pose_scale` 0.5, the Colossus's 384 px at 0.56 (`crystal-colossus.tscn`); the Colossus's side walk
  is drawn facing right (mirror it and swap L and R for the left). `docs/TOOLING.md` does not list
  `boss_frames.py` or round 16 yet (this session was kept to the handover among the existing docs).
- **Weakest:** the walks are short four-step loops with small arm swings (they read as a heavy
  plod at 6 fps, not a stride); the Matron's dazed frames keep her red eyes bright (asked dim); the
  Colossus's mid-air fall frame shows two plates; two of the hiss takes end in the generator's own
  cut at two seconds (faded).

### The fights (2026-11-24, same session: "Yes, build the fights")

The frames are packed for the game (`python scripts/art/boss_frames.py pack`:
`godot/asset/MAPS/enemies/bosses/{matron,colossus}/`, strips, the Colossus's plate atlases and burst
shards, `frames.json`; drawn by `game/bosses/boss_sheet_sprite.gd`). Round 16's sounds were picked
by the owner and applied (audio spec §18; players under `Effects` in `global.tscn`, naming packed
copies). Each new fight is its own boss scene in its own lab, so the built dungeons keep today's
fights until steps 3 and 4 rebuild their rooms.

- **The Matron: built and filmed.** `character.orb-weaver-matron-rework` (`game/bosses/matron_ram.gd`
  extends matron.gd, whose only change is the `_runs_ai()` hook; `matron_ram_look.gd`, `web_glob.gd`)
  in `world.matron-lab` (`tools/build_matron_lab.gd`); the whole fight in
  [matron spec §9](../godot/specs/matron.md#9-the-ram-fight-the-rework-built-2026-11-24-in-a-lab-not-yet-in-the-hollow).
  The owner changed the plan while it was built, and the build follows him: **five rams along the
  north wall**, their targets roped across the room so which target trips which ram takes finding
  (his drawing); **the rams are both sides' tools** (a ram catching her dive hurts her 20; she
  spits a glob of web at a target to trip a ram at the slime); **every cocoon hangs over one ram's
  lane, at random**, so round 1's cocoon can be knocked down too; **her spit and webs bigger**.
  Films (`scripts/godot/film-matron.sh`, `output/boss-rework/matron-films/`): `round1`, `dive`,
  `ram-catch`, `ring`, `round3`, `ram-call`, `look`, each looked at; four sent to the owner as small
  GIFs (`*-owner.gif`, `output/boss-rework/make_owner_gifs.py`). Weak: the films stage her health and
  hold her attacks while the slime casts (a hit or her web breaks a cast, her brood bites through
  one); a knocked-down cocoon tears only when the bomb lies by its middle; five web rings in round 2
  are a lot of white; the climb pose's move to a new lane during a respin glides along the ceiling.
  Not played with a keyboard; no tests for the ram fight.
  **The review's three fixes (2026-11-24), done:** (1) a cocoon always closes over its lane: far from
  the new lane's middle she climbs to its hang and crawls along her web to it (shell "relocating",
  `relocate_speed` 320), then spins there; refilmed `round3-south` (from (768, 1088), the farthest lane
  ram-1: closed at x 288.0 on its middle 288.0, 4950 ms) and `round3-west` (from ram-1's lane to ram-5's:
  closed at 1247.7 on 1248.0, 5616 ms), both through to her fall; no snap in the frames. (2) Round 2's
  first dive keeps its time: a dive clears `_next_dive_at`, a climb's end sets it only when it is
  clear. (3) `ram.gd` has `get_knock_target()`; her ram call and the film use it. Every touched script
  compiles. **The follow-up check (her crawl blocked):** with the slime standing on the new lane's
  middle she stalled 55 units short, still crawling after 10 s (`--lie=slime`); a target's post on her
  line only slowed her (`--lie=post`, about 0.4 s). Fixed as the Colossus in the air: up on her web
  (hanging, climbing, crawling, spinning, cocooned, diving) her body collides with nothing; down on
  the floor (landed, flung, open, her cocoon knocked down) her mask (world, player, water) is back
  (`_set_shell`). Refilmed: `relocate-slime` closes at 1247.7 on 1248.0 (5.6 s), `relocate-post` at
  290.6 on 288.0 (5.0 s), and `ram-catch` still crashes at the south wall.
  **The owner's two changes after the films (2026-11-24):** (1) "move the triggers, they should
  align vertically with the ram ... player can't even see where the trigger connects": every target
  now stands straight below its ram's lane by the south wall (row 16.8), its rope up the lane; the
  lanes are 9 cells (ending at row 14.6), the slime spawns at (10.1, 16.9), the bottom pots sit between
  the targets. Round 2's catch is now: bait her dive at the lane's lower end, step down into the
  target's ring (the Silk skin or a Spear cut) and throw up at it; the log flings her about 100 units
  into that ring (no longer to the far wall), where she lies beside the slime. (2) "the webs that she
  miss should be throwables in case we ran out of pot ... in fattys was the mud balls": a volley's
  mark that misses the slime, and a spit that misses it, leaves a **web ball** (new liftable kind
  `web-ball`, two looks; one Magnific generation, 40 credits, the total now 1,190 of the 1,200; cut by
  `scripts/art/split-web-balls.py`, packed by `scripts/props/pack-gulp-art.py` into row 8's last two
  cells), at most 6 at once, the oldest unravelling; thrown it sticks as the mud ball does.
  `ProjectileScript` gained `did_hit_target()`. Refilmed on the new layout: `look`, `ram-catch`,
  `web-balls` (new: no pots, her volley misses, a web ball thrown at her lane's target knocks the cocoon
  down; a missed spit left a fifth ball), `ring` (now thrown down from the north: the thrower stands in
  the lane's lower end, so the ram it trips hits it for 20; from the side or from inside the ring is
  safe), `round3` (through to her defeat), `ram-call`; `ram-catch` and `web-balls` sent to the owner as
  small GIFs. A crash the owner hit after throwing a web ball (a sucked-up ball is freed; the list's
  typed `filter` failed on it at the next drop) is fixed with `_prune_web_balls()`.
- **The Matron, the owner's third round (2026-11-24):** her full heart rises in the lab's middle
  (`matron-lab.tscn` edited in place, the builder too); after a dive she lies `landed_ms` **4000**
  (900 before: "time to trigger the" ram); and lying there she **calls a ram from the floor**
  (`ground_call_after_ms` 600 after landing, once a landing, the slime in a ready ram's lane, her own
  lane too), staying down `ground_call_stay_ms` 1000 past the glob's landing so her own log reaches
  her: the slime waits in her lane, steps out when she spits, and she flings herself ("the player can
  trick her to make her hit her self"). Films: `ground-call` (new: called 600 ms after landing, the
  slime unhurt, flung 1.6 s after landing, 190 to 170, on her back), `dive` (the slime now in a gap
  between lanes; down 4.0 s), `round3` (the heart in the middle). `ground-call` sent as a small GIF.
- **The Colossus: built and filmed** by a builder agent this session started, checked here (the
  scope, every script compiled, the films looked at). `plate_fight` on `crystal_colossus.gd` (off: the
  mine's fight as before; its other changes are gated by it) and `colossus_arena.gd`, his look
  `game/bosses/colossus_look.gd` (bare body, plates laid on cold, hot or gone) and the burst
  `colossus_shards.gd`, the cart's `through` mode and kick (`ram_cart.gd`), new keys in
  `enemy-types.json` `crystal-colossus`; `world.colossus-lab` (`tools/build_colossus_lab.gd`, its own
  boss id, so the real Colossus is never marked beaten). All of it in DUNGEONS.md
  ["The plate fight"](../godot/DUNGEONS.md#the-plate-fight-step-2-of-the-rework) and
  ["The Colossus lab"](../godot/DUNGEONS.md#the-colossus-lab). With the owner's changes: a bigger
  room (24 x 20 cells); a void strip down each side (a fall costs 10 and puts the slime back where it
  stepped off); the carts come out of tunnels in the side walls (the mine gate's doorway turned on its
  side), cross the voids on their rails and pass through if they miss him; a cart that hits him he
  kicks back into its tunnel; a lit brazier's ring (150) makes his plates hot, the Lantern lights it
  from about a cell. Films (`scripts/godot/film-colossus.sh`,
  `output/boss-rework/colossus-films/`): `look`, `poses`, `walks`, `glow`, `burst`, `clang`, `pass`,
  `dip`, `bare`, `wall`, `core`; four sent to the owner as small GIFs. **Decided by the owner:** his
  time on his back stays 4 s (`plateFallStunMs`), not the plan's 2.5 s ("Keep 4 seconds",
  2026-11-24; the cart now comes from the far tunnel); the upper line's target moved by the middle
  roots. Weak: no kick art (the side walk's
  stride), the tunnels are flat portals and the rails cross the voids on bare sleepers, the stomp and
  stagger art faces the viewer only, a cart counts as hitting him with his feet up to about 130 units
  south of the rails; the kick reuses `ColossusStomp`. Not played with a keyboard; no tests.
- **The Colossus, the owner's second round (2026-11-24),** built here:
  - **His leap** ("he is so slow ... does not have a jump or a charge to follow you"): a slime more
    than `hopFarPx` 300 from him for `hopAfterMs` 1.2 s and he crouches (a bright orange ring where he
    will land: a dark one was lost on the dark floor), leaps and lands `hopShortPx` 150 short of it,
    `hopDamage` 20 in the ring, no brazier out; every `hopCooldownMs` 5 s at most (new keys in
    `enemy-types.json`, the reactions' `hop` state immune).
  - **Dousing** ("the stump that shut braziers off is to frecuent"): hurt with all four lit, his
    stomps put them out one per stomp until none burns. Else a stomp puts one out only once
    `douseAfterMs` 45 s have passed with no brazier lit or put out (the owner's follow-up: the wait
    restarts whenever a brazier is lit or goes out, so "the player have 45 seconds after lighting a
    brazier to make his move"); that put-out restarts it too.
  - **His quake** (the owner asked if any phase made the vines a refuge; then "the queke last 5
    secodns and it make damage over time the way to avoid it is by climbing . a warning have to be
    issue by colossus ... add art if need it"): every 22 s (the first 14 s in), a 2.5 s warning (a
    roar and `GroundCreak`, reared and trembling, the screen rumbling, glowing cracks spreading over
    the whole floor, the root climbs lit with the glow moss's light), then 5 s of pounding: 6 every
    0.6 s to a slime on his floor (about 50), nothing to one climbing. First drawn with code lines;
    then the owner raised the Magnific budget to 1,400 ("make the crack art"): two GPT 2.5 stills
    (80 credits, 1,270 of 1,400 now), four painted fissures and four craters
    (`scripts/art/pack-quake-art.py`, `effects/colossus-quake-*.webp`), laid along rays from his feet
    and growing as the crack spreads, clipped to his floor (`game/bosses/colossus_quake.gd`). Film
    `quake`: on the floor 8 hits, 48; up the roots 0. Sent as a GIF with the two sheets.
  - **Falling rocks** (the pots run out: "colossus need to make rocks or cristals on every single
    attack ... thy never block the rails"): 2 a stomp, 1 a leap's landing, 1 every other quake pound;
    each falls (a growing shadow, the rock's picture dropping, `game/bosses/colossus_debris.gd`) on a
    free spot of his floor never by the rails, 10 to a slime under it, and lies as a light liftable
    (ore rock, crystal cluster, geode; their own weights are medium and heavy, too heavy for a low
    Gulp); at most 8. Film `rocks`: every pot gone, two stomps drop 4 rocks (none by the rails), one
    on the slime 10, a thrown one trips the lower cart and it bursts his breastplate. Sent as a GIF.
  - **Heat cues, the clang hint, all four lit** (the owner asked whether one brazier is enough: it is,
    in its ring; then "yes build the heat up cues and the clang hint, also when all 4 braziers are on
    make the plater brittler also"): embers, a flash and `FireIgnite` as his plates heat, embers
    rising and the knock target of the cart line he stands on glowing while hot, steam as they cool;
    the first clang off a cold plate shows "Too cold to crack. Heat it in a brazier's light!" and the
    nearest unlit brazier flickers; with all four lit he is brittle anywhere (read as "brittle also":
    say so if he meant more brittle). `ram_cart.gd` gained `get_knock_target()`. Films `heat` (new:
    cold, hot with the target glowing, cold, hot far from every ring with all four lit) and `clang`
    (the hint); both sent as GIFs. A teaching monster before his arena (the owner's idea, my
    recommendation for the main teacher) waits for step 4, when his room in the Mine is rebuilt.
  - **Review fixes (the second read, 2026-11-25):** the Colossus's leap gets its time back when a
    crouch ends without its landing (a cart's blow staggered him in the crouch and he never leapt
    again: `_restore_leap`, in `_stagger` and at every step out of the leap); rocks still falling
    when he is beaten go with a puff of dust (`_clear_falling_rocks` in `_defeat`: his step stops, so
    they would have lain as rocks nobody can lift); the Matron lying after a dive says `landed_text`
    ("Her shell turns it. A ram would crack her.", throttled as `high_text`; diving and flung stay
    silent); two stale comments in `matron_ram.gd` (five rams in step 3, `get_home` is the picked
    lane's middle) and the spec's step 3 line. Compiled; not filmed.
  - **The Colossus's last phase lives on his wall** (the owner asked why nothing hurt him in phase 3: his
    core stops at 0 while a plate is left, and standing his last plate never glows, so only the wall
    route reaches him; then: "the last phase he stay on the vines and only comes down to do the quake
    ... every 5 seconds he trhow a rock at you this rock can hit you even in the vines"): with one
    plate left (and on his core alone) he goes straight up his wall whenever he is on his feet and
    stays there; mites as before; a rock every 5 s at the slime, on the floor or up the roots (lies
    as ammo on the floor off the rails, shatters on the wall); down only to quake, then back up
    (`_last_phase`, `_throw_rock`; `wallRock*` keys). Film `last` (new) shows each.
  - **The climb is a toggle** ("i cant use e while climbing since W have to be press ... i can't
    neither use spear while climbing"): an interact press clings, the next lets go (a fall starts let
    go, so a press while falling still catches); on the wall the chosen box ability's key (A) strikes
    with the Spear when its power is chosen, and E opens the ability carousel (player.gd
    `_step_climb`); the climb wall's prompt is "Climb". Every climb in the game changes. Film
    `climb`: the key let up, still on the wall; A with the Spear strikes; a second press lets go;
    `wall`: the claws struck three times as before. Tests that climb by holding interact
    (`tests/test_skins.gd` and others) will need a second press to let go; not run.
  - **The Heavy Roll smashes light things to throw** ("it make no sence that light throwables make you
    bounce back on roll ... break them with heavy roll ... the same animation as when throw"): a light
    liftable in the ball's way bursts as a thrown one does and goes as if sucked up (its loot left);
    the ball rolls on; medium and heavy ones still bonk; a plain Roll unchanged (`player_roll.gd`
    `_break_ahead`, `rollHeavyBreakRadiusPx` 34). Film `film-matron.sh <name> --film=smash`.
  - **The roots as a refuge, the top tunnels** (the owner: "if i climb the vines he stay there and don't
    let me go down ... if a roll there i fall behind the wall. when the player is in the vines colosus
    goes to the middle of the map"; "he keeps drawing behind the top rail gates"): while the slime
    climbs he leaps (or walks) to the middle of his floor, engaged or not (a climbing slime was no
    target, so he had stood still under it); no Roll off a wall (player.gd drops a Roll press while
    climbing, `_try_dodge` refuses); the north-wall tunnel doorways are sorted by where they meet the
    floor (`ram_cart.gd`), so he draws in front of them on the floor and a cart inside is still
    hidden. Film `climb` (new) and `wall` show all three. `retreatLeapPx` 140 is a new key.
  - **Two Colossus fixes the owner hit:** a crash in phase 2 (`live_mites()` filtered his thrown
    mites with a typed lambda, which fails on a freed mite and hands back an untyped Array: now a
    Variant loop; the `wall` film frees a thrown mite and the count reads 1); and he was drawn behind
    the tunnel doorways and the roots while leaping and clinging (now z 3 in `UP_PHASES`, the
    `wall` film shows him in front of both).
  - **The clang hint, readable, pointing** ("this hint need to stay longer on camara ... an arrow the
    braziers need to flash 2 or 3 times ... write that in the documents"): the line now follows the
    slime for 6 s, opaque until it fades at its end, wrapped and kept on screen (new
    `GameFeel.hint_text` / `floating_text_layer.gd` `spawn_hint`); every unlit brazier flashes three
    times under a bobbing arrow (new `game/feel/hint_cue.gd`). The rule is in GAME_GUIDELINES.md
    "Hints". Film `clang`: the arrows over all four, the line kept inside the screen. Note: the films
    run slower than real time and floating text runs on real time, so a film shows the line for less
    than its 6 s.
  - **The Goo Bomb has no cast** ("rework the bomb it not longer need casting and you can put many
    with a 1 second cool down"): `abilities.gooBomb.castMs` 0 (was 2000), `cooldownMs` 1000 (was
    600), 20 energy each as before; with no cast the sequence skips the swell, the bomb inside, the
    ring and its chime (`goo_bomb_sequence.gd`). Film `film-matron.sh <name> --film=bombs`: a press
    0.5 s after a bomb refused, three bombs lying at once, all blew. Tests that wait out a cast
    (`tests/`) may need their timing looked at; not run.
  - **The Matron's round 3** ("in phase 3 mattron not longer use if frist grounf web attack , is too
    many attacks"; "phase 3 is only when she have a hit left"): no volley in round 3
    (`volley_in_round_three` off: film `quiet3`, about 12 s, no volley); round 3 starts at 25 health
    (`round_three_below_hp` on the rework scene, `orb-weaver-matron-rework.tscn`) and open in it the
    first hit that lands is her last (`mitigate_damage`). Film `round3`: staged at 20, knocked down,
    torn, one Spear thrust, defeated. Round 2 now runs from 200 to 25 (not filmed end to end).
  - **The Heavy Roll crushes tiny enemies** ("the small spiders are push back by heavy roll"; the
    owner picked "Crush them"): a Heavy ball pops the Matron's Broodlings and the Colossus's Crystal
    Mites (reaction weight `tiny`) just ahead of it and rolls on, no bonk (`player_roll.gd`
    `_crush_ahead`, four `rollHeavyCrush*` keys in `character.player.movement`; SKINS.md). Film
    `film-matron.sh <name> --film=crush`: three Broodlings, all popped, no bonk, rolled 169. Sent as
    a GIF.
  - **The lab's arena is the whole floor** ("the fight reset every time i wal to the bottom of the
    scene"): the lobby is now a nook in the south wall (cells 12-13, rows 21-22; the lab 26 x 24
    cells), the pots that stood in it on the floor by it; rebuilt with `--force`.
  - **Two down lines** ("the top ram make no sense ... remove it and put to verticals"): the upper
    line is gone; two lines roll south from tunnels in the north wall (the doorway face on, whole:
    `ram_cart.gd`) under his two climb spots (three before) to the south wall, crossing the lower
    line; each target beside its line, its rope up along the rails into the tunnel; his crash lands
    on the line under him (`crash_carts`, the nearest, in the arena and on him). The lab rebuilt with
    `--force` (it had no hand edits); braziers renamed `west-brazier`, `east-brazier`.
  - Films: `look`; `hop` (new: crouched 1.2 s after the slime got far, leapt 448 then 254, landed
    133 and 149 short, the slime unhurt); `glow` (his stomp now leaves the brazier lit); `douse`
    (new: all four lit, the cart bursts his breastplate, then his stomps leave 3, 2, 1, 0 lit and he
    stops; two relit put the wait back to 45.0 s and survive a stomp; the wait staged as over, one
    goes out, the wait is back to 44.7 s and the next stomp leaves the other); `wall` (the crash on the west line at x 640, the cart out of the north tunnel takes his
    last plate, he kicks it home). The films that stage him hold his leap too (`_hold_stomps`).
    `hop`, `wall` and `douse` sent to the owner as small GIFs. Weak: the leap's frames face the
    viewer whichever way he leaps; the down lines cross the lower line, and two carts rolling at once
    pass through each other there.

## Step 3: the Trunk and the Roots

The first piece of step 3 (2026-11-24/25, a builder session): the Weaver Hollow's ground floor and
cellar rebuilt as room worlds with the root-rock interior walls, **beside** today's Hollow. Today's
four worlds (`weaver-hollow-trunk`, `-roots`, `-boughs`, `-crown`), their room scenes and the
forecourt's root gate are untouched: the game still plays the old Hollow; the switch-over comes when
the Boughs and the Crown are built too.

### The list of links (written before any scene)

Every room is its own world, as Fatty's Lair: a room scene in
`godot/game/scenes/worlds/rooms/weaver-hollow/`, `world.<id>` in `scene_index.json`, its Dungeon node an
instance of `game/scenes/objects/dungeon/weaver-hollow-dungeon.tscn` (`dungeon_id` and
`record_map_id` `weaver-hollow`, the final ids, so the switch-over changes no record), its map room
on `rooms/weaver-hollow/layout.tscn`. Cells are the room's own (column, row) from its top-left; a
room's rim is two cells deep (floor from (2, 2)). L0 is the floor, L1 the upper level.

| Room | World id | Size (cells) | Floor | Upper level (L1) |
|---|---|---|---|---|
| T1 Root Door | `weaver-hollow-t1-root-door` | 18 x 16 | L0, floor webs | the loft, cols 11-15 x rows 2-5, its chest |
| T2 the Hollow Heart | `weaver-hollow-t2-hollow-heart` | 36 x 32 (2 x 2) | L0 | the gallery: north rows 2-5 (all cols), west cols 2-4 (rows 2-25), east cols 31-33 (rows 2-29); its stair a front flight at row 6, cols 24-25 |
| T3 the Larder | `weaver-hollow-t3-larder` | 18 x 16 | L0 | the walk, cols 13-15: north part rows 2-3, the gap rows 4-6 (the drawbridge), south part rows 7-8 |
| T3's map nook | `weaver-hollow-t3-map-nook` | 10 x 8 | L0 | - |
| T4 the Well Room | `weaver-hollow-t4-well-room` | 18 x 16 | L0, the cracked floor | the ledge, cols 13-15 x rows 2-13 |
| R1 Root Fall | `weaver-hollow-r1-root-fall` | 18 x 16 | L0 | the landing ledge, cols 2-6 x rows 2-5, a front flight down at row 6, cols 3-4 |
| R2 the Bone Cellar | `weaver-hollow-r2-bone-cellar` | 36 x 16 (2 x 1) | L0 | - |
| R2's compass pocket | `weaver-hollow-r2-compass-pocket` | 10 x 8 | L0 | - |
| R3 the Ram Cellar | `weaver-hollow-r3-ram-cellar` | 18 x 16 | L0; a void (L-2) round the target's island | - |
| D1 the Old Cellar | `weaver-hollow-d1-old-cellar` | 18 x 16 | L0, dark | - |

The map (`layout.tscn`, a room 1152 x 1024): the Trunk (floor 0) T4 at (1152, 0), T2 at (2304, 0),
T3 at (1152, 1024), the nook at (512, 1152), T1 at (3456, 2048); the Roots (floor -1) R1 at (1152, 0),
R2 at (2304, 0), R3 at (4608, 0), D1 at (3456, 1024), the pocket at (2624, -512).

Doors and stairs (room doors pair `door_id` <-> `target_door`; "scroll" unless said):

| From (side, cells, level) | To | Lock |
|---|---|---|
| T1 south, cols 8-9, L0: `weaver-hollow-entrance` (door.gd) | the forecourt `gloop-forest-f4` / `weaver-hollow-root-gate` (one way while the forecourt keeps the old Hollow); the seal stands here | the seal (after Pearl 2, a later piece) |
| T1 north, cols 7-8, L0: `t1-north` | T2 south, cols 25-26, L0: `t2-south-t1` | - |
| T1 north, cols 13-14, L1 (the loft): `t1-loft-north` | T2 south, cols 31-32, L1 (east gallery): `t2-south-gallery` | from the hub: the web wall across the north gallery at col 30.5 (Silk, a later piece) |
| T2 west, rows 27-28, L0: `t2-west-floor` | T3 east, rows 11-12, L0: `t3-east-floor` | - |
| T2 west, rows 23-24, L1 (west gallery): `t2-west-gallery` | T3 east, rows 7-8, L1 (the walk's south part): `t3-east-walk` | from T3: the walk's gap (the drawbridge) |
| T2 south, cols 8-9, L0: key door `weaver-hollow-t2-south-door` (one keyhole) | nowhere yet (the Boughs) | key 1 |
| T2 north, cols 16-17, L1: the Crown Door (`weaver-hollow-crown-door`, boss door) | nowhere yet (the Crown) | the big key |
| T2 gallery stair, row 6, cols 24-25, L1 down to L0 | - | the stone block at its foot (`weaver-hollow-t2-stair-block`, a shutter), sunk for good by the gallery's winch (`weaver-hollow-t2-winch`) |
| T3 north, cols 7-8, L0: `t3-north-crack` | T4 south, cols 7-8, L0: `t4-south-crack` | a cracked wall on both sides, one flag `weaver-hollow.t3-crack-well` (the Goo Bomb) |
| T3 west, rows 5-6, L0: `t3-west-nook` (iris) | the nook east, rows 3-4: `nook-east` (iris) | a cracked wall, flag `weaver-hollow.t3-crack-nook` (the Goo Bomb); the nook's side a blown hole |
| T3 north, cols 13-14, L1 (the walk's north part): `t3-north-walk` | T4 south, cols 13-14, L1 (the ledge): `t4-south-ledge` | - |
| T3's walk, the gap rows 4-6, L1 | - | the drawbridge `weaver-hollow-t3-bridge` (hinge on the south part, lowers north 3 cells, L1), let down by the cracked winch post on the far rim (`weaver-hollow.t3-bridge-post`): a Goo Bomb thrown over the gap |
| T4 floor, the cracked floor at (6.5, 6.5): `weaver-hollow-t4-well-floor` (a fall, one way) | R1's landing on the ledge `weaver-hollow-r1-landing` (L1) | the Goo Bomb (flag `weaver-hollow.t4-well-floor`) |
| R1 east, rows 7-8, L0: `r1-east` | R2 west, rows 7-8: `r2-west` | - |
| R2 east, rows 7-8: `r2-east` | R3 west, rows 7-8: `r3-west` | - |
| R2 south, cols 26-27: `r2-south` | D1 north, cols 8-9: `d1-north` | - (D1 is dark: the Lantern, Chapter 3) |
| R2 north, cols 9-10: `r2-north-pocket` (iris) | the pocket south, cols 4-5: `pocket-south` (iris) | a cracked wall, flag `weaver-hollow.r2-crack-pocket`; the pocket's side a blown hole |
| R3 north, cols 10-11, L0: the Guard's stair up (`weaver-hollow-r3-guard-stair`, a stair door in the wall's stairs opening) | T4 north, cols 13-14, L1 (the ledge): the stair down (`weaver-hollow-t4-guard-stair`) | the bricked arch (`weaver-hollow-r3-arch`) in front of it: the ram (`weaver-hollow-r3-ram`, lane north, 5 cells) bursts it, let go by the knock target (`weaver-hollow-r3-target`) on an island in the void straight below the ram (col 11), its rope up to the ram's post |

The prizes: key 1 in a chest on T2's west gallery (seen from the hub's floor); the map in the nook;
the compass in R2's pocket; T1's loft chest (100 coins and a Slime Tonic, the Silkspun Stew recipe's
stand-in) seen from T1's floor, reached later from the hub's east gallery; D1's chest as today (the
war journal's second page, its old record kept so the page cannot be had twice).

The way through: T1, T2 (key 1 and the Crown Door in sight on the gallery, the stair blocked), T3
(two orb-weavers; bomb the north crack, and the west crack for the map), T4 (bomb the floor), R1 (the
landing ledge, the egg sac), R2 (the Watcher Eye, two Bone Throwers, the compass behind the crack),
R3 (a pot thrown over the void at the target: the ram bursts the arch), the Guard's stair up to T4's
ledge, the ledge into T3's walk, the bomb thrown over the gap at the post, the bridge, the walk into
T2's west gallery: key 1; the north gallery's winch sinks the stair block; down to the floor and key 1
in the south door.

## For the owner, in the editor

- Give the editor focus once: it imports the 23 new pictures and 22 new sounds and writes their
  `.import` and `.gd.uid` files (to commit).
- If `game/scenes/audio/global.tscn` is open in the editor, reload it before a save-all, or the ten
  new sound players are lost.
- Nobody has heard the new sounds: they wait in the sound picker as round 15.
- The fix round changed `scenes/objects/dungeon/bricked-arch.tscn` and `rail-gate.tscn` (their
  hurtboxes): if either is open in the editor, reload it before a save-all.
- Every film log warns that `mechanism-lab.tscn` names `chest_root.gd` by a UID the project does not
  know yet (the editor has not imported that script): focusing the editor once should settle it.
- No existing world or room scene was touched.
- Round 16 (2026-11-24) added seven players under `Effects` in `game/scenes/audio/global.tscn`
  (`MatronHiss` ... `ColossusClang`): if it is open in the editor, reload it before a save-all.
- The liftables sheet (`asset/MAPS/props/192x192-tile_8x9-gulp-liftables.webp`) was repacked with the
  web ball (2026-11-24): until the editor imports it, a run shows web balls as empty (the Matron films
  read the sheet's file instead). Give the editor focus once.
- Two new pictures for the Colossus's quake (`asset/MAPS/effects/colossus-quake-fissures-1x4.webp`,
  `colossus-quake-craters-4x1.webp`): the game reads their files until the editor imports them
  (`SheetSprite.load_picture`); give the editor focus once. `colossus-lab.tscn` was rebuilt
  (2026-11-24): if it is open, reload it before a save-all.
- `game/dev/bosses/matron-lab.tscn` was edited in place on 2026-11-24 (her full heart moved to the
  room's middle, the note's text), not rebuilt: if it is open in the editor, reload it before a
  save-all.
- New since: `game/dev/bosses/matron-lab.tscn`, `colossus-lab.tscn`,
  `game/scenes/characters/orb-weaver-matron-rework.tscn`, the packed boss frames; the editor imports
  them on focus (they load without it too). If `crystal-colossus.tscn` or a Crystal Mine room is open
  in the editor, nothing in them changed, but reload before a save-all anyway after these edits.

## Next

State on 2026-11-24: step 1 passed review after two fix rounds (the reviewer kept the blow through a
sleeping statue's shield, and left the shove's lead for a playtest). The owner has seen four films of
the fix round (ram-enemies, ram-slime, cart-gate, target-blast).

Step 2 (both boss fights, each in its lab) passed the reviewer's code read on 2026-11-24 after one
fix round on the Matron (a new cocoon now always closes over its ram's lane; round 2's first dive on
time; a getter on the ram), and her crawl check (up on her web she collides with nothing). The
health and damage rebalance is built and reviewed
([the table](../design/2026-11-24-health-and-damage.md)). The plan doc carries both bosses "as
built", with the owner's changes.

**The reviewer's second read (2026-11-24, at the owner's word "review step2 implementation"):**
everything the owner had built after the first read (the Matron's targets under their rams, her web
balls, her call from the floor, her last-hit round 3; the Colossus's leap, dousing, quake, falling
rocks, heat cues and wall phase; the climb's toggle, the Heavy Roll's smash and crush, the Goo Bomb
without a cast, the hint line and pointer). All 22 scripts compile; the films `last`, `quake`,
`rocks`, `ground-call` and `web-balls` match their notes. Four small things went back to the boss
session: a leap whose crouch a cart cut short left him unable to leap again (`_hop_ready_at`);
rocks still falling when he was beaten never landed and stayed as pictures; her 4 s on the floor
after a dive refused every hit without a line; two comments in `matron_ram.gd` no longer true. Not
read line by line in this pass: `ram_cart.gd`'s later changes (the north tunnels, the doorway's
depth order) and the two lab builders. Left for the owner's hands: with the mouse scheme's button
held the climb's cling ignores the toggle; the Goo Bomb without a cast changes every bomb puzzle's
pace, not only the bosses'; tests that climb by holding interact, or wait out a cast, will fail
until step 5 updates them.

**Screenshots (owner, 2026-11-24):** agents delete their frame pictures when done (AGENTS.md
"Working Rules"). 10,020 frames (11 GB) were deleted from `output/` that day; the strips, GIFs and
`film.json` of every film are kept.

1. The owner plays both labs with a keyboard (`?map=matron-lab`, `?map=colossus-lab`): nobody has.
   For his judgment there: the Colossus lab's darkness outside a brazier's ring, a thrown thing's 6
   against a Spear hit's 12 on both bosses, and the Colossus's open points listed above.
2. **Step 3 started on 2026-11-24** ("Start step 3"): a builder session (Opus 5.5, extra-high
   effort) builds the Hollow's Trunk and Roots as room worlds beside today's Hollow (new world ids,
   today's four worlds and the forecourt's door untouched until all three pieces are built), writes
   its list of links here first, and stops for the reviewer's code read. Then the Boughs, then the
   Crown with the five rams as the Matron lab has them.
3. Steps 4 and 5 as the plan lists them, each reviewed before the next.
