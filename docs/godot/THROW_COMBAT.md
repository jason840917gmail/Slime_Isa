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
  In the keys-only scheme (owner, 2026-10-22, to try) the keys are **A** the Gulp, **S** the Roll
  and **D** the chosen box ability ([MOUSE_CONTROLS.md](MOUSE_CONTROLS.md#the-keys-only-scheme)).
- **The Gulp's levels are their own upgrades** (Zelda's Power Bracelet): 1 lifts light things, 2
  medium, 3 heavy. The Heavy skin keeps its plates and heavy blocks.
- **One thing in the mouth at a time.**
- **Aim help**: to try, but the owner fears it helps too much, so it is off unless switched on.

Later ideas he named, not built yet: enemies immune to hits that must be lured into a trap, and
putting enemies to sleep (a first sleep effect is built: the puffball).

## Running it

The mode is on wherever the rework mode is on (the playground, `?shapes`, a story run with a
shape), while `gulp.throwCombat.enabled` is true. Launch options:

| Option (web / desktop) | What it does |
|---|---|
| `?melee` / `-- --melee` | the throw mode off: the rework game as on `main` |
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
  refusal sound. A placed liftable with `heavy` set counts as heavy.
- **Carrying.** The slime walks at the held weight's `holdingSpeed` (light 0.85, medium 0.7, heavy
  0.55 of its speed).
- **Throwing.** Damage is `throwDamage` (25) x the material's `gulp.throwDamageByMaterial` x the
  weight's `damageScale` (1, 1.8, 3) x the effect's `damageScale`. The weight also scales the
  flight's speed and reach (heavy things fly shorter) and the break's radius, and picks the hit's
  class: `thrown`, `thrown-medium` or `thrown-heavy` (heavier classes knock enemies further; their
  reactions per enemy weight are in `combat.weights.<weight>.classes`).
- **Effects** (`kindEffects` first, then `materialEffects`):

| Effect | Things | What it does |
|---|---|---|
| freeze | ice and snow (snowball, ice block, icicle, frost crystal, frosted jar, snow brick) | a long stun (`thrown-freeze`: about 3 s on light enemies), an icy crust drawn on the enemy |
| sleep | puffball, toadstool, glow mushrooms | no damage, a longer stun (`thrown-sleep`: about 4.5 s), z's over its head |
| stick | honey jar, mud ball | a stun (`thrown-stick`: about 2.5 s), an amber puddle with drips |
| shatter | glass and crystal | the break's radius x 2.2 |
| pierce | metal (kettle, lantern, iron ball) and the worm arrow | it flies on through enemies, striking up to 3, each once |

  The look (`game/throw/throw_status_look.gd`) lasts as long as the reaction's stun; bosses and
  armored phases shrug the effect classes off like any thrown hit, and so does an enemy getting up
  from a knockdown or a launch (the reactions' wake guard): put it to sleep before you knock it
  down, not right after.
- **Shape powers.** The learned shapes stand first in the Ability Box (the bag's Shapes row hides).
  Choosing one and pressing the ability key (F; D in keys-only) fires that shape's charge at once
  (the Spear's Lunge, the Axe's Spin, the Hammer's Quake) along the facing or the pointer, for its
  energy (15, 20, 25), with no ring. E (or the wheel) steps the box's choice and names it over the
  slime. The HUD's Ability slot shows the shape's icon and cost; the Shape slot is hidden.
- **Ammo from enemies.** A worm arrow that misses (a wall, the end of its flight) lies where it ended
  for `arrowLifeMs` (12 s, fading at the end) and can be sucked in and thrown back (it pierces). A
  Worm Brawler's blow knocks a mossy rock loose (`rockOnAttack`: half its blows, `rockAheadPx` ahead,
  never within `rockSpacingPx` of another liftable). Fatty already knocks rocks loose.
- **Aim help.** When on, a throw within `aimAssist.coneDeg` (24) of a live enemy within `rangePx`
  (320) flies straight at the one closest to the aim.
- **Hints.** The attack and charge hints never show; the barred gate's hint names the ability key
  and the Spear.

## Data (`gulp.throwCombat` in game-constants.json)

`enabled`, `throwDamage`, `playgroundLevel`, `levels`, `weights.<light|medium|heavy>`
(`level`, `damageScale`, `rangeScale`, `speedScale`, `radiusScale`, `holdingSpeed`, `hitClass`),
`kindWeights`, `materialEffects`, `kindEffects`, `effects.<id>` (`hitClass`, `lookMs`,
`damageScale`, `radiusScale`, `pierceTargets`), `aimAssist` (`enabled`, `coneDeg`, `rangePx`),
`ammo` (`rockOnAttack.<enemy type>` {`chance`, `kind`}, `rockSpacingPx`, `rockAheadPx`,
`arrowStays`, `arrowLifeMs`). The hit classes `thrown-medium`, `thrown-heavy`, `thrown-freeze`,
`thrown-sleep` and `thrown-stick` are in `combat.hits` and every `combat.weights.<weight>.classes`.

The Gulp's level in a run: 2 once the run learned `gulp-lift-medium`, 3 once it learned
`gulp-lift-heavy` (RunState abilities, saved). Nothing in the story grants them yet.

## Code

| File | What it does |
|---|---|
| `game/throw/throw_mode.gd` | the mode, the Gulp's level, weights, effects, the aim help, shape-power ids |
| `game/throw/throw_status_look.gd` | the freeze, sleep and stick looks on a stunned enemy |
| `game/throw/spent_shot.gd` | a missed arrow lying on the ground, suckable |
| `game/throw/throw_ammo.gd` | the Brawler's rocks; `spawn_liftable` for any liftable at run time |
| `game/throw/throw_testbed.gd` | the playground's throw yard and its keys |
| `game/main.gd` | `decide_throw_mode` (with the rework mode), the yard, `throw_combat` (the test runner's switch) |
| `game/scripts/liftable.gd` | `can_take` by weight, `weight`, `is_too_heavy` |
| `game/player/gulp/mouth.gd`, `mouth_hold.gd` | the "Too heavy" line, the aim help on the throw |
| `game/player/gulp/thrown_object.gd` | weight and effect on the flight and the break, pierce, the looks |
| `game/scripts/player.gd` | no attack, holding speed by weight, E steps the box, a shape power's status |
| `game/shapes/shape_controller.gd` | `power_strike(id)`: a shape's charge at once, for its energy |
| `game/player/abilities/ability_box.gd` | shapes in the box, `cycle`, `title`, their cost and use |
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
  (15 energy) hurts it; his falling rocks are the ammo for the dazes. The bosses need throw-first
  patterns (throwing their own things back, Zelda style).
- **The prologue.** Yoi's lesson still talks about attacking; the barred gate's lever needs a hit
  tagged `spear`, which the Lunge should carry (not checked by playing).
- **Gulp upgrades in the story**: where `gulp-lift-medium` and `gulp-lift-heavy` are found.
- **Chapter 1's ammo**: its four level-1 chunks hold only 13 liftables, and the crates (18 in the
  worlds) and kegs (9) are now medium and heavy.
- **Bigger looks for heavier things** (the held look and the flight use one size for all).
- **Immune enemies and traps**, **more ammo-making enemies** (the owner's next ideas).
