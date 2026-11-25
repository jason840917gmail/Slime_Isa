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
| T3's walk, the gap rows 4-6, L1 | - | the drawbridge `weaver-hollow-t3-bridge` (built: hinged on the north part, where the slime comes in, standing raised there, lowers south 3 cells, L1; planned hinged on the far rim, changed so the post's chain runs across the gap to the raised bridge and shows what the post holds), let down by the cracked winch post on the far rim (`weaver-hollow.t3-bridge-post`): a Goo Bomb thrown over the gap |
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

### What is built (2026-11-25)

All ten rooms of the list, their layout and their Dungeon scene, to the list above (one change: T3's
bridge, see "Changed"). Details, ids and how to run it:
[DUNGEONS.md, "The Weaver Hollow rebuilt"](../godot/DUNGEONS.md#the-weaver-hollow-rebuilt-the-trunk-and-the-roots-step-3-2026-11-25).

| Piece | Files |
|---|---|
| Rooms (first versions; hand-edited from now on) | `godot/game/scenes/worlds/rooms/weaver-hollow/*.tscn`, `layout.tscn`; `scene_index.json` (ten `world.weaver-hollow-*` lines) |
| Their builder | `godot/tools/build_weaver_hollow_rooms.gd` (refuses to overwrite a room without `--force`) |
| Dungeon node | `godot/game/scenes/objects/dungeon/weaver-hollow-dungeon.tscn` (`dungeon_id`, `record_map_id` `weaver-hollow`) |
| Walk and films | `godot/tools/film_weaver_hollow_rooms.gd` (`--film=walk|ram|wall-walk`) |
| Small changes to shared code | `game/scripts/winch_post.gd` `blast_rise` (opt-in, 0 by default: see the review's point 4); `game/dungeon/doorway_art.gd` skips worlds with interior walls (point 1); `tools/render_room_scene.gd` `--hide=<node>` (D1 seen without its darkness) |
| Data | `dungeon.devPowers.weaver-hollow` (the Spear, the Roll, the Heavy skin, the Goo Bomb, for F6 / `?map=` runs) |
| Art | root rock's cracked pieces remade from the plain frame (`scripts/art/make-root-cracked.py`, `asset/Originals/dungeon-kit/interior-walls/root-bevel-cracked-made.png`; `pack-interior-walls.py` points at it); `godot/asset/MAPS/walls/interior/root-rock.webp` repacked, only its eight cracked pieces differ (checked pixel by pixel). No Magnific credits spent |

**Proof.** `film_weaver_hollow_rooms.gd --film=walk` passes its 45 checks on the final scenes: every
door both ways it uses, each lock played (four cracks and the floor blown with cast Goo Bombs, a pot
sucked in and thrown at R3's target, the ram bursting the arch, the Guard's stair, a bomb spat, sucked
in and thrown over T3's gap, the bridge crossed at level 1, the gallery entered at level 1, key 1, the
winch, the stair down, key 1 in the south door) and the wrong ways refused (the stair block, the key
door without the key, T3's walk and T4's ledge out of reach from the floor, the arch before the ram);
a drop off the west gallery lands at level 0 with health unchanged. The slime is put near each
step (the rooms are big), never through a lock; enemies are calmed and health kept full while it runs
(an early run fainted in R1 to the egg sac's brood). Pictures, all looked at:
`output/dungeon-rework/hollow/rooms/` (every room as the editor shows it; `rooms/lit/` D1 without its
darkness), `walk/` (`strip.png`, the walk's 20 step pictures in one sheet, and `walk.json`),
`ram-film/` and `wall-walk-film/` (`strip.png`, `film.gif`; filmed every 3rd and 4th step, looked at
frame by frame in sheets; the frames, step pictures and review sheets deleted, AGENTS.md).

**Weakest three** (as first reported; the review's points below say what changed).
1. **The hub is big and plain** (36 x 32 cells): the gallery, the heart (braziers, a glowing ring,
   root posts), web patches, an orb-weaver; much of its floor bare. *Since the review: packed earth,
   gravel paths between its doors, a grass bed at the heart.*
2. **The second floor texture was dressing, not paint.** *Since the review: the Trunk's rooms are
   painted grounds (point 3 below).*
3. **The hub's gallery stair drew as a root archway.** *Fixed in the review: it was the old doorway
   art (point 1).* Still: T3's raised bridge reads as a tall wooden gate standing on the walk; the
   hub's web wall is a long silk band across the gallery; the Guard's stair walk plays the stair
   door's steps in the wall's stairs opening.

**Changed from the plan, and why.**
- T3's drawbridge is hinged on the **near** rim (where the slime comes in) and stands raised there,
  chained across the gap to the cracked post on the far rim: the plan's far-rim hinge put the raised
  bridge on the far part, where it read as a door lying on the walk, and the chain now shows what the
  post holds (the owner's "see what it connects to").
- R3's target stands on a two-by-two **island** in the void straight below the ram (the plan's
  sketch had it at the void's far side, off the ram's line): straight below, per the owner's rule,
  and still out of reach but for a throw (from the void's west or east rim).
- The map nook (west of T3) and the compass pocket (north of R2) are small worlds of their own,
  entered through a crack with the iris, as the Lair's pockets: the sketch drew the nook in T4's
  corner. T4 stays a plain rectangle.
- D1's dividing rock is a wall of stacked casks: a one-cell raised strip (today's rock column, as a
  room face) read as a narrow walk; the root style of dungeon dividers is not made yet.
- The Stair foot room of the sketch (behind the hub's south door) is not built: it is the Boughs'
  piece; the key door opens onto its dead passage.

**Art found missing.** The root-rock wall's cracked render (fixed here from the plain frame, above);
a root-rock dungeon divider (`fences` layer: only fort stone exists). (A second floor inside a room
was listed here too: it exists, see the review's point 3.)

**For the owner, in the editor (the Boughs).** Focus the editor once (the ten new room scenes and
their caches import). Reload before a save-all if open: `t2-hollow-heart.tscn` (a room door and a
landing added), `r3-ram-cellar.tscn` (its void's `pit_depth`), `layout.tscn` (rewritten), and the
scripts `game/main.gd`, `game/scripts/brood_warden.gd`. No test run; not played with a keyboard.

**For the owner, in the editor.**
- Give the editor focus once: it imports the new scenes, scripts (`build_weaver_hollow_rooms.gd`,
  `film_weaver_hollow_rooms.gd`, `make-root-cracked.py` is Python) and the repacked `root-rock.webp`
  (the game reads its file until then), and writes their `.import` / `.gd.uid` files.
- Changed existing files: `game/scripts/winch_post.gd`, `game/dungeon/doorway_art.gd`,
  `tools/render_room_scene.gd`, `game/data/game-constants.json` (one line), `scene_index.json`,
  `scripts/art/pack-interior-walls.py`; no existing world or room scene was touched (today's Hollow
  and the forecourt as they were).
- The six rooms with levels are baked (`godot/game/scenes/worlds/elevation_cache/rooms__weaver-hollow__*.res`,
  new files to commit); after painting a room's `elevation`, bake it again. No tests run; not played
  with a keyboard.

### The review's five points (2026-11-25)

The reviewer's read passed the code and asked for five things, done one scene at a time (the scenes
are edited, not regenerated; `build_weaver_hollow_rooms.gd` follows the trims and the post's rise,
the second floors are scene edits only):

1. **The hub's gallery stair drew as a doorway.** Not the stairs art (the root-rock face picks the
   forest set's wooden steps in the hub as in R1): `game/dungeon/doorway_art.gd`, the old cliff-wall
   doorway frames the owner rejected, dresses every world whose id begins with `weaver-hollow-`, the
   rebuilt rooms too, and turned the stair block (a shutter without `frame_drawn_by_wall`) into a
   root-rock arch with a pale leaf, then a dark arch once sunk. It now skips any world with an
   `interior-walls` layer (today's Hollow and the Mine have none: unchanged). In the game the block
   is the kit's stone block and, sunk, the stair's wooden steps show (checked in two pictures).
2. **One floor trim:** `rubble-umber` (round stones, like root rock's own) in every room; T3, T4, the
   map nook, R2, R3 and the compass pocket repainted (only their `floor-trim` cells), one scene each.
3. **A second floor.** Grounds with edge art (`terrain_materials.gd`): amberleaf, cavern-floor,
   crystal-floor, forest-floor, forest-moss, frozen, garden-soil, gravel-path, highland (grass),
   sand, town-cobble; a ground draws its edges over the grounds below it in `ORDER`. Fatty's Lair
   does not mix floors: every room draws its wall style's plain floor (`draw_floor`), one per room.
   Here **the Trunk's rooms are earth** (T1, T2, T3, T4, the map nook: `draw_floor` off, the
   `ground` painted garden soil, "packed earth") and **the Roots keep the root-rock stone floor** (the
   cellar). Over the soil: **gravel-path** paths between doors (the hub: the west doorway and the key
   door to the heart, the heart to T1's doorway and up to the gallery stair; T1: the way in to the
   hub's door; T3: the east door to the north crack), a **grass** (highland) bed at the hub's heart,
   **wood planks** (hard-edged, the interior floor tile) in the Larder's store corner; the stepping
   stones those paths replace were taken out. Found on the way: a ground without a 128 px sheet
   (forest-moss, cavern floor) loses its edge under garden soil's 128 px surface, and the root-rock
   floor cannot sit beside a ground patch (the patch's edge tiles draw the base ground over the floor:
   a blue ring with cavern floor), so a room is all ground or all floor. Weak: the grass bed keeps
   the cells' steps (its edge is a fringe, not a rounding), and the editor render
   (`render_room_scene.gd`) draws no ground edges: in-game pictures are in `rooms/game/`.
4. **The winch posts.** Placed today: today's Hollow B2 (`B2-drawbridge.tscn`, (2214.4, 1305.6): a
   bomb thrown east over the void stops at the hurtbox's west side, about 33 beside the foot), B6
   (`B6-the-pillar.tscn`, (3814.4, 486.4): the last blast keg at (3728, 486.4), 86.4 beside it, 0.96
   of the blast's reach) and the rebuilt T3. `tests/test_weaver_bombs.gd` blows one 30 beside and 10
   below its foot. Raising every post's blast point to its hurtbox's middle (as first done) would have
   put B6's keg (1.83 of the reach) and the test's blast (1.33) out of reach, so it is now
   **opt-in**: `blast_rise`, 0 by default (every placed post as it was), 56 on T3's post only (a bomb
   thrown from the north stops at the hurtbox's top, 52 from the raised point).
5. **The repacked root rock.** No existing room paints root rock's cracked tile (every world and dev
   scene with interior walls searched: only the rebuilt T3, T4 and R2 do); Fatty's arena, the
   Glow-moss Burrow and the bolt-hole have no crack. Fatty's arena rendered: as before. The owner
   sees the new crack only in the rebuilt Hollow.

## Step 3: the Boughs

The second piece of step 3 (2026-11-25): the Hollow's upper floor, built as the Trunk and the Roots
are (room worlds, root-rock interior walls, `build_weaver_hollow_rooms.gd` writes first versions,
scenes hand-edited after), beside today's Hollow. The reviewer's brief: the stair foot behind the
hub's south door; B1 to B7, the Hoard and D2; the Brood Warden answering the ram; a falling slab
under a floor web; the Rafter Run to the big key and down to the hub's gallery. Not the Crown.

### The list of links (written before any scene)

Floors on the map: the Trunk 0, the Roots -1, the Boughs 1 (each room 1152 x 1024 a cell).
**Floors:** the Trunk's packed earth goes on up (garden soil, `draw_floor` off) with gravel paths
between doors; **the raised walks of the Boughs (the rafters, the Hoard's loft, the Spinning Loft) are
wooden planks** (the interior wood floor tile: timber, as rafters are). L0 the floor, L1 the upper
level; cells are the room's own (column, row), its rim two deep (floor from (2, 2)).

| Room | World id | Size | Map (floor, place) | Floor | Upper level (L1) |
|---|---|---|---|---|---|
| The stair foot | `weaver-hollow-stair-foot` | 18 x 16 | 0, (2304, 2048) | L0, the Guard's stair up in its north wall | - |
| B1 the Bough Stair | `weaver-hollow-b1-bough-stair` | 18 x 16 | 1, (1152, 2048) | L0, a Silk Lurker, floor webs; the stair down in its north wall | - |
| B2 the Drawbridge | `weaver-hollow-b2-drawbridge` | 36 x 16 (2 x 1) | 1, (1152, 1024) | L0, a void (L-2) down the middle (built: cols 17-20, every row; listed as 17-21), the drawbridge across it (rows 7-8) | the rafters, rows 2-3 along the north wall, cut by the same void: across it on row 3 (built) slab, landing, slab, slab under floor webs (listed: two slabs, a landing, two slabs) |
| B3 the Mimic's Pantry | `weaver-hollow-b3-mimics-pantry` | 18 x 16 | 1, (0, 1024) | L0, the Cocoon Mimic (key 2), S2's parcels behind a web wall in a nook (Silk) | the rafters, rows 2-4 along the north wall, the big chest (the big key) in sight from the floor; an open hole in them, the one-way drop to the hub's north gallery |
| B4 the Nursery | `weaver-hollow-b4-nursery` | 18 x 16 | 1, (2304, 2048) | L0, the ambush (once): three egg sacs in rings of webs, an orb-weaver, shutters on both doorways, the hidden chest (30 coins, a Slime Tonic) | - |
| B5 the Warden's Den | `weaver-hollow-b5-wardens-den` | 18 x 16 | 1, (3456, 1024) | L0, the Brood Warden (a room fight, `weaver-hollow-brood-warden`), an egg sac; a ram across the den (lane east, rows 10-11, built cols 5-13), its knock target past the lane's east end in its line, the rope along the lane | - |
| The Hoard | `weaver-hollow-hoard` | 18 x 16 | 1, (3456, 0) | L0, Pearl 2 on the brood's altar (Silk; seals the Hollow) | the loft, cols 2-5 x rows 2-9, a front flight down at row 10 (cols 3-4) behind a web wall (the Silk skin's first lock) |
| B6 the Spinning Loft | `weaver-hollow-b6-spinning-loft` | 18 x 16 | 1, (2304, 0) | built without levels (a room painted wholly L1 held the slime at its south door; the scroll keeps each walk's level, below) | the whole room is the Rafter Run's: two rows of web walls wall to wall, two Slime Spiders, key 3 in a silk parcel |
| B7 the Pillar | `weaver-hollow-b7-pillar` | 18 x 16 | 1, (3456, 2048) | L0, a void, a keg chain along the parapet to the pillar's cracked post, the drawbridge to the far shore and its chest (coins and a potion; no heart quarter) | - |
| D2 the Dark Bough | `weaver-hollow-d2-dark-bough` | 18 x 16 | 1, (0, 2048) | L0, dark, as today: three candles, lit for good, bring its chest (20 coins, a Slime Tonic: today's record kept) | - |

Doors and stairs ("scroll" room doors unless said):

| From (side, cells, level) | To | Lock |
|---|---|---|
| T2 south, cols 8-9, L0: `t2-south-stair` (a room door added behind today's key door) | the stair foot north, cols 8-9: `sf-north` | key 1 (the key door in T2) |
| The stair foot north, cols 13-14, L0: the stair up (`weaver-hollow-sf-stair`, stair door in a stairs opening) | B1 north, cols 12-13, L0: the stair down (`weaver-hollow-b1-stair`) | - |
| B1 north, cols 7-8: `b1-north` | B2 south, cols 7-8: `b2-south-b1` | - |
| B1 west, rows 7-8: `b1-west` | D2 east, rows 7-8: `d2-east` | - (D2 is dark: the Lantern) |
| B2 west, rows 7-8, L0: `b2-west-floor` | B3 east, rows 7-8: `b3-east-floor` | - |
| B2 west, rows 2-3, L1 (the rafters): `b2-west-rafters` | B3 east, rows 2-3, L1: `b3-east-rafters` | from B2: the webbed slabs over the void |
| B2 south, cols 25-26, L0: `b2-south-b4` | B4 north, cols 7-8: `b4-north` | the drawbridge (the void between); B4's ambush shutter while it lasts |
| B2 east, rows 7-8, L0: key door `weaver-hollow-warden-door` (one keyhole) + `b2-east` | B5 west, rows 7-8: `b5-west` | key 2; the drawbridge before it; B5's fight shutter while it lasts |
| B2 north, cols 27-28, L1 (the rafters' east part): `b2-north-rafters` | B6 south, cols 9-10, L1: `b6-south` | - |
| B2's void, rows 7-8, L0 | - | the drawbridge `weaver-hollow-b2-bridge`, standing raised on the near (west) rim, chained to the cracked winch post on the far rim (`weaver-hollow.b2-bridge-post`, a Goo Bomb thrown over the void) |
| B2's rafters across the void, row 3, L1 | - | four falling slabs under floor webs and a landing: a Roll sticks in the web without the Silk skin and falls with the slab; with it the slime rolls across |
| B4 east, rows 7-8: `b4-east` | B7 west, rows 7-8: `b7-west` | B4's ambush shutter while it lasts |
| B5 north, cols 7-8: `b5-north` (shutter `weaver-hollow-hoard-shutter`, `starts_shut`, the fight's reward) | the Hoard south, cols 7-8: `hoard-south` | the Brood Warden beaten |
| The Hoard west, rows 7-8, L1 (the loft): `hoard-west-loft` | B6 east, rows 7-8, L1: `b6-east` | from the Hoard: the web wall at the loft stair's foot (Silk) |
| B3's rafters, the open hole at (8, 3) (a fall, one way) | the hub's north gallery, the landing `weaver-hollow-gallery-landing` at (14, 4), L1 | - |
| The key 3 door, the Crown Door | the Crown (the next piece) | key 3, the big key |

The prizes: key 2 (the Cocoon Mimic's, spat when beaten), the big key (B3's rafters' big chest),
key 3 (the Spinning Loft's silk parcel), Pearl 2 (the Hoard: the Silk skin, the seal), B4's chest
(30 coins, a Slime Tonic), B7's chest (40 coins, an energy potion: today's Goo Heart goes), D2's chest
(today's), S2's three parcels in B3's nook (today's: a Slime Tonic, an energy potion, 40 coins), and
after the Pearl the hub's east gallery web wall and T1's loft chest (built in the first piece).

The way: the hub's south door (key 1), the stair foot, the Guard's stair up to B1 (a Silk Lurker),
B2: a bomb thrown over the void at the post lets the bridge down; west to B3: the Mimic swallowed key 2
(beaten, it spits it); the bridge, key 2 in the Warden's door, B5: lure the Warden onto the ram's lane
and throw at the target (a pot, a stunned Broodling): knocked flat, his plates open (the Spear, the
bomb); won, the Hoard's shutter sinks; Pearl 2: the Silk skin, the Matron's roar, the seal. The Silk
skin's lock at the loft stair's web wall; up, west into the Spinning Loft (web walls, spiders, key 3);
south onto B2's rafters; a Roll over the webbed slabs; west onto B3's rafters: the big key; the hole:
down onto the hub's north gallery by the Crown Door.

### The Boughs: what is built (2026-11-25)

All ten rooms of the list, the hub's two additions (the room door behind its south key door, the
gallery's landing for the Rafter Run's drop) and the layout's ten map rooms. Ids, the way and how to
run it: [DUNGEONS.md, "The Boughs"](../godot/DUNGEONS.md#the-boughs-step-3s-second-piece-2026-11-25).

| Piece | Files |
|---|---|
| Rooms (first versions; hand-edited from now on) | `godot/game/scenes/worlds/rooms/weaver-hollow/{stair-foot,b1-bough-stair,b2-drawbridge,b3-mimics-pantry,b4-nursery,b5-wardens-den,hoard,b6-spinning-loft,b7-pillar,d2-dark-bough}.tscn`; `layout.tscn` rewritten (`--layout --force`: it had no hand edits); `scene_index.json` (ten lines) |
| The hub (one scene edit) | `t2-hollow-heart.tscn`: `RoomDoors/t2-south-stair`, `Objects/gallery-landing` |
| Their builder | `tools/build_weaver_hollow_rooms.gd` (the Boughs' rooms added; voids now floored with cavern stone and `pit_depth` 2) |
| New code | `game/scripts/brood_warden.gd`: `on_mechanism_hit(&"ram")`, a `knocked` phase (plates open, hits land as when planted); his numbers in `enemy-types.json` (`ramDamage` 20, `ramSlidePx` 110, `ramSlideMs` 260, `knockedMs` 3000, `states.knocked`) |
| Shared code touched (small) | `game/main.gd`: a room-door scroll takes the level of the spot the slime walks out onto when the carried level cannot stand at the doorway (see "Levels across rooms" in DUNGEONS.md); R3's void got `pit_depth` 2 (one property: its hazard warned) |
| Walk and films | `tools/film_weaver_hollow_rooms.gd`: the walk runs on through the Boughs; `--from=boughs`, `--film=warden-ram`, `--film=webbed-slab`, `--film=look` |

**Proof.** `--film=walk` from T1 passes all 84 of its checks on the final scenes (the first piece's
44 and the Boughs' 40; `output/dungeon-rework/hollow/walk/`: `strip.png`, its 35 step pictures in one
sheet, and `walk.json`). The Boughs' checks: the stair foot,
the stair to B1, B2's void holds (a push drops the slime in and puts it back), a bomb spat, sucked and
thrown over the void breaks the post, the bridge crossed, the Warden's door holds without key 2, the
rafters out of reach from both floors, the Mimic's key 2, the Warden's door opened, the ram knocks the
Warden flat, his fight won opens the Hoard's shutter, the loft's web wall holds without Silk, Pearl 2
(the Silk skin, the seal), the web wall waded, the Spinning Loft entered, both rows of web walls
waded, key 3, B6 onto B2's rafters at level 1, the webbed slabs crossed with two Rolls, B3's rafters at
level 1, the big key, the hole onto the hub's gallery at level 1, the east gallery's web wall waded,
T1's loft at level 1 and its chest. Staged: enemies calmed and beaten by the tool (the walk proves the
way, not the fights), the Warden's home put on the ram's lane (a calmed Warden walks home off it),
the slime placed near each step.

**Films**, looked at frame by frame in sheets, then the frames deleted: `warden-ram-film/` (the
Warden on the lane, a pot at the target, the log, his slide and the 20, knocked flat, the Spear's lunge
for 25, his rise; PASS) and `webbed-slab-film/` (with the skin: a Roll to the landing, a second off it;
without: the Roll sticks in the web on the slab, the slab falls with the slime, it is put back on the
rafters; PASS). Rooms: every Boughs room rendered (`rooms/`, D2 also in `rooms/lit/`) and, since their
floors are painted ground, in the game (`rooms/game/look-<room>.png`).

**Weakest three.**
1. **The Warden has no knocked-flat pose**: the sheet's 16 frames are guard, wind-up, sweep, planted
   and walks; knocked is the planted frame (plates open on glowing joints) squashed flat and twitching.
   It reads as "down and open", not as "on his back". Real frames need art (not made: no credits).
2. **The square grass beds** round the Hoard's altar (and the hub's heart, left as it is for the owner):
   the painted ground keeps the cells' steps, its edge a fringe.
3. **B2's crossing is one way**: from the east rim a quick Roll lands on the landing; from the west it
   overshoots onto a slab. The Rafter Run goes west only, but a player who walks back east on the
   rafters must take the slabs another way (the charged Roll crosses all of it). Also: the staged walk
   beats the Mimic and the Warden's fight by the tool (their fights are today's, not re-checked).

**Art found missing:** a Brood Warden on his back (two or three frames: flipped, legs kicking); a
root-rock dungeon divider (still).

**Changed from the plan and the list, and why.**
- **B2's void is four cells, not five, and the rafters' crossing is slab, landing, slab, slab** (three
  webbed slabs, the plan's four): a throw carries about 280 units, so over five cells a bomb from the
  west rim landed 110 short of the post; over four it reaches the post on the east rim's edge (as
  today's B2). With a quick Roll of 165 units the landing must sit one Roll from the east rim's edge;
  the crossing works westward (the Rafter Run's way), not back east.
- **B2's void has two hazards** (the floor's, rim 0; the rafters', rim 1): a hazard drops only a body
  at its rim, so with one a slime stuck on a fallen rafter slab stood on the air.
- **B6 the Spinning Loft has no levels**: painted wholly level 1 it held the slime at its south door;
  the scroll keeps each walk's level on both sides, so it needs none (still reached only from the
  Rafter Run).
- **The Brood Warden's ram damage comes as he stops sliding**, not at the blow: the hit's stun held his
  body still and he slid 27 of his 110 units.
- **Rooms' details:** B5's ram rests one cell in from the west wall (its log lay in the wall); its
  pots stand beside the target, where the throw is made; B3's S2 nook is walled off by casks and the
  web wall (today's alcove); B7 keeps today's keg chain on a parapet in the void.

## Step 3: the Crown

The last piece of step 3 (2026-11-25): C1, C2 and C3, built as the Trunk and the Boughs are, beside
today's Crown (today's `weaver-hollow-crown` world untouched). Not the switch-over.

### The list of links (written before any scene)

Map floor 2 (each room 64 units a cell). L0 the floor, L1 the upper level.

| Room | World id | Size | Map place | Floor | Upper level (L1) |
|---|---|---|---|---|---|
| C1 the Crown Stair | `weaver-hollow-c1-crown-stair` | 18 x 16 | (2816, -1024) | L0 rows 9-13 (the flight on row 8): floor webs wall to wall (the Silk test); a front flight up at row 8, cols 8-9, its foot choked by a web wall (wade or cut it: cut, every climb after a faint is quick) | rows 2-7 (planks): the top, four pots by the key 3 door, the calm spot before her |
| C2 the Crown | `weaver-hollow-c2-crown` | 24 x 20 (the Matron lab's room, its floor cols 2-21 x rows 2-17) | (2752, -2304) | her arena, **the lab's at the lab's coordinates**: five rams along the north wall (x 288, 524.8, 768, 1011.2, 1248; row 5.6; lanes south, 9 cells), each knock target straight below at row 16.8, her camp at (768, 640) with the lab's arena and wake shapes, the twelve pots where the lab has them, her full heart in the middle, her thread in the north-west corner | - |
| C3 the Outer Bough | `weaver-hollow-c3-outer-bough` | 18 x 8 (*built*; the list had 18 x 16) | (4288, -1920) (*built*; the list had (4288, -2176)) | planks: a timber walk; her web wall across it at col 6, wall to wall (*built*; the list had it in the west doorway); the open hole at (13.5, 4) in a patch of bark: the drop | - |

Doors ("scroll" room doors):

| From (side, cells, level) | To | Lock |
|---|---|---|
| T2 north, cols 16-17, L1 (the gallery): `t2-north-crown` (a room door added behind today's Crown Door) | C1 south, cols 8-9, L0: `c1-south` | the big key (the Crown Door, a boss door, built in the first piece) |
| C1 north, cols 8-9, L1: `c1-north` | C2 south, cols 9-10: `c2-south` (where the lab's slime starts, between targets 2 and 3) | key 3 (a key door, one keyhole: `weaver-hollow-k3-door`); C2's boss shutter (`weaver-hollow-crown-shutter`, shut by her camp's `boss_engaged`, opened by `boss_defeated`, as today) |
| C2 east, rows 9-10: `c2-east` | C3 west, rows 3-4 (*built*; the list had 7-8): `c3-west` | the seal (`object.dungeon-seal`, shut since Pearl 2, sunk when she falls) |
| C3, the open hole at (13.5, 4) (a fall, one way) | the forecourt `gloop-forest-f4`, the marker `weaver-hollow-silk-drop` (today's landing, by S1's nook) | - |

**Where the drop lands, and why:** the forecourt, at today's marker. It is the dungeon's way out once
she falls, as today; the rebuilt T1's own way out (`weaver-hollow-entrance`) also leads to the
forecourt, and its seal sinks with hers. The forecourt's root gate still enters today's T1 until the
switch-over.

**Her camp:** today's (`encounter.weaver-hollow-matron`) with the lab's settings: `boss_scene`
`character.orb-weaver-matron-rework`, `boss_id` `orb-weaver-matron` (her defeat is recorded by it, as
today), `camp_id` `weaver-hollow-matron`, `map_id` `weaver-hollow-c2-crown` (*built*: the room's world, as
every camp's; the list had `weaver-hollow`, the dungeon's record id),
`respawn_ms` -1 (today's: a dungeon boss never returns), `spawn`, `boss_overrides`, the arena and
wake shapes the lab's. Her full heart and her thread as today's camp has them.

**The way:** the hub's gallery, the Crown Door (the big key), C1: up through the floor webs, the web
wall at the flight's foot (the Silk skin), the key 3 door; C2: she wakes as the slime walks in, the
shutter shuts behind it, the seal holds the east doorway; her fall sinks the seals (C2's east, T1's way
out) and opens the shutter; C3: her web wall, the hole, the forecourt.

### The Crown: what is built (2026-11-25)

Three room worlds in `godot/game/scenes/worlds/rooms/weaver-hollow/` (`c1-crown-stair`, `c2-crown`,
`c3-outer-bough`; `world.weaver-hollow-<room>` in `scene_index.json`, floor 2 of `layout.tscn`),
first written by `tools/build_weaver_hollow_rooms.gd` (`_c1`, `_c2`, `_c3`; C2's numbers in its
`CROWN_*` constants, the lab's) and edited by hand from now on. C1's elevation cache is baked
(`rooms__weaver-hollow__c1-crown-stair.res`, new); C2 and C3 have no levels. One scene edit of the
hub: the room door `RoomDoors/t2-north-crown` behind the Crown Door (to C1's `c1-south`).

- **C2 is the lab's arena**, as it is (the rams, targets, camp, shapes, pots and the slime's way in at
  the lab's coordinates; see DUNGEONS.md "The Crown"). Nothing of `matron_ram.gd`, her scene or the
  lab changed.
- **Dressing:** C1 and C2 packed earth (garden soil), planks on C1's top and the Outer Bough's walk, a
  patch of bark (soil) round C3's hole; the `rubble-umber` trim; her nest: sconces and silk hanks on
  the north wall between the gantries, a web in the north-east corner, bones, glow mushrooms, floor
  scraps between the lanes. Nothing on a lane or between a target and its throwing spot.

**New and shared code touched.**
- New: `tools/film_crown.gd` (extends `tools/film_matron.gd`: the Crown's world set as the game enters
  the tree, the Silk skin lent, a PASS or FAIL on round1, ram-catch and round3; the parent untouched).
- `scripts/godot/film-matron.sh`: `--tool=film_crown` (its own output folder; the film lock shared).
- `tools/film_weaver_hollow_rooms.gd`: the walk runs on through the Crown (`_crown_door_refused`,
  `_walk_crown`, `_matron`), `--from=crown`, its watchdog 20 minutes, `_wait_world` takes a world
  outside the Hollow.
- `tools/build_weaver_hollow_rooms.gd`: the three rooms; the decorative cocoons and egg sacs gone.
- No game script changed in this piece.

**The clarity rule, fixed in every rebuilt room.** The Hollow's design (its clarity rule: "no
decorative cocoons or egg sacs in the Hollow", her cocoon and the egg sacs being a lock and an enemy)
was broken by the first two pieces: 34 hanging or ground cocoons and 10 egg-sac props, taken out of
17 room scenes (one run per scene, the Scenery props only; the egg sacs that are enemies in R1, B4
and B5 stay) and out of the builder. The brief asked for cocoons and egg sacs in her nest: not built,
for the same reason; her nest is webs, silk and bones.

**Proof.** `--film=walk` from T1 passes all 115 of its checks on the final scenes (the first two
pieces' 84 and the Crown's 31; `output/dungeon-rework/hollow/walk/`: `strip.png`, its 44 step
pictures in one sheet, and `walk.json`). The Crown's: the Crown Door refuses the slime without the
big key (on the gallery, before the Boughs); from T1's loft back into the hub's east gallery; the big
key opens the Crown Door into C1, on its floor; the Silk slime wades the floor webs and the flight's
web wall up to the top (L1); the key 3 door refuses without key 3 (staged: the key taken from the
record and given back), key 3 opens it into C2; she wakes as the slime walks in, the shutter shuts
behind it and holds the way back; **a faint** in her fight wakes the slime at T1, and the way back up
(T1, the hub, the gallery's stair, the Crown Door, C1's flight, the key 3 door) takes four doors and
no key (12.5 s of game time, the slime put along the floors, never through a lock); she wakes again
and the shutter shuts again; the seal holds C2's east doorway; her fight ended by the tool (`_hp` 0,
`_defeat()`): her defeat in `defeated_boss_ids` and the Hollow's record, the seals broken, the shutter
open, her full heart in the arena; through the east doorway into C3, the Silk slime wades her web
wall, the hole drops it to the forecourt; travelled back to T1 (the forecourt's gate still enters
today's T1), its way out stands open to the forecourt.

**Her fight in the room** (`tools/film_crown.gd` through `film-matron.sh --tool=film_crown`;
`output/dungeon-rework/hollow/crown-films/<film>/`: `strip.png`, `film.gif`, `film-slow.gif`,
`film.json`; the frames looked at in sheets, then deleted):
- `round1` **PASS**: her low cocoon over ram 1's lane, a Goo Bomb under it, "The cocoon tears
  open!", she falls dazed, the Spear (25) and a pot (5), she climbs to hang and rings the five targets.
- `ram-catch` **PASS**: baited over the lower end of ram 2's lane, a pot thrown up at target 2 from
  inside its ring (the Silk skin) as she dives: the log flings her down the lane, she crashes open
  (20), the Spear and a pot, she climbs back up.
- `round3` **PASS**: her last hit (health staged at 20), her high cocoon over ram 1's lane, a blast
  under it refused, a pot at target 1: the ram knocks the cocoon down, a bomb tears it, one Spear
  thrust: "Orb-Weaver Matron defeated", her full heart.
- Round 1's first run failed its own check: her cocoon hung over ram 4's lane, and the lab film's
  Spear thrusts went the way the slime had last moved (down, away from her), so nothing landed and
  she spun a new cocoon (as her fight should). `film_crown.gd` now makes the Spear and the pot from
  beside her, as ram-catch does; round1 and ram-catch were filmed again with it.

**Rooms:** rendered (`output/dungeon-rework/hollow/rooms/c1-crown-stair.png`, `c2-crown.png`,
`c3-outer-bough.png`) and in the game (`rooms/game/look-<room>.png`).

**Weakest three.**
1. **Her fight is proven by films, not by hands.** The lab's films and their staging (health staged,
   her brood burst, her attacks held while the slime casts) run in the room and pass, and the walk ends
   her fight by the tool; nobody has played her fight in the Crown with a keyboard.
2. **C3 is plain and small**: a straight timber walk, her web wall, a hole in a square patch of bark
   (the soil's square edge on the planks; the hole is the stone-ringed floor hole, there is no hole cut
   in timber). It reads as a corridor, not as a bough out in the air, and the room (8 rows) leaves the
   screen dark round it.
3. **Her nest reads thin**: with no cocoon or egg sac for show (the clarity rule) and no floor webs (the
   fight), the Crown is the lab on packed earth with silk hanks, sconces, bones and one corner web.
   Also: nothing walks from the forecourt into the rebuilt Hollow until the switch-over (the drop and
   T1's way out both land there; the walk travels back to T1).

**Changed from the plan and the list, and why.**
- **C3 is 18 x 8, its doorway rows 3-4, her web wall across the walk at col 6** (the list: 18 x 16,
  rows 7-8, the web wall in the west doorway): a room door's scroll lands the slime inside the room,
  past its doorway, so a web wall in the doorway would have stood behind it. Its map place moved with
  it ((4288, -1920)), the doorway still level with C2's east one.
- **Her camp's `map_id` is the room's world** (the list: `weaver-hollow`): as every camp's; it keys
  only the camp's respawn record, which a boss that never returns clears. Her defeat is recorded by
  `boss_id`, and the seals read the Hollow's record.
- **No cocoons or egg sacs in her nest** (the brief asked for them) and **none left in the first two
  pieces' rooms**: the Hollow's clarity rule. **No floor webs in C2**: the lab's floor is bare and
  webs would slow the slime in her fight.
- **The walk also proves a faint and the way back up** (the brief's rule), and `film_crown.gd`'s Spear
  staging differs from the lab film's (above).

**Art found missing:** a hole cut in a timber floor (C3's hole is the stone-ringed floor hole on a patch of soil). Her
poses, her cocoon and her sounds all exist; nothing was faked.

**For the owner, in the editor (the Crown).** Focus the editor once (the three new room scenes, C1's
cache and `film_crown.gd` import). Reload before a save-all if open: `t2-hollow-heart.tscn` (the room
door `t2-north-crown`, and its cocoons and egg sacs taken out), every other rebuilt room scene (their
cocoons and egg sacs taken out; T1, R1, B1, B4, B5, the Hoard, D2 and C2 dressed after, below),
`layout.tscn` (rewritten). No test run; not played with a keyboard.

### The dressing after the clean-out (2026-11-25, the reviewer's round)

Every room of the first two pieces rendered again after the 44 cocoon and egg-sac props came out
(`output/dungeon-rework/hollow/rooms/<room>.png`, D1 and D2 also in `rooms/lit/`), and the in-game
pictures retaken for the 13 that had one, and C2 (`rooms/game/look-<room>.png`). Where a room read
thin, it was dressed by hand, one scene per run (a scratch tool adding Scenery props, named as the
builder names them), with what the rule allows: nothing on a ram's lane, in a throw's line, by a lock
or where it could be taken for one, or for an enemy. Positions in cells.

| Room | Added |
|---|---|
| T1 Root Door | brown mushrooms where the egg sacs stood (3.2, 7.4); a bone pile where a cocoon hung (5.6, 3.4), off the path |
| T2 the Hollow Heart | nothing: reads full |
| T3 the Larder, its map nook | nothing: reads full (the nook had none) |
| T4 the Well Room | nothing: reads full |
| R1 Root Fall | a corner web over the ledge (2.9, 2.6) and cream mushrooms at its east end (6.1, 4.6), the landing and the flight clear; a bone pile on the floor (13.4, 5.4), out of the column above the egg sac |
| R2 the Bone Cellar, its pocket | nothing: reads full |
| R3 the Ram Cellar | nothing (had none) |
| D1 the Old Cellar | nothing: reads full |
| The stair foot | nothing: reads full |
| B1 the Bough Stair | a silk spool (14.6, 4.4) beside the path; a bone pile (5.0, 6.0) |
| B2 the Drawbridge | nothing: reads full |
| B3 the Mimic's Pantry | nothing: reads full (the Mimic is the room's only cocoon) |
| B4 the Nursery | a bone pile (3.4, 10.6) and glow mushrooms (2.6, 6.2), clear of the three egg sacs |
| B5 the Warden's Den | glow mushrooms (2.6, 5.0), a moss bed (5.0, 6.2), a root (8.0, 4.4): the north half, off the ram's lane (rows 10-11) and the throwing spot by the target, all flat or without collision, so nothing stands in the Warden's way onto the lane |
| The Hoard | a bone pile (14.4, 4.0); a tall glow mushroom by the east wall (15.3, 8.6); sacks under the loft (2.6, 12.6), clear of the loft's stair |
| B6 the Spinning Loft | nothing: reads full |
| B7 the Pillar | nothing: reads full |
| D2 the Dark Bough | hanging roots on the north wall (8.0, 2.2) where a cocoon hung, a corner web (15.1, 2.6); no glow (a dark room) |
| C1, C3 | nothing (built after the clean-out) |
| C2 the Crown | a spool of her silk on the east strip (21.3, 3.4), off lane 5. Without a cocoon, floor webs or wall room between the gantries nothing more fits: it reads as the lab with her silk, sconces and bones |

**The walk after the last scene edit:** `--film=walk` from T1 passes all 115 checks (the strip and
`walk.json` in `output/dungeon-rework/hollow/walk/`, the step pictures deleted). The look film gained
`--slime=<x>,<y>` (where the slime stands: B2 and B7 have a void in the middle, B3 its Mimic).

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

**Step 3 (2026-11-25):** the Weaver Hollow rebuilt on all four floors (the Trunk, the Roots, the
Boughs, the Crown), passed by the reviewer, and **switched over** the same day at the owner's word
("Switch it over", given before he has played the rebuilt rooms): the game enters the rebuilt Hollow.
Nothing committed; no tests run.

**The switch-over: what changed (2026-11-25):**

| File | What and why |
|---|---|
| `godot/game/scenes/worlds/chunks/gloop-forest-f4.tscn` | the root gate's two link lines, by hand: `target_area_id` `weaver-hollow-t1-root-door`, `target_door_id` `weaver-hollow-entrance` (were `weaver-hollow-trunk` / `trunk-entrance`) |
| `godot/game/dev/area_edit/areas/area-e4-f5.tscn` (not in git) | the same two lines in the atlas's joined copy of F4. Its write-back could not bring the old target back anyway: it refuses when a chunk changed on disk since the area was opened, and F4's recorded hash differed already before this edit |
| `godot/game/scenes/encounters/weaver-hollow-matron.tscn` | the encounter's own values are the rework's: `boss_scene` `character.orb-weaver-matron-rework`, `map_id` `weaver-hollow-c2-crown`, `spawn` (0, -30), wake 1280 x 864 at (0, -80), arena 1280 x 1024 (position kept at (32, 0)), heart at (0, 0), thread at (-588.8, -422.4) |
| `godot/game/scenes/encounters/weaver-hollow-matron-old.tscn` (new) | a copy of the encounter as it was (the cocoon fight), for today's Crown only |
| `godot/game/scenes/worlds/rooms/weaver-hollow-crown/C2-the-crown.tscn` | one line: its camp instances the copy, so today's Crown never turns into the ram fight without rams |
| `godot/game/scenes/worlds/rooms/weaver-hollow/c2-crown.tscn` | its camp's inner overrides gone (the `BossCampScript` lines, the wake shape, the arena's shape, the heart's and the thread's positions, two shapes); kept: the arena's position (0, 0), which the encounter does not say (the lab, not setting it, uses (32, 0)), and the `[editable path]` line the camp-to-shutter connections need |
| `godot/game/scenes/worlds/rooms/weaver-hollow/b4-nursery.tscn`, `b3-mimics-pantry.tscn` | today's records on the prizes, as D1 and D2 already had: B4's chest `chest_id` `weaver-hollow-boughs-nursery-chest`, `map_id` `weaver-hollow-boughs`; S2's parcels `weaver-hollow.s2-parcel-0..2` (so an old save never has them twice) |
| `godot/game/autoload/run_state.gd` | `RETIRED_HOLLOW_WORLDS`, `moved_world`: a save standing in one of today's four floors loads into the new T1 at its entrance; a record entrance naming one of them is forgotten; `load_slot` checks the moved world (so it still loads once today's worlds leave `scene_index.json`) |
| `godot/game/dungeon/room_fight.gd` | `_reward_if_beaten_elsewhere`: a boss fight whose boss fell but never in this fight gives its reward when its room is built (the Warden beaten in today's Boughs: the Hoard's shutter would have stayed shut, the dungeon unfinishable) |
| `godot/game/data/world-map.json` | the Gloop Forest's interiors and the Hollow's marker name `weaver-hollow` (its record id, as `fatty-lair`); the marker's notes |
| `godot/game/data/game-constants.json` | `dungeon.devPowers`: the four floors' lines go (`weaver-hollow`'s, the same powers, is read for every world of the dungeon) |
| `godot/game/shell/area_titles.gd` | `weaver-hollow`: one banner for all the rooms; today's four names kept for an old save's slot label |
| `godot/game/dev/second_half_run.gd`, `game/dev/weaver-hollow-second-half.tscn` | the second-half dev run starts in the Hoard (`weaver-hollow-hoard`) |
| `godot/game/scripts/matron.gd` | a comment: today's Crown's camp is the copy |
| `godot/tools/build_weaver_hollow_rooms.gd` | the same record ids on B4's chest and S2's parcels |
| `godot/tools/film_weaver_hollow_rooms.gd` | the walk starts in the forecourt: the gate refuses, a Goo Bomb blows it, in to T1 (T1 records itself the entrance); after C3's drop in through the gate again and out by T1's way out, landing at the gate |
| docs | DUNGEONS.md ("The switch-over" and the lines that said "beside"), matron.md (8.4, 9, 9.4), CONVENTIONS.md (the second-half run, the falls' example), AGENTS.md (the walk line), audio.md, story/03-world.md |

**Proof:** the walk from the forecourt: PASS, 124 checks, none failed (the gate refuses, a Goo Bomb
blows it, in to T1, T1 records the entrance, the designed way to her defeat with a faint and the way
back up, C3's drop to the forecourt, in through the gate again, out by T1's way out 84 px from the
gate; `output/dungeon-rework/hollow/walk/strip.png` and `walk.json`, the step pictures deleted).
`tools/check_crossings.gd`: the Hollow's only line is today's old T1 door (`weaver-hollow-trunk`
`trunk-entrance`), now one way: it still leads to the gate, and the gate leads to the new T1.
Expected; it goes with today's worlds at step 5. The gate and the new T1's `weaver-hollow-entrance`
pair without a complaint. Its other lines (Sunscar's five broken cellar doors, the bolt-hole, Tom's
raft, E4/E5's openings drawn apart) are not the Hollow's.
The camp's values dumped before and after (C2, the lab, today's Crown, the encounter): C2, the lab and
today's Crown build exactly as before (today's Crown from the copy); only the encounter itself and the
gate changed. Every changed script compiles (`--check-only`). A save standing in today's Boughs (its
record sealed, its entrance today's T1, the Warden beaten), written to a scratch save folder and loaded
through `main.load_run` in a game window: the slime wakes in the new T1 42 px from its entrance marker,
on walkable floor, sealed, its small key kept, T1 recorded as the entrance.

**Saves** (an old save half-played in today's Hollow, on paper):

| What | Kept by | Carries over? |
|---|---|---|
| Where it stands | location | today's four floors load into the new T1 at its entrance (`moved_world`), inside, the record kept, as a dungeon's resume save; anywhere else as before |
| Small keys held | the record `weaver-hollow` (same id) | yes; the keys it found come again from the new chests, the Mimic and the loft's parcel, so it holds at least enough, often more (extra keys) |
| Key doors opened | the record's keyholes (today's object keys) | no: the new doors are shut again; the keys spent there are gone, the new keys make up for them (above) |
| The big key, the map | the record's items | yes; their new chests give nothing new (a dungeon item is held once) |
| The compass | the record's items | today's Hollow had none |
| Chests opened | map records (today's ids) | D1's page, D2's chest, B4's chest, S2's parcels: yes (the new ones use today's ids); the map's, the big key's and the keys' chests: no, harmless (above); T1's loft chest, R2's compass, B7's chest: new prizes |
| Pearl 2, the Silk skin | the run's flag and skins | yes (Pearl 2 does not rise again; the skin is held) |
| The Warden's fall | `defeated_boss_ids` | yes: his fight does not run again, and its reward (the Hoard's shutter) is given when B5 is built (`room_fight.gd`) |
| Her defeat | `defeated_boss_ids` and the record | yes: her camp never spawns her, the seals stay sunk, her full heart (a flag) is not had twice |
| The seal | the record | yes: a save sealed in today's Hollow is sealed in the new one, T1's way out shut, until she falls |
| The Crown's shutter | the record (today's key) | no, and nothing needs it: the new shutter stands open until she wakes |
| Doors, bridges, winches, webs, fights | today's object keys and flags | no (played again); only the Hoard's stair web and D2's candles share a flag and carry over |
| Rooms on the map | the record's visited rooms | no (seen again) |
| S3's parcel (30 coins), B6's heart quarter | flags | kept if taken; gone with the rework if not |

**Turning the switch back, in one place:** the forecourt's root gate in `gloop-forest-f4.tscn` (its
two lines back to `weaver-hollow-trunk` / `trunk-entrance`) is the only way in; with it turned back the
game plays today's Hollow again, whose Crown still has its own fight (the copy). The rest can stay
(the new rooms are unreached again, the save move only touches saves that stand in today's floors,
which then load into the new T1: take `RETIRED_HOLLOW_WORLDS` out too if that matters). A full undo is
the files in the table above, `git diff` against `850c98eb` (the step 3 files are uncommitted, so
`git checkout` would take other work with them: undo by hand).

**Left for step 5:** retire today's four worlds (`weaver-hollow-trunk`, `-roots`, `-boughs`,
`-crown`, their room scenes in `rooms/weaver-hollow-{trunk,roots,boughs,crown}/`, their four
`scene_index.json` lines, their elevation caches), the copy `weaver-hollow-matron-old.tscn`, today's
four names in `area_titles.gd`, the tools only they use (`build_weaver_hollow.gd`,
`weaver_hollow/hollow_*.gd`, `film_weaver_hollow.gd`, `render_weaver_hollow.gd`, their lines in
`lib/dungeon_room_splitter.gd` and `render_dungeon_room_views.gd`), and the tests below. Keep
`RETIRED_HOLLOW_WORLDS` (old saves still name them).

**Tests that enter or name today's Hollow** (not edited, not run):
- **fail now:** `tests/test_matron.gd`'s Hollow tests, which build `encounter.weaver-hollow-matron`
  and expect the cocoon fight (`test_hollow_matron_hangs_in_her_cocoon_and_every_hit_clinks`,
  `test_a_blast_on_her_shadow_tears_the_cocoon_for_a_window`,
  `test_three_rounds_of_a_hundred_with_webs_then_egg_sacs`,
  `test_beaten_she_never_comes_back_and_her_brood_bursts`,
  `test_with_the_silk_skin_round_two_cages_her_and_round_three_webs_the_floor`,
  `test_her_full_heart_adds_twenty_max_hp_once`, `test_her_thread_is_taken_only_with_the_silk_skin`:
  every one through `_mount_hollow`; its `map_id` check expects `weaver-hollow-crown`).
- **pass while today's worlds exist, go at step 5:** `tests/test_weaver_hollow.gd` (builds the four
  floors; their Crown has the copy), `tests/test_dungeon_rooms.gd` (line 76, the floors' dungeon id),
  `tests/test_dungeon_seal.gd` (line 99, `weaver-hollow-crown`'s dungeon id).
- **only a flag or a doc link, unaffected:** `test_weaver_bombs.gd`, `test_glimmerhill.gd`,
  `test_journal.gd`, `test_main_quest.gd`, `test_skins.gd` (`pearl.orb-weaver-matron`).
- **may see the room-fight change:** `tests/test_lair_rooms.gd` marks the Big Squint and Fatty beaten
  by hand before building rooms: their fights now record themselves won on the build (their shutters
  are open then; no `reward` is set), nothing else.

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
   **The reviewer's read of the Trunk and Roots (2026-11-25):** the code passes (no new gameplay
   code; every door paired with its other end; the walk's 65 recorded steps read, no fail; enemies
   and chests as today's rooms; the four scripts compile). Five things went back to the builder
   before the owner judges it: the hub's gallery stair draws as a cave mouth, not steps; the floor
   trim differs from room to room without a reason; the second floor (which grounds have edge
   tiles, before calling it missing art), the hub's bare floor first; every winch post in the game
   checked against the new `blast_point()`; the existing rooms whose root-rock cracks changed with
   the repack, named. Steps 1 and 2 were committed as `850c98eb` (not pushed); step 3's files are
   uncommitted.
   **The fix round, accepted (2026-11-25):** the stair fixed in `doorway_art.gd` (a world with
   interior walls is skipped), one trim in all ten rooms, the Trunk on packed earth with gravel
   paths, the winch post's `blast_rise` opt-in (only T3's post has it), no existing room's crack
   changed. Waiting for the owner's eye: the floor look, and the hub's grass heart with its square
   steps. **The Boughs started the same day**, by the same builder session, to stop again for the
   reviewer before the Crown; new code expected there: the Brood Warden's answer to the ram, and a
   falling slab under a floor web.
   **The reviewer's read of the Boughs (2026-11-25): accepted, no fix round.** Read line by line:
   `brood_warden.gd`'s ram hook and `main.gd`'s room-door level change (against `Elevation.track`,
   `walkable_level_at` and `door.gd`'s `arrival_point`: a step inside the room); both compile, as
   the three tools do. All 44 room doors pair both ways; no heart quarter; the walk's json has no
   fail, both films pass; nine in-game pictures and the strips looked at; no frame pictures left.
   Not read line by line: the builder tool's Boughs part, the film tool's staging. Accepted as
   built: B2's four-cell void with three slabs, its two hazards, B6 without levels, B5's target at
   the east end of the ram's lane (one screen, one straight line, the rope along the lane). Open
   for the owner: the Warden has no pose on his back (knocked is the planted frame squashed; real
   frames need Magnific credits, so his yes), the square grass beds (hub, Hoard), B2's rafters
   crossed eastward (a quick Roll ends on a slab), and `main.gd`'s change touches every room-door
   scroll (today's rooms are all one level, so nothing should change there; no test was run).
   **The Crown started the same day**, same builder session: C1 the Crown Stair, C2 the Crown with
   the Matron lab's arena carried over as it is (five rams, targets under their lanes, web balls;
   no change to her fight unless the room cannot work without it), C3 the Outer Bough; the walk on
   through her defeat and the seals; her fight filmed in the room. It stops for the reviewer
   before the switch-over.
   **The reviewer's read of the Crown (2026-11-25): accepted.** C2's rams, targets, pots, camp,
   thread and the slime's spot sit at the lab's coordinates to the decimal; the camp is today's
   encounter with `boss_scene` the rework (an override on the camp's inner node, held by its
   `[editable path]` line: at the switch-over make it the encounter's own); all 50 room doors pair;
   the walk's 115 checks have no fail on scenes written before it ran; the three fight films in
   the room say PASS, no script error in their logs; the tools compile; no frame pictures under
   `output/`. The builder took 44 cocoon and egg-sac props out of 17 rooms (the clarity rule, in
   DUNGEONS.md since before this work; the reviewer missed it twice), so those rooms' pictures
   were stale: one last round rendered them again, dressed eight scenes by hand where the
   removal left them thin (listed per room above) and walked once more. **Checked by the
   reviewer:** every room picture is newer than its scene, the walk (115 checks, no fail) ran
   after the last scene edit, no frame pictures under `output/`. Step 3's rooms are done. **The switch-over started on 2026-11-25** at the
   owner's word ("Switch it over"; he has not played the rebuilt rooms), by the same builder
   session, to stop for the reviewer's read: the forecourt's gate into the new T1, the rework fight
   as the encounter's own, nothing in the game leading into today's Hollow worlds, old saves landing
   in a sane place with their records, today's world files kept on disk until step 5.
   **The reviewer's read of the switch-over (2026-11-25): accepted.** Read line by line:
   `run_state.gd`'s migration and `load_slot`, `room_fight.gd`'s reward for a boss beaten elsewhere
   (a no-op for a fight won in its own room: both records are set together), the encounter's diff,
   F4's diff (the gate's two lines, nothing else). The copied old encounter is the committed one
   byte for byte; the lab sets its own camp values and is untouched; the changed scripts compile;
   the walk's 124 checks have no fail and ran after the last scene edit; no frame pictures under
   `output/`. Left open: `test_matron.gd`'s seven Hollow tests fail until step 5; C2's shutter
   still hangs on the camp's `[editable path]` line (an editor save that drops it leaves the
   shutter open, the fight stays the ram fight); an old half-played save gets spare small keys;
   the forecourt (the owner's scene) still shows wrapped cocoon shapes on its terraces, which
   DUNGEONS.md says the open world no longer has: his call.
3. Steps 4 and 5 as the plan lists them, each reviewed before the next.
