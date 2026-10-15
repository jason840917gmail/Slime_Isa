# Body Shapes Prototype (branch `exp/body-shapes`)

The rework of 2026-10-11 (plans: [body shapes](../design/2026-10-11-body-shapes-plan.md),
[combat feel](../design/2026-10-11-combat-feel-plan.md),
[Release 1 dungeons](../design/2026-10-11-release-1-dungeons-plan.md),
[power curve](../design/2026-10-11-world-power-curve.md)) is built here as a prototype that runs
**beside** the old weapon system. The old game is unchanged while the rework mode is off.

This page is the contract between the prototype's parts: who owns which file, what data passes
between them, the exact functions each part provides and may call, what is built and what still
stands in, and how to try each part in the playground.

The owner's decisions of 2026-10-11 override the plans where they differ: the second shape is the
**War Axe** (`shape-axe`); every shape has its hold-to-charge attack from the start; Q works as in
"Mouth" below; the suck never pulls live enemies (`suck: "none"` for everyone); **no energy back
from hits**, but enemies may drop an **energy shard** on death (`combat.energyShard`); damage
numbers are on, with a setting to hide them; abilities set up combos (the Slam's outer ring bounces
in place, a thrown pot dazes light enemies); the Ability Box lives in the bag window's top band (no
extra key); Chapter 1 enemies die within one combo (the Axe arrives in Chapter 2's dungeon, so
Chapter 1 is the Spear's).

The owner's playtest of 2026-10-12 changed it again (the full list, old and new numbers:
[combat-feel plan section 11](../design/2026-10-11-combat-feel-plan.md#11-owner-playtest-2026-10-12)):
attacks and the Roll fire on the **release** (holding never strikes first; a hold charges); the
slime walks at half speed while a charge ring fills; every chain's **last step loads** (a visible
wind-up) and each step moves its own way; the Spear is a thin shaft with an arrowhead; hits stop
enemies' attacks and walking for longer stuns (no wind-up armor on light and medium enemies); the
Axe's Spin hits **once**, all round; in the rework mode **energy no longer refills by itself**
(`character.player.rework.energyRegenPerSecond` 0: energy shards, items and a respawn bring it
back); the juice panel's number keys **play** each effect.

## Running it

- **Playground:** the rework mode is **on** by default in `game/dev/playground.tscn` (F6, or
  `?map=playground`), and stays on in the playground's rooms (worlds named `playground-<room>`:
  the sinkhole's `playground-cavern`, the Bomb corner's `playground-bomb-cave`; main.gd
  `decide_rework_mode`). `?classic` (desktop `-- --classic`) turns it off there. The test runner
  turns it off too (`main.rework_in_playground = false`), so playground tests keep the classic game.
- **Any other world:** `?shapes` (desktop `-- --shapes`) turns it on. Both options skip the title
  (`LaunchOptions.SKIP_TITLE_OPTIONS`). The rework mode never writes the recovery autosave
  (main.gd `_start_autosave`, like the playground), and the quiet grants below are lent for the
  session only: `RunState.learn_session_ability` lists them in `RunState.session_ability_ids` and
  `RunState.serialize` leaves them out of `story.learned_ability_ids`, so no save (slot 0 or one
  made by hand) carries them into a classic game. An ability the run had already learned stays as
  it was, and a real lesson of a lent one (a quest's `learn_ability`, not quiet) keeps it for good
  and plays its ceremony. The box choice (`player.loadout.ability_id`) is saved; the classic game
  never reads it.
- In the rework mode the slime learns, quietly, the three shapes (`shape-spear`, `shape-axe`,
  `shape-hammer`) and the Ability Box abilities the game has (`squash-slam`, `stretch-lash`,
  `teleport`, `lantern`, `goo-bombs`). In the playground the **shapes testbed** (`game/shapes/shapes_testbed.gd`, exports
  for every position below) uses the open grass south-west of the player spawn (1280, 1536), clear
  of the feel yard's three dummies (y 1400), the test chest, the gulp yard, the web nook and the
  liftable gallery (x 1600 on):
  - **Four training dummies**, with the reaction presets light, medium, heavy and boss, in a column
    west of the spawn: their feet at the slime's spawn feet + (-320, -60), 120 px apart top to
    bottom (x 960, y 1504 / 1624 / 1744 / 1864), each with its preset's name over it. Each is the
    training-dummy scene's parts on a CharacterBody2D root on the enemy layer
    (TrainingDummyScript `body`): holds stop it, knockbacks, launches and the break-free move slide
    it, it splats on walls, bowls the next dummy, and walks back to its post (90 px/s) once the stun
    is over. It never attacks or falls.
  - **The enemy pen**, a rectangle outlined on the ground east of the dummies (old centres x
    1080-1540, y 1664-1944, titled "Enemy pen  (F4: respawn, F5: full energy)"; the hill's wall
    south of it is there for splats): a slime spider (light) at (1170, 1754), a worm swordsman (medium) at (1310, 1854)
    and a Clod Stomper (heavy) at (1450, 1754). No tiny type exists yet, so none stands in for a
    Broodling. They are spawned as EnemyPopulation spawns (`character.<type>` by its old centre,
    `configure_navigation`, with no camp and no safe zones) and take their `enemy-types.json`
    `maxHp` when it is higher than the scene's (the swordsman 90, not level-1's 8). They fight only
    while the slime's centre is inside the pen (`configure_arena` with the pen); while it is outside,
    each one's arena is a dot at its post, so it walks back there and never shoots at the slime by
    the dummies or at the spawn. Each comes back 3 s after it dies; **F4** brings the whole pen back
    at once. They drop energy shards like any enemy.
  - **F5** fills the slime's energy to full ("Energy full" in cyan over it; `refill_energy`), since
    energy no longer refills by itself in the rework mode.
  - **The Roll's upgrade:** the testbed lends `roll-charge` for the session
    (`RunState.learn_session_ability`, never saved), so a tap of the Roll key rolls the quick roll
    and a hold the charged one (checklist 10).
- The shapes strike with their own chains and charges, drawn with the prototype's first painted art
  (2026-10-12, [Art](#art-2026-10-12) below: the slime's attack poses, the Spear's strike frames
  with its rigid spear, the War Axe's and the Hammer's strike frames with their rigid weapons and
  code neck, the jelly weapons, the Axe swoosh, the Spear glint, the goo splat, the energy
  shard and the shape icons); the rest is still
  code-drawn grey-box. In the rework mode the playground hands out no crafted weapons and mounts
  nothing in the hand (main.gd `equip_run_start`), so the bag holds only the Gulp essences and other
  items.

## Trying it in the playground (checklist)

Keyboard + mouse scheme (F2 switches schemes; keys-only in brackets).

Every attack and the Roll fire on the **release** of their key (owner, 2026-10-12): a quick tap
strikes as it is let go; holding never strikes first.

1. **Spear chain** (current shape at start; HUD Shape slot shows it once two shapes are learned):
   tap left click [A] three times in rhythm at the light dummy: jab, jab, lunging jab. Each step
   fires on the release of its tap (a press let go within 250 ms). A tap pressed during a step
   (from its first active frame) waits for the step's cancel point (240 ms); one pressed within
   150 ms after it links at once (also while the step's recovery still plays; the link is judged
   at the press, so a tap pressed in the window and let go just after it still links); a later one
   starts at step 1. A press in a step's wind-up is dropped. Walking out of steps 1-2 after their
   cancel point works; the finisher cannot be walked out of. Each step plays the slime's painted
   strike frames ([The Spear's strike frames](#the-spears-strike-frames-2026-10-12), the look the
   owner approved on 2026-10-12): the jabs the spear-jab strip (lean back through the wind-up, a short
   lunge with the bump just before contact, the full lean from the hit frame, the spring back, the
   rest), the lunging jab the spear-finisher strip, which **loads**: the big wind-up squash while its
   art pulls back 6 px and a glint shows at the body's front (160 ms), the launch with the bump, then
   the strongest pose (the cry) from the hit frame, with an 18 px step (160-260 ms). The body keeps
   its size: every frame of a strip is drawn at one scale and no code squash plays on them. A rigid
   spear (the painted jelly spear without its root blob: a thin shaft, 5 px on the jabs and 6 on the
   finisher and the Lunge, and an arrowhead) slides out from **behind** the body through a jelly neck
   painted onto the lunge and full-lean frames: part of it on the lunge frame (with 4-5 speed streaks
   beside it), the whole reach on the hit frame to the hit line's end (110 px from the slime's centre,
   the finisher 132), where a painted glint flashes at the tip; it pulls back for 40 ms after the
   active window and is hidden on the spring back and the rest. The hit line starts where the spear
   leaves the neck (the full lean's socket). Jab 1 and jab 2 look the same (jab 2's 12 px `sidePx`
   does not apply on the strike frames). Expect a hit-stop per swing, a bigger yellow number and camera trauma on the finisher,
   and the light dummy launched (it slides back to its post). Numbers: 14 / 16 / 21; the chain is
   slower than on 2026-10-11 (cancel points 240 ms, the finisher's wind-up 220 ms, rest 210 ms).
2. **Charge:** hold left click: nothing strikes. After 250 ms a goo ring fills under the slime
   (after the running step; after the rest for a finisher) and the slime walks at **half speed**
   (`combat.chain.chargeWalkScale`) while it fills or waits full, holding its charge's wind-up frame
   (the Spear: its finisher strike's; the Hammer: hammer-boom's, which the Quake plays; the Axe: its
   drawn `load` pose; standing or walking, turned to its facing). Let go when it is full for the
   Lunge (Spear, 15 energy), the Spin (Axe, 20 energy: **one** hit per target, a full r72 circle
   swept round from the aim, one hit-stop, 40 damage) or the Quake (Hammer, 25). Letting go before
   the ring is full drains it with no attack and no energy spent; a release before 250 ms is a
   normal tap. Too little energy fizzles (a cue and a puff). Energy does not refill by itself: pick
   up energy shards, or press **F5** in the playground.
3. **Switch shape:** E or the wheel [E]: Spear, War Axe, Hammer. During a strike the switch waits for
   the step's cancel point (during a charge: its end); it never cancels a strike, so a Hammer
   wind-up, a finisher or a paid charge always lands. The bag (B) top band: click a shape (or
   Enter / Space on a focused one) to make it current (tagged NOW); arrowing onto one only shows
   its card.
4. **War Axe:** sweep, backswing, chop (18 / 21 / 27); slower than on 2026-10-11 (cancel points
   325 / 300 ms). Each step plays the slime's strike frames ([The War Axe's and the Hammer's strike frames](#the-war-axes-and-the-hammers-strike-frames-2026-10-12)): a rigid axe grows out of the
   painted knob through a jelly neck and turns with the frames; the sweep comes **down** from a
   raised head along its 140 deg arc (r76), the backswing swings **up** the other way (in the front
   and back views the sweep's frames mirrored), each trailed by the painted swoosh along the head's
   path, and the chop **loads**: the head rises behind the slime, its art crouches, hops 28 px and
   lands on the contact frame, chopping down in front (110 deg, r70, the whole sector at once, a small
   shock ring and dust, no crack); in the back views a long jelly arm carries the axe to the target.
   The Spin keeps the slime's drawn poses (page 6) and swaps the two swing poses once per quarter turn,
   the painted axe swinging round it. Stand east of the
   column between two dummies and sweep west to catch both. In the pen a tap stops the worm
   swordsman's swing and holds it (no wind-up armor any more).
   Trees: the Axe chops (harvest wood 1); the Spear clinks off a tree (24 px recoil, the chain ends).
5. **Hammer:** thud, boom (36 / 54, the boom's ring 18 bounces in place); the 260 ms wind-up drops a
   press. The Thud steps 8 px into its smash (160-260 ms); the BOOM **loads** (the art pulls back and
   squashes, the head lifts far back) and steps 20 px (170-280 ms). Both play the slime's strike
   frames ([The War Axe's and the Hammer's strike frames](#the-war-axes-and-the-hammers-strike-frames-2026-10-12); the Quake plays the BOOM's): a jelly stalk with the mallet head on it grows out of
   the knob, swings over and stands the head flat on its face on the ground 68 px in front (the
   impact's `offset`), then pulls back in. A tap pressed after the Thud's first active frame waits for its cancel point
   (460 ms); one pressed within its link window (to 610 ms) gives the BOOM. The crack, the dust and
   the shock ring are about as wide as the hit (r48, the BOOM's ring r72, the Quake's cracks r120).
   Rocks: harvest stone 1, iron 2 in the Stone form; a Hammer impact in the Stone form breaks
   cracked ground.
6. **Reactions** on the four testbed dummies: light (holds, launch on the finisher, break-free on
   the third hold in a row), medium (knockback finisher), heavy (armor, poise breaks into a
   stagger), boss (armor, belly wobble); the dummies move, so launches, splats against the hill's
   wall and bowling into the next dummy show. Then the **enemy pen** (step in to start the fight,
   F4 respawns it): every accepted hit that is not armor or a clink cancels the enemy's swing, shot
   or lunge before its impact and stops it, walking included, for the whole stun (holds of
   530-900 ms, knockback 500 ms, launch 600 ms). The slime spider (light), the worm swordsman
   (medium: no wind-up armor, a tap stops its swing; its counter-slash break-free) and the Clod
   Stomper (heavy: poise, a stagger or a knockdown holds its stomp back), and the playground's own
   camp north-east (`playground-enemy-pen`: worm archer, worm brawler (no lunge armor), slime
   spider, orb weaver, clod stomper): wall splats, bowling into another enemy, kill launches, daze
   stars. For 400 ms after a knockback or launch stun ends (the wake guard) hits only deal damage
   and flash. Each kill has a 20 % chance to drop an **energy shard** (walk over it: +15 energy; it
   stays while energy is full, and fades after 12 s).
7. **Q (mouth):** with an empty mouth, a press sucks for one second (essences and liftables only,
   never live enemies). With a liftable in the mouth, a tap throws it: a pot on a light enemy dazes
   it (1.55 s). With an essence in the mouth, a tap spits it out whole; hold Q 2 s to swallow it (the
   ring fills in the essence's colour, both ways from the front of the slime). In a form with an
   empty mouth, hold Q 2 s to spit the form out.
8. **Ability Box:** F [S] uses the chosen box ability (the Squash Slam first). Bag (B) top band,
   Abilities row: click one to put it on F (tagged ON F); the choice is saved with the run. The HUD's
   Ability slot shows it with its cost chip and cooldown sweep; a click on it opens the bag.
9. **Slam combo:** F next to the dummies: the inner half (40) launches, the outer ring (24) bounces
   in place for 600 ms, so a Spear chain can follow. The slime cannot be hit from 140 to 440 ms and
   ignores knockback for the whole slam.
10. **Roll:** Space [D] (moved from 2; the number keys are free in the rework mode). It fires on the
    **release**: a tap (let go within 200 ms) rolls the quick roll: no spin-up, about 165 px in
    330 ms (about 667 easing to 333 px/s), safe for 250 ms, the same bonk and bounce; tap rolls can
    follow each other every 580 ms. With the `roll-charge` upgrade (the testbed lends it), a hold
    past 200 ms spins up while held, launches at the release or at the spin-up's end (260 ms), then
    rolls on while held (draining energy); without the upgrade a hold rolls the quick roll on the
    release. The slime walks while the key is down before the roll starts. The ability bar's click
    is a quick roll.
11. **Juice demos and switches:** F9 shows the juice panel. While it shows, 1-9 and 0 **play**
    freeze, flash, squash, jitter, trauma, kick, sparks, pitch, numbers and slow motion once, on the
    nearest dummy or enemy within 200 px of the slime (else on the slime itself): first at the
    current shape's finisher value, then 600 ms later "shown 4x" (4x as long, or as many; the squash
    and the jitter also 2x as big; the trauma x4, 1 at most; each step's pitch rise above 1 x4). The
    freeze, the jitter and the slow motion play on the target's squash or tumble so there is
    something to hold. The panel names what played, and why a layer did not show (switched off,
    reduce motion, the shake slider, the Damage numbers setting). Shift + the same key switches the
    layer off and on (a layer left off keeps a reminder on screen). Settings: "Damage numbers"
    (rework mode only) hides the numbers; reduce motion drops freeze, shake, kick and stutter and
    plays the squash at 35 %.
12. **Classic check:** `?classic` (or a world without `?shapes`): the old sword, number keys, Q,
    Swallow on 1 and the old Slam (30 damage, radius 90) are back, with no F action.
13. **Art** ([Art](#art-2026-10-12)): strike each shape down, up, left and right (every shape aims
    4-way since the owner's round 2: a diagonal key press or pointer strikes to the side, left or
    right, and movement stays 8-way): the slime's drawn pose follows the aim,
    a left strike mirrors the side pose and its weapon, an up strike draws the weapon behind the
    slime; in the pointer scheme (F2) moving the pointer across the slime mid-strike does not flip
    it. The Spear's jabs and finisher show its strike frames in every direction: the spear comes out
    of the jelly neck behind the body (down the screen in front views, up behind the sprout in back
    views), and the slime does not grow or shrink at contact. The Axe's and the Hammer's chains and the Quake show their strike frames
    the same way: the weapon stays on the knob as the body frames change, the code neck covers the
    join, a left strike and the backswing's front and back views are mirrored, and the blade or head
    draws over a target in front at contact; aimed down or up, the chop and the smashes turn the
    painted weapon through its toward or away views over the head instead of jumping. Swallow the Stone essence and strike: the weapon wears
    the form's skin. Hold for a charge: the slime holds its charge's strike wind-up frame while the ring
    fills, walking or not (the Axe: its `load` pose). Hit the slime spider (goo):
    a small painted goo splat on taps, a bigger one on the finisher. A dropped energy shard is a
    honey-gold crystal with a slow glow. The HUD Shape slot, its carousel and the bag's Shapes row
    show the new shape icons.

## What is built, and what stands in

Built: the mode and input layer, the three shapes (chains, charges, switching, holds, clinks,
harvest, the Spear's wall-cut line), the shared reaction function with every verb of the
combat-feel plan, hit motions and break-free moves, the energy shard, the juice layer (hit-stop
rule, trauma, kick, sparks by material, flash curve, number pop, room clear with the music dip, dev
switches and demos), the Q state machine, thrown hits, the improved Slam, the Ability Box (saved
choice), the bag band, the HUD Shape and Ability slots, the Controls rows and first-time hints. The
2026-10-12 round added the release-fired attack and Roll, the half-speed charge walk, the last
steps' anticipation, the per-step motion, the Spear's shaft and arrowhead, the one-hit Spin, the
quick roll and the charged-roll upgrade, the rework's energy without regen (F5 in the testbed),
longer stuns without wind-up armor on light and medium enemies, and the juice demos. The art round
of the same day ([Art](#art-2026-10-12)) added the slime's drawn attack poses (page 6), the painted
weapons, the Axe swoosh and the Spear glint, the goo splat flipbook, the painted energy shard and
the shape icons (res://asset/UI/shapes/<shape>-icon.webp: the HUD Shape slot, its carousel and the
bag's Shapes row). Then the Spear got its approved look ([The Spear's strike
frames](#the-spears-strike-frames-2026-10-12)): six-frame body-only strike strips per direction with
a rigid spear drawn behind the body, synced to the frames; then the War Axe's and the Hammer's
chains and the Quake got theirs ([The War Axe's and the Hammer's strike frames](#the-war-axes-and-the-hammers-strike-frames-2026-10-12)): body-only strips with a knob, a rigid weapon on a key
timeline and a code neck over the body.

Stand-ins and gaps (grey-box until art and sound passes):

- **Art:** every chain step, the Spear's Lunge and the Hammer's Quake play their strike animations
  (`game/shapes/shape_strikes.gd`, StrikeLibrary); while the Spear's or the Hammer's charge ring fills
  the slime holds its charge strike's wind-up frame (frame 2, the strike's hold), which the charge
  starts on. The Axe's Spin shows the slime's drawn key poses (page 6, `game/shapes/shape_poses.gd`:
  the two swings alternating once per quarter turn, each one held frame; its ring holds the Axe's load
  pose) with the painted axe drawn by `shape_visuals.gd`. A strike whose file is missing plays the
  stand-in `attack-1` with no weapon drawn (its hit still lands). The weapons, the Axe swoosh, the Spear
  glint, the goo splat and the energy shard are painted; the charge ring, the clink tick, the shock
  rings, the speed streaks, the dust and the other particles are still drawn in code, and the
  Hammer's crack is the boss's crack decal.
- **Sound:** swings play `Lash` / `Dodge` / `SlamWindup`, impacts `HitDull` / `SlamImpact`, the
  switch `EquipBlade` / `EquipTool`, the full ring `Heal`, the fizzle `AbilityDenied`, a clink
  `HitBlocked`; the Slam's `SlamRise`, `SlamDive`, `SlamImpactStone`, `Clink` play placeholders;
  `FinisherThump` and `MaterialGoo` / `Worm` / `Chitin` / `Mud` / `Stone` / `Silk` are silent until
  they are baked; the mouth's throat sound is the `GulpSuck` stream pitched up.
- **Not wired yet:** the Roll's bonk still sends an old-style request (no `hit`), so the `roll`
  class and its verbs (bowl, bonk, break) are mapped but unused; the current shape is kept for the
  session only (`ShapeController._last_shape_id`), not saved (the box choice is saved); the boss
  scripts keep their own phase flow (a daze or stagger on Fatty or the Matron plays its motion but
  does not stop their phase machines); hits ignore height levels except the Spear's wall ray and the
  Slam's own-level ellipse; `room_clear` plays only when a boss camp's boss falls (no dungeon rooms
  or ambushes yet); gamepad and the box's R key are not done.
- **Grey-box numbers** chosen where the plans are silent: each charge's `windupMs` / `activeMs` /
  `recoveryMs`, `combat.energyShard.pickupRadiusPx` 28 and `fadeMs` 12000, `gulp.throwHit`, the
  spark and debris counts and tints, the kick's shape (30 ms out, 120 ms back), the hit motion's
  shapes (consts in `enemy_hit_motion.gd` and `enemy_reactions.gd`), the shape drawing sizes
  (`shape_visuals.gd`: the pierce glint 26 / 34 px fading over 90 ms, the load glint 18 px fading
  in 60 ms, 4 / 5 speed streaks 30 / 44 px long; the Spin's axe tip at the hit radius with its head's
  middle at 0.76 of it, the swoosh over 0.42-1.05 of the radius at 0.85 opacity; the chop's impact
  ring 0.45 of its radius; the impact dust's puffs; the Spear on its strike frames: `SPEAR_PART_SHARE` 0.45 of the
  shaft out on the lunge frame, `SPEAR_BACK_SHARE` 0.25 once pulled back, its hidden end
  `SPEAR_INSET_PX` 3 behind the bump, at least the arrowhead and the neck's fade plus
  `SPEAR_MIN_EXTRA_PX` 1.5 showing, the root blob cut `ROOT_FLARE_TX` 20 texture px past `root_end`),
  the strike frames' timeline (`shape_strikes.gd`: the lunge frame over the wind-up's last
  `LUNGE_MS` 50, at most `LUNGE_SHARE` 0.4 of it; the full lean `BACK_MS` 40 into the recovery, at
  most `BACK_SHARE` 0.25 of it; the spring back to `SPRING_SHARE` 0.5 of the recovery), the Axe's
  and the Hammer's drawing on their strike frames (`shape_visuals.gd`: the neck growing over the first
  `NECK_GROW_SHARE` 0.25 of the length, across from `NECK_MIN_ACROSS` 0.6; the swoosh sampled every
  `SWOOSH_STEP_MS` 8 over `SWOOSH_TRAIL_MS` 120 while the weapon turns `SWOOSH_MIN_TURN` 0.6 deg a ms,
  `SWOOSH_IN_PX` 5 / `SWOOSH_OUT_PX` 3 round the head, `SWOOSH_FADE_MS` 110, a `SWOOSH_CUT_DEG` 90
  step a cut; the head's `HEAD_COLLAR_TX` 16 over the stalk; `DOWN_FRONT_Y` 0.5), the goo splat flipbook's 46 / 31 px and 50 ms frames
  (`particle_fx.gd`), the shard's 24 px crystal and its 1.6 s glow pulse (`energy_shard_look.gd`),
  no code squash on the strike frames (`STRIKE_SQUASH_SHARE` 0) and the Spin's 4 pose swaps
  (`shape_poses.gd`), the last
  steps' `anticipation` (Spear finisher: pull 160 ms, 6 px back, 4 px push, squash 0.84 / 1.12;
  Axe chop: pull 90 ms, 4 / 3 px, 0.86 / 1.12, hop 28 px; Hammer BOOM: pull 170 ms, 6 / 5 px,
  0.86 / 1.14), the steps' `stepFromMs` / `stepToMs` windows, the Spin's one-hit `damageScale` 2.2,
  the quick roll (`character.player.rework`), the testbed's layout and its dummies' 90 px/s walk
  back, the pen's 3 s respawn (`shapes_testbed.gd` exports), `combat.rules.bowling.minSpeed` 140,
  and the juice demo's reach 200 px, "shown 4x" (sizes 2x) and 600 ms gap (`juice_demo.gd`).

## Art (2026-10-12)

The prototype's first painted art (Magnific GPT 2.5, transparent backgrounds; sources, prompts, the
kept variants and the page layout in
[asset/Originals/characters/slime-v2/shapes/README.md](../../asset/Originals/characters/slime-v2/shapes/README.md)).
`python scripts/characters/pack-slime-shape-poses.py` packs all of it, then
`tools/build_player_clips.gd -- --only=shape-` builds the pose clips the game shows, the War Axe's
for its Spin ([TOOLING.md](../TOOLING.md)). The Spear's strike frames
([below](#the-spears-strike-frames-2026-10-12)) are packed by
`python scripts/characters/pack-slime-strikes.py`, the War Axe's and the Hammer's
([below](#the-war-axes-and-the-hammers-strike-frames-2026-10-12)) by
`python scripts/characters/pack-slime-weapon-strikes.py`; the game builds their animations at run time
from the strike files (no clips in the scene). Everything below shows only in the rework mode; the
classic game never plays a pose clip or strike animation or draws these textures, though it loads some
of them (the player scene references page 6, and the scripts that draw the weapons, the effects and
the shard are preloaded through player.gd, enemy.gd and ParticleFx; the strike sheets load only when
the rework builds its strike animations; the icons load on demand).

| Art | Runtime file (res://) | Drawn by | When it shows |
|---|---|---|---|
| The slime's attack key poses, four per shape and direction, no weapon on the body | `asset/characters/256x256-tile_8x8-slime-v2-page-6.webp` (page 1's cells and baseline; where each pose landed: `asset/Originals/characters/slime-v2/page-6.json`); the 9 clips the game shows, `shape-axe-<load\|swing-down\|swing-up>-<down\|up\|side>`, in `game/characters/player_slime.tscn` | `game/shapes/shape_poses.gd`, through the player's animation API | the Axe's Spin (below); its `load` pose while the Axe's charge ring fills or waits full |
| The Spear's strike frames: six body-only frames per strike (spear-jab, spear-finisher) and direction, one scale per strip, the jelly neck baked into frames 3 and 4 | `asset/characters/512x416-tile_8x8-slime-v2-strikes.webp` (8 x 8 cells of 512 x 416 centred like page 1's), `game/data/shape-strikes.json` (sockets, bumps, spear states, origin, scale, tint) | the strike animations `strikes/spear-<jab\|finisher>-<direction>` and their holds `...-hold` (built at run time from `game/characters/strikes/spear-<jab\|finisher>.tres` by `strike_library.gd`), sought by `shape_poses.gd`; the StrikeRig (`game/shapes/strike_rig.gd`: the rigid spear under the Visual); `game/shapes/shape_strikes.gd` (the manifest) | the Spear's jabs, its lunging jab and its Lunge, and the Lunge's charge ring ([below](#the-spears-strike-frames-2026-10-12)) |
| The War Axe's and the Hammer's strike frames: six body-only frames per strike (axe-sweep, axe-backswing, axe-chop, hammer-thud, hammer-boom) and direction, a jelly knob where the weapon leaves the body, no neck baked; the code neck, a horizontal jelly cone | `asset/characters/512x416-tile_8x8-slime-v2-strikes-axe.webp`, `...-strikes-hammer.webp` (the Spear sheet's grid and cells), `asset/characters/shapes/neck.webp`, `game/data/shape-strikes.json` (rows, flips, sockets, knob widths, arms, the `weapons` and `neck` blocks with the views, the `contact` report; the key timelines until round 3) | the strike animations `strikes/<strike>-<direction>` and their holds `...-hold` (built at run time from `game/characters/strikes/<strike>.tres` by `strike_library.gd`), sought by `shape_poses.gd`; the StrikeRig (`game/shapes/strike_rig.gd`: the weapon on StrikeRig / StrikeRigFront, the neck on StrikeRigNeck, the swoosh); `shape_strikes.gd` (the manifest) | the Axe's sweep, backswing and chop, the Hammer's Thud, BOOM and Quake, and the Quake's charge ring ([below](#the-war-axes-and-the-hammers-strike-frames-2026-10-12)) |
| The jelly weapons, lying horizontal, root left, tip right, 512 px on the long side | `asset/characters/shapes/spear.webp`, `axe.webp`, `hammer.webp`, `shapes.json` (the Spear's `shaft_px`, `root_end` and `head_start`; the axe's and the hammer's `head_start`) | the StrikeRig (`strike_rig.gd`: the Spear with its root blob cut off, the axe and the hammer at the manifest's weapon blocks); on the Spin `shape_visuals.gd` (its ShapeWeapon layer: the axe) | each step and charge, along its hit (the shape_visuals paragraph under "API by part") |
| The Axe swoosh, a crescent trail | `asset/MAPS/effects/shape-axe-swoosh.webp` | the StrikeRig, along the head's path; on the Spin `shape_visuals.gd`, bent onto the swept arc | behind the head through the swings and the Spin's active window, fading |
| The Spear glint, a star with streaks | `asset/MAPS/effects/shape-spear-glint.webp` | `shape_visuals.gd` (ShapeOver) | at the tip on every thrust's contact frame (90 ms; on the strike frames at the hit line's end, where it stays while the spear pulls back), and small at the body's front through the finisher's load |
| The goo splat, 4 frames | `asset/MAPS/effects/256x256-tile_4x1-goo-splat.webp` | `game/feel/particle_fx.gd`, flipbook `goo-splat-sheet` | the debris of a hit on a goo enemy (HitJuice `MATERIAL_FEEL` goo): small on taps, bigger on big hits |
| The energy shard, a honey-gold crystal | `asset/MAPS/effects/energy-shard.webp` | `game/combat/reactions/energy_shard_look.gd` | a dropped shard, with its bob and glow pulse, until it is picked up or fades |
| The shape icons, 128 px | `asset/UI/shapes/spear-icon.webp`, `axe-icon.webp`, `hammer-icon.webp` | `game/ui/body_cards.gd` `SHAPE_ICONS` | the HUD Shape slot, its carousel and the bag's Shapes row |

The poses (`shape_poses.gd` TIMELINES, by the charge's `id`) are the Spin's only, the one strike
without a strike animation: `load` through its wind-up, then `swing-down` and `swing-up` in turn,
once per quarter turn (4 swaps over its 360 ms active window), then `swing-down` in its recovery (a
pose changes at the start, the contact frame and the recovery; the last one reached shows). Every
other step and charge plays its strike animation (below); with neither (a strike file missing) the
slime plays `attack-1`.

A charge ring: standing or walking at half speed, the slime holds its charge's strike wind-up frame
(player.gd `_locomotion_clip` asks `ShapeController.held_pose_clip()`): the Spear's ring
`strikes/spear-finisher-<direction>-hold` (its Lunge plays that strike), the Hammer's
`strikes/hammer-boom-<direction>-hold` (its Quake plays that strike), the frame each animation starts
on (StrikeLibrary builds a hold for every strike and direction but the mirrored strips); the Axe's ring
holds its `load` pose, `shape-axe-load-<direction>`.

A strike's direction is its hit's aim by the player's 3-way rule (a mostly vertical aim picks
down or up, any other side; with the 4-way aims of 2026-10-12, round 2, every strike is right, down,
left or up). A side frame faces
right and the player's flip mirrors it for left, following the facing the strike set (a hold as its
strike's `-side`); in the pointer scheme the slime does not turn to the pointer while a step runs, so
the frame stays mirrored like its weapon. Each pose clip is one frame held 0.1 s and played once, so
the frame stays until the next pose. Once a strike ends or is cancelled the player plays idle or walk
again (or the clip that cancelled it: the Roll's, the knockback's).

The weapons, the swoosh, the glint, the splat and the shard draw with
`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`, and their seven imports ask for mipmaps
(`mipmaps/generate=true`), which the next import builds (until then, plain linear). The weapons and
the swoosh wear the Gulp form's skin (their own form_skin.gdshader material with the form's `skin`;
the form's tint where the slime's Visual has no skin shader).

Still grey-box: the charge ring, the clink tick, the shock rings, the speed streaks, the sparks,
the dust and the other particles; the Hammer's crack (the boss's crack decal); every sound. On the
Spin the axe's root follows the hit geometry (its haft 12 px out), not the drawn poses.

## The Spear's strike frames (2026-10-12)

The look the owner approved on 2026-10-12 ("much better, I think this is the way to go"), after the
prototype in `asset/Originals/characters/slime-v2/shapes/prototypes/synced/` (its README, "Separate
spear synced to body frames" and "Strike sheet"): a separate rigid spear synchronised to body-only
strike frames that keep the slime's size. Rework mode only; the Axe and the Hammer got their own
later the same day ([below](#the-war-axes-and-the-hammers-strike-frames-2026-10-12)). Since round 3
the motion below (the timeline, the spear's states) lives in the strike animations, and since round 4 in
the strike files `game/characters/strikes/spear-jab.tres` and `spear-finisher.tres`
([Editing the strike animations](#editing-the-strike-animations-2026-10-12)); the StrikeRig draws the spear;
the numbers here describe that first build.

- **The frames.** `asset/Originals/characters/slime-v2/shapes/strikes/spear-<jab|finisher>-<side|down|up>.png`,
  six frames each (jab: 1 rest, 2 lean back, 3 lunge with the bump, 4 full lean, 5 spring back,
  6 rest; finisher: 1 rest, 2 big wind-up squash, 3 launch with the bump, 4 strongest (the cry),
  5 bounce back, 6 rest), packed by `scripts/characters/pack-slime-strikes.py` into the strike sheet:
  every frame of a strip at one scale, set by its rest frame (as tall as page 1's first idle frame of
  that direction), the back (side) or the middle (down / up) and the ground on the same pixel in every
  frame, the rest frame where page 1's idle stands. Side views face right; a left strike mirrors about
  the cell's origin (the Visual's flip_h). In the front views the bump hangs below the mouth and the
  spear goes down the screen; in the back views it rises in front of the sprout and the spear goes up
  behind the leaves. Frames 3 and 4 carry a jelly neck grown from the painted bump's tip along the
  strip's aim (no outline at the join, fading into the shaft): the game draws only the rigid spear.
- **Which strip** (`ShapeStrikes.STRIKES`): jab and jab-2 play spear-jab, the lunging jab and the
  Lunge spear-finisher, in the aim's direction by the player's 3-way rule (`ShapePoses.direction_of`).
  A strip plays only when the player has its strike animation (`ShapePoses.strike_frames_for`);
  otherwise the stand-in `attack-1` plays and no spear is drawn (the hit still lands).
- **The timeline** (the Spear's stages, first built into its strike files; until round 3 `ShapeStrikes.stage_at`, on the step's own `windupMs`, `activeMs`
  and `recoveryMs`; the hit keeps its timing): frame 2 through most of the wind-up; frame 3 over its
  last 50 ms (at most 40 % of it; the finisher's from the end of its 160 ms pull-back); frame 4 from
  the contact frame (shown before the hits, so the hit-stop freezes it) through the active window and
  40 ms more (at most 25 % of the recovery) while the spear pulls back; frame 5 to the middle of the
  recovery; then the rest frame 6 (the manifest's `rest_frame`; frame 1 is drawn taller and would pop
  the size) until the strike ends and idle or walk plays. Frame 1 never shows. Jab: frame 2 at 0-30 ms,
  3 to 50, 4 to 150, 5 to 195, 6 to its end (a waiting tap ends it at its 240 ms cancel point); the
  lunging jab: 2 to 160, 3 to 220, 4 to 350, 5 to 435, 6 to 560; the Lunge: 2 to 36, 3 to 60, 4 to 220,
  5 to 310, 6 to 440.
- **The animation.** StrikeLibrary builds the strike's animation from its file: each frame (the Visual's texture, frame and offset
  (-256, -208), the sheet's -origin) and ShapePoses seeks it by the gameplay clock, so the art and the
  hit cannot drift; the next clip the player plays puts page 1's rest offset back (`_play_clip`).
  `PlayerScript._flip_for` mirrors a `-side` animation for a left facing; ShapePoses also pins the
  offset and the mirror on every physics step. Each strike and direction also has its hold,
  `strikes/<strike>-<direction>-hold` (its first frame on its sheet, held: the charge ring's frame); the
  player scene holds no strike clips (the held `strike-<strike>-<direction>-f<n>` clips and the
  whole-strike previews were removed).
- **The sockets** (`game/data/shape-strikes.json`, per frame, in cell px: pixel (x, y) covers
  [x, x + 1]; `socket_game` = (socket - origin) x scale, game px from the Visual's origin, which is
  the slime's centre at rest): `socket`, the neck's end, where the spear's visible part starts;
  `bump`, the painted bump's tip, where the neck leaves the body; `neck_fade_end`, where the neck has
  faded into the shaft; `spear`: `hidden`, `part` (frame 3) or `full` (frame 4). On a hidden frame the
  socket is the body's front edge on frame 4's socket line (only the finisher's load glint uses it). A
  left strike negates the game x (`ShapeStrikes.socket_game`). The full lean's sockets, game px from
  the centre: jab side (42.8, 16.3), down (-0.1, 46.1), up (-4.9, -20.3); finisher side (63.5, 13.9),
  down (-3.4, 51.6), up (0.3, -31.0). Since round 5 the strike file's `socket_nudge` for the frame is added
  (`StrikeLibrary.socket`, all zero so far; mirrored with the strike), for every weapon.
- **The spear** (the StrikeRig, `game/shapes/strike_rig.gd`, a Node2D under the player's Visual with
  `show_behind_parent`, scaled so its px are game px, keyed by the animation: `socket`, `length` (0
  hidden, 0.45 on the lunge frame, 1 at full reach, 0.25 once pulled back), `spear_inside`,
  `spear_fade`, `spear_shaft`, `layer`): spear.webp without its root blob (cut
  `ROOT_FLARE_TX` texture px past `root_end`), anchored at the arrowhead, scaled uniformly so its shaft
  is the strike's `shaft_px` wide (5 on the jab strip, 6 on the finisher strip), tinted by the
  manifest's `tint_gain` (about 40 % toward the body's jelly, as the baked neck fades into it), in the
  Gulp form's skin. It is drawn from the socket of the frame the Visual shows (read off the live
  Visual: its texture, frame, offset and flip) along the strike's aim, its hidden end 3 px
  behind the bump inside the jelly: on frame 3 the arrowhead and 45 % of the shaft, on frame 4 the
  whole reach to the hit line's end, on frame 4 after the active window the arrowhead and 25 %, none
  on frames 5 and 6; always at least the arrowhead and the neck's fade. Under the Visual it moves with
  the art's offsets and its physics interpolation, so it never parts from the neck. On a downward aim
  (down) the part past the neck's fade end draws on StrikeRigFront instead, its twin under the Visual at the over layer's z (over the world), so a target lower on
  screen, which sorts after the slime, never covers the shaft or the tip; the root stays behind the
  body. Where a reach
  needs more shaft than spear.webp holds past the blob (only the Lunge aimed up, 151 px), the shaft
  stretches behind the whole arrowhead.
- **The hit line** (`ShapeStrike.area_shapes`; the controller's `_with_strike` adds `lineFrom` to a
  copy of the step's numbers): from the full lean's socket (mirrored for left) along the aim to
  `reach` measured along it from the slime's centre, cut at walls; `sidePx` does not apply. The hit
  ends where the drawn tip is at full reach; its near end comes back along the aim to `minReach`
  (24), keeping the socket's offset across the aim, so a target pressed against the slime's front,
  closer than the socket (jab 43 / 46 / 20 px side / down / up, the finisher and the Lunge 64 / 52 /
  31), is still hit.
- **The hit's feel:** the hit-stop on the contact frame, the target's white-then-pink flash, the
  pierce glint at the hit line's end (it stays there as the spear pulls back), the goo splat on goo
  targets; the speed streaks beside the spear on frame 3; the finisher's load glint at the body's
  front on frame 2. No code squash plays on the strike frames (the anticipation's squash share is 0,
  `ShapePoses.STRIKE_SQUASH_SHARE`, and the strike squash is skipped), so the body and the spear keep
  their size; the finisher's pull-back and push offsets and every step's `stepPx` stay.
- **Known limits:** the neck is painted along the strip's aim; until the 4-way aims (round 2) the
  Spear aimed the exact angle and on steep diagonals left the neck at an angle, now it always
  strikes along a strip's aim; on side and up aims the spear
  draws behind the slime, so a target sorted after the slime covers the tip where they overlap (it
  reads as a pierce; the glints draw over the world, z 1); in the back views the sprout hides most of the
  neck and a hidden frame's socket may sit on a leaf (the finisher's up load glint); jab 1 and jab 2
  look the same; the jab's frame 3 lasts about 20 ms (a physics step or two); the Spear's ring pose
  (the strike's wind-up frame) has no walk cycle, so the slime glides in it. The strike sheet is 4096 x 3328 (about 54 MB of video memory
  uncompressed, 36 of its 64 cells used; `GRID` 6 in the packer would make it 3072 x 2496 but needs
  hframes and vframes 6 while it shows); it loads when the rework mode builds the strike animations
  (the player scene no longer references it, so the classic game does not load it).

## The War Axe's and the Hammer's strike frames (2026-10-12)

The owner saw the side-view prototypes (`asset/Originals/characters/slime-v2/shapes/prototypes/synced/`,
`compose_axe.py`, `compose_hammer.py`) and said "go": the Spear's method for the Axe's chain and the
Hammer's, every direction. The build contract was
[docs/design/2026-10-12-weapon-strike-frames.md](../design/2026-10-12-weapon-strike-frames.md); this
section describes what was built. Rework mode only; the Spear and the classic game are unchanged, and
the Axe's Spin keeps its page-6 poses and its old drawing.

- **The frames.** `asset/Originals/characters/slime-v2/shapes/strikes/` `axe-sweep`, `axe-backswing`
  (side only), `axe-chop`, `hammer-thud` and `hammer-boom`, `-<side|down|up>.png`, six body-only frames
  each (1 rest, never shown; 2 wind-up / lift; 3 swing / spring up; 4 follow-through / chop / smash; 5
  spring back; 6 rest), each painting a round jelly knob where the weapon leaves the body, moving round
  the body with the swing. `python scripts/characters/pack-slime-weapon-strikes.py` packs them (the
  Spear's method: one scale per strip, set by its rest frame) into one sheet per shape beside the
  Spear's, the same 8 x 8 grid of 512 x 416 cells: `asset/characters/512x416-tile_8x8-slime-v2-strikes-axe.webp`
  (rows 0-2 the sweep's side / down / up, 3 the backswing's side, 4-6 the chop's) and
  `...-strikes-hammer.webp` (rows 0-2 the Thud's, 3-5 the BOOM's). The backswing's down and up strips
  are the sweep's rows shown flipped (`flip`, `source`: no rows of their own). It also writes the
  code neck (`asset/characters/shapes/neck.webp`) and merges the manifest's five strikes, the `weapons`
  block and the `neck` block into `game/data/shape-strikes.json` (the Spear's entries stay). No neck is
  baked into these frames.
- **Since round 4** the timeline, the layers and the views below are the keys of the strike files
  ([Editing the strike animations](#editing-the-strike-animations-2026-10-12); `game/characters/strikes/`, read
  by `game/shapes/strike_library.gd`), and the StrikeRig (`game/shapes/strike_rig.gd`) draws the weapon, the neck
  and the swoosh with the code that was ShapeVisuals'; the names in brackets below are the rig's.
- **Which strip** (`ShapeStrikes.STRIKES`): the sweep plays axe-sweep, the backswing axe-backswing, the
  chop axe-chop, the Thud hammer-thud, the BOOM and the Quake charge hammer-boom, in the aim's
  direction by the player's 3-way rule (with the 4-way aims: right and left side, down, up). A strip plays only when
  the manifest has its row, its weapon block and the neck (`ShapeStrikes.is_complete`) and the player
  has its strike animation; otherwise the stand-in `attack-1` plays with no weapon drawn.
- **The timeline** (until round 3 the manifest's `keys`, then the animation's tracks, now the strike file's keys, on
  the step's own `windupMs`, `activeMs`, `recoveryMs`; the hit keeps its timing): each strip's `keys` sat at `w<share>`, `a<share>` or `r<share>` of the
  wind-up, the active window or the recovery. A key sets the frame shown from it (until the next key
  that names one) and the weapon's `angle` (screen degrees in the strip's own frame, 0 right, +90 down:
  from the socket along the handle), `length` (the share out: 0 inside the jelly, 1 full), the
  Hammer's `head_angle` and the `layer` (`behind` / `front`); angles, length and head angle ease
  linearly to the next key and hold after the last. A value a key leaves out is the previous key's;
  the head angle where a key names none is that key's own stalk angle. The sweep's and the
  backswing's active window runs the hit arc itself (from the aim minus half `arcDeg` to the aim plus
  half, in the sweep's sense, linear in time, as ShapeStrike's arc grows); the chop and the smashes show
  their contact angle from `w1`, the contact frame, which the hit-stop freezes. The animation keys the
  frame (a flip strip keys its source's row, and the flip). A frame shown is identified by the running strike (sheet, row and
  flip: `ShapeStrikes.shown_frame`), never by its row alone.
- **Mirrors and diagonals.** A left side strike and a flip strip show the frames flipped
  (`shown_flipped`; both would cancel), and a flipped view mirrors the strip's angles (a -> 180 - a)
  and its sockets' x; the slices are reflected across their axis so the art keeps its light. On the
  diagonals the side strip's angles turn by the aim's offset from the strip's aim (45 deg; the body
  frame stays); a head angle a key names (the smash's head standing flat on its face) is the head's
  own on the ground and does not turn (`POSE_HEAD_TURN`). Since the 4-way aims (round 2) no strike
  aims on a diagonal, so the turn is 0 in play; the rule stays for data and modes that might.
- **The weapon** (`StrikeRig.geometry_of`, `_draw_parts`), all from the socket of the
  frame the Visual shows (read off the live Visual), in the layers' game px under the Visual, so it
  moves with the art's offsets, the chop's hop and its physics interpolation and never parts from the
  knob: axe.webp or hammer.webp at the weapon block's `scale`, its handle (texture x 0 to `head_start`,
  row `axis_row` on the axis, `handle_across` as thick: the Hammer's 0.8) stretched from `hidden_px`
  behind the socket, inside the jelly, to `handle_px` past the neck's tip (the joint), then its head
  from the joint (the Hammer's at its head angle; where it turns away from the stalk its collar
  overlaps the stalk's end by `HEAD_COLLAR_TX`). It slides out and back in with `length`: everything
  but the neck's arm slides back along the axis by (1 - length) x (`hidden_px` + the neck + `handle_px`
  + the head's depth) and is cut at the hidden end, so at 0 none of it shows. Tinted by the block's
  `tint_gain`, in the Gulp form's skin (the strike layers' own form_skin.gdshader material, never the
  Visual's).
- **Weapon views** (the owner's round 2, the contract note's "Round 2": aimed down or up, the side
  drawing turned upright read wrong and jumped from above the head to the front). The axe and the
  hammer each have four painted views of one vertical swing as the camera sees it, toward the viewer
  (the down strips) and away (the up strips): 1 raised straight up, 2 tipping over, 3 pointing at
  the viewer or away, 4 planted on the ground in front or beyond (sources
  `asset/Originals/characters/slime-v2/shapes/weapon-<axe|hammer>-<toward|away>.png`; the packer
  writes `weapons.<name>.views.<toward|away>`: a texture, its `scale` and per frame its `rect`, its
  `pivot` (the handle's free end), its `dir` (the direction from the pivot to the head) and its
  `head`). A key's `view` and `view_frame` (steps, like the frame; a key without `view` draws the
  side weapon; `view_frame` is kept within the same view) pick one; while a view shows
  (`StrikeRig._view_geometry`, `_draw_view`) its frame is drawn with its pivot on the neck's
  tip, turned by the key's angle less its `dir`, the neck along the angle, slid back with the length
  as the side weapon (the arm left out) and cut at the same hidden end and `front` split, tinted and
  skinned like the side weapon (`head_angle` and `handle_across` do not apply). The front and back
  chop, Thud and BOOM (and the Quake) use them through the swing: view 1 through the wind-up, 2 and 3
  over the head, 4 from the contact frame through the hold. Since the owner's review of round 5 the back
  (up) strikes first raise the weapon back over the head toward the camera, in front of the body (the
  `toward` frames 1, 2 and the chop's 3, turned head up), then swing it over the head and away (`away` 1 to
  3, behind) to land beyond (`away` 4), as the side and front strikes bring it from behind the head. The
  swoosh follows the view's `head` (gated by the head's speed where a view shows, `SWOOSH_MIN_SPEED` 0.35 px
  a ms, a jump of `SWOOSH_CUT_PX` 40 or more a cut; a change of the view's frame never starts one).
- **The neck** (`StrikeRig._draw_neck_on`): neck.webp (a horizontal jelly cone in the body's colours
  and grain, root left) drawn OVER the body on StrikeRigNeck (a child of the Visual drawn after it) at
  the socket along the weapon, its `root_x` on the socket, scaled uniformly so `width_px` is the
  frame's knob width (`knob_w`, keyed), in the weapon's colour without its tint; its tube (`arm_from_x`
  to `arm_to_x`) stretches by the animation's `arm_px` x the length (the back views' 22-35 px jelly arm, so
  the weapon reaches where the hit lands; 0 in most strips), the cap, the fillet and the taper keep
  the knob's scale. It grows out over the first quarter of the length (`NECK_GROW_SHARE`). Its tip,
  the neck's length plus the arm, is where the handle shows.
- **Layers.** `behind`: the whole weapon and its swoosh on StrikeRig, under the Visual (the body
  covers the hidden end). `front`: the part past the neck's tip and the swoosh on StrikeRigFront (z 1,
  over the world, so a target lower on screen never covers the blade), the root still behind. The
  converter baked the old downward rule into the layer keys (a down strike's `behind` weapon pointing
  more than 30 deg below level keys `front`).
- **The swoosh** (`StrikeRig._draw_swoosh_trail`): the painted swoosh along the head's recent path:
  the strike sampled at earlier gameplay times (StrikeLibrary.state_at) every 8 ms back over 120 ms of gameplay time (a hit-stop freezes it) while the
  weapon turned at least 0.6 deg a ms one way, bent onto the band from 5 px inside the head to 3 px
  past it along the weapon, its thin tail at the oldest sample, fading over 110 ms once the head slows;
  a sample step that turns 90 deg or more is a cut (the front and back chop and smash turn the weapon
  through the camera's axis in a ms) and ends it.
- **The charge ring:** while the Quake's ring fills or waits full the slime holds hammer-boom's
  wind-up frame (its hold `strikes/hammer-boom-<direction>-hold`: the frame its animation starts on), as
  the Spear's Lunge holds the finisher's, and the release goes on from the same frame on the Quake's own
  windows.
- **The hit** keeps its shapes and numbers (the Axe's arc round the slime's centre, the Hammer's circle
  `offset` ahead); the art was fitted to them: the packer's `contact` report gives the art's reach at
  the hit, and the reach numbers were set from it (Axe sweep and backswing `radius` 76, chop 70;
  Hammer Thud, BOOM and Quake `offset` 68); since round 4 each direction's `hit_reach` (in its strike file) carries them
  per direction, and since round 5 only there: the chain steps hit with it and game-constants.json holds none for
  them (the Lunge, the Spin and the Quake keep their own). Each direction's `hit_center` moves where it is measured
  from; the up chop, Thud and BOOM have since been given a shorter reach from their own centre (the perspective:
  a strike away from the camera reads smaller). The hit feel stays: the hit-stop, flash and splat, the
  chop's small shock ring and dust, the Hammer's crack, dust and shock rings, the shake, the clinks. No
  code squash plays on these frames; the chop's 28 px hop and every `stepPx` stay.
- **Known limits:** the swing turns about the socket while the hit's arc turns about the slime's centre,
  so the blade and the arc's edge differ by a few px away from the contact frame; the head's distance
  from the socket changes a little with each frame's knob width (the neck's length follows it); the
  swoosh is the old crescent texture bent onto the head's path, so a short fast flick (the side
  sweep's last 20 ms of wind-up) already shows a piece of it; a target that overlaps the slime's body
  covers the body and its neck (only the part past the neck's tip goes over the world); the Quake's
  ring holds frame 2 without the hammer; the Spin still uses the page-6 poses and the old axe.

## Editing the strike animations (2026-10-12)

Every strike is one small file that you edit in the Inspector (round 4), with a live preview above its fields
(round 5, 2026-10-14; [the contract note](../design/2026-10-12-weapon-strike-frames.md)). The game and the editor
read the same files; nothing is generated.

**See a strike.** Open `godot/` in Godot 4.7.2 and click a file in `game/characters/strikes/` in the FileSystem
dock: `spear-jab`, `spear-finisher` (the Lunge plays it too), `axe-sweep`, `axe-backswing`, `axe-chop`,
`hammer-thud` or `hammer-boom` (the Quake plays it too). Above its fields the Inspector plays it on a large slime
from the side (a left strike is its mirror), from the front (down) and from the back (up), drawn as the game draws
it.
- **Play / Pause** loops the strike in real time.
- **The time bar:** the windup (blue), the active window (red) and the recovery (grey), and a tick for every key of
  each direction (pink: a `jump` key). Click or drag on it to stop at a moment.
- **Each view** shows the hit area (filled while it hits), a yellow cross at the hit centre, a blue ring at the
  hit's far edge with a blue handle on it along the aim, a white tick at the body's edge, a green dot at the
  weapon's tip and a pink dot at the socket, where the weapon leaves the body. Under it, large: how far the weapon's
  tip and the hit's edge reach past the body; then the hit centre and the same numbers from the slime's centre.
- **Drag the cross** to move where the hit is measured from (`hit_center`), and **drag the blue handle** to change
  how far it reaches (`hit_reach`). The picture follows while you drag; each drag is one step that Ctrl+Z undoes.
- Every change, in a view or in the fields, shows at once.

**What you can change** (open `side`, `down` or `up`):
- `hit_reach`: how far the hit reaches in this direction (game px: the Axe's arc radius, the Hammer's circle
  distance ahead, the Spear's line), measured from `hit_center`. This is the only place a chain step's reach is set;
  the charges (the Lunge, the Spin, the Quake) keep theirs in `game-constants.json`.
- `hit_center`: where the hit is measured from (game px from the slime's centre; a left strike mirrors it). In this
  top-down view a strike away from the camera starts from the top of the head, so the up hit can sit higher and reach
  less than the down one.
- `arm_px`: how far the weapon reaches out from the body (game px): the one number for the drawn reach. Positive
  stretches the jelly arm; negative pulls the weapon back into the jelly by that many px.
- `socket_nudge`: six offsets (game px, x right, y down), one per body frame, that move the socket the weapon
  leaves from; a left strike mirrors them.
- `flip_h` (the strip shown mirrored: the backswing's down and up) and, for the Spear, `spear_inside`, `spear_fade`
  and `spear_shaft` (the Spear's drawn length follows its `hit_reach`).
- `keys`: the timeline. A key's `phase` (windup, active, recovery) and `share` (0 to 1 through it) place it.
  `frame` (1 to 6; frame 1 never shows), `layer` (behind the body, or in front past the neck), `view` and
  `view_frame` (the Axe's and the Hammer's painted front and back views) hold until the next key. `angle` (0 right,
  90 down), `length` (0 inside the jelly, 1 out: the grow-out and the pull-in; the reach itself is `arm_px`) and
  `head_angle` (the Hammer's head) slide to the next key, or, when the next key has `jump`, hold and then snap at its
  moment. Keep the keys in time order, the first at the windup's start.

**Undo and save:** Ctrl+Z undoes a drag or a field edit; Ctrl+S saves (as always it also saves the scene that is
open; the Inspector's own Save button saves only this file). The preview never changes the player scene.

**Leave alone:** `shape`, `step` and the file names (the game looks strikes up by them), and the frame numbers (the
rows of the sheets in `game/data/shape-strikes.json`). A step's timing and damage stay in `game-constants.json`; the
sheets, the sockets, the knob widths and the weapon art stay in the manifest.

**In the game** (rework mode; the code is in [API by part](#api-by-part)). StrikeLibrary builds the player's
`strikes` library from the files at run time, one animation per strike and direction (`strikes/<strike>-<direction>`,
3 units: windup 0 to 1, active 1 to 2, recovery 2 to 3) and its hold (`strikes/<strike>-<direction>-hold`, the
first frame held while a charge ring fills), and ShapePoses seeks it every physics step at the step's
elapsed gameplay time, so a hit-stop freezes the body, the weapon and the swoosh together. The StrikeRig under the
player's Visual draws the weapon from the same file. A chain step hits with the direction's `hit_reach` measured from
its `hit_center` (`StrikeLibrary.chain_hit`: the Axe's arc round it, the Hammer's circle ahead of it, the Spear's
line and its wall ray from it), and the Spear's line starts at the socket the strike has at its contact. The preview
is the editor plugin `addons/strike_preview/`: the same Visual and rig nodes, on the step's own timing.

**History.** Round 4 converted round 3's library (21 generated animations) once into the seven files (checked at
every millisecond: angle and head within 0.37 degrees, length within 0.0005, the held values exact). Round 5 thinned the
keys, 231 to 216, the fewest the rules allow (a key wherever the frame, layer, view or a jump changes, another only
where a straight line would miss by more than 3 degrees or 0.05): at most 2.85 degrees from round 4, the held values
exact, the sweeps still running the hit arc exactly. It also moved the chain steps' reach from
`game-constants.json` into the files, with the same numbers. Later the same day the up chop, Thud and BOOM got a new
motion (the weapon raised back over the head toward the camera, in front of the body, then over the head to land
beyond) and a shorter reach with their own hit centre, and the keys' contact-length slides became negative arms
(the same drawn reach from the contact on).

## The rework mode

`res://game/shapes/rework_mode.gd` (no `class_name`; preload it):

```gdscript
static func is_on() -> bool                                # read anywhere, any time
static func set_on(on: bool) -> void                       # main.gd only
static func is_rework_request(request: Dictionary) -> bool # a request with a non-empty top-level `hit`
```

`main.gd` `decide_rework_mode(target_map_id)` runs at the start of every world build, before the
player spawns: on with `shapes`; on in the playground unless `classic` or `rework_in_playground` is
off; else off. It applies the input layer at the same time (`ReworkInput.apply(on)`), and
`main._exit_tree` turns both off. `start_rework()` (after `equip_run_start`) learns the shapes and
box abilities for the session (`RunState.learn_session_ability(id) -> bool`; `serialize` leaves
`RunState.session_ability_ids` out of every save; `new_run` and `install` clear the list), makes
the ShapeController and, in the playground, the testbed. Every hook into an old
file is guarded by `ReworkMode.is_on()` (or by the request's `hit`), so with the mode off the old
code path runs exactly as before. The Squash Slam is picked by mode too: `PlayerAbilities` runs
`classic_slam_sequence.gd` (the old Slam, unchanged) with the mode off and `slam_sequence.gd` (the
improved Slam) with it on; `AbilityDefinitions.energy_cost` / `cooldown_ms` read
`abilities.squashSlam` only in the mode. In the mode the Roll's cooldown from the press is the
quick roll's `character.player.rework.quickRollMs` + `rollCooldownMs` (580 ms; classic: spin-up +
shortest roll + pause, 960 ms); a charged roll is held back by its own end (`PlayerRoll`).

## Controls in the rework mode

| Action | Keyboard + mouse | Keys only | Input action |
|---|---|---|---|
| Attack with the shape (a tap strikes on its release; hold to charge, let go when full) | Left click | A | `attack` |
| Next shape | E / wheel | E | `weapon_next` (and `weapon_previous` on the wheel) |
| Mouth (the Q table, "Mouth" below) | Q | Q | `eat` |
| Use the chosen box ability | F | S | `ability_use` (new) |
| Roll (on the release; a hold charges with `roll-charge`) | Space | D | `dodge` |
| Interact; held by a heavy block: grab it (walk to push or pull, Stone only) | Right click | W | `interact` |
| Bag (the Ability Box is its top band) | B | B | `menu` |
| Juice panel (dev); while it shows: play a layer / switch it | F9; 1-0 / Shift + 1-0 | F9; 1-0 / Shift + 1-0 | none (keys read by the panel) |
| Respawn the testbed's enemy pen (dev, playground) | F4 | F4 | none (a key read by `shapes_testbed.gd`) |
| Fill the energy (dev, playground) | F5 | F5 | none (a key read by `shapes_testbed.gd`) |

- `ability_use` is in `project.godot` on F. With the mode off nothing captures it
  (`PlayerInputBuffer.REWORK_ACTIONS`), so F does nothing in the classic game.
- `res://game/shapes/rework_input.gd`, `static func apply(on: bool) -> void` and
  `static func is_applied() -> bool`: on, `swallow`, `stretch_lash`, `squash_slam` and `teleport`
  lose their number keys and `dodge` moves from 2 to Space (Space is free: only the dialogue box and
  the quest offer window read it, while they are open); off, every one gets back exactly its events.
  The slime keeps capturing input while a window holds the clock still, so when the `modal` pause
  ends player.gd drops a pending Roll press (`_update_modal_pause`, also checked at the top of its
  physics step; `PlayerInputBuffer.drop_press`): a Space press a window did not take never rolls the
  slime as it closes.
- The keys-only scheme (`game/player/mouse/key_bindings.gd`) adds `REWORK_LAYOUT`
  (`ability_use` S, `dodge` D) only while the mode is on; its classic layout is unchanged. It is a
  layer on top of the rework layer: `ReworkInput.apply` takes it off and puts it back around every
  change, so each layer restores only what it changed, whichever is applied first.
- In the rework mode the Swallow press does nothing (Swallow is a Q hold) and the old
  lash/slam/teleport/jump presses are dropped (those abilities are box abilities used with
  `ability_use`).
- Texts that name an ability's key ask `AbilityBox.key_action(id)`: `ability_use` for a box socket
  and `eat` for Swallow in the mode, the ability's own action otherwise (the ceremony card, the
  quest toast, the cracked ground's creak hint). In the mode the Swallow ceremony reads "Hold Q with
  an essence in your mouth until the ring fills" and the Roll's "Tap Space to roll; with the
  charged-roll upgrade, hold it to spin up and keep rolling"
  (`AbilityDefinitions.REWORK_CEREMONY_HOW`). The creak hint names F only while the Slam is the
  chosen box ability; with another one chosen it reads "It creaks under you... choose the Slam in
  the bag (B), then press F" (`CrackedGroundScript.CREAK_CHOOSE_TEXT`, `creak_text(slam_learned,
  player)`). The Controls window's Attack and Roll rows say they strike and roll as the key is let
  go (`ControlLabels.rework_rows`).

## Files and owners

| Part | Files | Notes |
|---|---|---|
| Mode, wiring, testbed | `game/shapes/rework_mode.gd`, `rework_input.gd`, `shapes_testbed.gd`; hooks in `game/main.gd`, `game/autoload/run_state.gd` (the session-only grants), `game/scripts/player.gd`, `game/player/roll/player_roll.gd` (the quick roll `begin_quick`, the charged roll's `launch_on_release`), `game/scripts/enemy.gd`, `game/scripts/training_dummy.gd`, `game/player/player_input_buffer.gd`, `game/player/mouse/key_bindings.gd`, `game/shell/launch_options.gd`, `project.godot`; the Damage numbers setting in `game/shell/game_settings.gd` and `settings_menu.gd`; `enemy_type` on the eight enemy scenes; `tests/run_tests.gd` (`rework_in_playground` off) | Hooks only: a guarded call into the part that owns the behaviour |
| Shapes | `game/shapes/shape_defs.gd`, `shape_controller.gd`, `shape_strike.gd`, `shape_visuals.gd`, `shape_poses.gd`, `shape_strikes.gd`, `strike_rig.gd`, `strike_library.gd`; the strike files `game/characters/strikes/*.tres` (`strike_animation.gd`, `strike_direction.gd`, `strike_key.gd`); their Inspector preview `addons/strike_preview/` (`plugin.gd`, `strike_inspector.gd`, `strike_preview.gd`) | Chains, charges, switching, hit delivery, the painted weapons, the slime's drawn poses and the strike frames |
| Art | `scripts/characters/pack-slime-shape-poses.py` (sources in `asset/Originals/characters/slime-v2/shapes/`), `scripts/characters/pack-slime-strikes.py` (sources in `.../shapes/strikes/`; writes the Spear's strike sheet and `game/data/shape-strikes.json`), `scripts/characters/pack-slime-weapon-strikes.py` (the Axe's and the Hammer's sheets, `neck.webp`, their manifest entries), the pose clips of `tools/build_player_clips.gd` (`POSE_PAGE`: the Axe's Spin poses) in `game/characters/player_slime.tscn` | The packed sheets, weapons, effects and icons ("Art" above), the strike sheet and its manifest |
| Shared ring | `game/shapes/goo_ring.gd` | The code-drawn charge / hold ring (mouth and charges) |
| Reactions | `game/combat/reactions/hit_reaction.gd`, `reaction_profile.gd`, `reaction_state.gd`, `enemy_reactions.gd`, `energy_shard.gd`, `energy_shard_look.gd`; `game/feel/enemy_hit_motion.gd`, `game/feel/daze_stars.gd`; `game/shared/arcade_mover.gd` (`COLLISION_META`); `game/scripts/clod_stomper.gd` (a reaction stun holds the stomp back) | One shared reaction function per the combat-feel plan |
| Juice | `game/feel/game_feel.gd`, `game/world/world_camera.gd`, `game/feel/particle_fx.gd`, `game/feel/hit_flash.gd`, `game/feel/hit_flash_curve.gd`, `game/feel/floating_text_layer.gd`, `game/feel/hit_juice.gd`, `game/feel/juice_dev_panel.gd`, `game/feel/juice_demo.gd`, `game/runtime/sfx_player.gd` (pitch payload), `game/audio/music_director.gd` (`dip`), `game/scripts/boss_camp.gd` (room clear on a boss's fall) | All additive: new functions, old ones unchanged |
| Mouth | `game/player/gulp/mouth_hold.gd`, `mouth.gd`, `gulp_controller.gd`, `thrown_object.gd`, `gulp_hud.gd` | The Q state machine, the thrown hit and the Q prompts |
| Slam | `game/player/abilities/slam_sequence.gd` (improved), `classic_slam_sequence.gd` (the old one), `ability_world.gd`, `ability_definitions.gd`, `player_abilities.gd`, `ability_fx.gd` | The improved Slam; `strike_area` carries a hit and reports outcomes |
| Lantern | `game/player/abilities/lantern_sequence.gd`, `lantern_flame.gd`, `lantern_glow.gd`; the fire and darkness parts in `game/world/fire/` (`fire_targets.gd`, `fire_fx.gd`, `candle.gd`, `burnable.gd`) and `game/world/darkness/` (`dark_room.gd`, `dark_room.gdshader`); `game/scenes/objects/deadthorn-hedge.tscn`; the playground's corner `game/dev/corners/lantern_corner.tscn` | The flame, the ember, dark rooms, candles, burnables ([The Lantern](#the-lantern-2026-10-14), [DARKNESS.md](DARKNESS.md)) |
| Goo Bomb | `game/player/abilities/goo_bomb_sequence.gd`, `goo_blast.gd`; `game/scripts/goo_bomb.gd` (`object.goo-bomb`), `cracked_wall.gd` (`object.cracked-wall`), `rubble_heap.gd` (`object.rubble-heap`), `blast_barrier.gd`; hooks in `player_abilities.gd` (`on_hurt`, the spend at the spit), `player.gd`, `mouth.gd`, `held_look.gd`, `thrown_object.gd`, `game/world/elevation/elevation.gd` and `elevation_grid.gd` (`open_passage`); the playground's corner `game/dev/corners/bomb_corner.tscn` (`bomb_corner.gd`) and its cave `game/scenes/worlds/playground-bomb-cave.tscn` | The cast, the bomb, the blast, cracked walls and rubble ([Goo Bomb](#the-goo-bomb-2026-10-14)) |
| Heavy plates and blocks | `game/scripts/heavy_plate.gd` (`object.heavy-plate`), `heavy_block.gd` (`object.heavy-block`, `object.heavy-statue`), `game/player/heavy_grab.gd`; hooks in `game/scripts/player.gd` (the grab) and `game/scripts/gate.gd` (`close`); the art `asset/MAPS/props/heavy-plate/` (`scripts/art/pack-heavy-plate-art.py`); the playground's corner `game/dev/corners/heavy_corner.tscn` (`heavy_corner.gd`) | Plates that only a heavy weight sinks, slowly, and blocks only the Stone form moves ([Heavy plates and heavy blocks](#heavy-plates-and-heavy-blocks-2026-10-14)) |
| Ability Box and HUD | `game/player/abilities/ability_box.gd`, `game/ui/body_cards.gd`, `game/ui/screens/inventory_screen.gd`, `game/ui/ability_bar.gd`, `game/ui/weapon_hotbar.gd`, `game/ui/console/hud_console.gd`, `game/ui/hud.gd` (`layout_changed`), `game/hints/control_hints.gd`, `game/shell/control_labels.gd`; key names in `game/ui/ceremony/ability_ceremony.gd`, `game/quests/quest_notifications.gd`, `game/scripts/cracked_ground.gd` | The bag-window band, the HUD shape and ability slots, the Controls list and hints |

New files declare no `class_name`: preload them (`const ShapeDefs := preload("res://game/shapes/shape_defs.gd")`).
Only the three strike resource scripts have one (`StrikeAnimation`, `StrikeDirection`, `StrikeKey`), for the
Inspector; code still preloads them.

## Data

Numbers live in `game/data/game-constants.json`, never in code:

| Path | What |
|---|---|
| `shapes.spear` / `.axe` / `.hammer` | `id`, `title`, `tags`, `baseDamage` (12 / 15 / 30), `aim` (`snap4` for all three since 2026-10-12, round 2: the nearest of right, down, left, up, an exact diagonal to the side; `exact` and `snap8` are still read), `lineCheck`, `targetModifiers`, `harvest` (Axe `{"wood": 1}`, Hammer `{"stone": 1}`), the Hammer's `harvestStoneForm` (`{"iron": 2}`), `chain[]` steps (`id`, `class`, `windupMs`, `activeMs`, `recoveryMs`, `cancelAtMs` (the last step: its whole length; the rest follows), `damageScale`, `launchSpeed`, `hopPx`, `stepPx` (over `stepFromMs`..`stepToMs`, default the wind-up and the active window), the area (a line's `minReach`/`width` with its `sidePx` (the second jab, 12 px beside the aim; on the Spear's strike frames the line runs from the full lean's socket to the reach and ignores `minReach` and `sidePx`), or an arc's `arcDeg`/`sweep` with `chop` (the Axe's last step: its whole sector at once), or a circle's `radius`; since round 5 (2026-10-14) a chain step's reach, the line's `reach`, the arc's `radius` and the circle's `offset`, is not here but its strike file's `hit_reach` in the strike's direction, measured from that direction's `hit_center`, [Editing the strike animations](#editing-the-strike-animations-2026-10-12)), `knockMode` (`aim` / `sweep` / `radial`), `walkCancel`, `hitStopMs`, `trauma`, `kickPx`, `pitch`, `sparks`, extras such as `impactRing`, `thump`, `debris`, `ringHit`, `flattenX`; the last step's `anticipation` {`pullMs`, `pullPx`, `pushPx`, `squashAlong`, `squashAcross`, `jumpPx`}), and `charge` (`ringMs`, `energy`, `class`, `windupMs`/`activeMs`/`recoveryMs` (grey-box guesses), its hit numbers with their own reach (the Lunge `reach` 170, the Spin `radius` 72, the Quake `radius` 56 and `offset` 68); the Spin hits once (`damageScale` 2.2, no `ticks[]` or `holdMs` since 2026-10-12; the tick code path stays for data that has ticks), the Quake `cracks`) |
| `combat.chain` | `linkMs` 150, `holdMarginMs` 140 (it also covers the tap's own press, since a tap fires on its release), `holdCapMs` 900, `chargeStartMs` 250, `chargeWalkScale` 0.5 (the walk while a charge ring fills or waits full), `restMs` {spear 210, axe 195, hammer 200}, `finisherRecoilPx`, `strikeSquash`, `clink` {recoilPx 24, recoilMs, hitStopMs}, `hitStop` {extraTargetMs, extraTargetCapMs, killMs, capMs}. No energy back from hits. (No switch buffer: a switch waits for the strike's cancel point or the charge's end) |
| `combat.hits` | the impact classes: `tier`, `poise`, `countsAsHold` |
| `combat.verbs`, `combat.weights`, `combat.rules`, `combat.trauma`, `combat.roomClear` | as the combat-feel plan, section 8, with the stuns of 2026-10-12: knockback 500, launch 600, stagger 1050, daze 1550 (knockdown 1200); `combat.rules` `poiseBreakMs` 1150, `wallSplat.dazeMs` 1050, `holdResetFreeMs` 300 (replaces `holdResetMs` 700); `combat.weights` light thrown daze 1550, heavy thrown and ring stagger 650, heavy `breakVerb` stagger 1150. A weight's `classes` entry is a verb or {"verb", "stunMs"?, "damageTaken"?}; `combat.rules.bowling` {speedShare 0.6, damage 4, `minSpeed` 140: a body bowls only a standing enemy it moves into at this speed or more, and one in flight is never bowled again} |
| `character.player.rework` | the rework mode's player numbers (2026-10-12): `energyRegenPerSecond` 0 (the classic `stats.energyRegenPerSecond` 8 stays), `rollTapMs` 200 (a Roll key let go within it is a tap), the quick roll `quickRollDistancePx` 165, `quickRollMs` 330, `quickRollEndSpeedShare` 0.5, `quickRollInvulnerabilityMs` 250, `quickRollEnergy` 0 |
| `combat.energyShard` | `dropChance` 0.2, `amount` 15, `pickupRadiusPx` 28, `fadeMs` 12000 |
| `combat.damageNumbers` | `smallColor`, `bigColor`, `popScale`, `popMs`, `bigClasses` |
| `gulp.rework` | `tapMs` 250, `suckBurstMs` 1000, `swallowHoldMs` 2000, `spitHoldMs` 2000, `ringCancelMs` 150, `ringRadiusPx` 30, `burstCooldownMs` 250 |
| `gulp.throwHit` | the thrown hit's class (`thrown`) and feel |
| `abilities.squashSlam` | the improved Slam (body-shapes plan section 4): timeline (`crouchEndMs` 120, `riseEndMs` 320, `hangEndMs` 380, `impactMs` 460, `doneMs` 640), `riseUnits` 96, `airborneFromMs`/`airborneToMs` 140/440, `ignoresKnockback`, `ellipse` 140 x 96 (`innerShare` 0.5), `inner` (slam 40, launch 380, hop 16), `outer` (ring 24, launch 300, `bounceMs` 600), `stoneDamageBonus` 0.25, `feel`, `stoneFeel`, `wobbleRadiusPx`, `energy` 35, `cooldownMs` 2500 |
| `abilities.lantern` | the Lantern (2026-10-14): `energy` 10, `cooldownMs` 300, `clipMs` 200 (the spit clip sped up to this), `releaseMs` 70 (the flame leaves the mouth), `flame` {`class` tap, `damage` 5, `holdMs` 250, `rangePx` 72, `speed` 900, `lingerMs` 150, `radiusPx` 10, `lightRadiusPx` 90, `feel`}, `glow` {`radiusPx` 160, `flareMs` 260}, `candle` {`lightRadiusPx` 110, `gutterMs` 5000}, `burnable` {`burnMs` 600, `spreadPx` 24}, `darkness` {`alpha` 0.92, `softPx` 40, `maxLights` 16, `litFadeMs` 1500} |
| `abilities.gooBomb` | the Goo Bomb (2026-10-14, [Goo Bomb](#the-goo-bomb-2026-10-14)): `energy` 20, `cooldownMs` 600, the cast `castMs` 2000 in `castPulses` 4 swells of `castSwell` 0.1, `spitMs` 320, the hop `hopPx` 64 in `hopMs` 260 with `hopArcPx` 18, `fuseMs` 3000, `pulseStartHz` 2 to `pulseEndHz` 8, `flashMs` 500, `chainDelayMs` 120, `ellipse` 176 x 120, `hit` {`class` slam, `damage` 40, `launchSpeed` 380, `hopPx` 16}, `selfDamage` 18, `mouthDamage` 28, `selfKnockback` 300, `feel` {`hitStopMs` 120, `trauma` 0.9}, `lightRadiusPx` 40, `blastLightRadiusPx` 220, `blastLightMs` 250 |
| `puzzles.heavyPlate` | the heavy plate (2026-10-14, [Heavy plates](#heavy-plates-and-heavy-blocks-2026-10-14)): `sinkMs` 3000 (up to fully down), `riseMs` 5000 (back up), `sinkPx` 6 (the cap's travel), `playerRadiusPx` 30 (the Stone slime's feet from its middle), `blockRadiusPx` 24 (a block's middle), `ringRadiusPx` 46, `grindIntervalMs` 420 |
| `puzzles.heavyBlock` | the heavy blocks: `cellPx` 64 (one move), `moveMs` 640 (a cell, 100 px/s), `startDelayMs` 180 (a walk key held this long before a block moves), `grabReachPx` 14, `strainLineMs` 2400, `strainWobble` 0.06, `strainHz` 7 |
| `abilityBox` | `socketCount` 8, `sockets` (squash-slam, stretch-lash, teleport, lantern, goo-bombs, then the later ids) |

The strike frames read `game/data/shape-strikes.json` (written by
`scripts/characters/pack-slime-strikes.py` (the Spear's) and `scripts/characters/pack-slime-weapon-strikes.py`
(the Axe's and the Hammer's, merged in), never by hand; `ShapeStrikes.manifest()` reads it, not
GameConstants): art placement and the drawing's timing only (the sheets, their cells, origin and
scale, each strike's sheet and weapon, each strip's row, flip, aim and `arm_px`, each frame's socket
(the Spear's bump, neck fade and spear state; the Axe's and the Hammer's `knob_w`), each Axe and
Hammer strip's key timeline, each strike's `shaft_px`, `rest_frame` and `contact` report, the spear's
tint, the `weapons` and `neck` blocks). The Spear's frame timeline's shares are presentation consts
in `shape_strikes.gd`; the hits' numbers stay in `shapes.spear`, `.axe` and `.hammer`.

Step damage = `baseDamage` x (attack 12 / 10) x `damageScale`, rounded by the resolver: Spear 14 /
16 / 21, Axe 18 / 21 / 27, Hammer 36 / 54 (ring 18); Lunge 25, Spin 40 (one hit), Quake 72 (cracks
18). A crit (5 %, x1.75) is rolled once per swing.

`game/data/enemy-types.json` has a `reactions` block per type (`weight`, `material`,
`knockbackScale` = 1 - knockbackResist, `hitstunScale`, `holdCap`, `breakFree`, `poise`,
`breakVerb`?, `roll`, `suck` "none", `classes`, `byTag`, `immune`, `states` keyed by
`reaction_phase()`, `parts`), for the four old types and new reaction-only entries `orb-weaver`,
`clod-stomper`, `fatty-one-eye`, `orb-weaver-matron`. Every enemy scene sets `enemy_type` to its
type (the scene id is `character.<type>`). Fatty's eye is open (`parts.eye.open`) in his phase-1
phases: chase, return-to-center, small-hop, landing, recovery, and dizzy. Since 2026-10-12 the worm
swordsman's and the worm brawler's `states` are empty (their wind-up and lunge armor removed, so a
tap stops their attack), the brawler's `rollDazeMs` is 1050 and the Clod's `breakVerb` stagger is
1150 ms; armor stays only on heavy enemies (the Clod's class armor, its crouch and air armor 4, its
poise) and bosses.

## The hit (what every rework attack sends)

Every damage request sent by a shape step, a charge, the Slam or a thrown object carries a
top-level `hit` Dictionary (not inside `impact`, which the resolver rebuilds) and the effect
`{"effect_id": "impact", "potency": 1.0}`, so a 0-damage hit still counts as accepted and reaches
the reaction. Requests without `hit` are old-style and get the old reaction (today the Roll's bonk
still is one).

```gdscript
hit = {
	"class": "tap",          # tap | finisher | smash | charge | ring | slam | thrown | roll | suck
	"step": 1,               # 1-3 in a chain; 0 for abilities and charges
	"last": false,           # true on the last step of a chain or charge (only `last` may move a body)
	"tier": 1, "poise": 1,   # from combat.hits[class]; a step may override
	"shape": "spear",        # spear | axe | hammer | ""
	"tags": ["weapon", "spear"],  # weapon, spear, cut, crush, slam, thrown, roll
	"hold_ms": 400.0,        # how long a hold lasts (computed by the sender, capped)
	"launch_speed": 0.0,     # this hit's launch / knockback speed (px/s)
	"hop_px": 0.0,
	"knock": Vector2.RIGHT,  # unit direction of the push
	"counts_as_hold": true,  # from combat.hits[class].countsAsHold: false for rings, throws, the suck
	"attacker": "player",
}
```

Build it with the shared helpers in `res://game/combat/reactions/hit_reaction.gd`:

```gdscript
static func build_hit(hit_class: String, fields: Dictionary = {}) -> Dictionary  # class defaults, then `fields`
static func attach(request: Dictionary, hit: Dictionary) -> Dictionary          # request.hit = hit, + the impact effect once
static func impact_effect() -> Dictionary                                       # {"effect_id": "impact", "potency": 1.0}
static func hit_of(request: Dictionary) -> Dictionary                           # {} for an old request
```

The request keeps the old fields too (`weapon_id` is the shape id, e.g. `shape-spear`, or
`thrown-<kind>`, `squash-slam`; `weapon_tags` are the hit's tags plus the shape's harvest tags
`harvest:<target>:<tier>`), so receivers that only read old fields still work: resources read the
harvest tags, Fatty's spear-only rule reads `weapon_tags`. The Thud's `flattenX` / `flattenY` are
not in the hit: read them with `ShapeDefs.step(ShapeDefs.id_for(hit.shape), hit.step - 1)`.

## The reaction (what the enemy answers)

`EnemyReactions.react(enemy, commit, is_dead)` (called by `enemy.gd` `_react_to_damage` when the
request has `hit`) runs `HitReaction.decide(profile, hit, state, now_ms)` and writes the answer
into the commit's result, which is the same Dictionary `DamageRouter.route()` returns to the
sender:

```gdscript
result.reaction = {
	"verb": "hold",          # hold | bounce | knockback | launch | stagger | knockdown | daze |
	                         # armor | clink | pulled | resist | bowl | bonk | break | pop | break-free
	"stun_ms": 400.0,
	"slime": "none",         # none | recoil | bounce | pass | break: what the attacker feels
	"recoil_px": 0.0,
	"feel": {},              # juice the sender should add (play_hit spec keys; pop carries "pitch")
	"weight": "light",       # the profile's weight and material (HitJuice turns the material into
	"material": "worm",      # the spark tint, the debris and the material cue)
	# when they apply: "move" (break-free: push | counter-slash | hop-back | skitter | skitter-spit),
	# "guarded", "poise_broken", "damage_taken", "gate", "slide_px", "killed", "override"
}
```

`decide` runs the plan's order: clink (an immune class, or a shut part gate; a gated daze or
knockdown still lands with 0 damage), the wake guard and break-free armor, the phase's armor, the
class verb (`byTag`, then the phase's classes, then the enemy's, then the weight's defaults), poise
(refills after a delay; a break plays `breakVerb`; a class's armor drains it, a phase's armor such
as the Clod's crouch and hop does not, so no poise break plays while it stomps), the owner's rule
(a non-last knockback or launch becomes a hold), the hold cap (the hold after `holdCap` becomes the
break-free move), then the memory (the longer stun wins, the wake guard, launch bookkeeping). A
chain's first step re-arms the wall splat (`splats_this_chain`) only on a free enemy (no stun in
force, no wake guard): a chain started in a splat's daze cannot splat it again. A hit whose stun is
shorter than the one in force keeps the running FALL, DAZE, TUMBLE or WOBBLE motion (a jab on a
downed enemy does not pop it upright); its flash and number still show. The sender reads
`result.reaction` after `route()` returns and plays the slime's recoil and the feel once per swing.
A clink answers from `can_receive_damage` (`{"accepted": false, "reason": "immune"}`, no commit, the
enemy shakes); the sender plays the clink and the slime recoils.

Every accepted hit whose verb is not armor or clink (holds included; `HitReaction.STUN_VERBS`)
cancels the enemy's running swing, shot or lunge before its impact (`cancel_attack`: an impact that
has not landed is dropped; the cooldown still counts from the swing's start) and stops it for the
whole stun: until the stun ends `enemy.gd` `_step_enemy` only slides it (no chase, territory, new
attack or clip change). Light and medium enemies have no wind-up armor (2026-10-12: the worm
swordsman's and the worm brawler's were removed); only heavy enemies and bosses absorb hits as
armor. The hold count clears once the enemy has stood free `combat.rules.holdResetFreeMs` (300)
after its last counted hold **ended** (`ReactionState.hold_until_ms`; measured from the hold's end,
so long holds cannot hide a spaced-jab lock); a wall splat's daze also cancels the attack. Shots
already fired (arrows, webs, spit) keep flying.

For rework hits the enemy flashes (GameFeel's white-then-tint `flash_hit`) but shows no old "-N"
number: the sender's `GameFeel.play_hit` shows it (with the Damage numbers setting). A 0-damage
rework hit emits no `damaged` (no hurt sound). A training dummy plays no DummyHit cue for a rework
hit (the swing's feel plays the one hit sound). Bowling (`after_move`) needs the launched body to
move into a standing enemy at `combat.rules.bowling.minSpeed` or more; a body still flying from a
launch is never bowled again, so a crowd cannot bowl itself in a loop. In the rework mode a reaction
stun (a hold, a stagger, a knockdown) holds the Clod Stomper's next stomp back until it ends, and a
dazed Clod's knockback slides it.

**Bosses:** Fatty (`fatty.gd`) and the Matron (`matron.gd`) keep their own `_react_to_damage`;
`enemy.gd` `commit_damage` then calls `EnemyReactions.react_override` (the reaction is decided and
written, only its motion plays: no stun, shove or attack cancel from it). In the rework mode
Fatty's Eye hurtbox registers without `acceptedSources` (the part gate decides for rework hits; old
hits still meet the rule in `can_receive_damage`). Base `reaction_phase()` returns the script's
`get_phase()` when it has one (Fatty, the Matron, the Clod Stomper), else "windup" during an
attack's wind-up, else "".

## Juice (the feel API)

`Services.feel()` (GameFeel) gains, without changing the old functions:

```gdscript
var show_damage_numbers: bool = true   # GameSettings `damage_numbers` (apply_to_feel)
func play_hit(spec: Dictionary, world_position: Vector2, direction: Vector2) -> void
func add_trauma(amount: float, direction: Vector2 = Vector2.ZERO) -> void
func kick(px: float, direction: Vector2) -> void       # the picture jolts px screen px along direction, eases back
func room_clear() -> void                               # music dip, freeze, stutter slow motion
func room_clear_scaled(length_scale: float) -> void     # room_clear with every length x length_scale (the demo's shown replay)
func is_stuttering() -> bool
func flash_hit(visual: CanvasItem, big: bool = false, tint: Color = HitFlash.HURT_TINT) -> void
func burst(preset: StringName, world_position: Vector2, direction := Vector2.ZERO, tint := Color.WHITE, count_scale := 1.0) -> void
func show_damage_number(world_position: Vector2, damage: int, big: bool) -> void
func show_damage_number_scaled(world_position: Vector2, damage: int, big: bool, length_scale: float) -> void  # pop and life x length_scale
func picture_speed() -> float      # rework: 0.08 in a hit-stop, the stutter's share (1/3) in the room clear, else 1 (always 1 with the mode off)
func squash_scale() -> float       # 0 with the squash switch off, 0.35 under reduce motion, else 1
func jitter_allowed() -> bool
func juice_layer_on(layer: StringName) -> bool
```

`play_hit` spec keys: `hit_stop_ms` (missing = the old `hit` preset's 65 ms, so per-target calls
pass 0; capped at `combat.chain.hitStop.capMs`), `trauma`, `kick_px`, `sparks` (a count),
`spark_preset`, `tint`, `pitch`, `sound_cue`, `number`, `number_big`; optional `flash_visuals` /
`flash_big` / `flash_tint`, `impact_ring`, `debris_preset` / `debris_tint` / `debris_scale`, `dust`,
`material_cue`, `thump_cue`. Order: freeze, trauma, kick, flash, particles, sounds (the impact cue
at `pitch` ±3 %), number. A sender calls it once per swing with the whole spec and once per other
target with the freeze, trauma, kick and sounds zeroed (ShapeStrike.feel_swing, the thrown object).

`res://game/feel/hit_juice.gd` (static) builds the spec:

```gdscript
static func swing_spec(step: Dictionary, hit: Dictionary, reactions: Array[Dictionary], damage: int, targets: int, killed: bool) -> Dictionary
static func hit_stop_ms(base_ms: float, targets: int, killed: bool) -> float  # + extra targets (capped), + kill, cap
static func number_spec(damage: int, hit: Dictionary) -> Dictionary          # {"number", "number_big"}
static func is_big(hit: Dictionary) -> bool                                  # class in combat.damageNumbers.bigClasses
static func material_spec(material: String, big: bool) -> Dictionary
static func clink_spec() -> Dictionary
static func whiff_spec(spec: Dictionary) -> Dictionary
static func layer_on(layer: StringName) -> bool                              # dev switches (always true with the mode off)
```

`swing_spec` reads the step's `hitStopMs`, `trauma`, `kickPx`, `sparks`, `pitch`, `soundCue`
(default "": the sender picks its impact cue), `impactRing`, `thump`, `debris`; big classes get the
finisher sparks and the long flash; each reaction's `feel` merges over the spec, and its material
(`feel.material`, else `reaction.material`) through `MATERIAL_FEEL` (goo, worm, chitin, mud, stone,
silk, straw, wood). The goo material's debris is the painted `goo-splat-sheet` flipbook
(`HitJuice.GOO_SPLAT_PRESET`), and since 2026-10-12 it splats on taps too (`tap_debris`, small;
bigger on big hits); the worm keeps its tinted goo-splat drops.

The other parts: `ParticleFx.emit_burst(preset, position, direction := ZERO, tint := WHITE,
count_scale := 1.0)` and the presets finisher-spark, impact-ring, mud-chunk, stone-chip, silk-tuft,
goo-splat (pools built on first use), plus the painted flipbook `goo-splat-sheet`
(`ParticleFx.FLIPBOOKS`: one pooled Sprite2D plays the 4-frame goo splat, 50 ms a frame, the last
fading over 110 ms, 46 px wide at `count_scale` 1 and 31 px at 0.5, turned up to ±18 deg and
mirrored at random, with goo-splat drops at 0.6 of the count scale; on the picture-speed clock, so a
hit-stop holds it; processing only while one plays); `HitFlash.flash_curve(visual, tint, big, white_ms, tint_ms,
white)` (driver `hit_flash_curve.gd`); `FloatingTextLayer.spawn_pop(position, text, color, big,
pop_scale, pop_ms, duration_ms)`; `ParticleFx.set_picture_speed(speed)` and
`FloatingTextLayer.set_picture_speed(speed)` (GameFeel hands them `picture_speed()` every frame);
`HitJuice.key_for_layer(layer)`; `WorldCamera.add_trauma(amount, direction)` / `get_trauma()` /
`kick(px, direction)` (added to the old shake's offset); the cue payload keys `pitch` /
`pitch_randomness` (`sfx_player.gd`); `MusicDirector.dip(db, duration_ms)`. `room_clear` runs when a
boss camp's boss falls in the mode (`boss_camp.gd` `_mark_boss_defeated`).

Dev demos and switches: in the rework mode F9 shows a top-left panel (`juice_dev_panel.gd`, made by
GameFeel the first time the mode is on); while it is open, keys 1-9 and 0 play freeze, flash,
squash, jitter, trauma, kick, sparks, pitch, numbers and slowmo once (`game/feel/juice_demo.gd`: on
the nearest dummy or enemy within `DEMO_REACH_PX` 200 of the slime, else the slime; the current
shape's finisher value, then `SHOWN_DELAY_MS` 600 later the exaggerated replay "shown 4x"; the panel
names what played and why a layer did not show), and Shift + the key switches that layer (session
only; a layer left off keeps a one-line reminder on screen; `HitJuice.key_for_layer(layer)`). The
demos go through the game's own juice functions (switches, reduce motion and the settings apply as
in a hit) and deal no damage. The hit motion follows `squash_scale()` and `jitter_allowed()`.

The freeze holds the whole picture: the hit-stop's tree pause stops the slime, the victims, their
AnimationPlayers, tweens and particles, SimClock and the shapes' drawing; in the rework mode
`GameFeel.picture_speed()` also holds GameFeel's own real-time pictures, the ParticleFx bursts (the
emitters' `speed_scale`) and the floating numbers (their clock), at 0.08 through a hit-stop (a burst
started on the frozen frame still spawns) and at the stutter's share (1/3) through the room clear's
slow motion. The camera's shake and kick, the victim's jitter, the white flash and the full charge
ring's pulse keep real time (they are how the freeze reads). With the mode off they all run as
before.

Settings: "Damage numbers" (GameSettings `damage_numbers`, on by default; the Settings window shows
its row only in the rework mode). Reduce motion means no freeze, shake, kick or stutter, and the
squash at 35 %; the screen-shake slider scales the trauma and the kick.

## API by part

A module may add functions in its own files; changing a signature listed here means updating this
page and every caller.

### Shapes: `res://game/shapes/shape_controller.gd` (extends Node)

Made by main.gd (`ShapeController.new()`, child "ShapeController" of the player root,
`setup(player)`, `player.set_shapes(it)`), again on every world build. player.gd calls it only in
the rework mode.

```gdscript
signal shape_changed(payload: Dictionary)          # {"shape_id": String}
func setup(player: PlayerScript) -> void           # the last shape used, else the first learned; makes ShapeVisuals and the ShapeHitbox
func update(now_ms: float, delta: float) -> void   # every physics step while alive (player.gd)
func press_attack(aim: Vector2) -> bool            # aim = the strike aim (player.get_strike_aim) or ZERO (= the facing); fires on the release
func drop_press() -> void                          # forgets the press not let go yet and drains the ring (player.gd clear_input)
func cycle(step: int) -> void                      # +1 / -1, wrapping through the learned shapes
func current_shape_id() -> StringName
func learned_shape_ids() -> Array[StringName]      # ShapeDefs.IDS order, from RunState
func set_current(id: StringName) -> bool           # learned only; resets the chain ("switch"), plays the switch cue
func is_busy() -> bool                             # a step or charge runs: the slime does not walk
func is_charging() -> bool                         # the charge ring fills or waits full
func walk_scale() -> float                         # combat.chain.chargeWalkScale while is_charging(), else 1 (player.gd _move)
func held_pose_clip() -> String                    # the charge ring's held pose: the Spear's and the Hammer's charge strike's hold "strikes/<strike>-<direction>-hold" (the frame its animation starts on), the Axe's load pose (a base clip the player plays for its facing), else ""; player.gd _locomotion_clip
func charge_progress() -> float                    # 0..1, -1 when no ring
func next_step_number() -> int                     # 1-based step the next press starts
func step_velocity() -> Vector2                    # the body's velocity while busy
func reset_chain(reason: String) -> void           # "hurt", "death", "roll", "ability", "mouth", "stopped", "switch", "clink"
func reaches(aim: Vector2, area: Area2D) -> bool   # the next step's whole area (click and moba attack orders)
```

- `press_attack` only records the press (its time and aim; owner, 2026-10-12: attacks fire on the
  release) and returns true when it is taken, false when it is dropped (no shape, dead, or in a
  step's wind-up before its first active frame). `update` reads the hold: let go before
  `combat.chain.chargeStartMs` it is a **tap**, which starts the next step at once, or waits for
  the running step's cancel point (or fires at once when it comes after the cancel point while the
  recovery still plays), a charge's end or the rest; the link window is judged at the tap's press.
  Held `chargeStartMs` it arms the charge ring instead (nothing strikes): the ring fills after the
  running step (after the rest for a finisher); let go when full it fires the charge and spends
  its energy, let go earlier it drains with no attack and no energy. Click and moba attack orders
  mark a press with no held state, so they are taps on the next physics step and cannot charge.
- A chain's last step loads (`anticipation`): through its wind-up `update` puts
  `ShapeVisuals.art_pose(data, t, aim)` on the player's effects channel (`set_effect_offset`, and
  `set_effect_scale` softened by `GameFeel.squash_scale()` until the contact frame, and by
  `ShapePoses.squash_share()`, 0 on the strike frames); it waits while an ability owns the
  channel, and the body never rises.
- Strike frames and drawn poses (`ShapePoses`, [Art](#art-2026-10-12)): `_begin_unit` starts them
  (`begin`; with neither a strike animation nor poses for the step it plays `attack-1`), the contact
  frame advances them before its hits, `update` every physics step (the strike's seek, the Spin's
  swaps), and `_end_unit` and `reset_chain` finish them; nothing is played on an end or a cancel. When `begin` shows strike
  frames, `_begin_unit` hits and draws with a copy of the step's numbers carrying the strike, its
  direction, `strikeMirrored` (a left side strike) and, for the Spear's line, `lineFrom`
  (`_with_strike`: the full lean's socket from the slime's centre, mirrored for left). Every chain
  step's copy hits with its strike file's `hit_reach` in the strike's direction (`StrikeLibrary.chain_hit`:
  the Spear's `reach`, the Axe's `radius`, the Hammer's `offset`; a missing file or reach is a
  `push_error`, and the step keeps only the numbers game-constants.json gives it), measured from its
  `hit_center` (`hitCenter`, mirrored as the strip shows: every area, the impact, the knock's origin and the
  Spear's wall ray start there, `ShapeStrike.hit_offset`); a charge keeps its own numbers. `reaches()`
  asks the same, so a click order's reach matches the drawn weapon. On those
  frames no strike squash plays (`_squash_strike` skips while
  `ShapePoses.shows_strike_frames()`).
- `cycle` during a strike waits for the step's cancel point, or for a charge's end; a switch never
  aborts a strike (a wind-up, a finisher or a paid charge always plays out). An attack press that
  waited with it starts the new shape's first step.
- `step_velocity`: `stepPx` over `stepFromMs`..`stepToMs` (default the wind-up and active window);
  `finisherRecoilPx` over the recovery after a finisher landed; the Lunge's `dashPx` in `dashMs`.
  The controller never moves the body itself and never calls `player.stop_movement()` (that resets the chain); it reads the hold
  with `player.is_action_held(&"attack")`, and recoils (clink 24 px, reaction recoils) through
  `player.recoil` (the knockback's movement and shrug-offs, without the hurt clip).
- Aims come from the slime's centre, where every area, the wall ray and the drawing start: a press
  and a charge's release use `player.get_strike_aim()` (the pointer from `get_centre()`, the pointer
  aim's dead zone; the old `_pointer_aim` rises `aim_rise_px` 28 first), the click and moba attack
  order aims from `get_centre()` at the target's hurtbox. A charge aims where the pointer is at the
  release (else the facing); the slime may walk while the ring fills, at `walk_scale()`; a Hammer
  impact in the Stone form calls `player.record_slam`.

`res://game/shapes/shape_defs.gd` (static): `SPEAR`, `AXE`, `HAMMER`, `IDS`, `NAMES`, `AIM_EXACT`,
`AIM_SNAP8`, `AREA_LINE`, `AREA_ARC`, `AREA_CIRCLE`, `AREA_NONE`, `KNOCK_AIM`, `KNOCK_SWEEP`,
`KNOCK_RADIAL`, `SWEEP_CCW`, `HARVEST_PREFIX`; `is_shape(id)`, `short_name(id)`, `id_for(short)`,
`definition(id)`, `title(id)`, `tags(id)`, `base_damage(id)`, `chain(id)`, `step(id, index)`,
`step_count(id)`, `charge(id)`, `charge_ticks(charge)`, `rest_ms(id)`, `chain_number(key)`
(`combat.chain.<key>`), `damage(id, scale)`, `num(data, key, fallback := 0.0)`, `length_ms(data)`,
`cancel_ms(data)`, `walk_cancel(data)`, `step_from_ms(data)`, `step_to_ms(data)`,
`anticipation(data) -> Dictionary`, `side_px(data)`, `is_chop(data) -> bool`, `area_kind(data)` (a line
by its `reach` or `minReach`, since a chain step's reach is in its strike file),
`impact_only(data)`, `contact_start_ms(data)`, `contact_end_ms(data)`, `ring_of(data)`, `hold_ms(id, index, contact_ms)`,
`charge_hold_ms(charge, contact_ms)`, `tick_hold_ms(charge, index)`, `aim_mode(id)`, `line_check(id)`,
`snap8(v)`, `snap4(v)` (`AIM_SNAP4`), `aim_for(id, v)` (by `aim_mode`: exact, snap8 or snap4),
`target_modifier(id, target_tags)`, `harvest_tags(id, form_id)`,
`request_tags(id, form_id)`, `crit_chance()`, `crit_multiplier()`.

`res://game/shapes/shape_strike.gd` (static; only the shapes module calls it):

```gdscript
static func make_hit(shape_id: StringName, step: Dictionary, step_number: int, last: bool, hold_ms: float, knock: Vector2) -> Dictionary
static func request_for(source: Object, shape_id: StringName, hit: Dictionary, attack_area: Area2D, target_area: Area2D, activation_id: int, damage: float, impact_position: Vector2) -> Dictionary
```

Plus `hitbox_of(player)` (the slime's layerless ShapeHitbox, body meta `shape_hitbox`),
`layer_bit(name)`, `wall_reach(player, origin, aim, reach, shift := Vector2.ZERO)` (the ray is cast from
the slime's feet moved by `shift`, the hit centre, where walls and prop footprints lie, and passes through any
body that owns a registered hurtbox: a dummy, a tree, a rock; the distance along the aim applies to the line from
`origin` moved the same way), `hurtbox_point(area)` (the hurtbox's first enabled shape's centre: where a hit, its
knock, sparks, debris and number land), `hit_offset(data)` (the step's `ShapeStrikes.HIT_CENTER_KEY`, else
zero), `impact_centre(data, origin, aim)` (`offset` ahead of the hit centre),
`area_shapes(data, origin, aim, reach, sweep_sign, progress := 1.0)` (every kind measured from the hit centre,
`origin` + `hit_offset(data)`; a line's `sidePx` beside the
aim on the sweep sign's side; a line whose data carries `lineFrom` (`ShapeStrikes.LINE_FROM_KEY`, the
Spear's strike frames) starts at that socket, px from `origin`, and runs along the aim to `reach`
measured along it, with no `minReach` or `sidePx`; a `chop` arc's whole sector at once; a 360 deg arc
with progress < 1 swept round from the aim, the Spin), `ring_shapes(ring, centre)`,
`areas_in(player, shapes)`, `targets_in(player, shapes)`, `knock_for(mode, aim, from, to,
sweep_sign)`, `damage_for(shape_id, scale, crit_factor, target_tags)`, `deliver(player, shape_id,
hit, activation_id, target, damage)`, `is_clink(result, resource)` and `feel_swing(data, outcomes,
first, crit, aim)` -> {hits, landed, clink, clink_point, killed, recoil_px}; a clink plays
`HitJuice.clink_spec()` (3 white sparks, the high tick at pitch 1.5; a resource's clink is silent
there). Outcomes are {receiver, area, position (`hurtbox_point`), result, hit, tags}. The play_hit
spec also carries `impact_ring` and `thump`.

`res://game/shapes/shape_visuals.gd` (extends Node2D; only the controller calls it): `setup(player)`
(puts a GooRing "ShapeChargeRing" at index 0 of the player body), `show_step(shape_id, step, aim,
duration_ms)` (the step may carry `reach` and `sweepSign`), `show_charge(shape_id, progress)`
(progress < 0 hides the ring), `drain_charge(duration_ms)`, `show_impact(world_centre, radius,
ring_radius)`, `show_chop()` (the Axe chop's small shock ring and dust, no crack),
`show_clink(world_point)`, `clear()` (the strike only; the ring stays), and
`static art_pose(data, t, aim) -> Dictionary` ({"offset", "scale"}: a last step's pull-back and
squash, its spring into the strike and the chop's `jumpPx` hop landing on the contact frame; the
controller applies it). It processes during pauses (PROCESS_MODE_ALWAYS) on the gameplay clock, so
a hit-stop's frozen frame shows the contact pose. It draws the painted art of 2026-10-12
([Art](#art-2026-10-12)) on three canvas items, in this order: the node itself (the code speed
streaks), its child "ShapeWeapon" (the Spin's swoosh and axe, in the Gulp form's skin) and its child
"ShapeOver" (the glints, the shock rings and the clinks), so the streaks lie under the weapon and
the glint and the clink over it. A strike on its strike animation is drawn by the player's
StrikeRig (below); on those steps this node draws only the Spear's speed streaks beside the spear on
the lunge frame, its pierce glint at the hit line's end (26 px; 34 for the finisher and the Lunge;
90 ms) and the finisher's load glint at the body's front (18 px), and the hit effects; it sits behind
the Visual and ShapeOver draws at z 1, over the world. `show_step` reads the
strike's keys (`ShapeStrikes.STRIKE_KEY`, `DIRECTION_KEY`, `MIRRORED_KEY`, the Spear's
`LINE_FROM_KEY`) from the step the controller hands it and gives the rig the Spear's wall-cut reach;
`_apply_skin` gives the rig's three canvas items its skin material and the rig the form's tint. The
Axe's Spin, the one strike without a strike animation, is this node's: axe.webp from its haft's root
(12 px out) with its head's middle where the hit's arc is swept (0.76 of the radius) and its tip at
the hit radius, the haft stretched between, all round from the aim linearly with the hit's arc,
trailed by the painted swoosh bent onto the swept arc (0.42 to 1.05 of the radius, its bright end at
the head), mirrored with the swing's sign (the head is double-bladed, so a blade always leads); up
aims draw it behind the slime (z 0), the rest in front of the world (z 1). The weapon layer wears its own ShaderMaterial on
`form_skin.gdshader` with the form's `skin` (none without a form; drawn in the slime sheet's
texture px, `SKIN_UNIT_PX`, so the pattern is as big as on the slime), not the Visual's material,
so the weapon is never ghosted behind higher ground or cut by the swim waterline, and it does not
flash with the slime's hurt flash; where the Visual has no skin shader it takes the form's tint. A
step whose strike file is missing draws no weapon (the old drawn spear, hammer and chop are gone,
2026-10-14). An impact's dust is small
`dodge-dust` puffs (one at the centre, and for a wider hit up to five on a ring 40 px inside its
edge), about as wide as the hit.

`res://game/shapes/shape_poses.gd` (extends RefCounted; only the controller uses it):
`setup(player)`, `begin(shape_id, data, aim) -> bool` (false: neither strike frames nor poses, the
controller plays `attack-1`; the strike frames first, where `strike_frames_for` finds them), `advance(elapsed_ms)`,
`finish()`, `squash_share()` (`STRIKE_SQUASH_SHARE` 0 on the strike frames: the anticipation's code
squash goes, its pull-back and hop stay; else 1), `strike_frames_for(shape_id, data, aim) -> String` (the strike when the manifest has
its strip in the aim's direction with what it draws, `ShapeStrikes.is_complete`, and the player has
its strike animation; else ""), `strike_id()`, `shows_strike_frames()` (the controller skips its strike
squash then); static `timeline_of(short, data)`, `pose_at(short, data, elapsed)`, `direction_of(aim)`
(the player's 3-way rule; the exact diagonals side, `DIAGONAL_EPSILON`), `mirrors(aim)` (a side
strike to the left), `clip_name(short, pose, direction)`, `ring_clip(shape_id)` (`shape-<shape>-load`;
the scene has the Axe's only). On a strike
animation `advance` seeks `strikes/<strike>-<direction>` at the elapsed time mapped to its 0-3 time
(`PlayerScript.seek_strike_animation`, `StrikeLibrary.unit_at`), hands the rig the strike file, its direction,
the clock and the step's timing (`finish` takes the clock back), and while the Visual shows the strike's sheet on its strip's
row pins the Visual's offset (-origin) and
flip (`ShapeStrikes.shown_flipped`: a left side strike, or a mirrored strip such as the backswing's
front and back) on every call. `TIMELINES` keys the Spin's charge `id` (the only one left) to [from,
pose] entries (from: start, contact, recovery; its `spin` pose swaps `SPIN_POSES` `SPIN_SWAPS`
times over its active window). Poses change at the wind-up's start, the contact frame (before the
hit-stop) and the recovery; once the strike ends or is cancelled the player plays idle or walk
again.

`res://game/shapes/shape_strikes.gd` (static, extends RefCounted; presentation only: the art of the
strike frames, not their motion): `manifest()` (`game/data/shape-strikes.json`, read once; {} when
missing), `strike_for(short, data)` (`STRIKES`: the step's or charge's `id` -> "spear-jab",
"spear-finisher", "axe-sweep", "axe-backswing", "axe-chop", "hammer-thud", "hammer-boom" (the BOOM and
the Quake); "" for none, the Spin), `animation_name(strike, direction)` (`<strike>-<direction>` in the
`strikes` library, `ANIMATION_LIBRARY`), `hold_name(strike, direction)` (`<strike>-<direction>-hold`,
`HOLD_SUFFIX`: its first frame held, the charge ring's), `strike_entry(strike)`, `strip(strike, direction)`,
`row(strike, direction)`, `frame(strike, direction, number)` (a strip without `frames` reads its `source`
strike's), `shaft_px(strike)`, `knob_w(strike, direction, number)`, `is_complete(strike, direction)` (a
row, and for the Axe and the Hammer their weapon block and the neck), `weapon_block(name)`, `neck()`,
`view_frame_of(weapon_name, view, number)` (a weapon view's frame: {"texture", "scale", "rect",
"pivot", "head", "dir"}), `apply_hit_reach(data, hit_reach)` (a copy hitting with it: an arc's radius,
a circle's offset, a line's reach), `shown_flipped(strip_flipped, mirrored)`,
`cell_point(frame_entry, key)` (`SOCKET`, or another point a frame gives), `socket_game(strike, direction,
number, mirrored)`, `texture_path(strike := "")`, `origin()`, `tint_gain()`,
`gain_of(block)`, `shows_strip(visual, strike, direction)` and `shown_frame(visual, strike, direction,
flipped)` (the frame 1-6 a Sprite2D shows of that strip with that flip; 0 for anything else). Consts
`COLUMNS` 8, `FRAME_LEAN` 2, `FRAME_LUNGE` 3, `KNOB_W`,
and the keys the controller adds to a copy of a step's numbers: `STRIKE_KEY` ("strike"),
`DIRECTION_KEY` ("strikeDirection"), `MIRRORED_KEY` ("strikeMirrored", a left side strike),
`LINE_FROM_KEY` ("lineFrom", a Vector2; lines only), and `HIT_CENTER_KEY` ("hitCenter", a Vector2: a chain
step's hit centre, StrikeLibrary.chain_hit). The key timelines left it in round 3 and the strike files in round 4
(`game/characters/strikes/`).

`res://game/shapes/strike_rig.gd` (@tool, extends Node2D; the player scene's `Visual/StrikeRig`, with
its canvas items `Visual/StrikeRigFront` (z 1) and `Visual/StrikeRigNeck`; the strike preview builds the same
three under its own Visuals): plain properties (no exports, so a scene saves none of them), each redrawing when
set: `animation` (a strike file), `direction` (side, down, up), `show_overlay`, `overlay_text` (the readouts drawn
on the overlay; the preview shows them as labels instead), `clock_ms` (< 0: nothing drawn), `timing` (windup,
active, recovery ms; x < 0: the step's own from game-constants.json) and `tint`; also `reach_override` (the
Spear's wall-cut reach), `overlay_in_game` (captures) and `overlay_hot` (`HOT_NONE`, `HOT_CENTRE`, `HOT_RING`:
the preview's handle under the pointer, drawn larger). It never changes its Visual (since round 5: the game's
strike animation sets the body frame, the preview its own Visual). In the game it also redraws every frame while
active; in the editor only its setters redraw it. A direction's `arm_px` is the drawn reach: positive stretches
the neck's tube, negative slides the weapon back into the jelly by that many px (both grow with the length), its
hidden end cut as with a shorter length. `is_active()` (a strike set and the clock running), `visual()`,
`state_now()` and `state_at_ms(elapsed, timing)` (StrikeLibrary.state_at, with the frame's socket,
`StrikeLibrary.socket`, and knob), `geometry_of(state)`, `body_edge(aim)`, `overlay_numbers()` ({"edge", "tip",
"far", "elapsed", "live"}: game px along the aim from the slime's centre; "aim", "centre" (the hit centre as
shown), "handle" (the ring's point along the aim), "ring" (the far edge from the hit centre)) and
`overlay_lines()` (the readouts). The overlay (in the editor, or with `overlay_in_game`) draws the hit area from
the hit centre, the ring round it at the far edge, the hit centre's cross and the ring's handle, the body's edge,
the weapon's tip and the socket (a pink dot). The Spear's drawn length runs to the hit line's end (the reach
from the hit centre). A step where the painted view or its frame changes never starts a swoosh (the head jumps
there; the swing's own steps still draw it). Static `art(shape)` (spear.webp, axe.webp,
hammer.webp and shapes.json: ShapeVisuals' Spin axe uses it too), `manifest_texture(path)`,
`slice_on_axis(...)`, `draw_swoosh(canvas, inner, outer, color, offset)`. Consts `NODE_NAME`, `FRONT_NODE`,
`NECK_NODE`, the drawing's numbers (moved from ShapeVisuals: `WEAPON_AXIS_ROWS`, `HEAD_COLLAR_TX`,
`NECK_GROW_SHARE`, `NECK_MIN_ACROSS`, the swoosh's `SWOOSH_*`, `SPEAR_MIN_EXTRA_PX`, `ROOT_FLARE_TX`) and the
overlay's colours.

`res://game/shapes/strike_library.gd` (static, preloaded; no `class_name`): the strike files and what they
show. `animation(strike)` (the file `game/characters/strikes/<strike>.tres`, loaded once; `STRIKES`,
`DIRECTIONS`), `direction_of(resource, name)`, `key_unit(key)` (a key's 0-3 time), `strike_of(resource)`,
`step_data(resource)` and `timing_of(resource)` (the step's numbers and its windup, active and recovery ms,
game-constants.json read directly so the editor needs no autoload), `unit_at(elapsed_ms, timing)`,
`state_at(resource, direction, elapsed_ms, timing)` and `state_at_unit(resource, direction, unit)` ({"frame",
"angle", "length", "head_angle", "layer", "view", "view_frame", "flip_h", "arm_px", "hit_reach", "hit_center", the
Spear's numbers}), `socket(resource, direction, number)` (the manifest's socket of frame 1-6 plus the direction's
`socket_nudge`, game px, unmirrored), `contact_socket(resource, direction)` (at the windup's end),
`hit_reach(resource, direction)`, `hit_center(resource, direction)` (unmirrored) and
`shown_hit_center(resource, direction, mirrored)` (x mirrored while the strip shows flipped),
`chain_hit(short, data, direction, mirrored := false)` (a chain step's numbers hitting with its strike's
`hit_reach` in that direction, measured from its shown `hit_center`, `ShapeStrikes.HIT_CENTER_KEY`; a missing file
or reach is a `push_error`, once per strike and direction), `flip_h(resource, direction)`, `build_library()` and
`install(player)` (the player's `strikes` library, built at run time: each strike and direction's animation and,
but for a mirrored strip, its hold `<strike>-<direction>-hold`, the frame it starts on with its sheet and offset,
one step long, keying no mirror; a missing file is a `push_error`). The three
resource scripts `strike_animation.gd` (`StrikeAnimation`: `shape`, `step`, `side`, `down`, `up`, `of(name)`),
`strike_direction.gd` (`StrikeDirection`: `hit_reach`, `hit_center`, `arm_px`, `socket_nudge` (6 x Vector2),
`flip_h`, `spear_inside`, `spear_fade`, `spear_shaft`, `keys`)
and `strike_key.gd` (`StrikeKey`: `phase`, `share`, `frame`, `angle`, `length`, `layer`, `view`, `view_frame`,
`head_angle`, `jump`, `unit()`) are @tool with a `class_name` for the Inspector.

`res://addons/strike_preview/` (editor plugin "Strike Preview", enabled in `project.godot` next to godot_ai):
`plugin.gd` adds `strike_inspector.gd`, an EditorInspectorPlugin that puts `strike_preview.gd` (a @tool
VBoxContainer) above a StrikeAnimation's fields. The preview: a Play / Pause button, the time bar (the bands and
every key; a click or drag sets the time and pauses), and three views (side, down, up), each a SubViewport with
a Sprite2D Visual at the player scene's scale (`VISUAL_SCALE`), its body frame and mirror from
`StrikeLibrary.state_at` on the step's timing, and the rig's three nodes under it; the three views are equally tall
and share one zoom (the largest that fits each, the body at least `BODY_SCREEN_PX`, 130, tall), so the slime and its
reach have the same size on screen in each, the slime anchored per view so the weapon fits; under each view the
rig's `overlay_numbers()` in words (past the body first and
larger). In a view a press within `GRAB_PX` of the hit centre's cross or the ring's handle starts a drag (the
strike pauses): the cross sets the direction's `hit_center` under the pointer, the handle its `hit_reach` (the
Hammer's less its circle), live and snapped to `SNAP_PX`; the release puts the start and end values into the
editor's undo history (`EditorInterface.get_editor_undo_redo()`: one action per drag, so Ctrl+Z undoes it and Ctrl+S
saves the file). It checks the file every frame (`_values_hash`, with the handles' state); after any change it
redraws the rig's nodes and renders the views for `REFRESH_FRAMES` (6) frames (`UPDATE_ALWAYS`, then back to
`UPDATE_WHEN_VISIBLE`), because the editor in its low-processor mode may draw only once after an edit; a paused,
unchanged preview lets the editor idle. It writes nothing else; the time and play state survive the Inspector's
rebuilds (`_remembered`).

### Shared ring: `res://game/shapes/goo_ring.gd` (extends Node2D)

`@export radius_px`, `thickness_px`, `color`, `track_alpha`, `fill_span` (TAU: the share of the
circle a full fill covers) and `fill_both_ways` (false: clockwise from the top; true: both ways from
the top, centred on it); `set_progress(t: float)`,
`get_progress() -> float`, `set_color(c: Color)`, `set_radius(px: float)`,
`set_thickness(px: float)`, `drain(duration_ms: float)` (real time, then hides),
`is_draining() -> bool`; `show()` / `hide()` are CanvasItem's. The owner adds it where it sits.

### Reactions

```gdscript
# res://game/combat/reactions/enemy_reactions.gd (static; every enemy call is has_method-guarded)
static func react(enemy: Node, commit: Dictionary, is_dead: bool) -> void          # writes result.reaction; old requests: react_classic
static func react_override(enemy: Node, commit: Dictionary, is_dead: bool) -> void # bosses: reaction + motion only, reaction.override = true
static func can_receive(enemy: Node, input: Dictionary) -> Dictionary             # {"accepted", "reason"}; a clink answers "immune"
static func damage_scale(enemy: Node, input: Dictionary) -> float                 # the gate's 0, the part's, phase's, knockdown's damageTaken
static func is_gated(enemy: Node, area: Area2D) -> bool                           # the hurtbox is a part the profile gates
static func after_move(enemy: Node, delta: float) -> void                         # rework mode: wall splat, bowling
static func on_defeated(enemy: Node) -> void                                      # rework mode: death puff, energy shard roll
static func state_of(enemy: Node) -> ReactionState                                # enemy meta "reaction_state"
static func motion_of(enemy: Node) -> EnemyHitMotion                              # child "HitMotion" of the script node
static func slide_decay() -> float
static func speed_for_distance(px: float, ms: float) -> float
# consts STATE_META, MOTION_NODE, PART_META ("reaction_part": a hurtbox's part, default its node name in snake_case)

# res://game/combat/reactions/hit_reaction.gd (static)
static func decide(profile: Dictionary, hit: Dictionary, state: RefCounted, now_ms: float) -> Dictionary  # writes the state (set state.phase / state.part first)
static func preview(profile: Dictionary, hit: Dictionary, state: RefCounted, now_ms: float) -> Dictionary # decide on a copy
static func gate(profile: Dictionary, hit: Dictionary, state: RefCounted) -> String                      # GATE_OPEN | GATE_CLINK | GATE_ZERO
static func damage_scale(profile: Dictionary, hit: Dictionary, state: RefCounted, now_ms: float) -> float
static func phase_entry(profile: Dictionary, phase: String) -> Dictionary
static func part_entry(profile: Dictionary, part: String) -> Dictionary
static func part_open(part: Dictionary, hit: Dictionary, phase: String) -> bool
static func class_entry(profile: Dictionary, hit: Dictionary, phase: Dictionary) -> Dictionary
static func reaction(verb: String, stun_ms := 0.0, slime := "none", recoil_px := 0.0, feel := {}) -> Dictionary
# consts VERB_* (incl. PULLED, RESIST, BOWL, BONK, BREAK, POP, BREAK_FREE), SLIME_*, GATE_*, MOVE_PUSH,
# MOVE_COUNTER ("counter-slash"), MOVE_HOP_BACK, MOVE_SKITTER, MOVE_SKITTER_SPIT, MOVING_VERBS, WAKE_VERBS, STUN_VERBS

# res://game/combat/reactions/reaction_profile.gd (static)
static func for_enemy(enemy: Node) -> Dictionary   # weights -> enemy-types reactions -> reaction_overrides; a dummy's preset
static func for_type(type_id: String) -> Dictionary
static func for_preset(weight: String) -> Dictionary
static func type_of(enemy: Node) -> String         # enemy_type, else the scene file name
static func merge(base: Dictionary, over: Dictionary) -> Dictionary
static func clear_cache() -> void
```

`reaction_state.gd` (extends RefCounted): `hold_count`, `last_hold_ms`, `hold_until_ms` (when the
enemy is free of its last counted hold), `wake_until_ms`,
`armor_until_ms`, `poise` (< 0 until filled), `last_hit_ms`, `verb`, `stun_until_ms`,
`damage_taken`, `launched_at_ms`, `launch_until_ms`, `launch_damage`, `launch_layer`, `bowled`,
`splats_this_chain`, `windup_sequence`, `windup_pushed_ms`, `phase`, `part`; `in_stun(now_ms,
of_verb := "")`, `copy()`, `reset()`.

`res://game/feel/enemy_hit_motion.gd` (extends Node, PROCESS_MODE_ALWAYS, process_priority 100):
motions `NUDGE`, `SQUASH`, `TUMBLE`, `FLATTEN`, `BOUNCE`, `JITTER`, `SPLAT`, `WOBBLE`, `LEAN`,
`FALL`, `DAZE`; `setup(visual: Sprite2D)`, `play(motion, direction := ZERO, params := {})`,
`is_playing()`, `current() -> StringName`, `stop()` (rest pose), `outline(duration_ms, color)`,
`flash(duration_ms)`, `show_stars(until_sim_ms)`, `hide_stars()` (stars: `game/feel/daze_stars.gd`).
It composes on top of other writers (the Clod's animated scale and rotation) and pauses in freezes,
except the jitter. Its offsets are screen offsets (the turn it writes is undone first, so a tumble's
hop goes up), and the TUMBLE spins the art about its own centre, not the node origin (a dummy's
origin is its feet).

The energy shard, `res://game/combat/reactions/energy_shard.gd` (extends collectible.gd):
`static func spawn(feet: Vector2, energy: float, radius_px: float, lifetime := 0.0) -> Node2D`
(added deferred), exports `amount`, `lifetime_ms`; `request_pickup` restores energy through
`player.restore_energy` and is rejected ("energy-full") while energy is full (step off and on to
retry). It rolls for every defeated enemy in the mode, bosses included, never for dummies; it is not
saved; the Stretch Lash can fetch it. Look: `energy_shard_look.gd`, the painted honey-gold crystal
(energy-shard.webp, 24 px tall) that pops out of the corpse and floats bobbing over a soft shadow,
with a soft glow behind it that swells 18 % and brightens (alpha 0.35 to 0.6) every 1.6 s while the
crystal brightens 12 %, each shard from a random phase; it blinks before it fades.

What `enemy.gd` gives the helper (public, every enemy and boss): exports `enemy_type: String`,
`reaction_overrides: Dictionary`; `get_body()`, `get_visual()`, `set_hit_stun_until(until_ms)`,
`get_hit_stun_until()`, `play_hurt(action := "knockback")`, `show_hit_feedback(commit)`,
`flash_hit()`, `react_classic(commit, is_dead)` (the old reaction), `cancel_attack()`,
`get_centre()`, `is_defeated()`, `get_facing_name()`, `is_facing_flipped()`,
`get_attribute(key, fallback := 0.0)`, `delay_attack(ms)`, `attack_sequence() -> int`,
`begin_counter_attack() -> bool`, `take_reaction_damage(amount) -> int`,
`set_death_slide(velocity)`, `mitigate_damage(input) -> float` (unchanged for old requests),
`reaction_phase() -> String`. The training dummy (`training_dummy.gd`) has `@export
reaction_preset: String`, `@export reaction_overrides: Dictionary`, `@export body: CharacterBody2D`
(null: the scene's static dummy, which nothing moves), `@export return_speed: float`,
`get_visual()`, `get_centre()` (its hurtbox shape's centre), `is_defeated()`, `get_body()`,
`set_hit_stun_until(ms)`, `get_hit_stun_until()`; it calls `EnemyReactions.react(self, commit,
false)` for rework hits, skips its own number, wobble and DummyHit cue for them, never drops a
shard. With a `body` (the shapes testbed's dummies) its `_physics_process` (rework mode) slides the
body while stunned (`slide_decay`), else walks it back to its first position at `return_speed`,
through `ArcadeMover.move`, then `EnemyReactions.after_move` (splats, bowling); `_enemy_of` finds
such a dummy by its body. `ArcadeMover.COLLISION_META` (`&"arcade_collider"`): the
body meta {collider, normal, velocity, frame} of a move's first contact, recorded only in the mode.

### Mouth: `res://game/player/gulp/mouth_hold.gd` (extends RefCounted)

Made by player.gd on first use (`player.get_mouth_hold()`), `setup(player, mouth, gulp)`. What a
press does is decided from the mouth's state when Q goes down:

| Mouth | Q | Result |
|---|---|---|
| empty | press | a suck burst for `suckBurstMs` (held or not); it ends early on a catch, or with a dust puff when nothing was in reach; `burstCooldownMs` blocks a new empty-mouth burst. Essences and liftables only, never live enemies |
| empty, in a form | hold | from `tapMs` (nothing caught or flying in) the spit ring fills ("Spit out Stone"); at `spitHoldMs` the form is spat out whole 44 px ahead ("Ptoo!"); a pull cancels it; over deep water in a swimming form: "Swim back to the shallows first" once |
| a liftable | release | thrown along the aim (`get_gulp_aim`) |
| an essence | tap | spat out whole |
| an essence | hold | from `tapMs` the swallow ring fills in the essence's colour ("Swallow Stone") with a rising throat sound; letting go drains it in `ringCancelMs`; at `swallowHoldMs` `use_ability(swallow)`. "Already Stone", the swim line, or before Swallow is learned "It won't go down yet" replace the ring |

```gdscript
func setup(player: Node, mouth: Mouth, gulp: GulpController) -> void
func press() -> void                          # every `eat` press (also while it roots the slime); ignored during a burst, a finishing pull, or (empty mouth) the cooldown
func step(now_ms: float, held: bool) -> void  # every physics step while alive, instead of Mouth.update (it calls Mouth.update itself)
func roots_player() -> bool                   # a burst or a hold ring runs: no walking, attack/ability/Roll presses dropped
func cancel(reason: String) -> void           # "hit", "knockback", "death" (the ring hides at once), "input-cleared", "sleep", "suppressed"
func ring_progress() -> float                 # 0..1 while a ring fills, else 0
func press_kind() -> String                   # "none" | "empty" | "liftable" | "essence"
func ring_kind() -> String                    # "none" | "swallow" | "spit"
func is_bursting() -> bool
```

Its nodes, made on first use under the body: "MouthRing" (a GooRing at the feet, scale y 0.55,
turned by PI, placed just before Visual; `fill_both_ways` over `RING_VISIBLE_SPAN` 1.45 PI, so the
fill grows both ways from the front over the arc the slime's art leaves visible and never seems to
stall behind it) and "MouthThroat" (an AudioStreamPlayer). `Mouth` gains
`begin_burst(now_ms, duration_ms) -> bool`, `end_burst()` (a pull in flight finishes first),
`is_burst()`, `is_pulling()`; `GulpController` gains `held_by_water()`, and in the mode a swap
leaves the old form's essence whole beside the slime (no `popGrabMs` fade). A hit still pops the
form and drops what the mouth holds, then `cancel("hit")` runs.

The thrown hit (`thrown_object.gd`, mode only): `static func rework_hit(direction: Vector2) ->
Dictionary` (class `gulp.throwHit.class` "thrown", step 0, last, tags ["thrown"], knock along the
throw, launch `gulp.throwKnockback`); the break sends each hurtbox in `gulp.throwHitRadiusPx`
(`AbilityWorld.hurtboxes_at`) one request with the hit and the impact effect, plays
`gulp.throwHit`'s feel once at the break and each target's number at the target, and a clink
(`combat.chain.clink.hitStopMs`, HitBlocked) when nothing took it and a target was immune.

Prompts (`gulp_hud.gd`, mode only): "[Q] Suck", "[Q] Throw", "[Q] Spit out  Hold [Q] Swallow"
("[Q] Spit out" before Swallow is learned); none while `roots_player()`.

player.gd gives it: `get_gulp_aim() -> Vector2`, `face(dir)`, `play_action_clip(clip)`,
`get_centre()`, `is_learned(&"swallow")`, `use_ability(&"swallow")`, `is_movement_suppressed()`,
`held()`, `current_form()`, `get_gulp()`, `get_mouth()`.

### Slam: `res://game/player/abilities/slam_sequence.gd` (rework mode)

The body never moves and never changes level; only the art rises on the effects channel (crouch to
120 ms, rise 96 units to 320, hang to 380, dive to 460, impact at 460, done at 640; the shadow stays
at the feet; poses `squash` then `hop`). At the impact the 140 x 96 ground ellipse on the slime's
own height level (tested at the old centre): the inner half 40 (class slam, launch 380, hop 16),
the outer ring 24 (class ring, bounce held 600 ms in `hit.hold_ms`, launch 300 where a profile
pushes), both +25 % in the Stone form; never resources; `record_slam` as before (cracked ground in
the Stone form); refused hits clink. Feel: `GameFeel.play_hit` at the slime with the per-swing
hit-stop and trauma 0.7 (Stone 0.8) and one material cue (no debris there); each target gets its
number, its material's tinted sparks and its debris at the target, flying away from the slime; a
shockwave ellipse, the crack decal, ground-tinted pebbles and dust, liftables within 200 px wobble.

`PlayerAbilities`: `is_invulnerable()` (the improved Slam's air time, `airborneFromMs` to
`airborneToMs`; player.gd's `can_receive_damage` then answers "state-blocked") and
`ignores_knockback()` (the whole improved Slam; `apply_knockback` returns). Both are false for the
classic Slam, and player.gd reads them only in the mode. `is_airborne()` is unchanged (the Slam is
not a flight, so plates still feel the slime).

`res://game/player/abilities/ability_world.gd` (static):

```gdscript
static func strike_area(player, centre, radius, damage, knockback, weapon_tags, weapon_id := "squash-slam", hit := {}, on_outcome := Callable()) -> int
static func strike_targets(player, centre, targets: Array[Area2D], damage, knockback, weapon_tags, weapon_id := "squash-slam", hit := {}, on_outcome := Callable()) -> int
static func hurtboxes_at(player, centre, radius) -> Array[Area2D]
static func hurtboxes_in_ellipse(player, centre, half_size: Vector2, level := ANY_LEVEL) -> Array[Area2D]
static func ellipse_points(half_size: Vector2, count := ELLIPSE_POINTS) -> PackedVector2Array
static func target_level(area: Area2D, receiver: Object, fallback: int) -> int
static func hit_toward(hit: Dictionary, knock: Vector2) -> Dictionary
static func is_clink(result: Dictionary) -> bool   # rejected "immune", or reaction.verb == "clink"
```

Without `hit` (old callers) a strike is exactly as before (knockback effect, a spark per damaged
target, the `hit` feel once). With `hit`: `effects = []` plus the impact effect, the hit copied per
target with its `knock` filled radially when ZERO, `knockback` ignored, no feel played (the sender
plays it). `on_outcome` gets {receiver, area, position, result} once per routed target.
`AbilityDefinitions` gains `box_sockets()`, `box_socket_count()`, `is_box_ability(id)` and
`REWORK_CEREMONY_HOW`; `AbilityFx` gains `shockwave`, `crack_decal`, `debris`, `ground_tint`,
`wobble_liftables`, `wobble`.

### Ability Box: `res://game/player/abilities/ability_box.gd` (static)

```gdscript
const USE_ACTION := &"ability_use"
static func socket_ids() -> Array[StringName]                 # abilityBox.sockets, in order
static func box_ids(player: Node) -> Array[StringName]        # learned sockets AbilityDefinitions knows (RunState's when player is null)
static func selected(player: Node) -> StringName              # the saved choice if still learned, else the first learned, else &""
static func select(player: Node, id: StringName) -> bool      # learned only; saved in RunState.player.loadout.ability_id, autosave scheduled
static func on_learned(player: Node, id: StringName) -> bool  # a box ability learned (not quietly) becomes the choice (the ability bar calls it)
static func use(player: Node) -> bool                         # the `ability_use` press: player.use_ability(selected); empty box: "Not learned yet"
static func use_count() -> int                                # box abilities started this session
static func key_action(id: StringName) -> StringName          # the action whose key a text names (see Controls)
static func energy_cost(id: StringName) -> float              # AbilityDefinitions'
static func cooldown_ms(id: StringName) -> float
```

### HUD and bag (Ability Box and HUD)

- **Bag window** (`inventory_screen.gd`): in the mode its top band (y 58-188) holds two rows instead
  of the belt: Shapes (a click, or Enter / Space on the focused cell, makes it current:
  ShapeController `set_current`; tagged NOW, with the charge's energy in the corner) and Abilities
  (only learned sockets; a click or accept chooses it: `AbilityBox.select`; tagged "ON F").
  Arrowing onto a cell (from the Close button, the bag or the other row) only shows its card;
  nothing changes until the click or accept. The focused or clicked one's card shows in the details
  panel (`game/ui/body_cards.gd`: `shape_card` / `ability_card`). Public:
  `choose_shape(id)`, `choose_ability(id)`; nodes `content/BodyBand/{ShapesTitle, ShapesHelp,
  Shapes, ShapesEmpty, AbilitiesTitle, AbilitiesHelp, Abilities, AbilitiesEmpty}`.
- **HUD:** the weapon slot is the Shape slot (the current shape's icon, E badge, the charge's cost chip;
  hidden below two learned shapes: `WeaponHotbar.slot_shown()`; a click takes the next shape). The
  ability bar (`AbilityBar.rework_slots`) holds `AbilityBar.BOX_SLOT` ("ability-box": the chosen box
  ability, the `ability_use` badge, a cost chip, the cooldown sweep; hidden while the box is empty;
  a click opens the bag) and the Roll once learned. `HudConsole.layout(viewport, count,
  weapon_shown := true)` and `signal layout_changed`, which `hud.gd` connects to its `_layout`.
  Every part polls the mode and goes back to classic when a world build turns it off.
- **Controls window:** `ControlLabels.rework_rows(scheme)` (`control_rows()` returns it in the mode).
- **Hints:** `ControlHints.REWORK_HINT_IDS` adds charge, mouth, ability and swallow (story flags
  `hint.<id>`) and a rework text for weapon-switch; the charge hint learns from
  `ShapeController.is_charging()`.
- `game/ui/body_cards.gd` (static): `SHAPE_ICONS` (shape id -> res://asset/UI/shapes/<shape>-icon.webp),
  `world_player()`, `shapes_of(player)`, `learned_shapes()`, `current_shape(player)`,
  `set_shape(player, id)`, `shape_icon(id)` (loaded on demand, null for an unknown id; the Shape
  slot, its carousel (`WeaponHotbar._entry_icon`: a model entry's `shape_id`) and the bag's Shapes
  row),
  `ability_icon(id)`, `charge_energy(id)`, `shape_card(id, current)`, `ability_card(id, chosen)`.

### Player hooks (`game/scripts/player.gd`, rework mode only)

- `strike_animation(name)` (the `strikes/<name>` Animation, null without it), `seek_strike_animation(name,
  seconds) -> bool` (assigns it paused the first time, from the Visual's rest offset with its facing's
  flip, then seeks it with an immediate update; refused while dead or during a knockback's clip), and
  `get_strike_rig()` (`Visual/StrikeRig`); const `STRIKE_LIBRARY` "strikes". The `strikes` library itself is
  installed by the shape controller (`StrikeLibrary.install`, from `ShapeController.setup`), not by the scene.

- `set_shapes(shapes)`, `get_shapes()`, `get_mouth_hold()`, `get_gulp_aim()`, `get_strike_aim()`
  (the pointer's aim from `get_centre()`, where the shapes strike from; ZERO without a pointer aim
  or in keys-only), `recoil(direction, strength, duration_ms)` (the knockback's movement, its
  shrug-offs (the improved Slam, the Heavy form) and the Roll cancel, without the hurt clip or its
  priority window).
- Each physics step: `ShapeController.update(now, delta)` after the abilities advance; then
  `MouthHold.step(now, eat held)` instead of `Mouth.update`; in the state machine, after a
  Roll/knockback and before the action lock, `_rework_owns_step()`: the mouth's root (stand,
  drop attack/ability/Roll presses, Q still reaches `press()`), then a busy shape step (velocity
  = `step_velocity()`, presses still reach the controller; interact waits).
- `_handle_rework_action_input`: E / wheel `cycle`, interact, Swallow ignored, old ability keys
  dropped, then `dodge` (the press only arms the Roll, `_roll_press_ms`, and the slime walks on;
  `_due_roll(now)` decides QUICK on the release or CHARGED on a hold past
  `character.player.rework.rollTapMs` with `roll-charge` learned; a release older than
  `input.bufferMs`, the slime busy meanwhile, is dropped; `_try_dodge(charged)` runs
  `PlayerRoll.begin_quick` or `begin(..., launch_on_release = true)`; `reset_chain("roll")`),
  `ability_use` (`AbilityBox.use`; `reset_chain("ability")`), `attack`
  (`press_attack(get_strike_aim())`, which only records the press: the controller strikes on the
  release, read in `update`; a step that starts there owns the body's velocity in the same physics
  step), `eat` (`reset_chain("mouth")`, `MouthHold.press()`). Swimming or holding something drops
  Roll, ability and attack presses. The ability bar's click (`use_ability(dodge)`) is a quick roll.
- `_move` multiplies the walk by `ShapeController.walk_scale()` (half speed while a charge ring
  fills or waits full); `_locomotion_clip` returns `ShapeController.held_pose_clip()` while it is
  not empty (after the swim and full-mouth clips), so the slime stands and walks in its charge's
  strike hold (the Axe's `load` pose) while the ring fills; `_regen_energy` uses
  `character.player.rework.energyRegenPerSecond` (0) in the mode, so energy comes back only from
  shards, items and a respawn.
- Cancels: a hit with damage (`cancel("hit")`, `reset_chain("hurt")`), death, knockback,
  `clear_input` ("input-cleared"; it also calls `ShapeController.drop_press()`, so a cleared Attack
  key never reads as a release), sleep; `stop_movement` resets the chain ("stopped"). Knockback,
  `stop_movement`, `clear_input`, the mouth's root, swimming and a full mouth drop an armed Roll
  press (`_drop_roll_press`).
- `can_receive_damage`: "state-blocked" while `is_invulnerable()`; `apply_knockback` returns while
  `ignores_knockback()`.
- The click and moba schemes' attack order uses `reaches` and `press_attack`, aimed from
  `get_centre()` at the target's hurtbox centre; in the pointer scheme `_face_pointer` waits while a
  step runs (`ShapeController.is_busy()`), so a side pose stays mirrored like its weapon.
- `_flip_for` reads a strike hold `strikes/<strike>-<direction>-hold` as its `strikes/<strike>-<direction>`
  (`STRIKE_HOLD_SUFFIX`), so a `-side` hold mirrors for a left facing and a `-down` or `-up` one never
  does; no classic clip ends in `-hold`.
- When the `modal` pause ends (a window closes) a pending Roll press is dropped
  (`_update_modal_pause`, also run at the top of the physics step; `PlayerInputBuffer.drop_press`).

## The Lantern (2026-10-14)

The owner's words: "a lantern ability that lights inside the slime to see in the dark, and it can
throw small flames to damage and to light candles" (design:
[bomb-lantern-and-secrets](../design/2026-10-14-bomb-lantern-and-secrets.md) section 2). A box
ability (socket `lantern`, F; S in keys-only), lent in the rework mode with the other box abilities
(`main.start_rework`). Dark rooms, candles and burnables: [DARKNESS.md](DARKNESS.md).

- **Use** (`PlayerScript.use_ability(&"lantern")` -> `PlayerAbilities.try_begin`, 10 energy, 300 ms
  cooldown, the usual refusals): `lantern_sequence.gd` turns the slime to the aim, flares the ember
  and plays the `spit-<direction>` clip sped up to `clipMs` (200); at `releaseMs` (70) the flame
  leaves the mouth (16 px ahead of the feet).
- **The flame** (`lantern_flame.gd`; owner, 2026-10-14: a short puff right in front of the slime,
  about one tile): it bursts out at 900 px/s for 72 px, growing, then burns there `lingerMs` (150)
  as it shrinks and fades, and acts on the first of: a fire target whose `receive_fire` answers true
  (a candle lit, a hedge set on fire, a Goo Bomb set off); an enemy hurtbox (one rework hit, class
  tap, 5 damage, a 250 ms hold, `last` false so it never moves a body, tags `fire`, `lantern`,
  weapon id `lantern`, through `AbilityWorld.strike_targets`, with its number and `flame.feel`); a
  wall (`AbilityWorld.line_reach`, tiles and small props never block); else it fizzles into smoke.
  It flies at the old centre's height over its ground point and is a light source (90 px).
- **The ember** (`lantern_glow.gd`, `LanternEmber` under the player's Visual, made on demand by a
  dark room or the first use): with the Lantern learned, inside a dark room that is still dark the
  slime shows a small warm flame in its body (a soft additive glow and the flame art at 0.24) and is
  a light source of 160 px with a slight real-time flicker. Outside dark rooms nothing shows, but
  each flame flares the ember for 260 ms.
- **The playground's Lantern corner** (`game/dev/corners/lantern_corner.tscn`, instanced in
  `game/scenes/worlds/playground.tscn`, which grew east from 40 to 52 columns for it): a walled cave
  room x 2624..3200, y 2048..2624 with its door in the north wall at x 2660..2780 (reach it along
  the grass east of the lake and the hills, about (2720, 1930); `?map=playground&spawn=2720,1930`),
  darkened by a DarkRoom (x 2588..3236, y 1960..2644); four candlesticks (burning 60 s each) that
  light the room while all burn, two training dummies to burn, and a deadthorn hedge closing a nook
  in the south-east corner with a chest (2 energy potions, 3 shards).

## The Goo Bomb (2026-10-14)

The owner's words: "a cast power: the slime casts for 2 seconds, building a bomb inside him, then
puts it out from his mouth (the same animation as the spit). The bomb explodes after 3 seconds. You
can suck it in and throw it as well. It costs 20 energy" (design:
[bomb-lantern-and-secrets](../design/2026-10-14-bomb-lantern-and-secrets.md) section 1). A box
ability (socket `goo-bombs`, F; S in keys-only), lent in the rework mode with the other box
abilities (`main.start_rework`). Numbers: `abilities.gooBomb` ([Data](#data)).

- **The press** (`PlayerScript.use_ability(&"goo-bombs")` -> `PlayerAbilities.try_begin`): the usual
  refusals, "Low energy" below 20, but no energy is taken yet; the cooldown (600 ms) starts.
- **The cast** (`goo_bomb_sequence.gd`, 2000 ms): the slime stands still (actions locked) and
  swells in 4 slow pulses on the effects channel, up to 10 % wider; a glowing bomb grows inside its
  jelly (`BombInside` on the body: the bomb art from 0.04 to 0.3 of its size, see-through, with an
  additive glow, at the belly). Under it the shapes' charge ring (a `GooRing` set up as ShapeVisuals
  sets up its own: radius `gulp.rework.ringRadiusPx`, squashed to 0.55, behind the body, the goo
  colour or the form's tint) fills over the cast; full, it turns light, chimes (`Heal`, the charge
  ring's) and pulses through the spit. A hit with damage cancels the cast (player.gd
  `commit_damage` -> `PlayerAbilities.on_hurt` -> the sequence's `interrupted_by_hit`): the bomb
  shrinks away, the ring drains (`gulp.rework.ringCancelMs`), no energy is spent and the cooldown
  is cleared.
- **The spit:** the 20 energy is spent (too little by now: "Low energy" and nothing), the
  `spit-<direction>` clip plays in the facing and the bomb (`object.goo-bomb`, `goo_bomb.gd`) pops
  out of the mouth (26 px up) and hops 64 px along the aim in 260 ms with an 18 px arc, stopping
  14 px short of what blocks the slime (a ray on its mask without bodies: walls, its level's cliffs,
  deep water). The sequence ends 320 ms later.
- **The bomb:** a jelly ball (bomb.webp at 0.45, about 43 x 50) with a shadow. Its fuse (3000 ms of
  the gameplay clock, so hit-stops and menus hold it) starts as it leaves the mouth: it pulses from
  2 to 8 Hz (faster near the end), squashing a little, its core glow grows and brightens, the leaf
  fuse sparks more, and it blinks white at 12 Hz in the last 500 ms. Groups: `goo_bombs`,
  `suckable`, `fire_targets` (`receive_fire(hit) -> true`: it blows at once; `fire_radius` 18) and
  `light_sources` (`light_circle()`: about 40 px, pulsing, over its core).
- **The mouth:** a light liftable of its own (not in liftables.json): `suck_info` gives the held
  kind `goo-bomb` with `bomb` = its instance id; `take` hides it and it rides with the slime,
  ticking, while the held look (HeldLook: the bomb art) pulses and flashes with its fuse. A Q tap
  throws it the usual throw (`thrown_object.gd`: `ride` while it flies); where the throw ends (its
  range, a wall, the first hurtbox) it lands whole (`land`), no break and no hit. A hit on the slime
  drops it whole beside it; death discards it. If it blows in the mouth, the mouth empties and the
  slime is always hurt. Landing on deep water it sinks ("Fsss...", no blast).
- **The blast** (`goo_blast.gd` `detonate`): the ground ellipse 176 x 120 around the bomb's ground
  point (centred 27.56 higher for hurtboxes, as the Slam's), on the level of the ground under it.
  Enemies and dummies: `AbilityWorld.strike_targets` with the rework hit (class slam, 40, launch
  380, hop 16), knocked away from the bomb. The slime: inside the ellipse (its feet), 18 damage and
  a 300 px/s knock away (an old-style request from the blast, so its i-frames, the Roll and the
  Slam's air time apply; 15 after defense); in the mouth 28 (25). `blast_targets`: each node whose
  `blast_point()` lies in the ellipse gets `receive_blast(hit) -> bool`. Other bombs in it go off
  120 ms later. Feel: `GameFeel.play_hit` once (hit-stop 120 ms, trauma 0.9, the targets' material
  cue), each target's number, sparks and debris, the painted burst (blast-6x1.webp, 70 ms a frame,
  at 0.66), a flash, the shockwave ring, pebbles and dust, goo-splat blobs and a goo puddle that
  fades over 3.2 s; liftables within 220 px rock. The blast is a light source: 220 px, fading over
  250 ms. Cues `GooBombCast`, `GooBombSpit`, `GooBombBlast`, `GooBombSink` play `SlamWindup`,
  `GulpSpit`, `SlamImpact`, `BreakSoft` until baked.
- **Cracked walls** (`object.cracked-wall`, `cracked_wall.gd`, `@tool`): a weak spot set on a real
  wall (an elevation cliff face of any style, or a built wall), never a wall of its own: the wall's
  own collision blocks. Intact, a crack decal (crack-overlay.webp, drawn as it is) on the face; a
  hurtbox refuses every weapon, throw and Slam as a clink ("Too deep for a hammer. It needs a
  blast."). Blown: the hole decal (hole-overlay.webp, greyscale, tinted to the rock: `hole_tint`, or
  at alpha 0 the mean of the brighter half of its wall style's art, x `tint_gain` 1.1) replaces the
  cracks, "The wall caves in!", the break cue and the `SecretFound` jingle (`GateOpen` until its
  take exists), and the passage opens: `Elevation.open_passage(rect, level)` makes the tris under
  `passage` walkable for that level (`ElevationGrid.open_rect`; only that level's collision is
  rebuilt, deferred; the wall stays drawn, so the slime in the hole is the ghost behind the rock).
  Without elevation a `blocker` node is removed instead. Saved as `flag_id`; a blown wall opens its
  passage again at load. With a door target (`door_id`, `target_area_id`, `target_door_id`) the
  hole is a door (a DoorScript of kind "opening" with its arrival `arrival_offset` in front, its
  trigger the `passage` rect): walking into the hole and pushing on toward `door_side` for
  `worldNavigation.doorPushMs` travels (no interact key since 2026-10-14; CONVENTIONS.md "Doors"). Every decal size and offset, the
  passage and the door are Inspector fields; the editor draws the passage and `preview_blown` shows
  the hole.
- **Rubble heaps** (`object.rubble-heap`, `rubble_heap.gd`): a StaticBody heap of loose rocks
  (rubble-2x1.webp at 0.5) that clinks off everything but a blast ("Too many rocks to move. It needs
  a blast."); blown, a pebble scatter on the ground that no longer collides, the break cue and the
  jingle, and its `flag_id`.
- **The playground's Bomb corner** (`game/dev/corners/bomb_corner.tscn`, instanced at the origin of
  `game/scenes/worlds/playground.tscn`; it removes itself with the rework mode off): the west edge,
  x 0..1500, y 6380..7950, around the lake cliff's west end (`?map=playground&spawn=330,6800`).
  - The **cracked wall** in the lake cliff (meadow rock, level 2) at its foot (330, 6720), east of
    the stairs: blown, its hole is a north door (the iris plays) to `playground-bomb-cave`, a small
    crystal cave room (10x8 cells, about 8x6 of floor, fixed camera, a campfire, two shards) with a
    chest (2 health potions, 2 berry mats). You arrive just inside its south door facing up; walking
    down out of it (its `walk_area`) or using it brings you back in front of the hole facing down
    ([CONVENTIONS.md "Doors"](CONVENTIONS.md#doors)).
  - The **rubble heap** at (32, 6600) chokes the one-cell path between the cliff's west end and the
    map's edge.
  - The **islet** (level 1, no stairs) in the lake at x 1088..1472, y 6848..7104 holds a rubble heap
    at (1280, 6960): wade into the shallows south of it (about (1280, 7230)), spit a bomb at the
    islet's wall, suck it, and throw it up (the throw flies 280 px over the wall). Blown, a chest
    (3 health potions) appears in the shallows at (1160, 7180).
  - A second **cracked wall** in the root-rock plateau south of the lake, at (176, 7808) west of its
    stairs: a plain opening (no door) with a nook chest (3 berry mats), showing the decals on a
    second wall style.
  - Two light training dummies on the shore at (120, 6930) and (250, 7000), and a title over the
    cliff's foot.

## Heavy plates and heavy blocks (2026-10-14)

The owner's idea (design: [bomb-lantern-and-secrets](../design/2026-10-14-bomb-lantern-and-secrets.md)
section 4): heavy plates that sink slowly and only under a heavy weight, and heavy blocks that only
the Stone form moves. Rework mode only: the blocks and plates stand only in the playground's Heavy
corner, which takes itself out with the mode off; the grab starts only from the rework interact
path. Numbers: `puzzles.heavyPlate`, `puzzles.heavyBlock` ([Data](#data)).

- **The heavy plate** (`object.heavy-plate`, `heavy_plate.gd`, group `heavy_plates`; its gates by
  `gate_id`): loaded by the Stone slime (a form that `presses_plates`, its feet within 30 of the
  plate's middle, not in the air) or a heavy block (its middle within 24). Loaded it sinks from up to
  fully down over 3000 ms; unloaded it rises over 5000 ms; weight coming back sinks it again from
  where it is (the gameplay clock, so hit-stop and menus hold it). Fully down it opens its gates
  (`GateScript.open`); they stay open while it rises and shut the moment it is fully up
  (`GateScript.close`, new: the doors block again, cue `GateLocked` until a take exists; a gate
  unlocked with a key never shuts), unless another heavy plate of the same gate still holds them
  (`holds_gate_open`). A block left on it keeps it down. Nothing is saved: a world entered again
  starts with the plate up.
- **Its look** (owner, 2026-10-14: only the pressable top moves): the **base** (a stone socket
  ring) is fixed, the **cap** (an oval stone slab with a carved weight glyph) slides 6 down into it
  as it sinks and back up as it rises, darkening; fully down the cap shows its pressed picture (the
  glyph lit amber). The ring's front is drawn over the cap. Art:
  `asset/MAPS/props/heavy-plate/base-2x1.webp` (full, front) and `cap-2x1.webp` (released,
  pressed), packed by `scripts/art/pack-heavy-plate-art.py` from
  `asset/Originals/props/heavy-plate/plate-b.png` (Magnific GPT 2.5); the script prints the
  placement the plate uses (`ART_BASE_OFFSET`, `ART_CAP_OFFSET`). Until those files are imported the
  plate draws a stand-in (the pressure plate's pressed frame as the base, a code-drawn cap).
  Around it the shapes' goo charge ring (as the Goo Bomb's cast sets it up, radius 46, squashed, the
  Stone colour) fills as it sinks and drains as it rises; fully down it turns light and pulses. A
  grinding cue (`HeavyPlateGrind`, `GroundCreak` pitched down until a take exists) ticks every
  420 ms while it moves; `HeavyPlateDown` / `HeavyPlateUp` play `PlatePress` / `PlateRelease`.
- **Heavy blocks** (`object.heavy-block`, the stone pedestal, and `object.heavy-statue`, the armor
  statue: the decorations sheet's art at 1.1; `heavy_block.gd`, group `heavy_blocks`): a
  CharacterBody2D on the `world` layer (the slime, enemies and other blocks collide with it), its
  footprint 58 x 50 around its root, the middle of a 64 cell. Not suckable. Its shadow grounds it
  (owner, 2026-10-14): a contact shadow the shape of the base's ground edge, no wider than the
  footprint, darkest at the base's front edge, and a short soft shadow to the lower right.
- **The grab** (`game/player/heavy_grab.gd`, owned by player.gd): an interact press (W in keys-only,
  right click in the keyboard + mouse and pointer schemes) while the slime faces a block and touches
  it (within 14 of its footprint) grabs it instead of interacting; anything else in reach is used
  as before. While the key is held the grab owns the step (`_rework_owns_step`; the other presses
  are dropped): the slime stretches toward the block and squares up on its side; a walk key held
  toward the block for 180 ms pushes it, away from it pulls it, one 64 cell per move over 640 ms,
  the slime moving with it (cell after cell while the key stays held); sideways does nothing.
  **Only the Stone form moves it**: the plain slime strains (it wobbles, the block trembles, cue
  `HeavyBlockStrain` = `WebStruggle`, the line "Too heavy... I need to be stone." at most every
  2.4 s). A block moves only into a cell that is walkable ground of its own level (no cliff, rim,
  hole or stairs: `Elevation.is_walkable`) with no body in it (walls, props, gates, other blocks,
  enemies, NPCs, deep water); else it knocks once (`HeavyBlockBump` = `HitBlocked`). A pull also
  needs room behind the slime. Letting go of the key releases it (a move under way finishes first);
  a knock, a hit, death or a teleport release it too. The click and moba schemes' right button is
  their order button, so they grab only with the `interact` key binding (none by default).
- **Not built:** a block pushed into a hole does not fill it (the elevation grid has no run-time
  level change; blocks stop at holes); the plates and blocks are not saved.
- **The playground's Heavy corner** (`game/dev/corners/heavy_corner.tscn`, instanced at the origin
  of `game/scenes/worlds/playground.tscn`; it removes itself with the rework mode off): the east
  edge south of the Lantern corner, x 2496..3328, y 2688..3712 (`?map=playground&spawn=2880,3460`).
  - Two walled vaults, x 2496..2880 and 2880..3264, y 2752..3200, each with a gate in its south
    wall (vault A's at (2688, 3200), vault B's at (3072, 3200)) and a chest inside (A: 2 health
    potions, 2 shards; B: 2 energy potions, 3 berry mats).
  - **Plate A** at (2688, 3616), 416 south of its gate: the Stone slime stands 3 s, then runs
    north (about 3.7 s at the Stone form's 120 px/s) while the plate rises for 5 s. A second heavy
    plate inside vault A at (2560, 2912) lets it out again.
  - **Plate B** at (3072, 3360), in front of vault B's gate, and the pedestal at (3200, 3488): push
    it two cells west and two north onto the plate and the gate stays open.
  - A spare statue at (2880, 3552) to push and pull (north it stops at vault A's wall), two stone
    essences at (2560, 3424) and (2560, 3520), and a title over the south edge.

## Chapter 1 and one combo

Chapter 1 (level-1) enemies must die within one combo. Chapter 1 has only the Spear (the Axe comes
in Chapter 2's dungeon). Level-1's enemies and their scene HP (what the game uses; not changed
here, level-1 waits for the atlas session), against one full chain without a crit:

| Enemy (level-1) | HP (scene) | Spear chain 14 + 16 + 21 = 51 | Axe chain 18 + 21 + 27 = 66 |
|---|---|---|---|
| worm swordsman | 8 (`enemy-types.json` says 90) | dies on the first jab (at 90: survives by 39) | dies on the first sweep (at 90: survives by 24) |
| worm archer | 40 | dies on the finisher | dies on the finisher (39 after two) |
| slime spider | 40 | dies on the finisher | dies on the finisher (39 after two) |
| **worm brawler** | **55** | **survives by 4: breaks the rule** | dies on the finisher |
| Fatty One Eye (boss) | 140 | boss: the eye only, spear only | boss (body takes 0) |

To keep the rule with the Spear: the brawler at 51 HP or less (or the lunging jab's `damageScale`
up from 1.46 to 1.71 or more, which makes it 25), and the swordsman's `enemy-types.json` entry
agreeing with its scene (8, or at most 51). A wall splat adds 40 % of the finisher (about 8), which the brawler cannot count on.

## Status

Built on 2026-10-11 by the foundation and six modules, integrated the same day: every script
compiles (`--check-only`), the project import registers every new script. Not tested by the suite;
the owner plays it in the playground (checklist above). Nothing here is committed until the owner
asks.

The same day a review and the lead's playground capture were worked in: the Spear's spike is out
on the hit frame and drawn in front; a press after a cancel point fires at once (the Thud links to
the BOOM); the shapes aim from the slime's centre; a switch never aborts a strike; the clink and
recoil feel; hits, sparks and numbers land on the hurtbox's centre; the wall ray starts at the feet
and passes bodies with hurtboxes; the impact dust and the death, splat and fizzle puffs are small;
the testbed moved off the feel yard, its dummies move, and the enemy pen (F4) was added; bowling,
wall splats, phase armor, kept motions and the tumble's pivot were fixed; the Slam's debris lands on
its targets; the mouth ring fills where it shows; the creak hint names the right key; the rework's
grants never reach a save; a closing window drops a stray Roll press; a dummy plays one hit sound;
arrowing onto the bag band only previews. Every edited script compiles (`--check-only`); none of it
has run yet.

On 2026-10-12 the owner's playtest was worked in by four builders (shapes, reactions, player,
juice) and integrated the same day ([combat-feel plan section 11](../design/2026-10-11-combat-feel-plan.md#11-owner-playtest-2026-10-12)
lists the feedback and every changed number): attacks and the Roll fire on the release, the slime
walks at half speed while a charge ring fills, the chains are slower and their last steps load,
each step moves its own way, the Spear has its thin shaft and arrowhead, the Spin hits once, hits
stop enemies' attacks for longer stuns (no wind-up armor on light and medium enemies, the hold
count measured from a hold's end), energy no longer refills by itself (F5 in the testbed), the Roll
has its quick roll and the charged-roll upgrade, and the juice panel's keys play each effect (the
freeze also holds the sparks and the numbers). One new script, `game/feel/juice_demo.gd`, waits for
the lead's import (its `.uid`). Every edited script compiles (`--check-only`); none of it has run
yet.

Later on 2026-10-12 the prototype's first art ([Art](#art-2026-10-12)) was wired by three builders
(the slime's poses, the weapons and effects, the icons) and integrated the same day: page 6's 36
pose clips in the player scene (built with `build_player_clips.gd -- --only=shape-`; no other clip
changed), the poses on every step and charge and the ring's held `load` pose (`_locomotion_clip`),
the facing kept through a strike in the pointer scheme, the painted weapons in the form's skin, the
swoosh, the glints, the goo splat flipbook, the painted shard and the shape icons; the axe's and
the hammer's `head_start` are in `shapes.json`, and the seven new textures' imports ask for
mipmaps. One new script, `game/shapes/shape_poses.gd`, waits for the lead's import (its `.uid`),
which also builds those mipmaps. Every edited script compiles (`--check-only`); none of it has run
yet.

Later still on 2026-10-12 the Spear got the look the owner approved ([The Spear's strike
frames](#the-spears-strike-frames-2026-10-12)), built by a packer and two builders and integrated
the same day: the strike sheet and its manifest (`pack-slime-strikes.py`; the cells are 512 x 416,
not the planned 384 x 256, which could not hold the finisher's side lunge and the front and back
necks), 42 strike clips in the player scene (`build_player_clips.gd -- --only=strike-`; every
existing clip byte-identical), the frames on the Spear's steps and its Lunge, the rigid spear behind
the body, the hit line from the full lean's socket, `_flip_for` reading `-f<n>` clips, and no code
squash on the strike frames. The new script `game/shapes/shape_strikes.gd` has its `.uid` (one
import, which imported nothing else). Every edited script compiles (`--check-only`); none of it has
run yet.

Last on 2026-10-12 the War Axe and the Hammer got the same look ([The War Axe's and the Hammer's strike frames](#the-war-axes-and-the-hammers-strike-frames-2026-10-12)), built by a
packer and a game builder against the contract note
([docs/design/2026-10-12-weapon-strike-frames.md](../design/2026-10-12-weapon-strike-frames.md)): the
two strike sheets, neck.webp and their manifest entries (`pack-slime-weapon-strikes.py`, which also
solved the back views' jelly arms against the reach numbers), 105 more strike clips
(`build_player_clips.gd -- --only=strike-`, now one sheet per strike), the key timeline, per-strike
sheets and flip-aware frame identification in `shape_strikes.gd`, the rigid weapon, the code neck
and the path swoosh in `shape_visuals.gd`, the Quake's held frame, and the reach numbers set from the
`contact` report (Axe radius 76 / 70, Hammer offset 68). It was filmed in the playground on every
aim (right, left, down, up, down-right) and the Quake charge, with no runtime errors; the suite was
not run.

Round 3 the same evening made the strikes real animations
([Editing the strike animations](#editing-the-strike-animations-2026-10-12)): the StrikeRig with the drawing code moved out of ShapeVisuals and the
editor overlay, the converter and its 21 animations in `game/characters/player-strikes.tres`, the
player scene's `strikes` library and rig nodes (nothing else in the scene changed), the game seeking
the animations by the gameplay clock, `hit_reach` per direction, and the manifest without its keys. The
chains, the Lunge and the Quake were filmed again on every aim and matched the films before it, with
no runtime errors; the scene was also rendered without the game's scripts, the rig and its overlay
drawing from the animations alone. The suite was not run.

Round 4 (2026-10-13) made each strike a Godot resource you edit in the Inspector
([Editing the strike animations](#editing-the-strike-animations-2026-10-12)): seven files in
`game/characters/strikes/`, read by `game/shapes/strike_library.gd`, which builds the player's `strikes`
library at run time (so the scene holds no library). The StrikeRig's track-driven state, the markers and the
converter are gone. The Round 3 library was converted once and the converter deleted. The films were checked
again on every aim (the axe, the hammer, the spear, the Quake and the Lunge) against the round 5 films: the body
frame, the weapon's angle, length and layer match on every tick; the pixel differences are the dummy's reaction,
the numbers, the impact effects and the render's 1 to 2 px jitter. Once the owner's editor closed, the lead made the
scene edit (the `strikes` library reference and the rig's old track properties out, the Visual's idle values back)
and deleted the Round 3 library file.

Round 5 (2026-10-14) put a live preview above a strike file's fields in the Inspector (the plugin
`addons/strike_preview/`, [Editing the strike animations](#editing-the-strike-animations-2026-10-12)) and took the
rig's own editor preview out (it no longer touches the Visual or the scene's save). The keys were thinned, 231 to
216 (at most 2.85 degrees from round 4, held values exact, the sweeps' arc exact; a before-and-after image of the
chop and the BOOM in every direction showed no visible change). The chain steps' reach moved from
game-constants.json into the strike files (the same numbers; no test reads them), and each direction got a
`socket_nudge`. Every touched script compiles (`--check-only`); the films of the axe, the hammer and the spear
(right, down, up) and the Quake (down, left) match the films before it on every tick (the body frame, the clock,
the weapon's layer; the angle within 2.4 degrees on the hammer, 0 elsewhere) with no runtime errors; the preview was
run in the real editor (`axe-chop.tres`, with `up.arm_px` raised in memory and put back). The suite was not run.

Later on 2026-10-14, after the owner's look at round 5: the up chop, Thud and BOOM got a new motion (the weapon raised
back over the head toward the camera, in front of the body, then over the head and away to land beyond; the body
frames unchanged) and, for the perspective, a shorter drawn reach (`arm_px` -6, 2, -2) with the hit centred where
the weapon lands (`hit_center` (0, -7.5) and `hit_reach` 25.5 on the chop, 25 and 17 on the smashes); every other
reach value stayed. Each direction got `hit_center` (zero everywhere else), the preview its two drag handles (the
cross and the ring's handle, through the editor's undo history) and a refresh after every change (in the real
editor in its low-processor mode, `up.arm_px` set 30, 10 and -10 through the undo history each drew six frames and a
changed picture; a drag of the cross moved `hit_center` and one undo put it back). A negative `arm_px` pulls the
weapon into the jelly, and the six directions whose keys slid the length below 1 from the contact on (the sweeps'
and the chop's down, the Thud's side and down, the BOOM's down) now hold the length at 1 with a negative arm: the
same tip from the contact on (within 0.006 px), the wind-up weapon drawn that many px further in (0.5 to 13.3). A
painted view's frame change no longer starts a swoosh. Every touched script compiles; the films of the axe and the
hammer (right, down, up) show the same body frame and clock on every tick, the angle and layer changed only on the
redesigned up strikes, and no runtime errors. The suite was not run.

Later on 2026-10-14 the unused animations went: the player scene's 126 held strike-frame clips
(`strike-<strike>-<direction>-f<1..6>`) and the 27 page-6 poses no strike shows any more (the Spear's, the Hammer's
and the Axe's chop), 215 clips to 62, removed by a run of `build_player_clips.gd -- --only=strike-` (nothing rebuilt;
the tool no longer builds them). The charge ring's held frame is each strike's hold, built at run time by
StrikeLibrary (`strikes/<strike>-<direction>-hold`); the old overlay drawings of the Spear, the Hammer and the chop
in ShapeVisuals, the poses' timelines but the Spin's, and the steps' unread `clip` and `reverseClip` numbers went
too. Every touched script compiles; the built strike animations match the old builder's key for key; the films of
the axe, the hammer and the spear (right, down, up) and of the Lunge, the Quake and the Spin (right, down, up, left)
ran with no runtime errors, each ring holding the frame it held before (the finisher's and hammer-boom's frame 2,
mirrored for left; the Axe's `load` pose) and the Spin swapping its poses; the classic playground swung `attack-1`
with no errors. The suite was not run.

Later on 2026-10-14 the Goo Bomb was built ([The Goo Bomb](#the-goo-bomb-2026-10-14)): the cast with its
charge ring and the bomb growing inside, the spit, the ticking bomb, the mouth's carry and throw, the blast,
cracked walls (overlays on real walls that open an elevation passage, or a door), rubble heaps, the Bomb corner
and its cave. Every new and touched script compiles (`--check-only`); a film in the playground cast, spat,
sucked, threw (onto the islet) and blew bombs (the cracked wall and its cave there and back, the rubble, the
islet, the root-rock wall, the dummies; a cast cancelled by a hit with no energy spent; a bomb blown in the
mouth; a flame's `receive_fire`; the Hammer clinking off a cracked wall) with no runtime errors. The new
scripts have no `.uid` files yet (an editor scan or import makes them). The suite was not run.
