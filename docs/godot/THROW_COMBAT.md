# Throw Combat (experiment, branch `exp/throw-combat`)

The owner's idea of 2026-10-19: killing enemies only by throwing things is more fun and more of a
challenge, because every throw counts. The Gulp (suck and throw) becomes the whole fight; the body
shapes become energy powers for special moments; what the slime can lift grows with the Gulp's
level. This branch builds it on top of the body-shapes rework mode so it can be played and judged.
Nothing here is on `main`.

The owner's decisions (2026-10-19/20):

- **No ammo = flee.** There is no fallback attack. Changing chunk rebuilds the screen (its liftables
  come back with it), which is a fair way out. Enemies make ammo with their attacks.
- **Q does everything as before** (suck, throw, swallow, spit); **the attack key (A) does nothing**.
  In the keys-only scheme (owner, 2026-10-22, changed 2026-10-23) the keys are **Q** the Gulp,
  **S** the Roll and **A** the chosen box ability, with **E** opening the ability carousel
  ([MOUSE_CONTROLS.md](MOUSE_CONTROLS.md#the-keys-only-scheme)).
- **The Gulp's levels are their own upgrades** (Zelda's Power Bracelet): 1 lifts light things, 2
  medium, 3 heavy. The Heavy skin keeps its plates and heavy blocks.
- **One thing in the mouth at a time.**
- **Aim help**: to try, but the owner fears it helps too much, so it is off unless switched on.

Later ideas he named, not built yet: enemies immune to hits that must be lured into a trap, and
putting enemies to sleep (built: the puffball's sleep lasts until a hit hurts the enemy, and it
lands on invulnerable enemies too, so they can be slipped past; owner, 2026-11-01).

## Running it

The mode rides on the body-shapes rework mode, which since 2026-10-24 (commit 9507c9e6) is on in
every world and every run ([BODY_SHAPES.md](BODY_SHAPES.md#running-it)): so the throw mode is on
everywhere too (F5 from the title, F6 in the editor, any `?map=`, a story run), while
`gulp.throwCombat.enabled` is true (main.gd `decide_throw_mode`). Launch options:

| Option (web / desktop) | What it does |
|---|---|
| `?melee` / `-- --melee` | the throw mode off: the rework game with its attack (the attack key strikes with the current shape, E and the wheel switch shapes, the box holds only box abilities, the keys-only scheme's layout is the rework's) |
| `?gulp=2` / `-- --gulp=2` | the Gulp's level for the session (1 to 3) |
| `?aimhelp` / `-- --aimhelp` | the aim help on |

In the playground (F6 on `game/dev/playground.tscn`) the **throw yard** stands in the shapes
testbed's enemy pen, south of the spawn:

- the pen holds the slime spider, the worm swordsman, the Clod Stomper, and in this mode also the
  **Worm Archer** (its missed arrows stay on the ground) and the **Worm Brawler** (its blows knock
  rocks loose);
- the left column holds light things: a pot, a honey jar (stick), a puffball (sleep), a snowball
  (freeze), a glass float (shatter), a toadstool (sleep);
- the right column holds a crate, an ice block (freeze), a kettle (pierce), a crystal cluster
  (shatter) (all medium), then a keg and an iron ball (pierce) (heavy);
- each thing comes back 4 s after it is taken;
- **F6** steps the Gulp's level 1, 2, 3, 1; **Shift+F6** turns the aim help on or off (a label under
  the pen shows both); **F4** respawns the pen, **F5** fills the energy (shapes testbed).

The playground starts at level 1 (`playgroundLevel`).

## How it plays

- **Lifting.** Every liftable kind has a weight (`kindWeights`: the medium and heavy kinds; every
  other kind, and bones, seeds, globs and arrows, is light). A thing heavier than the Gulp's level
  is not sucked in: an empty burst with one in reach says "Too heavy! (Gulp N needed)" with the
  refusal sound. The thing's own **`weight`** (the root's field in the Inspector, liftable_root.gd)
  is the source of truth: picking a kind fills it with the kind's usual weight from `kindWeights`, and
  it can be changed per thing; the weight travels with it into the mouth and the throw. A thing
  whose scene has no `weight` yet uses its kind's; a placed liftable with `heavy` set counts as heavy
  (in the game, and in the `weight` the editor fills in). A weight's level is its place: light 1,
  medium 2, heavy 3 (`ThrowMode.level_for`, `can_lift`).
- **Carrying.** The slime walks at the held weight's `holdingSpeed` (light 0.85, medium 0.7, heavy
  0.55 of its speed).
- **Throwing.** Damage is `throwDamage` (25) x the material's `gulp.throwDamageByMaterial` x the
  weight's `damageScale` (1, 1.8, 3) x the effect's `damageScale`. The weight also scales the
  flight's speed and reach (heavy things fly shorter) and the break's radius, and picks the hit's
  class: `thrown`, `thrown-medium` or `thrown-heavy` (heavier classes knock enemies further; their
  reactions per enemy weight are in `combat.weights.<weight>.classes`).
- **Knockback** (owner, 2026-11-01: a throw that hurts knocks back, one that does not hurt does
  not). A throw that deals damage always pushes the enemy back along the throw: where its reaction
  would hold it in place (a daze, a knockdown, a stagger) it slides `gulp.throwHit.knockbackPx`
  (52) x the enemy's `knockbackScale` (light enemies 1, medium about 0.6, heavy 0.2) while it is
  stunned, `knockbackSpeedScale` (2) times as fast as a stunned enemy's usual slide (it gets there
  in about 0.3 s), and a kill that would not fly slides its corpse that far; a launch keeps its own bigger
  push (`gulp.throwKnockback`). No damage, no push: an immune enemy (the clink), a shut part, a sleep
  throw. Enemies whose `knockbackScale` is 0 (turrets, the eyes, the bosses) and armored hits (a
  boss, an armored phase, the wake guard right after a launch) stay put (owner, 2026-11-01: keep
  them still; [BODY_SHAPES.md](BODY_SHAPES.md), the thrown hit). It is every thrown hit's, with the throw mode
  on or off.
- **What a throw reaches** (owner: "nothing should cross walls"): only hurtboxes on the height level
  it was thrown from (the slime's) with no wall between it and them (AbilityWorld
  `hurtboxes_in_reach`: the same walls that stop its flight). It flies over an enemy on lower
  ground, and neither its break (`throwHitRadiusPx` x the weight's and a shatter's `radiusScale`:
  89 px for a crystal cluster) nor a piercing throw strikes round a wall or up or down a cliff.
- **Effects** (`kindEffects` first, then `materialEffects`):

| Effect | Things | What it does |
|---|---|---|
| freeze | ice and snow (snowball, ice block, icicle, frost crystal, frosted jar, snow brick) | a long stun (`thrown-freeze`: about 3 s on light enemies), an icy crust drawn on the enemy |
| sleep | puffball, toadstool, glow mushrooms | no damage; it sleeps (the verb `sleep`) until a hit that deals damage wakes it, even an invulnerable enemy on the ground; z's over its head while it sleeps |
| stick | honey jar, mud ball | a normal hit of its weight (0.6 of its damage), then half pace (`slowScale` 0.5) for `slowMs` 6 s: it walks and attacks 50% slower; its picture coated in honey, dripping |
| shatter | glass and crystal | the break's radius x 2.2 |
| pierce | metal (kettle, lantern, iron ball) and the worm arrow | it flies on through enemies, striking up to 3, each once |

  The Scenery dock's Suckables show each kind's usual weight and effect on hover
  (`LiftableRoot.kind_weight` and `kind_effect`, read from the data files).
  The look (`game/throw/throw_status_look.gd`) lasts as long as the reaction's stun, the sleep or
  the slow; bosses and armored phases shrug the effect classes off like any thrown hit, and so does
  an enemy getting up from a knockdown or a launch (the reactions' wake guard): put it to sleep
  before you knock it down, not right after.
- **Sleep** (owner, 2026-11-01: "keep the enemy sleeping until new damage wakes them, so
  invulnerable enemies can be bypassed"). Every non-boss weight answers `thrown-sleep` with the verb
  `sleep` (`combat.weights.<weight>.classes`): its stun (`combat.verbs.sleep.stunMs`, 1 s) is
  renewed every step while it sleeps (EnemyReactions `keep_asleep`, from enemy.gd's,
  patterned_enemy.gd's and the dummy's stun step), so it sleeps until a hit that deals damage wakes
  it (`wake_if_hurt`: any hit, old-style ones too; being bowled into). It lands through the enemy's
  immunities (`immune`, a phase's `immune`, a patterned enemy's `_shields`: the Gloomling, a
  walking Squint, a charging Bramble Boar, a Prism Eye from the front) while it is on the ground
  (`HitReaction.sleeps_through`); the phases off the ground, where a sleep throw still clinks, are
  marked `noSleep` in the enemy's `reactions.states` (the Hopper's, the Squints' and the Bone
  Leaper's `air`, the Popworm's `burrowed`, `tell` and `sink`, the Pick Mole's `ducked` and
  `line-up`, the Crystal Mite's `wait` and `drop`, the Pipe Worm's `hidden`). Bosses never sleep. A
  hit that deals no damage (another puffball, a clink) leaves it asleep; it sways without stars.
- **Honey** (owner, 2026-11-01: a better look than the circle, longer, the enemy moves and attacks
  50% slower). The honey jar and the mud ball hit like any throw of their weight (the daze and the
  knockback), then `effects.stick.slowScale` (0.5) of the enemy's pace for `slowMs` (6000): enemy.gd
  `apply_tempo` slows its walk and chase (`_current_slow`) and stretches its attack's wind-up,
  recovery and cooldown; a patterned enemy's every `pattern` time (a key ending in `Ms`) lasts twice
  as long and every speed (`...Speed`, `...DegPerS`) runs at half (`_paced`), so its walks,
  wind-ups, rests and leaps slow down. Bosses, a kill and armor shrug it off. Enemies whose timings
  are scene exports rather than `pattern` numbers (the Clod Stomper's stomp) only walk slower. The
  look: the enemy's own picture coated in honey (a copy of its sprite, frame for frame, under a
  shader: a thick glossy amber coat over the top of the art with drips running down, a thin glaze
  below; `COAT_THICKNESS`, `COAT_EDGE`), and honey drops falling from it.
- **Shape powers.** The learned shapes stand first in the Ability Box (the bag's Shapes row hides).
  Choosing one and pressing the ability key (F; A in keys-only) fires that shape's charge at once
  (the Spear's Lunge, the Axe's Spin, the Hammer's Quake) along the facing or the pointer, for its
  energy (15, 20, 25), with no ring. E (or the wheel) opens the ability carousel
  (`game/shell/ability_carousel.gd`): a quick menu. The game pauses, every learned ability sits as a
  big card (icon and name) in a matrix, the arrows move the lit card, Space or Enter makes it the
  box's choice (named over the slime), and Escape closes it with no change. The arrows are read in
  the window's `_input`, before the player's movement takes them. The HUD's Ability slot shows the shape's icon and cost; the Shape slot is hidden.
  A shape power is busy (the slot dimmed) while a strike runs, the mouth is full or the slime swims.
- **No attack.** The attack key does nothing, and a click on an enemy (the click scheme's order
  button) only walks there, as a click on the ground does.
- **Climbing** (the Feral skin): while it clings to a wall the **Gulp key (Q)** strikes from the face
  (`_climb_strike`: a press of the current shape, the Spear unless another shape's power was used
  last), as the attack key does outside this mode; nothing can be gulped from a wall. So the
  Crystal Colossus's claws can still be struck.
- **Ammo from enemies.** A worm arrow that misses (a wall, the end of its flight) lies where it ended
  for `arrowLifeMs` (12 s, fading at the end) and can be sucked in and thrown back (it pierces); the
  shots that stay, their material and picture size are `ammo.spentShots`. A Worm Brawler's blow
  knocks a mossy rock loose (`rockOnAttack`: half its blows, `rockAheadPx` ahead of its feet along
  the swing, only where a body fits: on its height level, not on a solid tile or against a wall or
  other static body; never within `rockSpacingPx` of another liftable; else no rock). Fatty already
  knocks rocks loose.
- **Aim help.** When on, a throw within half of `aimAssist.coneDeg` either side (24: 12° each way)
  of a live enemy within `rangePx` (320) of the slime's feet, on the slime's height level with no
  wall between, flies straight at the feet of the one closest to the aim (the throw's ground track
  runs from the slime's feet, so it meets the enemy's).
- **Hints.** The attack and charge hints never show; the barred gate's hint names the ability key
  and the Spear.

## Fatty's Lair (2026-10-22)

Owner, 2026-10-22: at least two throwables by every enemy in Fatty's rooms, and only light ones.
Every medium or heavy liftable in `rooms/fatty-lair/` became a light one of the same sort (28: crate
to wicker basket, keg to bucket, flour sack to hay bundle, desert urn and fancy pot to clay pot,
amphora to water jug, gargoyle head to rock), and 35 pots and rocks were added under each room's
`Throwables` node, on free floor near each enemy short of two within 170 px (9 rooms; a headless
check found each spot walkable at the enemy's level, clear of bodies, hazards and doors). The bell
bridge (r7) is the exception: its Watcher Eye stands over the void with no floor near it; the
room's 8 buckets and rocks are within reach of the bridge. The Squints (and the Big
Squint) take thrown hits in the eye while their visor is open. The Glint Bats are awake only while
their room is dark and sleep once every candle burns, so the two in lit rooms (c2, r7) were taken
out with the two pots placed for c2's (2026-10-23; BESTIARY.md).

## Data (`gulp.throwCombat` in game-constants.json)

`enabled`, `throwDamage`, `playgroundLevel`, `weights.<light|medium|heavy>`
(`damageScale`, `rangeScale`, `speedScale`, `radiusScale`, `holdingSpeed`, `hitClass`; the
weight's level is its place in that order), `kindWeights`, `materialEffects`, `kindEffects`,
`effects.<id>` (`hitClass`, `lookMs`, `damageScale`, `radiusScale`, `pierceTargets`, `slowMs`,
`slowScale`), `aimAssist`
(`enabled`, `coneDeg`: the cone's whole width, `rangePx`), `ammo` (`rockOnAttack.<enemy type>`
{`chance`, `kind`}, `rockSpacingPx`, `rockAheadPx`, `arrowStays`, `arrowLifeMs`,
`spentShots.<projectile id>` {`material`, `picturePx`}). The hit classes `thrown-medium`, `thrown-heavy`, `thrown-freeze`,
`thrown-sleep` are in `combat.hits` and every `combat.weights.<weight>.classes` (`thrown-sleep`: the
verb `sleep`, `combat.verbs.sleep.stunMs`); honey has no class of its own.
The knockback distance of a throw that hurts is `gulp.throwHit.knockbackPx` and its pace
`knockbackSpeedScale` (shared with the rework's thrown hit), the launch speed of a throw that launches `gulp.throwKnockback`.

The Gulp's level in a run: 2 once the run learned `gulp-lift-medium`, 3 once it learned
`gulp-lift-heavy` (RunState abilities, saved). Nothing in the story grants them yet.

## Code

| File | What it does |
|---|---|
| `game/throw/throw_mode.gd` | the mode, the Gulp's level, weights, effects (`weight_in`, `effect_in` for the editor too), the aim help, shape-power ids |
| `game/throw/throw_status_look.gd` | the freeze, sleep and honey looks (the honey coat's shader, `_art_rect`) |
| `game/combat/reactions/hit_reaction.gd`, `enemy_reactions.gd`, `reaction_state.gd` | the `sleep` verb, `sleeps_through`, `keep_asleep`, `wake` |
| `game/scripts/enemy.gd`, `game/enemy/patterned_enemy.gd` | `apply_tempo` (honey), `_paced` pattern numbers, sleep through `_shields` |
| `game/throw/spent_shot.gd` | a missed arrow lying on the ground, suckable |
| `game/throw/throw_ammo.gd` | the Brawler's rocks (where a body fits); `spawn_liftable` for any liftable at run time |
| `game/throw/throw_testbed.gd` | the playground's throw yard and its keys |
| `game/main.gd` | `decide_throw_mode` (with the rework mode), the yard, `throw_combat` (the test runner's switch) |
| `game/scripts/liftable.gd`, `liftable_root.gd` | `can_take` by weight (`ThrowMode.can_lift`), `weight`, `is_too_heavy`; the root's `weight` in the Inspector |
| `game/player/gulp/mouth.gd`, `mouth_hold.gd` | the "Too heavy" line, the aim help on the throw |
| `game/player/gulp/thrown_object.gd` | weight and effect on the flight and the break, pierce, the looks, only what it reaches (`_targets`), the knockback distance on the hit (`knock_px`) |
| `game/combat/reactions/enemy_reactions.gd` | the knockback slide of a throw that hurts (`_knock_slide`, `slide_decay_of`) |
| `game/player/abilities/ability_world.gd` | `hurtboxes_in_reach` (its level, no wall between), `clear_line`, `body_level` |
| `game/scripts/player.gd` | no attack (a click on an enemy walks there), the climb strike on Q, holding speed by weight, E opens the ability carousel, a shape power's status |
| `game/shell/ability_carousel.gd` | the carousel window (E): the learned box abilities in a row, picked with Space or Enter |
| `game/shapes/shape_controller.gd` | `power_strike(id)`: a shape's charge at once, for its energy |
| `game/player/abilities/ability_box.gd` | shapes in the box, `choose` (the carousel's pick), `title`, their cost and use |
| `game/ui/body_cards.gd`, `screens/inventory_screen.gd`, `ability_bar.gd`, `weapon_hotbar.gd` | the bag and HUD for shape powers |
| `game/hints/control_hints.gd` | no attack hints; the bars hint names the ability key |
| `game/scripts/projectile.gd`, `game/scripts/enemy.gd` | the spent arrow; the Brawler's rock |
| `game/shapes/shapes_testbed.gd` | the Archer and the Brawler in the pen |
| `tests/test_throw_combat.gd` | the mode's tests (the runner keeps the mode off for every other test) |

## Status and open points

Built on 2026-10-20 by one agent while the owner was away. Every script compiles; a headless check
in the playground (the same steps as `tests/test_throw_combat.gd`) passed: the yard, the box, no
attack, 25 from a light pot, a crate refused at level 1 and lifted at 2 for 45, freeze, sleep, a
kettle through two worms, the Spear's power for 15 energy, E stepping the box, a missed arrow lying
there, the Brawler's rocks, and no engine errors. The suite itself was not run, and nobody has
played it with a keyboard yet: the feel (throw speed, the stuns' lengths, damage, how often enemies
make ammo) is a first guess to tune by playing.

Open points for the owner:

- **Bosses.** Fatty One Eye's eye takes only Spear hits, so in this mode only the Spear's power
  (15 energy) hurts it; his falling rocks are the ammo for the dazes. The Crystal Colossus also
  takes only Spear hits: the Spear's power on his weak spot and his back, and the Feral skin's climb
  strike (Q here) on his claws while he clings. The bosses need throw-first patterns (throwing
  their own things back, Zelda style).
- **The prologue.** Yoi's lesson still talks about attacking; the barred gate's lever needs a hit
  tagged `spear`, which the Lunge should carry (not checked by playing).
- **Gulp upgrades in the story**: where `gulp-lift-medium` and `gulp-lift-heavy` are found.
- **Chapter 1's ammo**: its four level-1 chunks hold only 13 liftables, and the crates (18 in the
  worlds) and kegs (9) are now medium and heavy.
- **Bigger looks for heavier things** (the held look and the flight use one size for all).
- **Immune enemies and traps**, **more ammo-making enemies** (the owner's next ideas).
