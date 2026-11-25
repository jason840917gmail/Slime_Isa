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
  [matron spec §9](../godot/specs/matron.md#9-the-ram-fight-the-rework-built-2026-11-24-in-a-lab-the-hollows-since-2026-11-25).
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

## Step 4: the Mine

Step 4 of the plan (2026-11-25, a builder session): the Crystal Mine rebuilt as room worlds with the
crystal-cave interior walls, **beside** today's Mine (`world.crystal-mine`, one 80 x 70 scene), one
wing at a time, each stopping for the reviewer. Today's Mine world, its camp door (G4's
`exit-to-crystal-mine`) and its dead room copies in `rooms/crystal-mine/M*.tscn` stay untouched until
the switch-over.

**Where the rooms live:** `godot/game/scenes/worlds/rooms/crystal-mine-rooms/<room>.tscn`, world
`crystal-mine-<room>` (`world.<id>` in `scene_index.json`). Not `rooms/crystal-mine/`, which the brief
named: that folder holds today's 14 dead copies (`M1-mine-mouth.tscn` ...), and on this case-blind disk
`m1-mine-mouth.tscn` would be the same file (and its elevation cache the same `.res`). Step 5 deletes
the old folder. The Dungeon node is an instance of
`game/scenes/objects/dungeon/crystal-mine-dungeon.tscn`: `dungeon_id` and `record_map_id`
`crystal-mine` (today's, so the switch-over changes no record), the Colossus's seal settings as today
(`#8a68c0`, the roar at 0.6, dust `#c8d4f0`), the entrance M1, the layout
`rooms/crystal-mine-rooms/layout.tscn`.

### The wings

Each wing can be walked and reviewed alone; the doorways of a wing's rooms into a later wing are
painted with their room doors set, and lead nowhere until that wing is built (a room door whose
room is not on the layout never travels, as T2's south key door did).

| Wing | Rooms | What it holds | Engine pieces it needs |
|---|---|---|---|
| **1. The Mouth and the High Line** | M1 Mine Mouth, M2 Lamp Tunnel, M4 the Great Shaft (its gallery and high ledge), M6 Bat Gallery, M7 Ore Store | the way in (the seal's doorway), the first dark room, the hub with the Foreman's Gate and key 2 in sight, the rotten timbers (Heavy Roll), **the cart's teach** (M7's runaway cart bursts the rail gate into M1: the short way back), **the High Line** (the Pick Mole's crate loft, the upper doorway, the high walk over the bats in the dark, the hub's ledge: **key 2**), S3 (Silk), S5 painted (Feral, a come-back) | crystal-cave door leaves; the cart that rolls on into the next room |
| **2. The Lantern's half** | M5 Tally Room, M3 Survey Office, M8 the Dark Maze, M9 the Chasm | key 1, the map, the Foreman's Gate opened, the maze's four candles, the Chasm's lens (the Bow), the travel cart M1 - M9 | crystal-cave cracked wall (M5 - M3); the travel cart between worlds |
| **3. The Den and the Feral half** | M13 Shardback's Den, M11 Crystal Veil (the rift), M10 Prism Gallery, M12 the Fort Hall | Pearl 3 and the seal, the Shardback's cart line, the painted vines and balconies of the second half, the big key; the secret over M3's shelf onto the maze's wall tops (S1's chest) | the Shardback's cart hook; vines and balconies in room worlds |
| **4. The Shaft and the Colossus** | M14 the Shaft Floor (new: the shaft's floor becomes its own world), M15 the Colossus's arena (the lab's) | the roots down from the Den's broken rim, the lift, the boss door, his plate fight, the climb out to the Lookout; then the switch-over | the ore lift between worlds; the arena as the lab |

### The list of links (the whole Mine, written before any scene)

Cells are the room's own (column, row) from its top-left; every room's rim is two cells deep (floor
from (2, 2)); a one-screen room is 18 x 16 (floor 14 x 12, today's screen's floor). L0 is the floor,
L1 the upper level, L-1 a lower floor. Map: one floor (0) on a 1152 x 1024 grid, a room at
(column x 1152, row x 1024) of today's 5 x 5 grid; M14 and M15 on floor -1.

| Room | World id | Size | Map (floor, place) | Floor | Upper level |
|---|---|---|---|---|---|
| M1 Mine Mouth | `crystal-mine-m1-mine-mouth` | 18 x 16 | 0, (1152, 4096) | L0: the way in, the travel cart's station, the rails from the rail gate to a buffer stop | the S5 shelf, cols 2-5 x rows 2-4, vines on its face (row 5, cols 3-4), its chest |
| M2 Lamp Tunnel | `crystal-mine-m2-lamp-tunnel` | 18 x 16 | 0, (1152, 3072) | L0, dark: rails north-south (col 13), two voids (L-2) west of them, three sconces | - |
| M5 Tally Room | `crystal-mine-m5-tally-room` | 18 x 16 | 0, (0, 3072) | L0, dark: four crystal pillars, the desk, a Gloomling on K1 | - |
| M3 Survey Office | `crystal-mine-m3-survey-office` | 18 x 16 | 0, (0, 2048) | L0: the map chest on the surveyor's table, a Crystal Crawler | the shelf along the north wall (rows 2-4), reached only from M4's west shelf (Feral, wing 3) |
| M4 the Great Shaft | `crystal-mine-m4-great-shaft` | 36 x 16 | 0, (1152, 2048) | L0, the gallery round the shaft (a void, L-2, cols 13-25 x rows 5-11), two braziers lit for good | the high ledge, cols 29-33 x rows 8-13 (key 2's chest); the west shelf, cols 2-4 x rows 2-5, vines on its face (row 6, cols 2-3) |
| M6 Bat Gallery | `crystal-mine-m6-bat-gallery` | 36 x 16 | 0, (2304, 3072) | L0, dark: rails from the north doorway to the timbers, two Glint Bats over them, two sconces, the S3 nook in the south-west corner (rows 11-13, cols 2-5) walled off by crates, behind a web wall (*built*: its prize a chest, shown only to a save that never freed today's silk parcel) | the high walk: north leg cols 11-33 x rows 2-4, east leg cols 31-33 x rows 5-13; two Glint Bats on it |
| M7 Ore Store | `crystal-mine-m7-ore-store` | 36 x 16 | 0, (2304, 4096) | L0: the Bone Leaper (west half), **the runaway cart** held at (23, 7) on rails along row 7 to the west doorway, its knock target at (23, 4.4), pots; ore carts and heaps | the crate loft, cols 26-33 x rows 2-5, a front flight down at row 6 (cols 27-28): the Pick Mole behind his crates |
| M8 the Dark Maze | `crystal-mine-m8-dark-maze` | 36 x 32 | 0, (0, 0) | L0, dark: four corner candles, the void and the shadow path, two Gloomlings, three Glint Bats, the exit gate | the maze's inner walls (L1, crystal tops, two cells thick: *built*: north wall cols 7-21 x rows 9-10, west wall cols 7-8 x rows 11-29 to the south rim, east wall cols 22-33 x rows 17-18, the goal's enclosure), walked after Pearl 3 from M3's shelf to S1's chest on the north wall's east end |
| M9 the Chasm | `crystal-mine-m9-the-chasm` | 18 x 16 | 0, (2304, 0) | L0: the chasm (L-2, cols 7-12), the raised drawbridge and its lens (the Bow), the Bone Thrower, the travel cart's other station | - |
| M13 Shardback's Den | `crystal-mine-m13-shardback-den` | 18 x 16 | 0, (2304, 1024) | L0, dark: the Shardback (two braziers), a cart line across the den (its target by the west wall), Pearl 3 on its cradle | the ledge, cols 13-15 x rows 7-10, vines on its face (row 11, cols 13-14): the Feral skin's teach (*built*: the cart line along row 12.6 with its target past its east end and no buffer stop; the rim one doorway, cols 12-13) |
| M11 Crystal Veil | `crystal-mine-m11-crystal-veil` | 18 x 16 | 0, (3456, 1024) | L0 the two landings (west cols 2-5, east cols 11-15), L-1 the rift between and along the south (vines on both faces: the test); the veil across the north doorway | - (*built*: the landings L1 along the north, the rift L0 between and south of them) |
| M10 Prism Gallery | `crystal-mine-m10-prism-gallery` | 18 x 16 | 0, (3456, 0) | L0: the Prism Eye, the heavy ore crate, the journal chest, the veil's far brazier | - |
| M12 the Fort Hall | `crystal-mine-m12-fort-hall` | 18 x 16 | 0, (4608, 1024) | L0, cobble: the Watcher Eye, the Bone Marcher, five armour statues, two watch-fires | the balcony along the north wall (rows 2-4, L1: today's L2 is two levels, a room's face is one), vines up its face at cols 5 and 12 (balconies where a climb rests), the big chest (*built*: fort stone walls, as the plan says) |
| M14 the Shaft Floor | `crystal-mine-m14-shaft-floor` | 18 x 16 | -1, (2304, 2048) | L0: the calm room (pots, two hearts, an energy flower), the lift's lower landing, the boss door | the Den's broken rim, cols 11-14 x rows 2-4, the roots (vines) down its face (*built*: the ledge cols 11-14, its doorway cols 12-13, vines at row 5; the boss door in the north wall, cols 7-8) |
| M15 the Colossus's Arena | `crystal-mine-m15-colossus-arena` | the Colossus lab's room | -1, (3456, 2048) | the lab's arena as it is: two down lines and the lower line, four braziers, the void dips, the roots on the north wall | - (*built*: the lab's world itself, 26 x 24, at (1984, 512) on floor -1, north of M14; its way in the lab's south nook) |

Doors and crossings (room doors that scroll unless said; L0 unless said; both ends listed once):

| From (side, cells, level) | To | Lock | Wing |
|---|---|---|---|
| M1 south, cols 8-9: `mine-entrance` (door.gd) | Crystal Caverns G4, `camp-mine-mouth` (one way while G4 enters today's Mine); the seal `crystal-mine-M1-mouth-seal` stands in it | the seal (Pearl 3's take until the Colossus falls) | 1 |
| M1 north, cols 12-13: `m1-north` | M2 south, cols 12-13: `m2-south` | - | 1 |
| M1 east, rows 6-7: `m1-east` | M7 west, rows 6-7: `m7-west` | the rail gate on both sides (`gate_id` `crystal-mine-ore-gate`, one record): only M7's runaway cart bursts it | 1 |
| M1's shelf (L1) | - | the vines on its face (Feral) | 1 (painted), played in 3 |
| M2 north, cols 12-13: `m2-north` | M4 south, cols 12-13: `m4-south-m2` | - | 1 |
| M2 west, rows 8-9: `m2-west` | M5 east, rows 8-9: `m5-east` | - | 1 / 2 |
| M4 south, cols 22-23: `m4-south-m6` | M6 north, cols 4-5: `m6-north` | - | 1 |
| M4 south, cols 30-31, L1 (the ledge): `m4-south-ledge` | M6 north, cols 12-13, L1 (the high walk): `m6-north-walk` | from M4: the ledge is out of reach from the gallery (the High Line is the only way up); a drop off it lands on the gallery | 1 |
| M4 north, cols 8-9: the Foreman's Gate (`key-door`, two keyholes, `door_id` `foremans-gate`, today's) + `m4-north` | M8 south, cols 26-27: `m8-south` | keys 1 and 2 | 1 / 2 |
| M4 west, rows 2-3, L1 (the west shelf): `m4-west-shelf` | M3 east, rows 2-3, L1 (its shelf): `m3-east-shelf` | the vines up the west shelf's face (Feral) | 1 / 2-3 |
| M4's shaft, the lift's upper landing | M14, the lift's lower landing (a crossing as a door is) | the lift worked once from below | 4 (*built*: M4 (22, 4.4) on the north lip, M14 (4, 4.4)) |
| M6 south, cols 20-21: `m6-south` | M7 north, cols 20-21: `m7-north` | the rotten timbers on both sides (flag `crystal-mine.rotten-timbers`, today's): a Heavy Roll | 1 |
| M6 south, cols 31-32, L1 (the walk): `m6-south-walk` | M7 north, cols 31-32, L1 (the loft): `m7-north-loft` | from M6's floor the walk is out of reach; the loft's stair is the only way up | 1 |
| M5 north, cols 4-5 (cracked) | M3 south, cols 4-5 (cracked) | the Goo Bomb (flag `crystal-mine.survey-wall`, today's), a crack on both sides | 2 |
| M3 north, cols 7-8, L1 (the shelf) | M8 south, cols 7-8, L1 (the west wall's top) | (the secret's way on; Feral at M4's shelf) (*built*: cols 7-8; the list had 4-5, the maze's west wall stands at 7-8) | 2-3 |
| M8 east, rows 6-7 | M9 west, rows 6-7 | the maze's exit gate (`lantern-gate`, the four candles: today's group `dark-maze`) | 2 |
| M1's cart station (`mouth`) | M9's cart station | the travel cart, between worlds as a door (wing 2's engine piece); it starts at the Chasm | 2 |
| M9 south, cols 13-14 (the far rim) | M13 north, cols 13-14 | the Chasm's drawbridge (the lens, the Bow); the Den's fight shutter `crystal-mine-M13-den-shutter` while his fight lasts | 2 / 3 |
| M13 east, rows 8-9, L1 (the ledge) | M11 west, rows 8-9 (the west landing) | the vines up the ledge's face (Feral: the teach) | 3 |
| M13 south, cols 11-14 (the broken rim) | M14 north, cols 11-14, L1 (the rim's foot, the roots down) | the two rim shutters (`starts_shut`, sunk for good when he falls) | 3 / 4 (*built*: one doorway, cols 12-13, one shutter, the fight's reward) |
| M11 north, cols 13-14 | M10 south, cols 13-14 | the crystal veil (its braziers: M11's east landing, M10's side) | 3 (*built*: a veil on each side, each opened by its own room's brazier) |
| M11 east, rows 8-9 (the east landing) | M12 west, rows 8-9 | the rift (vines down and up: Feral) | 3 |
| M14 east, rows 8-9: the boss door (`colossus-door`, today's) | M15 west (the lab's lobby) | the big key | 4 (*built*: M14 north, cols 7-8, to M15's south nook, `m15-south`) |
| M15, the climb out (vines up the north-east wall) | Crystal Caverns H4, `lookout-from-mine` | the seal at its foot until he falls | 4 (*built*: today's root wall at (1344, 340), the seal at its foot) |

**Keys and locks in order:** key 1 (M5's floor key, `tally-k1`, today's) and key 2 (M4's ledge,
the chest with today's record `crystal-mine-M7-K2-chest`) open the Foreman's Gate (two keyholes);
the Bow lowers the Chasm's bridge; the Shardback's fall (`crystal-mine-shardback`) gives Pearl 3 and
the Feral skin, seals the mine and sinks the Den's rim shutters; the big key (M12's balcony, today's
record) opens M14's boss door. The prizes keep today's records: the map's chest, S1 (moved to a maze
wall top: 50 coins and the belt slot), S3 (*built*: a chest `crystal-mine-M6-S3-chest`, shown only while
today's parcel flag `silk-parcel.crystal-mine:Objects/M6-S3-parcel` is unset, so it is never had twice), S4, S5, M10's journal page, the big key; Pearl 3 the
Shardback's. No heart quarter.

**What each room teaches or holds (wing 1):**
- **M1:** the way in; the rail gate (shut, rails running under it) is in sight from the first step;
  the travel cart's empty station ("The cart is at the far end of the line."); the S5 shelf and its
  chest seen, out of reach (vines: Feral).
- **M2:** the first dark room: the ember shows the two voids beside the rails; three sconces light it
  for good.
- **M4:** the hub, seen from its south doorway: the Foreman's Gate (two locks), key 2's chest on the
  ledge in the south-east corner (no way up from the gallery), the shaft.
- **M6:** dark; the floor's way runs along the rails to the rotten timbers (a Heavy Roll); the high
  walk over it is out of reach. Later, on the walk in the dark, the bats wake under the slime's
  light. S3: Silk.
- **M7: the mechanism's teach.** A loaded cart held on its rails, its brake's rope running to a round
  target; a pot thrown at the target lets it go: it rolls west, bursts the rail gate and rolls on
  into M1 (seen there at its buffer stop, the gate burst on both sides): the short way back, for good.
  Nothing on its line can go wrong (the slime is knocked aside, the Bone Leaper struck). The Pick
  Mole on his crate loft; the loft's stair is the only way up, and the loft's north doorway starts
  the High Line.

**Checked against the plan's limits:** every target stands on the floor it is thrown from (M7's,
M13's, M15's on L0); enemies stay on the level they are placed on (the walk's bats and the loft's Mole
on L1); every face is one level (M12's balcony comes down from today's L2 to L1; M11's rift is L-1
under L0 landings; M4's shaft is a hole); no ladder inside a world (stairs and painted vines only);
no door in a face (every upper doorway is in a wall at its level's floor).

### Engine pieces the Mine needs (that do not exist yet)

| Piece | Wing | New art? |
|---|---|---|
| The crystal cave's door leaves (key1, key2, boss, shutter, seal, bolt, barricade) | 1 | Built without credits: the cave rock's leaves (the crystal frame was made from the cave rock's, so its doorway boxes are the same pixel for pixel) packed into `crystal-cave.webp`. A crystal set of its own is 7 renders if the owner wants it |
| The runaway cart that rolls on into the next room (M7's cart leaves by the west doorway; M1 shows it at its buffer stop once it has run) | 1 | No (the cart's own pictures) |
| Painted vines on a room's face inside a room world (M1's shelf, M4's west shelf) | 1 (checked), 3 | No |
| The crystal cave's cracked wall, blown hole and stairs openings | 2 (M5 - M3) | The cracked and blown pieces can be made from the plain frame by a script (as `make-root-cracked.py`); a stairs opening needs a render |
| The travel cart between worlds (`mine_cart.gd` and `mine_travel.gd` travel as a door does) | 2 | No |
| The Shardback answers the cart (`on_mechanism_hit(&"cart")`: brittle in the fire light, his shell shatters in one blow) | 3 | Maybe: a shattered-shell pose (his sheet has a stun) |
| Balconies in a room world (M12's climbs) | 3 | No (the balcony pictures by wall style; crystal rock's exists) |
| The ore lift between worlds | 4 | No (*built*: `ore_lift.gd` `partner_world`) |
| The Colossus's arena: the lab's room carried into M15 with `plate_fight` on | 4 | No (*built*: the lab's scene saved as the room) |

### Wing 1, the Mouth and the High Line: what is built (2026-11-25)

The five rooms of the list (M1, M2, M4, M6, M7), their layout and their Dungeon scene, beside today's
Mine; how to run it and what each room holds:
[DUNGEONS.md, "The Crystal Mine rebuilt"](../godot/DUNGEONS.md#the-crystal-mine-rebuilt-wing-1-the-mouth-and-the-high-line-step-4-2026-11-25).

| Piece | Files |
|---|---|
| Rooms (first versions; hand-edited from now on) | `godot/game/scenes/worlds/rooms/crystal-mine-rooms/{m1-mine-mouth,m2-lamp-tunnel,m4-great-shaft,m6-bat-gallery,m7-ore-store}.tscn`, `layout.tscn` (wing 1's five rooms; later wings add theirs); `scene_index.json` (five `world.crystal-mine-*` lines) |
| Elevation caches (new, to commit) | `godot/game/scenes/worlds/elevation_cache/rooms__crystal-mine-rooms__*.res` (all five) |
| Their builder | `godot/tools/build_crystal_mine_rooms.gd` (refuses to overwrite a room without `--force`) |
| Dungeon node | `godot/game/scenes/objects/dungeon/crystal-mine-dungeon.tscn` (`dungeon_id`, `record_map_id` `crystal-mine`; entrance M1; the seal's colour, roar and dust as today's) |
| Walk and films | `godot/tools/film_crystal_mine_rooms.gd` (`--film=walk|cart|look`) |
| Shared code changed | `godot/game/crystal_mine/ram_cart.gd`: `rolls_out` (the cart rolls on out through a doorway, gone for good) and `arrives` (the same cart seen at the next room's buffer stop once it has run): the teach needs the cart to cross from M7 into M1, and a cart that ended in the doorway would block it; a spent cart built again leaves its target slack. Both off by default: every placed cart as it was |
| Art (no credits) | `scripts/art/pack-interior-walls.py`: the crystal cave takes the cave rock's door leaves (the crystal frame has the cave rock's layout); `godot/asset/MAPS/walls/interior/crystal-cave.webp`, `interior-walls.json`, `palette.png` repacked, `game/world/interior/interior_wall_tileset.tres` (seven new tiles in column 5: the leaves' rows), `palette.res` and `trim-palette.res` saved again by `tools/pack_interior_palette.gd` (it writes both; the trims' picture is not changed by this work). The other styles' tables are byte for byte as before; the crystal cave's old pieces sit where they were, within the webp's encoding noise (mean 1.2 levels in 255) |

**Proof.** `--film=walk` passes all 41 of its checks, run after the last scene edit
(`output/dungeon-rework/mine/walk/`: `strip.png`, its 16 step pictures in one sheet, and `walk.json`;
the step pictures deleted): M1's rail gate holds; without Feral the shelf's vines are no way up; M2's
three lamps lit with the Lantern (lit for good); a step into its void costs 10 and puts the slime back;
the Foreman's Gate holds without keys; the ledge out of reach from the gallery; the west shelf's vines
no way up; M6's walk out of reach from its floor; the timbers hold, a Heavy Roll smashes them (shown
smashed on M7's side too); the Spear only knocks on M7's target (the cart stays held) and does nothing
to the rail gate; a pot at the target: the target knocked, the cart bursts the gate and rolls out,
spent; west through the burst gate into M1, the cart at M1's buffer stop, M1's gate burst; back east;
up the loft's stair (level 1), its north doorway onto M6's high walk (level 1), along both legs, its
north doorway onto M4's ledge (level 1), key 2 from the chest; a drop off the ledge lands on the
gallery unhurt; key 2 opens one of the Foreman's Gate's two locks and it holds; out through M2 and M1
to the camp (G4). Staged: enemies calmed, health kept full, the slime put near each step; the pot at
the target is made by the tool behind the slime (the room's pots stand beside it).

**The cart's teach, filmed** (`output/dungeon-rework/mine/cart-film/`: `strip.png`, `film.gif`,
`film-slow.gif`, `film.json`, `cart.json`, `m7-after.png`, `m1-after.png`; the frames looked at, then
deleted): PASS. The Spear's knock first, then the pot; the brake lets go at 0.8 s, the cart rolls from
0.9 s, bursts the gate at 3.5 s (splinters, dust) and has rolled out by 3.8 s; M1 after: the cart
against its buffer stop, the gate burst.

**Rooms:** as the editor shows them, `output/dungeon-rework/mine/rooms/<room>.png` (M2 and M6 without
their darkness), and in the game `rooms/game/look-<room>.png` (M2 and M6 with their lamps lit), every
one looked at.

**Weakest three.**
1. **The voids are flat black.** M2's two pits and M4's shaft draw the abyss: their far wall shows
   for 110 units and fades, their sides are cut straight; M4's shaft is a big black box in the hub's
   middle that reads as a hole, not as a deep shaft with its roots and the lift going down. The shaft
   is a void (a fall costs 10) until wing 4 makes its floor a world of its own and the lift joins them.
2. **The burst rail gate narrows its doorway** to the gap between its posts (about 74 units): a slime
   walking along the doorway's upper edge snags on a post (the walk had to line it up on the rails, row
   7.35). It is the gate's built shape (its posts always block), first used in a side doorway here.
3. **Nothing in it has been played with a keyboard,** and its enemies are calmed in the walk: the
   bats on M6's three-cell walk in the dark (can they knock a slime off? the walk's edge holds a body
   until it pushes on), the Pick Mole on his loft, the Bone Leaper on the cart's line. Also: M6's walk
   runs along the north and east walls, so it has a drop on one side only (the sketch's free-standing
   leg, drops on both sides, would have cut the floor's east strip off: no way in or out of it).

**Changed from the plan and the list, and why.**
- **The folder is `rooms/crystal-mine-rooms/`**, not `rooms/crystal-mine/` (today's dead copies live
  there under the same names, which this case-blind disk would have mixed up).
- **The cart rolls on into M1** (new: `rolls_out`, `arrives`): the plan's "bursts the rail gate into
  M1" crosses two worlds; the cart is gone from M7 and stands at M1's buffer stop, one record.
- **M6's high walk** runs along the north and east walls (above), and **S3's nook** moved from the
  east wall (where the walk's east leg now runs) to the south-west corner, walled off by crates and
  its web wall, as the Hollow's B3 nook (a wall stub inside a room would need four cells to show both
  faces).
- **M4's shaft is a void**, its floor (today's M14, the calm room and the boss door) a world of its own
  in wing 4 (a room's face is one level high, the shaft two). **S1's spire and lens** are not in the
  shaft: S1's chest moves to the Dark Maze's wall top (the plan), its record kept for wing 3.
- **M4's ore line** runs along the gallery's south side between its two south doorways (the mine's
  rails pass through); **M1's travel cart** station is placed, its line to the Chasm wing 2's.
- **The voids draw the abyss** (the Hollow's draw cavern stone): the Mine's floor is cavern stone, so a
  hole floored with it read as a step down.

**Art found missing:** none for wing 1. The crystal cave's door leaves are the cave rock's (above);
if the owner wants crystal ones of their own: seven GPT 2.5 renders, about 40 credits each (280 in
all), each "exactly the first reference image (`cave-bevel-leaf-<kind>.png`) ... the only change is the
material: the frame is dark blue slate packed with glowing icy-blue and violet crystals (second
reference `crystal-bevel-doorways-b.png`); the door in every opening stays exactly as it is", transparent.
For wing 2: the crystal cave's cracked wall and blown hole (made from the plain frame by a script, as
`make-root-cracked.py`, no credits); no stairs opening is needed (M9 to M13 is a doorway between two
worlds).

**For the owner, in the editor.** Focus the editor once (the five room scenes, their caches, the
layout, the Dungeon scene, the two tools import; the tools' `.gd.uid` files are written then, to
commit; the repacked `crystal-cave.webp` is read from its file until then). Reload before a save-all if
open: `game/crystal_mine/ram_cart.gd`, `interior_wall_tileset.tres`, and any crystal-cave room
(the Gloop Cavern, the Caverns' caves, the silk nook's cave: their walls are unchanged). No test run;
not played with a keyboard.

### The reviewer's read of wing 1 (2026-11-25): accepted, five polish points

The code was accepted (`ram_cart.gd`'s `rolls_out` / `arrives`, the borrowed leaves, the folder, the
cart in M1, M6's walk, M4's shaft as a void, the two chests' records, all 14 doors paired, the walk
after the last scene edit). The five points, done (the five rooms rebuilt one at a time with
`--force`: none had been edited by hand), the rooms rendered and pictured again:

1. **The voids were flat black boxes.** New, presentation only: `game/dungeon/pit_depth.gd`
   (`PitDepth`), laid over each hole right after the `ground` layer at z -2, so the room's own faces
   round the hole draw over it: from their foot the dark falls off smoothly to black (two gradient
   bands, the far wall seen a little deeper), dust drifts down and fades as it sinks, faint crystal
   glints twinkle deep down. The void hazards keep catching (their own flat abyss off). The Colossus
   lab's dips and the sky floor were looked at first: the dips are the same flat black, the sky floor
   is clouds. It can also hang ropes from the far rim (`cables`): tried as the lift's cables in M4's
   shaft, taken out (they hung from the top of the crystal face with nothing to hang from; the lift
   brings its own in wing 4). Best without art; a painted look down a shaft would need a picture
   (below, "Art").
2. **The tall plain boards** (the village houses' wall planks, `interior-structure-beam-wood*`) are out
   of every room: the project has no mine timber set (posts and a cap beam) that reads as a pit prop at
   a two-cell wall, and stretching the house posts would show. Crates, lumber, barrels, an ore heap and a
   toolbox stand in their places.
3. **M6's pale strip and bundle** were S3: the web wall (the Silk skin's lock, today's Mine's S3) and
   the silk parcel behind it. The lock stays a web wall (it is the only Silk lock there is; the Silk
   skin is Chapter 2's, used here for a first-half secret), across a nook now three rows tall walled
   off by crates, its strip off the trim's row (a barrel closes the row under it). The prize is a
   chest in the Mine's look (`crystal-mine-M6-S3-chest`, 30 coins and an energy potion, today's
   parcel's), inside a StoryVariant shown only while today's parcel flag
   `silk-parcel.crystal-mine:Objects/M6-S3-parcel` is unset, so a save that freed the parcel never has
   it twice.
4. **The burst rail gate.** `game/crystal_mine/rail_gate.gd` `posts_solid_when_smashed` (on by default:
   the lab's gate, on open floor, keeps its blocking posts) is off on the Mine's two gates: they stand
   in side doorways whose jambs already block beside the passage, and once burst their posts no longer
   narrow it (they still stand in the picture). The walk crosses M7 to M1 at row 6.65 and M1 to M7 at
   row 7.4, off the rails (row 7), near the doorway's two edges; the doorway's own passage is 120 units
   tall, so a slime placed higher than 6.65 meets the jamb, not a post. The lab's gate: its default is
   unchanged and nothing else in `_open()` changed (not filmed again).
5. **Doors into rooms not built yet:** a room door whose room is not on the layout has no target world
   (`room_door.gd` `target_world()` returns ""), and `door.gd` never travels without one (it is an
   arrival point only, line 207): the slime walks into the passage and stops there, inside the room.
   M2 west, M4 north and M4's west shelf led nowhere this way until wing 2 put M5, M8 and M3 on the
   layout; the Foreman's Gate is a key door (shut until keys 1 and 2). Today the only such door is M9's
   south doorway (the Den, wing 3): the walk pushes into it for 1.5 s and checks the slime is still in
   M9, inside its bounds.

### Wing 2, the Lantern's half: what is built (2026-11-25)

M5, M3, M8 and M9 to the list (their changes below), on the layout with wing 1's; how to run them and
what each holds: [DUNGEONS.md, "Wing 2, the Lantern's half"](../godot/DUNGEONS.md#wing-2-the-lanterns-half-2026-11-25).

| Piece | Files |
|---|---|
| Rooms (first versions; hand-edited from now on) | `rooms/crystal-mine-rooms/{m5-tally-room,m3-survey-office,m8-dark-maze,m9-the-chasm}.tscn`; `layout.tscn` rewritten (`--layout --force`, no hand edits: nine rooms); `scene_index.json` (four more lines); M1 rebuilt (its station joined to the Chasm's, its arrival point) |
| Elevation caches (new) | `rooms__crystal-mine-rooms__{m3-survey-office,m8-dark-maze,m9-the-chasm}.res` (M5 has no levels), the wing 1 rooms' baked again |
| Builder, films | `tools/build_crystal_mine_rooms.gd` (wing 2's rooms, `_pit`, `_crack`, `_arrival`, `_variant`), `tools/film_crystal_mine_rooms.gd` (the walk through both wings, `--from=wing2`, `--film=ride`) |
| New code | `game/dungeon/pit_depth.gd` (point 1) |
| Shared code changed | `game/crystal_mine/mine_cart.gd`: `partner_world`, `partner_station`, `partner_door`: the travel cart rides between the Chasm's world and the Mouth's as a door does (`request_exit`, a fade), its place kept under the dungeon's record; off, as before (today's Mine, the smith's cart: `smith_cart.gd` compiles unchanged); the station it leaves says nothing as the slime rides off. `game/crystal_mine/rail_gate.gd`: `posts_solid_when_smashed` (point 4) |
| Art (no credits) | new `scripts/art/make-crystal-openings.py` and its two pictures `asset/Originals/dungeon-kit/interior-walls/crystal-bevel-{cracked,blown}-made.png` (both pass `strip-credentials.py --check`); `scripts/art/pack-interior-walls.py` packs them for crystal-cave; `crystal-cave.webp`, `interior-walls.json`, `palette.png`, `interior_wall_tileset.tres`, `palette.res`, `trim-palette.res` written again (the other styles byte for byte as before; the crystal cave's old pieces within the encoding's noise, a mean of 1.4 in 255; four `*_doorway_front` pieces and the leaves moved in the sheet, the table says where) |

**Proof.** `--film=walk` from M1 passes all 82 of its checks, run after the last scene edit
(`output/dungeon-rework/mine/walk/`: `strip.png`, its 29 step pictures in one sheet, and `walk.json`;
the step pictures deleted): wing 1's 41 (the burst gate now crossed off the rails, near both edges) and
wing 2's 41: the Tally Room's crack holds, key 1 where the Gloomling sat, a Goo Bomb blows the crack
(today's flag), the Survey Office's map, its shelf out of reach from the floor, back to the hub, key 1
opens the Foreman's Gate's second lock and the slime walks through into the maze; the exit gate holds
while the candles are cold, the wall tops out of reach from the floor, the four candles lit with the
Lantern open the gate for good, through it and the enclosure's east doorway into the Chasm; the bridge
stands raised, a step into the chasm costs health and puts the slime back, the Bow's arrow over the
chasm strikes the lens, the bridge comes down for good, across it; the Den's doorway (wing 3) stands
without loading a world, the slime still in M9; the cart rides from the Chasm to the Mouth and back,
standing at the station it rode to; back through the maze and the gate to the hub; with the Feral skin
lent (as Pearl 3 gives it), up the vines onto the hub's west shelf (level 1), its doorway onto the
Survey Office's shelf (level 1), the shelf's doorway onto the maze's west wall (level 1), north along its
top, east along the north wall's top, S1's chest opened and emptied, a drop off the west wall's side to
the floor; out through the maze, the hub, the Lamp Tunnel and the mouth to the camp. Staged: enemies
calmed, health kept full, the slime put near each step; the four candles lit by putting the slime by
each in turn; S1's two things taken as the chest window's buttons take them. `--from=wing2` plays wing 2
alone (key 2 given).

**The travel cart, filmed** (`output/dungeon-rework/mine/ride-film/`: `strip.png`, `film.gif`,
`film-slow.gif`, `film.json`, `ride.json`; the frames looked at, then deleted): PASS: the interact key at
the Chasm's station, the fade, the Mouth's world fading in with the cart at its station and the slime
beside it.

**Rooms:** all nine rendered again as the editor shows them (`output/dungeon-rework/mine/rooms/`, the
dark ones without their darkness) and pictured in the game (`rooms/game/look-<room>.png`, the dark ones
with their lamps lit; M5 and M8, which stay dark for good, pictured with `--bright`: their darkness
hidden, so their floors show).

**Weakest three.**
1. **The Dark Maze is a few walls in the dark**, as today's: three long walls and the goal's
   enclosure on a 32 x 28 floor. It is a maze only in the dark (the ember's small circle); lit, its way
   is plain. Its walls are now two cells thick (one-cell raised strips read as narrow walks and would
   be walked on top in the second half), which takes room from the corridors.
2. **The four candles in 60 s are staged**: the walk puts the slime by each candle in turn (its game
   time between the first and the last flame is a few seconds). Walked, the way from the south-east
   candle round to the south-west one is about 75 cells through the maze; nobody has timed it with a
   keyboard. The Gloomling on the north-west candle had to be driven off by standing in the Lantern's
   light for 2.5 s first (its smothered wick refuses the flame meanwhile).
3. **The voids are deeper but still drawn by code**: the dark falls off over two gradient bands with
   dust and glints, the hole's sides are the room's one-cell faces. It reads as a hole with walls going
   down, not as a painted mine shaft with timbering. Also: M9's bridge, crossed over the chasm's depth
   look, draws as the kit's planks (not filmed close).

**Changed from the list, and why.**
- **M3's north doorway and M8's south shelf doorway are at cols 7-8** (the list: 4-5): the maze's west
  wall, whose top the secret walks, stands at cols 7-8 and runs down to the south rim to meet it.
- **M8's walls** (the list: "inner walls (L1)"): north wall cols 7-21 x rows 9-10, west wall cols 7-8 x
  rows 11-29, east wall cols 22-33 x rows 17-18, the enclosure (cols 26-27 x rows 2-9; its south wall
  rows 8-9 with the gate's gap at cols 30-31), all two cells thick, crystal tops; the void cols 12-21 x
  rows 12-22. Today's maze's walls were one cell thick, its west wall short of the south rim.
- **M9's lens stands on the far rim's edge** ((13.6, 8.0); today's lay a cell further east): the Bow's
  arrow carries 512 units, and from the near rim's edge the lens must be within it.
- **The wall-top secret is built and walked now** (the reviewer's choice offered: build the wall tops and
  S1 now, leave the climb to the Feral wing): the climb itself is the vines painted on M4's west shelf in
  wing 1, which only the Feral skin climbs; the walk lends the skin (as Pearl 3 gives it) to prove the
  way: the vines, M3's shelf, the maze's west and north wall tops, S1's chest, a drop to the floor.
  Nothing else waits for wing 3.
- **S1's chest** stands on the north wall's top at its east end ((20.6, 9.4)), its glint over the maze.
  A drop south off that wall lands in the void (one row of floor lies between them): a fall, 10 health.

**Art.** None missing for wing 2 (the cracked and blown pieces are made, above). For point 1, if the
owner wants the shaft painted rather than drawn: one GPT 2.5 still, about 40 credits: "top-down view
straight down a deep square mine shaft, dark blue slate walls with glowing icy-blue and violet crystal
veins and old timber cribbing receding into black darkness, faint dust in the air, hand-painted game art
matching the reference (crystal-bevel-doorways-b.png), seamless edges, transparent outside the shaft",
laid in the hole under the faces as the depth look's floor.

**For the owner, in the editor.** Focus it once (four new room scenes, their caches, the new scripts and
pictures import; `.gd.uid` files written then). Reload before a save-all if open: any of the nine
rooms, `layout.tscn`, `mine_cart.gd`, `rail_gate.gd`, `interior_wall_tileset.tres`. No test run; not
played with a keyboard.

### The reviewer's read of wing 2 (2026-11-25): accepted, four points

The fix round, the travel cart, the rail gate, S3, the doors and wing 2 were accepted in code. The four
points, done:

1. **M8 is a maze now.** Lines of crystal clusters (the `crystal walls` props, one cell each, at 1.25 so
   their collision, 60 x 55 in a 64-unit cell, closes each cell to the 30-wide slime) part the floor
   into branches and dead ends: the north-west candle in a nook behind two lines, the north-east one
   in a nook off the north corridor, the south-east one in a pocket by the way in, the south-west one
   at the foot of a zigzag down the west strip; dead ends with something in each (S4's chest and its
   Gloomling at the end of the strip under the void, pots in the zigzag's bays, an ore heap and pots in
   the bay by the way in, lumber and a pot behind the north corridor's stub, a Gloomling, an ore heap
   and a pot in the north-east hall's pocket). Not the Lair's fort-stone dividers: they are the only
   divider art there is, cream masonry, and would read wrong in the crystal mine; the crystal clusters
   are the mine's own walls. The raised walls and S1's wall-top route are as built; the void shrank
   to cols 14-21 x rows 14-22: a raised wall's front face fills the cell south of it, its side and back
   faces about half the cells beside and north of it, and a hole keeps a rim round it, so the first
   corridors (row 11 between the north wall and the void, col 11 beside it) were closed (found when the
   walk first walked them; the maze is laid with those cells counted as blocked).
2. **The candles' time, worked out.** Measured on the new maze (a grid walk of its free cells, the
   faces counted as blocked): the best order from the way in is south-east, north-east, north-west,
   south-west; from the first flame to the last 128 cells = 8192 units = 45.5 s at the slime's 180
   units a second (`player.movement.baseSpeed`), plus about 2.5 s holding the Lantern on the
   north-west candle's Gloomling and four flames (about 0.5 s each): **about 50 s**. The limit is
   **90 s** (`MAZE_CANDLE_MS`, each candle's `burn_ms` in the scene): 40 s for wrong turns and a bat.
   The walk lights them by walking the route (no placing): **49.8 s** from the first flame to the last,
   138 cells walked, all four lit at once, the gate open.
3. **Key 1's record:** `crystal-mine:key:tally-k1` in both: the floor key's record is
   `DungeonState.object_key(key, "key:" + pickup_id)`, keyed by the dungeon's record id, and the new
   M5's key has today's `pickup_id` `tally-k1` under the record `crystal-mine`, as today's one-scene
   world (its map id `crystal-mine`). The same record: an old save that took key 1 never gets it again.
   Nothing changed.
4. **The crystal crack toned to the wall:** `make-crystal-openings.py` lays the Goo Bomb's crack decal
   thinned (its alpha eroded 3 px), filled with the frame's dark blue (`#0e1634`), a pale blue edge
   (`#96c4f0`, 55 %) one pixel below and right, once and at 90 % (it was the decal's brown laid twice
   with a shadow). Compared side by side at the sheet's size and at game size with the cave rock's
   (a crack drawn into its stones' joints, the faintest) and the root rock's (the brown decal): the
   crystal's now reads as dark lines through the crystals, about as strong as the root rock's. Both
   pictures pass `strip-credentials.py --check`; the crystal sheet repacked.

### Wing 3, the Den and the Feral half: what is built (2026-11-25)

M13, M11, M10 and M12 to the list (changes below), on the layout; what each holds and how it plays:
[DUNGEONS.md, "Wing 3"](../godot/DUNGEONS.md#wing-3-the-den-and-the-feral-half-2026-11-25).

| Piece | Files |
|---|---|
| Rooms (first versions) | `rooms/crystal-mine-rooms/{m13-shardback-den,m11-crystal-veil,m10-prism-gallery,m12-fort-hall}.tscn`; `layout.tscn` rewritten (13 rooms); `scene_index.json` (four more lines); M8 rebuilt (point 1); M9's south doorway now leads to M13 |
| Elevation caches (new) | `rooms__crystal-mine-rooms__{m13-shardback-den,m11-crystal-veil,m12-fort-hall}.res` (M10 has no levels); M8's baked again |
| Builder, films | `tools/build_crystal_mine_rooms.gd` (wing 3's rooms; a room's own wall style and trim, `ROOM_STYLES`: the Fort Hall in fort stone; the maze's partitions, void and candles' time as constants), `tools/film_crystal_mine_rooms.gd` (the walk through all three wings, `--from=wing3`, `--film=shardback`, the candle run walked, a page's window closed as Escape does, energy kept full with health) |
| Shared code changed | `game/scripts/shardback.gd`: `on_mechanism_hit(&"cart")` (brittle: his shell shatters, he falls; cold: a clang, a stagger: a `stagger` phase, his walk frame rocked), his slam knocks a crystal chunk loose (`slam_chunk_kind`, at most `slamChunksMax`, off a cart's line and the lane to its target): the plan's "the cart shatters his shell" and the rule that a throw fight has ammo that renews. In today's Mine and his pen his slams now leave chunks too (harmless: things to throw); no cart there. `game/data/enemy-types.json`: his ten new numbers (`cartShatterDamage`, `cartShatterShakeMs`, `cartShatterShake`, `cartColdDamage`, `cartClangShakeMs`, `cartClangShake`, `cartStaggerMs`, `slamChunksMax`, `slamChunkOffsetPx`, `slamChunkRailClearPx`) |
| Docs | DUNGEONS.md (wing 3, the maze, the candles' time, the hooks' list), BESTIARY.md row 28, INTERIOR_WALLS.md (the crack's tone), AGENTS.md (the films), this handover |

**His frames:** none faked. The shattered shell is his own defeat frame (frame 3 of
`256x256-tile_16x1-shardback.webp`: the shell burst into a heap of crystal), shown as he falls, with the
crystal burst, the `BreakGlass` cue and a hard shake; the cold clang's stagger is his walk frame rocked
and shaken (no stagger frame exists). If the owner wants the blow itself drawn: two or three frames
(the shell cracking open under the blow, shards flying, the tortoise thrown on its side), one GPT 2.5
sheet, about 40 credits: "the crystal-shelled tortoise from the reference sheet, three frames in a row:
struck from behind by a mine cart, its crystal shell cracking with orange-hot light in the cracks;
the shell bursting, shards flying up; lying on its side, the shell in pieces round it; same style,
same scale, transparent background".

**Proof.** `--film=walk` plays wings 1 to 3 from M1 and passes all 126 of its checks (166 steps),
run after the last scene edit: the candle run (49.8 s walked, 138 cells), the Den's shutter, the vines
refused without the skin, the Spear only knocking on the target, the cold clang (140 to 130, a stagger),
the cart hauled back and the target rearmed, a slam's chunk, the brittle shell, one blow, both shutters
open, Pearl 3 and the seal, the rift's climbs, the veils with and without their braziers, the Prism Eye
untouched by a throw, the journal page, the big key, the drop off the balcony, the Den's rim leading
nowhere yet, the wall-top secret walked with the route's skin, the sealed mouth. `--from=wing3` passes
alone too. `--film=shardback` films the blow frame by frame (PASS): the strip and two GIFs in
`output/dungeon-rework/mine/shardback-film/` (`strip.png`, `film.gif`, `film-slow.gif`, `film.json`).
The walk's strip and `walk.json` in `output/dungeon-rework/mine/walk/`; the rooms drawn whole in
`output/dungeon-rework/mine/rooms/` (all 13), the game's view of each in `rooms/game/`. Frames and step
pictures deleted.

**Changed from the list, and why.**
- **M13's broken rim is one shuttered doorway, cols 12-13** (the list: cols 11-14, two shutters): a room
  fight's `reward` is one node; its other end in M14 (wing 4) is one doorway too.
- **M13's target stands past the line's east end, the rope along the rails, no buffer stop** (the
  list: "its target by the west wall"): the slime baits him along the rails toward it and he stands
  between the cart and the slime when it strikes (the Hollow's B5, accepted); the buffer stop would
  stand between the slime and the target and catch the throw (found in the film: the pot broke on it),
  so the cart halts at the rails' end a cell short of the target.
- **M11's landings are L1 and the rift L0** (the list: landings L0, the rift L-1): the same one level;
  vines climb front faces only, so the landings are along the north and the rift south of them; the
  Den's ledge (L1) carries its level onto the west landing.
- **M10 has a veil and a brazier on its own side** (the list: "the veil across the north doorway,
  its braziers on M11's east landing and M10's side"): the two rooms are worlds, a veil opens for the
  braziers of its own world.
- **M12's balcony is L1** (as the list said), its walls fort stone (the plan: "fort stone in the Fort
  Hall"); no balcony pieces are painted: every climb is one level.
- **The wall-top secret is walked in wing 3**, after Pearl 3, with the skin the route gave (in wing 2 the
  walk had lent it); wing 2's walk now ends with the cart back at the Chasm.

**The painted shaft (the owner's yes, 2026-11-25): made, 40 credits** (one GPT 2.5 still, 16:9, 1k,
the first one kept; the style reference a crop of M4's render). Source
`asset/Originals/dungeon-kit/pits/mine-shaft-a.png` (stripped: 4.7 MB to 2.0 MB; leaves git with the
folder), packed by the new `tools/pack_pit_picture.gd` into `godot/asset/MAPS/interiors/mine-shaft.res`
(2.5 MB, a texture resource: no import, as the interior palette). `pit_depth.gd` gains `picture`,
`picture_margins` (it begins at the faces' inner edge: drawn over the whole hole it covered them) and
`picture_dark`; M4's scene and the builder set it. Before and after:
`output/dungeon-rework/mine/shaft/m4-before-after.png`, close: `m4-after-close.png`. M8's void could take
a square crop of it; M9's chasm (a rift with a bridge) not; no credits spent there.

**For the owner, in the editor.** Focus it once (four new rooms, their caches, the changed scripts
import). Reload before a save-all if open: any of the 13 rooms, `layout.tscn`, `shardback.gd`,
`enemy-types.json`, `interior_wall_tileset.tres`. No test run; not played with a keyboard.

### The reviewer's read of wing 3 (2026-11-25): accepted

The four fixes and wing 3 were accepted (`shardback.gd`'s cart hook, stagger and slam chunks, his ten
numbers; M8's partitions and the candle run; key 1's record; the crack's tone; M13's target past the
rails' end, its one rim doorway; M11's levels; M10's own veil and brazier; the Fort Hall in fort stone;
the walk's 126 checks; the painted shaft, 40 credits). His defeat frame as the shattered shell stands
for now; the three drawn frames are the owner's call, not asked yet. Asked in the read: **M5's and M8's
dark rooms list no candles**, so nothing ever lifts their dark. Meant: carried over from today's Mine,
whose `dark-M5-tally-room` and `dark-M8-dark-maze` list none either (only M2, M6 and M15 do); M5 is
"dark for good" in the list, and M8's four candles open its gate, each lighting its own pool. How dark
rooms brighten is being settled with the owner; nothing here changed `dark_room.gd`, `candle.gd` or the
candles' numbers.

### Wing 4, the Shaft and the Colossus: what is built (2026-11-25)

M14 and M15 on the layout's floor -1; the ore lift between M4 and M14; the walk through all four wings
from the camp in G4; his fight filmed in the room. What each room holds and how it plays:
[DUNGEONS.md, "Wing 4"](../godot/DUNGEONS.md#wing-4-the-shaft-and-the-colossus-2026-11-25).

| Piece | Files |
|---|---|
| Rooms (first versions) | `rooms/crystal-mine-rooms/{m14-shaft-floor,m15-colossus-arena}.tscn`; M4 rebuilt (the lift's upper landing and its arrival point; nothing else changed); `layout.tscn` rewritten (15 rooms; M14 and M15 on floor -1); `scene_index.json` (two more lines) |
| Elevation caches (new) | `rooms__crystal-mine-rooms__{m14-shaft-floor,m15-colossus-arena}.res` |
| Builder | `tools/build_crystal_mine_rooms.gd`: `_m14`; `_build_m15` loads the Colossus lab's scene and saves it as the room with the mine's pieces (below); `_lift` |
| Films | `tools/film_crystal_mine_rooms.gd` (the walk from G4 through all four wings, `--from=wing4`); `tools/film_colossus_arena.gd` (new: `film_colossus.gd`'s films in M15, four with PASS or FAIL); `scripts/godot/film-colossus.sh` (`--tool=film_colossus_arena`); `tools/render_room_scene.gd` (a room without interior walls, M15, rendered at its world's size, not 18 x 16) |
| Shared code changed | `game/crystal_mine/ore_lift.gd`: `partner_world` and `partner_door` (the lift rides to a landing in another world as a door does, its states under the dungeon's record, as `mine_cart.gd` does since wing 2); empty, every lift as it was (today's Mine's) |
| Docs | DUNGEONS.md (wing 4, the ore lift's line, the plate fight's status, the M4 row, Not done yet), AGENTS.md (the films), this handover |

**M15 against the lab, to the decimal.** The room is the lab's scene loaded and saved again, so every lab
node keeps its numbers; a line-by-line diff of the two scenes (resource ids aside) shows only:

| Lab (`colossus-lab.tscn`) | M15 (`m15-colossus-arena.tscn`) |
|---|---|
| root `colossus-lab`, no script | root `m15-colossus-arena`, `room_scene.gd` (`world_id`, `room_id`) |
| `map_id` `colossus-lab` | `crystal-mine-m15-colossus-arena` |
| camera room `hall` | named as the room (`wall_bands` off, as every mine room) |
| `Objects/lobby-note` | gone |
| `ColossusArena`: `camp_id`, `boss_id` `colossus-lab`; `refights` on; `seal_cells` none | today's ids (`crystal-mine-colossus`, `crystal-colossus`: the script's defaults); `refights` off; `seal_cells` (800, 1376), (864, 1376); `climb_wall` `../M15-root-wall` |
| `Dungeon` (`dungeon.tscn`, `colossus-lab`) at (828, 1330), `dungeon-entrance` | `Dungeon` (`crystal-mine-dungeon.tscn`) at (828, 1330); no entrance marker (M1's) |
| the nook, cols 12-13, rows 21-22 | cut on through row 23 (ground and elevation), `RoomDoors/m15-south` at (832, 1536) |
| - | `M15-root-wall` (1344, 340), top (0, -312), art (104, 300), to H4 `lookout-from-mine`; `M15-climb-out-seal` (1344, 324); `M15-full-heart` (832, 640); `MusicPlayer` |

Unchanged, among the rest: the arena at (832, 862), `arena_rect` (64, 320, 1536, 1024), `floor_rect`
(192, 320, 1280, 1024), `wall_rect` (64, 64, 1536, 296), `post` (0, -40), `climb_spots` (640, 300) and
(1024, 300), the carts, targets, braziers, roots, the 14 pots (their loot: all 14 `loot` lines and all
14 `[editable path]` lines kept), the dips at (64, 320) and (1472, 320), `dark-hall` 0.6, the spawn.
His encounter's values are on the arena node itself (a plain node of the room, no instance), and the
full heart is the room's own nodes, so no value of the fight hangs on an inner node behind an
`[editable path]` line.

**Proof.** `--film=walk` plays all four wings from the camp in G4 and passes all 154 of its checks
(203 steps), run after the last scene edit: wings 1 to 3 as before (the lift refused from M4's gallery
in wing 1), M14 after Pearl 3 (the rim's ledge, the roots down, the boss door refused without the big
key, the lift's crank up to the hub, the platform up there and the lift offered both ways), the mouth
sealed, the wall tops to S1, round to the Den, the rift, the big key, the Prism Gallery; M14 again, the
boss door opened with the big key, M15 (his camp's ids, the plate fight, once), he wakes, the crystal over
the nook, the climb out refused while he stands, his fight ended by the tool, Release 1's end card, his
defeat recorded, the seals sunk, his full heart risen and taken, up the roots to the Lookout (H4), the
mouth's seal sunk, out to the camp. Its strip and `walk.json` in `output/dungeon-rework/mine/walk/`.
**His fight in M15** (`scripts/godot/film-colossus.sh <film> --film=<film> --tool=film_colossus_arena`):
burst PASS (the cart bursts his breastplate in the ring, he kicks it home), clang PASS (cold, it clangs
off, he kicks it home), wall PASS (three claw strikes from the roots, he crashes across the west line,
its cart takes his last plate), core PASS (the Spear until he falls); strips, GIFs and `film.json` in
`output/dungeon-rework/mine/arena-films/<film>/`. The rooms drawn whole in
`output/dungeon-rework/mine/rooms/` (M4, M14, M15 new), the game's view of M14 and M15 in `rooms/game/`.
Frames and step pictures deleted.

**Changed from the list, and why.**
- **M15's way in is the lab's nook, south** (the list: "M15 west (the lab's lobby)"): the lab's lobby is
  a nook in its south wall, and the room keeps the lab whole; the nook is cut on to the room's edge for
  the door. So **M14's boss door is in its north wall, cols 7-8** (the list: east, rows 8-9), and **M15
  sits north of M14 on floor -1, at (1984, 512)** (the list: (3456, 2048)), its nook straight above the
  boss door. M14 stays at the list's (2304, 2048), its rim's foot under the Den's rim.
- **M14's rim ledge is cols 11-14, its doorway cols 12-13** (the list: cols 11-14; wing 3 made the Den's
  rim one doorway).
- **The ore lift's landings:** M4's upper at (22, 4.4) on the shaft's north lip, M14's lower at (4, 4.4):
  one place on the map (x 2560), under the painted shaft's right-hand rope.
- **The walk visits M14 twice**: right after Pearl 3 (the boss door refused without the big key, the
  lift worked from below up to the hub, then the mouth, the wall tops and round to the Den), and with
  the big key to his fight. The wall-top secret is walked there now (it was wing 3's end).
- **The walk starts in G4** but G4's mine door still enters today's Mine until the switch-over: its
  first step puts the slime through to M1's mouth (a staged door), and its last goes back to M1 the
  quick way to see the mouth's seal sunk and walk out to G4. It lends the powers a run started in M1
  gets (`dungeon.devPowers.crystal-mine`), as F6 on M1 does.
- **Release 1's end card** opens at his fall (`chapter-3-complete`, as today's Mine); the walk checks it
  opens and closes it (in play "Return to title" saves and the run goes on from the save).

**Art.** None missing for wing 4 (the lift's, the boss door's, the roots' and the full heart's pictures
exist). M14 shows the lift and the cold light from the shaft above, not the painting's timbers and
ladder: the project has no timber cribbing that reads as a pit prop (wing 1's finding), and a ladder
object is a crossing. If the owner wants the shaft's foot drawn (timber cribbing round the lift, a
ladder broken off above): one GPT 2.5 sheet of three props, about 40 credits (not spent).

**For the owner, in the editor.** Focus it once (two new room scenes and caches, a new tool script).
Reload before a save-all if open: M4, `layout.tscn`, `ore_lift.gd`, and any room scene. No test run;
not played with a keyboard.

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

**Step 5 (2026-11-25): done** (the owner: "step 5 this is the way to go so get rid of the old"), by the
hollow-floors session, for the reviewer's read before the commit. Today's Weaver Hollow (four floor
worlds) and today's Crystal Mine (one world) are gone, with their copies, builders and the code only
they used; the tests that built them are rewritten for the rebuilt dungeons; the docs read as the game
is. Files deleted with the file system (no `git rm`); all of them are in `09d5ebae`. Nothing
committed; the suite not run. **Turning back** is no longer one line in a chunk scene (the two switch-overs' notes below
predate this): the old worlds would have to come back from `09d5ebae` (files, `scene_index.json`
lines, tools), and the two gates' targets with them.

**Removed (76 files):**

| What | Files |
|---|---|
| The Hollow's four floors | `worlds/weaver-hollow-{trunk,roots,boughs,crown}.tscn`, their 22 room copies in `rooms/weaver-hollow-{trunk,roots,boughs,crown}/`, their four elevation caches, their four `scene_index.json` lines |
| The Mine's one world | `worlds/crystal-mine.tscn`, its 14 unused copies in `rooms/crystal-mine/`, its cache `crystal-mine.res`, its `scene_index.json` line |
| The old Crown's fight | `encounters/weaver-hollow-matron-old.tscn` (the copy only today's Crown used) |
| Game scripts only they used | `game/dungeon/doorway_art.gd` (the cliff-wall doorway frames: it acted only in worlds named `crystal-mine` or `weaver-hollow-*` without interior walls, so on no world left; its call in `dungeon.gd` and the room mask's frame cut-outs, `room_mask.gd` and `room_mask.gdshader`, went with it), `game/scripts/room_arenas.gd` (the floors' node), `game/scripts/latched_hatch.gd` (the old hub's hatch; attached to nothing else, a comment in `door.gd` had hidden it from the first count) |
| Tools only they used | `build_weaver_hollow.gd` with `weaver_hollow/hollow_{canvas,floors,scene}.gd`, `film_weaver_hollow.gd`, `render_weaver_hollow.gd`, `render_matron.gd` (mounted her in today's Crown), `build_crystal_mine.gd`, `split_dungeon_rooms.gd` with `lib/dungeon_room_splitter.gd` (its worlds list held only the five), `render_dungeon_room_views.gd` (the doorway review's stills: two of its five shots were the removed worlds, two more named rooms that left the `fatty-lair` world in 2026-10-18 and were skipped), `scripts/maps/weaver-hollow-contact-sheet.py` (laid out `film_weaver_hollow.gd`'s shots) |

Each `.gd` went with its `.gd.uid`: 14 scripts, 14 uids, 42 scenes, 5 caches, 1 Python script.
`scene_index.json` holds no path to a missing file (checked).

**Kept that looked removable, and why:**

- **The Colossus's first fight** (`plate_fight` off in `crystal_colossus.gd` and `colossus_arena.gd`:
  the weak spot under four braziers, the stomp-count climb, every stomp a brazier out). Dead in the
  game now: only today's Mine left the switch off; M15 and the lab set it on. Not removed: it runs
  through about 45 branches of the 2,200-line boss script (the plate fight is built on it: the
  stomp, the wall, the mites and the claws are shared), the mine-wings session was editing that file
  this same day (`in_fire_ring`), and the two scenes that set the switch (M15, the lab) are other
  sessions' files. Its comments and DUNGEONS.md say it is placed nowhere; its rules are in the
  archive. A follow-up of its own, with M15's arena films as the proof.
- **The cocoon fight** (`game/scripts/matron.gd`, `character.orb-weaver-matron`): the ram fight
  (`matron_ram.gd`) extends `MatronScript` and keeps `cocoon_enabled` on; the nest camp
  (`encounter.gloop-matron-nest`) and `test_matron.gd`'s first eight tests mount the base fight. The
  nest is placed in no world (since the Hollow took the forecourt, 2026-10-17): an older orphan, the
  owner's call.
- **The room shell** (`room_scene_shell.gd`): the box-room lab is assembled by it.
- **The doorway textures** (`asset/MAPS/objects/dungeon/doorways/`, `pack-doorway-art.py`,
  `pack_doorway_textures.gd`): the latch door and the carts' tunnels use them.
- **Three props only today's Mine placed** (`props/caverns/256x256-crystal-pillar.webp`,
  `props/mine/256x256-ore-heap.webp`, `props/mine/256x256-rock-stump.webp`): runtime art, in no palette;
  kept for the owner's eye rather than deleted with the world.
- **`RunState.RETIRED_WORLDS`, `moved_world`**, the four old names in `area_titles.gd` (an old save's
  slot label), both boss labs and the mechanism lab with their film tools, every record id the rooms
  share with the old worlds (`weaver-hollow-roots`, `weaver-hollow-boughs`, `weaver-hollow-crown-*`
  door and shutter ids, `crystal-mine`).
- The `wall_bands` meta the two room builders still set on CameraRooms: nothing reads it now (the
  room mask did, for the doorway frames); harmless, in the new rooms' scenes, not mine to edit.
- `.godot/global_script_class_cache.cfg` still lists `LatchedHatch` and `RoomArenas`: the editor
  rewrites it on its next scan (no headless import run).

**The grep** (every removed world id, scene path, script and tool across `godot/`, `scripts/` and
`docs/`, after the removal):

| Where | Verdict |
|---|---|
| `run_state.gd` `RETIRED_WORLDS` (the five old ids) | kept: old saves still name them |
| `area_titles.gd` (the four old floor names) | kept: an old save's slot label |
| `game-constants.json` `devPowers.crystal-mine`, `world-map.json` (`crystal-mine`), `crystal-mine-dungeon.tscn` | the record id, also the old world's: right as it is |
| `scene_index.json` `world.crystal-mine-m*` | the rebuilt rooms (the id only matches as a prefix) |
| the rooms' prize records: M1, M3, M4, M6, M8, M10, M12 (`map_id` `crystal-mine`), D1 (`weaver-hollow-roots`), D2 and B4 (`weaver-hollow-boughs`), C2's shutter and T2's Crown Door (`weaver-hollow-crown-*`) | the old worlds' record ids on purpose: an old save never has a prize twice |
| `build_weaver_hollow_rooms.gd`, `build_crystal_mine_rooms.gd`, `film_crystal_mine_rooms.gd`, `film_colossus_arena.gd`, `scripts/godot/film-colossus.sh` | the same record ids; the M15 world id as a prefix |
| `room_fight.gd`, `run_state.gd`, `crystal_mine.gd`, `mine_cart.gd`, `ore_lift.gd`, `colossus_arena.gd`, `crystal_colossus.gd`, `matron.gd`, `door.gd`, `heap_hatch.gd`, `build_colossus_lab.gd` | comments: changed to say the old worlds are retired |
| `dungeon.gd`, `room_mask.gd`, `room_mask.gdshader` | changed: the doorway art's call and frames gone |
| tests | below |
| `docs/` | changed (below); what still names the old files: the archive, `docs/handover/` and `docs/reviews/` (history), the 2026-10 design docs (decisions of their day; the two first designs carry a status line), `GAME_ROADMAP.md`'s dated entries (each now says what happened on 2026-11-25), and DUNGEONS.md / DUNGEON_ROOMS.md / matron.md where they say what was retired |
| open world, dev scenes, `prop_palettes.json`, tilesets, export presets, `.claude/launch.json`, `package.json` | no hit: no door, landing, marker, `?map=` example or palette entry names a removed world |

`tools/check_crossings.gd`: no line names a removed world. The Hollow has none left (the old T1 door's one-way line went with its world); the Mine's only line is M1's way out to G4's `camp-mine-mouth`, one way by design (G4's way in is a world exit). The others (Sunscar's five broken cellar doors, the bolt-hole, Tom's raft, the Sally Port's ladder, E4/E5's openings drawn apart) are not these dungeons'.


**Tests** (rewritten, not run: the owner decides when the suite runs; every file touched compiles
with `--check-only`). They stage what a suite cannot press (private timers, a knock target's
`strike()` for a thrown pot, a boss's health) as the film tools do; their positions and timings come
from the walks and films, inferred, not proven:

- `test_weaver_hollow.gd` (24): rewritten for the 23 rooms. Deleted, their subject gone: the gaps
  between camera rooms inside a floor world, the hub's hatch opened from below. Added: the forecourt's
  gate held until blown and out again, T4's floor onto R1's ledge, R3's ram and the Guard's stair, key 1
  and the big key, the Hoard's shutter for a Warden beaten elsewhere (`room_fight.gd`), C3's hole
  (refused while sealed), the prizes keeping the old floors' records, an old save in the retired
  Boughs waking in T1. The rest (doors pairing, keys, map and compass, B2's and B7's bridges, the
  winch, the Crown's shutter, the Warden and Pearl 2, the Loft, the cracks, the Nursery, the Mimic,
  the seals, the Hoard's stair, C1) rewritten in the rooms.
- `test_matron.gd` (17): the nest tests untouched; the seven Hollow tests now play the ram fight in C2
  (`_mount_crown`): cocooned over a ram's lane with every hit clinking, a blast under her low cocoon,
  three rounds with a ram flinging her and round 3 her last hit, the Silk slime wading her rings and
  round 3's webbed floor, never back, the full heart once, the thread only with Silk; added: her lane's
  ram knocking the cocoon down.
- `test_crystal_mine.gd` (19): rewritten for the 15 rooms. Deleted: the Dark Maze's candles and the
  braziers' burn (the darkness work's, `test_dark_room_candles.gd`), and the first fight's four tests
  (the weak spot, the stomp's brazier, the claws' stun, the Spear on his claws: placed nowhere).
  Added: keys 2 and 1 into the Dark Maze, a cart bursting a hot plate and his kick, a cart clanging off
  a cold plate, bare crystal and his core, an old save in the retired Mine waking in M1. The rest
  (rooms and doors, the travel cart, the lift, the lens and bridge, the veils, the timbers, the Feral
  climbs, the Den and Pearl 3, the boss door, his fall and the climb out) rewritten in the rooms.
- `test_mine_camp.gd`: its two Mine tests enter M1 (`crystal-mine-m1-mine-mouth`, the record
  `crystal-mine` for the seal); the rest unchanged.
- `test_dungeon_rooms.gd`: the Hollow floors' test became every room world of both rebuilt dungeons
  reading its dungeon and record id, and no retired world left in `scene_index.json`.
- `test_dungeon_seal.gd`: one line, a room world's dungeon id (`weaver-hollow-c2-crown`).
- The climb is a toggle (2026-11-24): `test_skins.gd` (its Feral test renamed
  `test_the_feral_skin_clings_on_a_press_and_lets_go_on_the_next`, and the vines test) and
  `test_balcony.gd` tap interact to cling and again to let go (they had released it to let go).
- The Goo Bomb without a cast: no test outside the three rewritten waits out a cast (checked).
- The room-fight reward for a boss beaten elsewhere: `test_lair_rooms.gd` needs no change (its one
  boss fight, R12's, has no reward; its shutters open either way); the Hollow's test covers it.
- Weak spots: the Mine's plate-fight burst reads the brazier's ring from `candle.gd`
  (`light_radius_px`), which the darkness work is changing; the Matron tests set her private fields.
- Possible game issue the Mine's test writer saw, not checked: M10's veil (`Objects/M10-veil`) lies on
  the room's last floor row, about 38 units north of the south doorway's mouth, with M11's arrival
  right at its foot; a slime from M11 may land at it or walk round its ends. M11's veil sits over its
  doorway's mouth.


**Docs:** DUNGEONS.md's two dungeon sections now describe the rebuilt dungeons ("The Crystal Mine
(built)" and "The Weaver Hollow (built)" keep their headings, which 21 links and 14 code comments
use; the wings and the Hollow's floors under them); the old worlds' text (their rooms, main paths,
doors between floors, the Colossus's first fight, their dev notes and limits) moved to
[docs/archive/2026-11-25-old-hollow-and-mine.md](../archive/2026-11-25-old-hollow-and-mine.md). Also
DUNGEON_ROOMS.md (one world per room for all three; the shell, the splitter and the doorway pieces as
history), AGENTS.md (the two walk lines), CONVENTIONS.md (dev powers), INTERIOR_WALLS.md, SKINS.md,
DARKNESS.md (the one-scene arena's line and the retired worlds' row in the dark rooms' table),
BESTIARY.md (the Shardback's slam), TOOLING.md, specs/matron.md (8.4, 8.8, section 9's title, 9.4),
specs/audio.md, specs/crafting.md, story/03-world.md and 04-characters.md (the Hollow's rebuild
noted), GAME_ROADMAP.md (three entries), the two first dungeon designs (a status line) and the plan's
step table. Every link into DUNGEONS.md and the archive resolves (checked).

**Proof without the suite:** `film_weaver_hollow_rooms.gd --film=walk`: PASS, 124 checks, none
failed, no error in its log (forecourt, the gate blown, the whole way to her fall, C3's drop, in and
out by the gate; `output/dungeon-rework/hollow/walk/strip.png`, `walk.json`). `film_crystal_mine_rooms.gd
--film=walk`: PASS, 158 checks, none failed (its two warnings: M15's two void dips' hazard settings
against their painted levels, carried over from the lab; `output/dungeon-rework/mine/walk/`).
`--film=old-save` (a save standing in the deleted `crystal-mine`, loaded through `main.load_run`):
PASS, 18 checks, it wakes in M1 with its records. A save standing in the deleted
`weaver-hollow-boughs` (written to `user://tool-saves/switch-probe`, deleted after) wakes in T1 42 px
from its entrance, on walkable floor, sealed, its key kept, T1 recorded as the entrance. The step
pictures are deleted (strips and `walk.json` kept). Every changed script and test compiles
(`--check-only`).

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
which then load into the new T1: take the Hollow's lines of `RETIRED_WORLDS` (the constant was
`RETIRED_HOLLOW_WORLDS` until the Mine's switch-over joined it into one table) out too if that matters). A full undo is
the files in the table above, `git diff` against `850c98eb` (the step 3 files are uncommitted, so
`git checkout` would take other work with them: undo by hand).

**Left for step 5:** retire today's four worlds (`weaver-hollow-trunk`, `-roots`, `-boughs`,
`-crown`, their room scenes in `rooms/weaver-hollow-{trunk,roots,boughs,crown}/`, their four
`scene_index.json` lines, their elevation caches), the copy `weaver-hollow-matron-old.tscn`, today's
four names in `area_titles.gd`, the tools only they use (`build_weaver_hollow.gd`,
`weaver_hollow/hollow_*.gd`, `film_weaver_hollow.gd`, `render_weaver_hollow.gd`, their lines in
`lib/dungeon_room_splitter.gd` and `render_dungeon_room_views.gd`), and the tests below. Keep
the Hollow's lines of `RETIRED_WORLDS` (old saves still name them).

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

**Step 4's switch-over: the Crystal Mine (2026-11-25).** The reviewer passed wing 4 and the owner had
said yes in advance ("make the switch when ready i will test and fix after"): the game enters the
rebuilt Mine. Nothing committed; no tests run.

| File | What and why |
|---|---|
| `godot/game/scenes/worlds/chunks/crystal-caverns-g4.tscn` | one link line, by hand: `Spiral/exit-to-crystal-mine`'s `target_area_id` `crystal-mine-m1-mine-mouth` (was `crystal-mine`); `target_door_id` stays `mine-entrance` (M1's way-out door has today's id). No joined area copy under `game/dev/area_edit/areas/` holds G4 (only `area-e4-f5.tscn` exists) |
| `godot/tools/build_caverns_spiral.gd` | the same target, so a rebuild of the Spiral keeps it |
| `godot/game/autoload/run_state.gd` | `RETIRED_HOLLOW_WORLDS`, `HOLLOW_ENTRANCE_WORLD` and `HOLLOW_DUNGEON_ID` became **one table**, `RETIRED_WORLDS` (retired world -> the rebuilt dungeon's entrance world): the Hollow's four floors -> `weaver-hollow-t1-root-door`, `crystal-mine` -> `crystal-mine-m1-mine-mouth`; `moved_world` reads it; `install` forgets any dungeon record's entrance that names a retired world (it was the Hollow's record only). One copy of the logic |
| `godot/game/scenes/objects/dungeon/crystal-mine-dungeon.tscn` | `dev_pearl_id` `crystal-colossus`, `dev_pearl_guard` `crystal-mine-shardback`, `dev_pearl_skin` `feral`: `?sealed` (the second half at once) works in every room, as `?map=crystal-mine&sealed` did in today's world |
| `godot/game/data/world-map.json` | the Mine marker's notes only (rebuilt, entered since the switch-over); its `map` and the Caverns' `interiors` already name `crystal-mine`, the record id |
| `godot/tools/film_crystal_mine_rooms.gd` | the walk goes in through G4's real door (the gate holds, the Lantern lights its brazier, up through the door) and, after his fall, from the Lookout round to the camp and in and out by the mouth; `--film=old-save` (below) |
| docs | DUNGEONS.md ("The switch-over (the Mine)", the lines that said the game still plays today's Mine, the Dev section's `?sealed`, G4's way in, the Hollow's `RETIRED_WORLDS`), DUNGEON_ROOMS.md, SKINS.md, CONVENTIONS.md (dev powers), specs/audio.md (the music line), story/03-world.md (the Mine's row), story/04-characters.md (his row: the plate fight is the game's now), AGENTS.md (the walk line, `?sealed`) |

**His fight:** nothing to copy. Today's Mine and M15 share no camp or encounter scene; each has its own
`ColossusArena` node (today's `plate_fight` off, M15's on, with today's ids on the node itself), so
today's world keeps its old fight until step 5.

**Proof.** The walk (`--film=walk`): PASS, 158 checks, none failed, run after the last scene edit:
from the camp in G4 the gate holds, the Lantern lights its brazier, up through G4's door into M1 (no
staged entry), the whole Mine as before, his fall, the climb out to the Lookout, round to the camp (the
open world, put there the quick way), in through G4's door again (the mouth's seal sunk) and out by
the mouth to the camp; its strip and `walk.json` in `output/dungeon-rework/mine/walk/`, the step
pictures deleted. `--film=old-save`: PASS, 18 checks: an old save written to the tool runs' save
folder (`user://tool-saves`, never the owner's) standing in today's world (`crystal-mine`, sealed by
Pearl 3, the Shardback beaten, the Feral skin, one small key, one of the Foreman's Gate's locks open,
the lift worked, the travel cart at the mouth, the record's entrance today's mouth), loaded through
`main.load_run` in a game window: it wakes in M1 28 px from its entrance, the mine sealed and the
mouth's seal shut, its key kept, the record's entrance now M1's, Feral kept; the Foreman's Gate shows
its lock open, the lift is offered on M4's gallery, the Den's rim shutter is sunk (`room_fight.gd`'s
reward for a boss beaten elsewhere), no Shardback, Pearl 3 not risen again, the travel cart not at the
Chasm (at the mouth, as saved). Its `old-save.json` in `output/dungeon-rework/mine/old-save/`; the
save file deleted afterwards.
`tools/check_crossings.gd`: the Mine's only line is M1's way out, `mine-entrance` -> G4
`camp-mine-mouth`, listed one way: the camp's marker is an arrival point, and G4's way in is the world
exit `exit-to-crystal-mine` behind the gate (an area, not a door end), which leads to M1's
`mine-entrance`. As meant; it has stood since wing 1 built M1. Nothing lists today's `crystal-mine`.
The other lines (Sunscar's five broken cellar doors, the bolt-hole, Tom's raft, E4/E5's openings drawn
apart, the Sally Port's ladder, today's old Hollow T1 door) are not the Mine's.

**The grep** (`crystal-mine` outside `rooms/crystal-mine-rooms/` and the elevation caches):

| Where | Verdict |
|---|---|
| `chunks/crystal-caverns-g4.tscn`: `exit-to-crystal-mine` | **changed** (above); `crystal-mine-gate` (the gate's and its brazier's `gate_id`) is G4's own id, right as it is |
| `tools/build_caverns_spiral.gd` | **changed** (the exit's target); the gate ids as above |
| `scene_index.json`: `world.crystal-mine` | right as it is: today's world stays until step 5 (a dev launch opens it; nothing in the game leads there) |
| `worlds/crystal-mine.tscn`, `rooms/crystal-mine/M*.tscn` | today's world and its dead copies: kept until step 5 |
| `game-constants.json`: `dungeon.devPowers.crystal-mine` | right as it is: one line for every world of the dungeon (`world_dungeon_id`), the rooms' and today's |
| `world-map.json`: the Caverns' `interiors`, the dungeon marker's `map` | right as it is: they name the record id, which is also today's world's id (as `weaver-hollow`, `fatty-lair`); notes changed |
| `game/shell/area_titles.gd` | no hit: the banner of a room world is its record id's, title-cased "Crystal Mine", the same as today's world's; an old save's slot label (map id `crystal-mine`) reads the same |
| `game/dungeon/doorway_art.gd` (`map_id == "crystal-mine"`) | belongs to today's world (doorway art for its painted cliffs); the rooms have interior walls and are skipped |
| `crystal-mine-dungeon.tscn` | the rooms' Dungeon (record `crystal-mine`); `dev_pearl_*` added |
| `colossus_arena.gd` (`camp_id` default `crystal-mine-colossus`), `mine_cart.gd` (`line_id` `crystal-mine-cart`), `ore_lift.gd`, `crystal_mine.gd` (comments, ids) | ids shared by today's world and the rooms (one record): right as they are |
| `tools/build_crystal_mine.gd`, `tools/lib/dungeon_room_splitter.gd`, `tools/render_dungeon_room_views.gd` | today's world's tools: go at step 5 |
| `tools/build_crystal_mine_rooms.gd`, `film_crystal_mine_rooms.gd`, `film_colossus_arena.gd` | the rooms' tools |
| `tests/test_crystal_mine.gd`, `tests/test_mine_camp.gd` | below |
| the open world otherwise | nothing else leads into the Mine: the smith's cart ends in G4's yard, H4's `lookout-from-mine` is the climb out's landing; no hole, landing, marker or respawn point names it; no quest, story step or dev run names the world (`mine_camp.gd` reads flags only) |

**Saves** (an old save half-played in today's Mine, on paper; the starred lines were loaded for real):

| What | Kept by | Carries over? |
|---|---|---|
| Where it stands* | location | today's Mine loads into M1 at its entrance (`moved_world`), inside, as a dungeon's resume save; anywhere else as before |
| The record's entrance* | the record `crystal-mine` | forgotten when it names today's world; M1 records itself |
| Small keys held* | the record (the same id) | yes |
| The Foreman's Gate's locks*, the boss door's | the record's keyholes (`crystal-mine:foremans-gate`, `:colossus-door`: today's door ids) | yes |
| Key 1, key 2 | key 1's floor pickup (`tally-k1`), key 2's chest (`crystal-mine-M7-K2-chest`): today's records | yes: never had twice |
| The big key, the map | the record's items; their chests' ids are today's | yes; not had twice |
| Chests | today's chest ids on the rooms' chests (S1, S4, S5, the map's, the journal page's, the big key's) | yes; S3 is a new chest shown only while today's silk parcel was never freed |
| Pearl 3, the Feral skin* | the Pearl's flag (`pearl.crystal-colossus`, the same `pearl-three.tscn`), the skins | yes: it does not rise again |
| The Shardback's fall* | `defeated_boss_ids` | yes: no fight; the Den's rim shutter sunk by `room_fight.gd`'s reward for a boss beaten elsewhere (without it the way to M14 would stay shut: unfinishable) |
| The seal* | the record | yes: sealed until he falls |
| The lift* | `ore-lift:great-shaft-lift` under the record (today's lift id, today's world id = the record) | yes |
| The travel cart* | `mine-cart:crystal-mine-cart` under the record, stations `mouth` and `chasm` (today's) | yes |
| The maze's gate, the candles' group | `dark-maze-exit`, `dark-maze` (today's ids) | yes |
| The rotten timbers, the survey wall | today's flags | yes |
| His defeat, his full heart, the end card | `defeated_boss_ids`, the record, `full-heart.crystal-colossus`, `chapter-3-complete` | yes: no fight, the seals sunk, M15 lit with the nook open, no heart twice, no second card |
| The lit rooms (M2, M6) | new flags (`crystal-mine.lamp-tunnel-lit`, `.bat-gallery-lit`) | no: lit again with the Lantern (it has it) |
| The Chasm's lens and bridge | the lens's own key | maybe not: struck again with the Bow (it has it) |
| The runaway cart and the rail gate (M7, M1), the Den's cart | new pieces | played fresh |
| Today's M4 spire lens and plank, M7's crank, the Den's second shutter | today's only | gone with the rework (S1's chest keeps its record) |
| Rooms on the map | the record's visited rooms | no (seen again) |

Nothing found that would make the dungeon unfinishable or give a prize twice beyond what the table
says; nothing fixed for it in this round (the Den's reward was `room_fight.gd`'s already).

**Turning it back, in one place:** G4's `exit-to-crystal-mine` `target_area_id` back to `crystal-mine`
(one line in `crystal-caverns-g4.tscn`; and in `build_caverns_spiral.gd` if the Spiral is rebuilt):
the game enters today's Mine again, with its own old fight. The rest can stay: the rooms are unreached
again, and `RETIRED_WORLDS`' `crystal-mine` line only moves saves standing in today's Mine (take that
line out too if they should stay there). A full undo is the files in the table above (uncommitted:
undo by hand, not with `git checkout`).

**Left for step 5 (the Mine):** retire today's world `crystal-mine` (`worlds/crystal-mine.tscn`, its
`scene_index.json` line, its elevation cache `crystal-mine.res`, its 14 copies in `rooms/crystal-mine/`),
its tools (`build_crystal_mine.gd`, its line in `lib/dungeon_room_splitter.gd` and
`render_dungeon_room_views.gd`), `doorway_art.gd`'s `crystal-mine` case, the Dev section's
`?map=crystal-mine&sealed`, and the tests below. Keep `RETIRED_WORLDS`' line (old saves still name it).
The nook's door art in M15 and the dark rooms' brightening are the owner's (open).

**Tests that enter or name today's Mine** (not edited, not run):
- **fails now:** `tests/test_mine_camp.gd`'s `test_the_open_gate_leads_into_the_mine_and_its_way_out_comes_back`
  (it walks through G4's opened gate and waits to be in `crystal-mine`; the door leads to M1 now).
- **pass while today's world exists, go at step 5:** `tests/test_crystal_mine.gd` (all 20: it builds
  `crystal-mine` directly, its rooms, carts, lift, lens, veil, maze, Den, Colossus and climb out),
  `tests/test_mine_camp.gd`'s `test_while_sealed_the_mines_mouth_keeps_the_slime_in_until_the_colossus_falls`
  (enters `crystal-mine` directly).
- **unaffected:** the rest of `test_mine_camp.gd` (the yard, the smith, the cart, the gate: G4 and the
  smith's cave only).

**Candles light the room (2026-11-25).** The owner on the walk's pictures: "candles dont light up
the room ... definitly a lot more that what is iluminate today"; he chose both remedies.

| | Before | After |
|---|---|---|
| A candle's or sconce's light (`abilities.lantern.candle.lightRadiusPx`) | 110 units | 300 |
| A brazier's light | 120 (`light_radius` in `brazier.tscn`) | 380 (`candle.brazierLightRadiusPx`; the brazier scene's `light_kind` "brazier") |
| The Colossus's braziers (his brittle rings) | 150 (their own `light_radius`) | 150, unchanged |
| Which candles lift a room's dark | only the room's listed `candles` | every candle, sconce or brazier inside its rectangle, and the listed ones |
| How much each lifts | `darkness.candleShare` 0.25 each, straight (one of three lamps: 0.75 black) | (lit / all) ^ `darkness.candleShareCurve` 0.5: one of three 58 %, one of four 50 %, two of four 71 % |
| All burning | lit while they burn (listed rooms only) | the same, for every room with candles; lit for good only where it already was |
| A room with no candle | never lifts | never lifts (M5, D1, the burrow, pens 23, 24, 28) |

The numbers were tuned by pictures (240 and a 0.6 curve first: one lamp still read dim).
`lifts_by_candles` (new, on by default) is off in M15 and the Colossus lab (his rings) and in Bestiary
pen 34 (its brazier is the shelter in full dark that the pen shows). Every dark room in the game and
what changes for it: [DARKNESS.md, "A share of the room per candle"](../godot/DARKNESS.md#a-share-of-the-room-per-candle-2026-11-25)
(`tools/list_dark_rooms.gd` lists them). **M8:** each candle now lifts its share of the maze's dark
while it burns (half with the first), so the maze reads once a candle burns; the candle run is
unchanged (the walk lit the four in 49.8 s of their 90, by the same route) and only gets easier; the
gate, the Gloomling on the north-west candle and the burn times stay. **The light-shy enemies** read the
bigger circles: a Gloomling flees from farther, a Glint Bat wakes from farther and sleeps in a lit room
(M11's while its brazier burns), the Shardback's shell is brittle anywhere in a brazier's 380 (the Den's
rails under either brazier); no fight broke in the walk, no enemy number changed.

| File | What and why |
|---|---|
| `godot/game/world/darkness/dark_room.gd` | `room_candles` (listed plus inside), `lift_share` (the curve), `lifts_by_candles`; lit while all burn, lit for good only as before |
| `godot/game/world/fire/candle.gd` | `light_kind` and `light_radius_px` (its own radius, else its kind's from the data) |
| `godot/game/scenes/objects/brazier.tscn` | `light_kind` "brazier" instead of a fixed 120 |
| `godot/game/scripts/crystal_colossus.gd` | `in_fire_ring` reads `light_radius_px` (his arena's 150 as before) |
| `godot/game/data/game-constants.json` | `candle.lightRadiusPx` 300, `candle.brazierLightRadiusPx` 380, `darkness.candleShareCurve` 0.5 (replaces `candleShare`) |
| `godot/game/scenes/worlds/rooms/crystal-mine-rooms/m15-colossus-arena.tscn`, `godot/game/dev/bosses/colossus-lab.tscn`, `tools/build_colossus_lab.gd` | `lifts_by_candles` off on the hall's dark room |
| `godot/game/dev/corners/bestiary_corner.tscn` | `lifts_by_candles` off on pen 34's dark room (one line) |
| `godot/tools/list_dark_rooms.gd` (new) | lists a scene's dark rooms with their candles and lights |
| `godot/tools/film_crystal_mine_rooms.gd` | `--film=candles` (a room's candles lit one by one, a picture at each count; `--before` for the old light) |
| `godot/tests/test_dark_room_candles.gd` (new) | five tests of the new rule (the share and its curve, all lit, no candle, a listed candle outside, `lifts_by_candles` off, the radii by kind); compiled, not run. No other test covers darkness or candles but `test_crystal_mine.gd`, which builds today's retired Mine (the hollow-floors session's) |
| docs | DARKNESS.md (the rule, the numbers, every dark room), DUNGEONS.md (the Mine's lessons of light, M8, M11, M13) |

**Pictures, before and after, as the game shows them** (`output/dungeon-rework/mine/candles/`): the Lamp
Tunnel with none, one, two and three lamps lit (`m2-lamp-tunnel-before-after.png`), the Dark Maze with
none, one, two and four candles (`m8-dark-maze-before-after.png`), the Hollow's D2 with none, one and
three (`hollow-d2-dark-bough-before-after.png`). The before row is the committed `dark_room.gd`,
`candle.gd` and `brazier.tscn` put back for that run only (and restored), with the old 110 set in
memory.

**The Mine's missing art (the owner: "spend in art if need dont worry about credits").**
- **M15's way in, done without credits:** the nook ends at a mine tunnel's mouth in the south rock, the
  carts' tunnels' own timber doorway (`mine-gate-leaves.webp`, as `ram_cart.gd` lays a south wall's
  mouth), the room door in it: a doorway, not a gap. The cut through row 23 is gone (the lab's nook as
  it was); the slime comes out 96 units inside the nook. Pictured in `rooms/game/look-m15-colossus-arena-bright.png`.
- **Not made: the generation was refused** by the builder session's own permission check, as the
  painted shaft's first try was, so no credit is spent; the owner's yes in that session lets it go on.
  What waits, each one GPT 2.5 picture of 40 credits (`simulate_cost` checked), references uploaded
  (crops of the game's own mine props and of the painted shaft):
  1. **A sheet of eight mine props** (2:1): a timber pit-prop frame against a wall, a ladder's foot
     with its upper rungs broken off, a lift gantry (A-frame, pulley, two ropes), a stack of spare props,
     a heap of fallen slate with crystal shards, a lantern post, a tipped ore cart, a pickaxe and shovel
     by a crate: M14's timbering, ladder foot and lift frame under the painted shaft, and dressing for
     the rooms whose floors read bare (M1, M5, M10, M11, M14).
  2. **The Chasm painted** (9:16): a natural rock chasm's inside, crystal veins, ledges going down
     into the dark, for M9's `PitDepth` (as M4's shaft).
  3. **A pit painted** (1:1): a natural pit, for M8's void and, cropped, M2's two voids.
  Looked at with the owner's eye, these are what reads makeshift today: the three code-drawn voids
  (black boxes with dust and stars beside M4's painted shaft), M14 without the shaft's timbers, and the
  bare floors. Not the crystal door leaves, not the Shardback.

**Proof.** The walk from G4's camp through the whole Mine and out: PASS, 158 checks, run after the last
scene edit (M15's tunnel mouth), with the new light (the candle run 49.8 s of its 90, the same route);
an earlier run with the light alone passed the same. Its strip and `walk.json` in
`output/dungeon-rework/mine/walk/`, the step pictures deleted. Every changed script and the new test
compile (`--check-only`); no test run.

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
   **Step 4 started on 2026-11-25:** a builder session cut the Mine into four wings and wrote the list
   of links for all of it ("Step 4: the Mine" above), then built **wing 1, the Mouth and the High
   Line** (M1, M2, M4, M6, M7: the cart's teach, key 2 by the High Line) beside today's Mine, which
   the game still plays. Its walk passes 41 checks; the cart's teach is filmed. **The reviewer's read
   of wing 1 (2026-11-25): the code accepted, five polish points** (the voids' depth, the bare boards,
   S3's look, the burst gate's posts, doors into unbuilt rooms), done; then **wing 2, the Lantern's
   half** (M5, M3, M8, M9: key 1, the map, the Dark Maze and its wall tops with S1's chest, the Chasm,
   the travel cart between worlds) built the same day: the walk through both wings passes 82 checks,
   the cart's ride is filmed. It stops for the reviewer before wing 3 (the Den, the rift, the Prism
   Gallery, the Fort Hall: Pearl 3, the Feral half). Nothing committed; no tests run.
   **The reviewer's read of wing 2 (2026-11-25): accepted, four points** (M8 a real maze, the
   candles' time worked out and walked, key 1's record, the crystal crack's tone), done; then **wing 3,
   the Den and the Feral half** (M13, M11, M10, M12: the Shardback's cart fight, Pearl 3, the rift, the
   veil, the Prism Gallery, the Fort Hall's big key) built the same day: the walk through wings 1 to 3
   passes 126 checks, the Shardback's blow is filmed. It stops for the reviewer before wing 4 (the
   Shaft Floor, the Colossus's arena); the Mine's switch-over follows wing 4's review.
   **The reviewer's read of wing 3 (2026-11-25): accepted**; then **wing 4, the Shaft and the
   Colossus** (M14, M15: the shaft's floor, the ore lift between worlds, the boss door, the Colossus
   lab's world carried into the room as it is, the climb out to the Lookout) built the same day: the
   walk from the camp in G4 through all four wings to his fall and out passes 154 checks; his fight is
   filmed in M15 (burst, clang, wall, core: PASS). It stops for the reviewer's read; the switch-over
   (the owner's yes given) is its own piece after it.
   **The reviewer's read of wing 4 (2026-11-25): accepted** (the nook's missing door art goes on the
   owner's list); **the Mine's switch-over** made the same day at the owner's word given in advance:
   G4's door enters M1, old saves standing in today's Mine wake in M1, one table of retired worlds
   (above, "Step 4's switch-over"). The walk through G4's real door passes 158 checks; an old save
   loads for real (PASS). It stops for the reviewer's read. Step 5 (retiring today's worlds) after it.
   **The reviewer's read of wing 1 (2026-11-25): the code accepted, a polish round before the owner
   sees the rooms.** Read line by line: `ram_cart.gd`'s `rolls_out` and `arrives` (off by default; a
   spent cart's target now hangs slack when its room is built again, for every cart that does not
   return). All 14 doors inside the wing pair both ways; five more lead out (G4's camp) or into rooms
   not built yet. The two chests carry today's record ids, no heart quarter; the walk's 41 checks have
   no fail and ran after the last scene edit; the three scripts compile; no frame pictures left. Sent
   back: the voids are flat black boxes (M4's shaft must read as deep); plain brown boards stand at
   the walls across the floor trim in four rooms; a pale strip crosses the trim in M6; the burst rail
   gate's posts catch the slime; what a door into an unbuilt room does. **Wing 2 goes to the same
   session after those fixes**, to stop again for the reviewer.
   **The reviewer's read of the fix round and wing 2 (2026-11-25): accepted in code.** Read in
   full: `pit_depth.gd` (presentation only), `rail_gate.gd`'s `posts_solid_when_smashed`,
   `mine_cart.gd`'s ride between worlds (the cart's place under the dungeon's record id). 26 of the
   nine rooms' 31 doors pair both ways, the other five are arrival points, the way out and M9's
   doorway to the Den (not built); the chests carry today's record ids, no heart quarter; the walk's
   82 checks have no fail and ran after the last scene edit; the six scripts compile; no frame
   pictures left. Sent back before wing 3: M8 is not a maze (more partitions as low dividers or a
   bigger room, dead ends worth a look); the four candles' time limit worked out from the walked
   path, and walked by the tool; key 1's record id against today's; the crystal cracked wall reads
   as a black scribble. **Wing 3 (M13, M11, M10, M12) goes to the same session after those**, to
   stop again for the reviewer.
   **The reviewer's read of wing 3 and its fixes (2026-11-25): accepted.** Read line by line:
   `shardback.gd`'s cart hook, stagger and slam chunks, his ten numbers in `enemy-types.json`. The
   walk's 126 checks have no fail; M8 has its partitions and a walked candle run; the painted shaft
   (40 credits, the owner's yes) reads well. **Wing 4 (M14, M15, the lift, the way out) went to the
   same session**, to stop for the reviewer; **the Mine's switch-over follows that read without
   asking the owner again** (2026-11-25: "make the switch when ready i will test and fix after").
   **The reviewer's read of wing 4 (2026-11-25): accepted.** `ore_lift.gd`'s ride between worlds
   read; M15 against the lab (81 of its 86 nodes at the same position, none moved, the five missing
   the lab's own shell); no fight value behind an `[editable path]`; 38 of the 15 rooms' 45 doors pair
   both ways, the rest arrivals, locks and the way out; the walk's 154 checks ran after the last scene
   edit; the four arena films' notes; every script compiles. For the owner's eye: M15's way in is a
   gap in the rock with no door art; M14 shows none of the painted shaft's timbers. **The Mine's
   switch-over went to the same session**, to stop for the reviewer.
   **The reviewer's read of the Mine's switch-over (2026-11-25): accepted.** Read line by line:
   `run_state.gd`'s `RETIRED_WORLDS` table (the Hollow's four floors and `crystal-mine`, one copy of
   the logic) and G4's diff (the mine door's one target line). The walk goes in through G4's real
   door and passes 158 checks, run after the last edit; the old save written to the tools' own
   folder loads into M1 and passes its 18 checks (key, lock, lift, the Den's shutter, Pearl 3, the
   cart); the changed scripts compile; no frame pictures left. Today's `crystal-mine` world stays on
   disk and opens only by `?map=crystal-mine`. `test_mine_camp.gd`'s gate test fails until step 5.
   **Step 4 is done and committed** (`09d5ebae`, with the switch-over and the Warden's frames).
   **The owner's word of 2026-11-25 on what was open:** candles "follow your recommendation" (a
   larger light per candle and a share of the room for every candle standing in it); "step 5 this
   is the way to go so get rid of the old"; "spend in art if need dont worry about credits"; then
   commit. Three sessions work at once, each on its own files, each read by the reviewer before the
   commit: **mine-wings** (the candles in `dark_room.gd` and the data, every dark room listed, the
   pictures side by side; then the Mine's missing art: M14's timbering, M15's doorway), **boss-art**
   (the Shardback's shatter and stagger frames, wired in `shardback.gd`), **hollow-floors** (step 5:
   today's Hollow and Mine worlds, their builders and dead fight code removed, the tests rewritten
   for the rebuilt dungeons, the docs cut to the game as it is; `RETIRED_WORLDS` and the labs stay).
   The suite is still not run: the owner decides when.
   **The reviewer's read of the candles (2026-11-25): accepted.** `dark_room.gd` (`room_candles`,
   `lift_share`, `lifts_by_candles`), `candle.gd` (`light_kind`, `light_radius_px`) and the numbers
   read (candle 300, brazier 380, `candleShareCurve` 0.5; the Colossus's rings stay 150 and his
   rooms keep `lifts_by_candles` off); the side-by-side pictures show the first lamp lifting the
   whole room. To tidy: the header comments of both scripts still quote the trial numbers (240, 320,
   0.6). For the owner's eye: one candle now makes the Dark Maze readable, so its lesson softens.
   **The Shardback's cart frames (boss-art, 80 credits): accepted.** Struck and cracking hot, the
   shell bursting, on his side among the pieces; a rocked-back frame for the cold clang. Weak: the
   clang's pose is close to his slam's tell, and he flips to face the cart.
   **The Mine's paid art:** the Mine's builder session cannot call the image tool (refused there), so
   the three pictures it specified (a sheet of eight mine props, the Chasm painted, a pit painted)
   are generated by the boss-art session and placed by the Mine's builder afterwards.
   **The Brood Warden's knocked frames (2026-11-25, the boss-art session, 80 credits): accepted.**
   Eight new frames (flung, on his back kicking, getting up) after his walk on a 24-frame sheet,
   wired into `PHASE_KNOCKED` (`knockedKickFrameMs`, `knockedRiseMs`); the squash is gone; the
   warden-ram film passes. Weak: the flung frames barely show under the ram hit's flash.
   **The owner's calls of 2026-11-25:** credits for the Brood Warden's frames on his back (the boss-art
   session: frames, his sheet, `PHASE_KNOCKED`, the warden-ram film) and for the painted shaft; the
   crystal walls keep the cave rock's door leaves; the Hollow's floor look is fine; the forecourt's
   Cocoon Mimics and Egg Sacs stay (DUNGEONS.md says so now); no file over 10 MB into git without
   his yes.
   **Open with the owner: the dark rooms' candles.** He watched the Mine's walk and said lit candles
   do not light the room. Found: a candle's light is a circle of 110 units (about 3 % of a one-screen
   room; the Lantern's is 160); a `DarkRoom` lifts `darkness.candleShare` (0.25) of its dark for each
   burning candle **listed in its `candles`**, and M8 and M5 list none, so their dark never lifts;
   one of three lamps lit leaves the room at 75 % black, which still reads as dark. Proposed, waiting
   for his word: a larger candle light, and each candle lifting its share of the room (one over the
   room's candle count) for every candle standing in the room, listed or not.
   **Also on 2026-11-25: `asset/Originals/` left git.** Its credentials blocks were stripped (1328
   sources, 1.15 GB, `scripts/art/strip-credentials.py`), then the folder was taken out of every
   commit and force-pushed at the owner's word (4.5 GB of the repository's 6.3 GB): it is on his disk
   only, git-ignored but for its text files. 483 of 491 commit ids changed; every id written in this
   handover before that day is an old one
   ([the map](../archive/2026-11-25-history-rewrite.md): `850c98eb` is `65a7954b`, `d620e774` is
   `6de12ff5`). The old history is whole in `D:/projects/Slime-isa-history-backup-2026-11-25.git`.
   **The Brood Warden's knocked frames, built (2026-11-25, the boss-art session; 80 of the 160
   credits the owner gave, two GPT 2.5 sheets, first takes):** the stand-in squash is gone. Sources
   `brood-warden-sheet-5.png` (on his back, kicking: a loop of four) and `-6.png` (tipped onto his
   side, tumbling over, heaving up on his blades, crouched on his feet) in
   `asset/Originals/enemies/bestiary/` (stripped; on disk only), prompts in its README. Packed as
   frames 16 to 23 after his walk: `256x256-tile_24x1-brood-warden.webp` at the same scale (his 16
   frames unchanged; the packer's `STILL_BODY` keeps the loop's body on one spot,
   `FAINT_HAZE_FILES` clears sheet 6's haze); the 16x1 sheet and its `.import` deleted,
   `brood-warden.tscn` points at the new one (`hframes` 24). The new sheet has no `.import` yet: the
   editor writes it on its next scan (commit it with the sheet; `sheet_sprite.gd` reads the file
   until then). `brood_warden.gd`: the flung frames over the slide (mirrored to the log's way), the
   loop at `knockedKickFrameMs` 150, the getting-up frames over the last `knockedRiseMs` 400 (both
   new in `enemy-types.json`), and beaten while knocked he stays on his back. Proof: `warden-ram`
   PASS (5 checks); `output/dungeon-rework/hollow/warden-ram-film/` has `strip.png`, `film.gif`,
   `film-slow.gif` and the owner's sheet picture `warden-knocked-frames.png` (the stand-in's strip
   and GIF kept as `*-before-frames`; frame pictures deleted). Weakest: the flung frames barely
   show in play, as the log passes over him and the ram blow's pink hurt flash covers most of the
   tumble; the getting-up is quick (two frames in 400 ms). Reload `brood-warden.tscn` in an open
   editor before a save-all. Nothing committed; no tests run.
   **The Shardback's cart frames, built (2026-11-25, the boss-art session; 80 credits, one GPT 2.5
   sheet in two takes, take A kept):** source `shardback-sheet-5.png` (struck from behind, the shell
   cracking hot; bursting; thrown on his side among the pieces; the cold clang, rocked back on his
   hind legs; take B beside it as `-take-b`) in `asset/Originals/enemies/bestiary/` (stripped; on
   disk only), prompts in its README. Packed as frames 16 to 19 after his walk:
   `256x256-tile_20x1-shardback.webp` at his old scale (the packer's new `SCALE_FROM` takes the scale
   from his first 16 poses, so his old frames keep their size; the pose on his side, wider than the
   cell with its heap, is drawn 3 % smaller); the 16x1 sheet and its `.import` deleted,
   `shardback.tscn` points at the new one (`hframes` 20; no `.import` yet, the editor writes it on its
   next scan: commit it with the sheet). `shardback.gd`: brittle, the cart's blow turns him away from
   the cart and his corpse plays struck (`cartShatterStruckMs` 300, its first 120 under the hurt
   flash), bursting (`cartShatterBurstMs` 240, a second puff of shards) and on his side among the
   pieces until the corpse fades; beaten any other way his defeat stays frame 3. Cold, the clang
   turns him to the cart, rocked back (frame 19) for `cartClangMs` 550, then his walk frame, shaken,
   to the stagger's end (the three keys new in `enemy-types.json`). Proof: the Mine tool's
   `shardback` film run through a scratch subclass that also films the first (cold) throw, PASS;
   `output/dungeon-rework/mine/shardback-film/` has `clang-strip.png`, `clang-film.gif`,
   `shatter-strip.png`, `shatter-film.gif` (and `-slow` GIFs) and the owner's sheet picture
   `shardback-cart-frames.png`; the old film's strip and GIF kept as `*-before-frames`; frame
   pictures deleted. Weakest: the Den's cart strikes him from behind, so the clang flips him round
   to face it under the hurt flash before he rocks back (the art is a blow on his front); the clang
   pose, reared up, is close to his slam's tell (frame 1), though cold, lower and with no ground
   mark. Reload `shardback.tscn` in an open editor before a save-all. Nothing committed; no tests run.
