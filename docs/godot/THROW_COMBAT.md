# Throw Combat

The owner's idea of 2026-10-19: killing enemies only by throwing things is more fun and more of a
challenge, because every throw counts. The Gulp (suck and throw) becomes the whole fight; the body
shapes become energy powers for special moments; what the slime can lift grows with the Gulp's
level. It is built on top of the body-shapes rework mode. It was tried on the `exp/throw-combat`
branch from 2026-10-20 and merged into `main` on 2026-11-01 (the branch and its worktree deleted);
it is on in every world unless `?melee` turns it off.

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

`gulp.throwFeel.enabled` (true) is the reworked feel of 2026-11-16; **F1** in the throw yard flips
it for the session.

In the playground (F6 on `game/dev/playground.tscn`) the **throw yard** stands in the shapes
testbed's enemy pen, south of the spawn:

- the pen holds the slime spider, the worm swordsman, the Clod Stomper, and in this mode also the
  **Worm Archer** (its missed arrows stay on the ground) and the **Worm Brawler** (its blows knock
  rocks loose);
- the left column holds light things: a pot, a honey jar (stick), a puffball (sleep), a snowball
  (freeze), a glass float (shatter), a rock (it rebounds: a toadstool stood here until 2026-11-16);
- the right column holds a crate, an ice block (freeze), a kettle (pierce), a crystal cluster
  (shatter) (all medium), then a keg and an iron ball (pierce) (heavy);
- each thing comes back 4 s after it is taken;
- **F6** steps the Gulp's level 1, 2, 3, 1; **Shift+F6** turns the aim help on or off; **F1** flips
  the throw's feel between new and old, **Shift+F1** the rebound, **Ctrl+F1** enemies as ammo (a
  label under the pen shows them all); **F4** respawns the
  pen, **F5** fills the energy (shapes testbed).

The playground starts at level 1 (`playgroundLevel`).

## How it plays

Since 2026-11-16 the throw's feel is reworked ([The throw's feel](#the-throws-feel-2026-11-16):
more damage, a faster and bigger thing, thrown on the key press, a real knockback, chains, a kill
that pops). The damage, speed and knockback numbers in this section are the ones with that feel
switched off; the rules (weights, effects, what a throw reaches) hold either way.

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

## The throw's feel (2026-11-16)

Owner, 2026-11-16: "it does not feel so fun to throw things at enemies ... I used to enjoy throwing
pots in Zelda, it was a strong hit and the monster got pushed back with nice effects and sounds."
His first complaint was the weak impact. The numbers and looks above this section describe the
throw with the feel **off**; with it on (the default, `gulp.throwFeel.enabled`) the throw is this:

| | Feel off (before) | Feel on |
|---|---|---|
| A light pot | 25 damage: two for a 40-health enemy | 40 (`throwFeel.throwDamage`), x material x weight x effect as before: a crate 72, a keg 120 |
| Flight | 560 px/s, 280 px, a 30 px picture | 860 px/s, 320 px (before the weight's scales), 46 / 56 / 66 px by weight (`lookPx`), a longer streak |
| In the mouth | 22 px, see-through | 34 px, solid (`heldLookPx`, `heldAlpha`, `heldRisePx`) |
| The key | thrown on the Q release, the slime locked about 300 ms | thrown on the Q press (`throwOnPress`; an essence keeps its tap and hold), locked `thrower.lockMs` |
| The break | where its centre came within 30 px of a hurtbox: short of the body | it meets at 30 px as before, then flies on until it touches the body (`contactPx`, at most `contactFlightPx` further); what it met is struck even if it stepped away |
| The hit | hit-stop 50 ms, six sparks, a small white number | per weight (`hit.<weight>`): hit-stop 90 / 120 / 150 ms (+`killStopMs` on a kill, up to `hitStopCapMs`), trauma, a camera kick, a star burst at the contact point (`star`), then a ring, the big yellow number |
| Shards | 3 x 3, dropping where it broke | on a hit 4 x 4 flying on along the throw; a miss on the ground or a wall keeps a smaller, duller burst (`shards.hit` / `miss` / `wall`) |
| The enemy | one white frame, a 52 px slide | a hard white flash that blinks, a shake during the freeze, knocked back `hit.<weight>.knockbackPx` x its `knockbackScale` (a light enemy 150 px by a light pot, in about 0.3 s) with a squash, a hop, afterimages and dust, then its verb's own motion (daze, fall, wobble) |
| Chains | never (only a launch could splat or bowl) | a knocked enemy splats on a wall (`combat.rules.wallSplat`) and bowls into other enemies: both take `bowlDamage` (15; a boss keeps 4), passed on `combat.rules.bowling.chainPasses` times |
| A kill | the corpse lay 800 ms and vanished | the send-off: the corpse flies back blinking and pops (`combat.rules.killSendoff`), with the `ThrowKill` sound at the pop |
| Sounds | `GulpSpit` on the throw, the material's break cue | `ThrowToss` on the throw; the material's break cue is the hit sound, pitched down for heavier things (`breakPitch`) |

A throw that deals no damage (a sleep throw, an immune enemy) keeps the soft old feel: no star, no
push, no hard flash. Enemies whose `knockbackScale` is 0 still stay put; a killed one pops in place.
The Goo Bomb and essences are untouched.

**The sound is the thing's own** (owner, 2026-11-16, Sound Picker round 11): "the hit sound depends
on the object that hits; the pot already makes a sound when it breaks on an enemy and that should
be enough; the other materials should have their sound as much as possible, that will give
identity to each type of material." So there is no generic impact thump: each material's break cue
is the hit. Snow, crystal and bone got cues of their own in round 12 (`BreakSnow`, `BreakCrystal`,
`BreakBone`; they borrowed the soft, glass and wood ones before; the old cue plays while a new
node is missing). The rounds: [TOOLING.md](../TOOLING.md), [specs/audio.md](specs/audio.md).

**Trying it.** In the playground's throw yard **F1** flips the feel between new and old for the
session (the yard's title shows it; "Throw feel: new/old" over the slime).

**How it is wired.** `game/throw/throw_feel.gd` is the switch and reads `gulp.throwFeel`. With the
feel on, the thrown hit (`thrown_object.gd` `rework_hit(direction, class, weight)`) carries the new
`knock_px`, `knock_speed_scale` and `launch_speed` and these fields, which the enemy's side reads
(`combat/reactions/enemy_reactions.gd`); a hit without them reacts as before:

| Field | What the enemy does with it |
|---|---|
| `big` | the hard flash and the freeze shake, when the hit dealt damage (`HitJuice.is_big` also shows the big number) |
| `knock_motion` | the knocked-back motion (`EnemyHitMotion` `KNOCK`, numbers in `combat.verbs.knock`) before the verb's own |
| `chains`, `bowl_damage` | the stun slide opens the launch window while it is faster than `wallSplat.minSpeed`, so splats and bowling run |
| `kill_sendoff` | a kill flies off and pops (`enemy.gd` `begin_sendoff`; never a boss or a dummy) |

Loot and the quest's death event still happen where and when the enemy died, not at the pop.

**The small things.** A miss (the ground, a wall, a blow that hurt nothing) plays its material cue
`missVolumeDb` (-5 dB) quieter (`sfx_player.gd` `play_cue` takes a `volume_db` offset in its
payload, played on a one-off copy of the player). An empty suck no longer roots the slime for the
whole burst: with nothing flying in after `emptyBurstMs` (180) it ends, with a cooldown of
`emptyCooldownMs` (120) (measured: 183 ms rooted against 517 ms with the feel off).

### Sturdy things rebound, and the mouth catches them (prototype)

`gulp.throwFeel.rebound.enabled` (on); **Shift+F1** in the throw yard flips it. From Zelda's sturdy
thrown things (they ricochet instead of breaking) and Yoshi's eggs (the catch is rewarded); it also
serves the owner's "identity for each material": clay, glass, wood, soft things, ice and snow
shatter, **stone, metal and bone are sturdy**.

- A sturdy thing has `uses.<material>` hits in it (stone 3, metal 5, bone 2; the count travels in
  the held Dictionary's `uses` and on the thing lying on the ground). A hit that hurts an enemy
  spends one: the star, a few chips, the material's cue, and the thing arcs back with its shadow
  to land `returnShortPx` (44) in front of where it was thrown from (never past the thrower;
  `reboundMinPx` .. `reboundMaxPx`, at `reboundSpeed` at most), with dust and a low quiet thud, as
  the same liftable again. On its last use it shatters with the full break (a darker tint warns,
  faintly).
- A miss spends no use: it hops `missReboundPx` on (or back off a wall) and lies there. A piercing
  metal thing spends a use per enemy and lies at the end of its flight.
- It lands only where a liftable can lie (`ThrowAmmo.fits`: its level, walkable, clear of walls,
  water and bodies, a clear line to it), trying `tries` shorter spots; with none it shatters.
- **The catch**: Q with an empty mouth while a rebound from a hit is in the air within
  `catchRangePx` (110) of the slime's feet, from `catchFromMs` (120) after the bounce, takes it
  straight into the mouth: no suck burst, no root, a streak, a sparkle ring and "Catch!". The next
  throw of it is a **hot throw**: x `hotDamageScale` (1.25) damage, x `hotSpeedScale` (1.15) speed,
  a warm glow. A hot throw that rebounds can be caught again; the bonus does not stack. Standing
  still after a 190 px hit, the window opens about 0.28 s after the hit-stop and lasts about 0.23 s.
- Bones and skulls (the only bone things) are laid back as a spent shot for `shotLifeMs`; this
  path has not been run.

Code: `game/throw/throw_rebound.gd` (the arc, the landing, the catch), `throw_glow.gd` (the hot
glow), `throw_impact.gd` `snap`, `throw_ammo.gd` `fits` and the spawn options.

### Stunned enemies as ammo (prototype)

`gulp.throwFeel.enemyAmmo.enabled` (on); **Ctrl+F1** in the throw yard flips it. Kirby, Klonoa,
Super Mario Bros. 2: the enemy you just stunned is the next thing you throw.

- **Who**: an enemy that is not a boss, not rooted (`knockbackScale` 0), light enough for the
  Gulp's level (tiny and light at level 1, medium at 2, heavy at 3: `ThrowMode.can_lift`; "Too
  heavy!" otherwise), while it lies helpless from a throw: dazed, knocked down, staggered, frozen
  or asleep, its knock's flight over, outside the wake guard and the `noSleep` phases
  (`EnemyReactions.is_helpless`). A body bowled into in a chain ends its tumble dazed
  (`combat.rules.bowling.chainDazeMs`), so it counts too. So the weak throwables have a job: a
  snowball or a puffball sets an enemy up.
- **Shown**: within `hintRangePx` of the slime a gulpable enemy pulses a goo-green ring at its feet
  and a green outline (`enemyAmmo.hint`).
- **Carried**: the suck takes it into the mouth as any suckable (`game/throw/gulpable_enemy.gd`);
  it is hidden and out of play, never dead (`enemy.gd` `begin_carry`, `end_carry`, `is_carried`:
  rooms, quests and placed enemies still count it as standing). The mouth shows its own picture,
  wriggling (`gulped_enemy_look.gd`). After `holdMs` (3 s; it wriggles harder for the last `tellMs`)
  it bursts out `outPx` (52) to the slime's side, away from its facing ("Ptoo!"), dazed `outDazeMs`; a hit on the slime, or anything else
  that empties the mouth, puts it out the same way. It is not saved in the mouth across a door or
  a save.
- **Thrown**: it flies like a thing of its weight. What it hits takes `damageScale` (1.5) x the
  base throw damage (60) as a `thrown-medium` hit with the whole feel; the thrown enemy reappears
  at the contact point (the nearest spot back along the throw where a body fits) and takes the
  same through its own damage path (class `landing`: a knockdown), so a death is a real death
  (reward, quest event, the send-off). On a miss it lands for `missDamageScale` (0.75) x the base
  and lies knocked down, to be gulped again. An enemy immune where it lands takes nothing there.
- It is never sturdy and never hot, and the rebound's catch cannot take it.

Filmed: `s-ammo-gulp`, `s-ammo-throw`, `s-ammo-snowball`, `s-ammo-miss`, and `r-carry-hit` (a Worm
Brawler hits the slime while it carries a spider: the spider comes out beside it, alive, once, and
the `enemy` group counts it once again). Not staged yet: a carried enemy put out by a hazard hurting
the slime, asleep enemies as ammo, a door or a save while carrying, a live room fight with one in
the mouth.

### Knocked enemies and the ground (2026-11-16)

Owner, 2026-11-16: "if enemies are pushed against an edge that has no fence and they can fall, they
should fall; if it is an endless hole they should die, disappearing as they fall, becoming smaller
until gone, similar to Zelda; in deep water they should drown if they are not aquatic creatures;
and in danger zones they should receive the damage as the player does until they get out or die."

`combat.rules.hazards` (`enabled`), `game/combat/reactions/enemy_hazards.gd`. Only a body a blow
moves is looked at: a knock's slide, a launch, a bowl, a sliding corpse (while it is faster than
`minSpeed` 140), and a thrown enemy's landing. An enemy's own walking never takes it off a rim,
into a hole or into water, and one that wanders into spikes by itself is not hurt. Bosses and
rooted enemies are never moved, so never affected. Each fate reuses the slime's own test:

| Where | The test (the slime's) | What happens |
|---|---|---|
| An unfenced ledge | `Elevation.drop_target`: a rim that drops, no fence, no wall, room below | it falls in the drop's arc and time, lands knocked down `fall.stunMs` (1200) with dust, takes `fall.damagePerLevel` (15) per level, and lives on that level from then on (its territory and leash dropped, a patterned enemy's home moved to the landing). A fenced rim, a wall, or a rim with no room below still stops it with the splat. A corpse stops at the rim and pops there |
| An endless hole | a void `Hazard` (the sky floor's included) | it dies at the rim, so its reward and the quest's death event happen there and the loot stays in reach; the body glides `hole.overPx` out, spins and shrinks to nothing with the `FallDown` cue, then `ThrowKill`. A send-off corpse that reaches the rim falls away the same way. A hole painted deep with no void hazard over it is a plain ledge |
| Deep water | the `deep-water` tile test (not bridged), or a water `Hazard` | it dies at the bank with the splash, glides `water.overPx` in, sinks and fades, then `ThrowKill`. `aquatic` types are stopped by the bank; shallow water is ground |
| A danger zone | a spikes or lava `Hazard` | a body that comes to lie in one (or falls into a sunken one) takes the hazard's own damage at once and then every `character.player.hitInvulnerabilityMs` (500), until it is out or dead; on its legs again it walks out the shortest way at `zone.walkOutSpeed` and is left alone (it cannot walk out of a sunken pit) |

A kill by any of them counts for the pop streak. Per-type flags in an enemy's `reactions`
(enemy-types.json): `flies` (rook-thief, glint-bat, ledge-raven: holes and water do nothing),
`aquatic` (none yet), `hazardProof` (a list of "fall", "void", "water", "spikes", "lava"; none yet).
A thrown enemy (enemies as ammo) that comes down over a hole or deep water dies on ground back
along the throw (`enemyAmmo.fateBackPx` (40) behind the edge, so its loot is not dropped in the
water) and its body falls or sinks where it came down; off a ledge it lands
below and lives; in a zone the zone starts hurting it.

Filmed with the slime spider (`r-fall-ledge`, `r-fall-fence`, `r-hole`, `r-hole-kill`, `r-water`,
`r-zone`), a Worm Swordsman and a Hopper (`r-swordsman-ledge`, `r-hopper-ledge`,
`r-swordsman-hole`, `r-hopper-hole`), and thrown enemies (`r-ammo-hole`, `r-ammo-water`,
`r-ammo-ledge`, `r-ammo-zone`). An essence dropped by an enemy drowned this way has not been seen
on the bank (its drop is random). Not run yet: flat danger zones and the walk-out (the only spikes found are a sunken
pit), lava, a water hazard under plank bridges, falls of more than one level.

### Filming a throw

`godot/tools/film_throw.gd` stages one throw in the playground (the slime, a liftable beside it, an
enemy standing in front) and saves every frame; `scripts/godot/throw-film-sheet.py` lays the frames
out as a strip and two GIFs; `scripts/godot/film-throw.sh` runs both, one film at a time (two game
windows rendering at once stall each other, so it waits on a lock folder):

```
bash scripts/godot/film-throw.sh <name> --title="..." [--enemy=<type>] [--kind=<liftable>]
    [--gap=<px>] [--frames=<n>] [--throws=<n>] [--dir=right|left|up|down] [--gulp=<1..3>]
    [--second=<type>@<px>[,<px aside>]] [--wall=<px>] [--back-wall=<px>] [--side=<px>]
    [--catch-at=<frame>] [--uses=<n>] [--empty-suck] [--drop-at=<frame>]
    [--ammo=<gulp frame>[,<throw frame>]] [--ammo-gap=<px>] [--ammo-wait=<frames>]
    [--ammo-dir=right|left|up|down] [--attacker=<type>@<dx>,<dy>] [--attacker-at=<frame>]
    [--stage=<x>,<y> (the slime's feet)] [--map=<world id>]
    [--set=<constant path>=<number>] [--crop=x,y,w,h] [--step=<n>] [--cols=<n>] [--zoom=<n>]
```

It writes `output/throw-feel/<name>/` (git-ignored): `fNNN.png`, `film.json` (the enemy's health
after each throw, each frame's pause state and the enemies' tracks), `godot.log`, `strip.png`,
`throw.gif`, `throw-slow.gif`. `--set=gulp.throwFeel.enabled=0` films the old feel. The film runs
with `--fixed-fps 60` and sets GameFeel's `frame_clock_ms`, so a hit-stop lasts its true number of
frames. The baselines of 2026-11-16 are the `before-*` films.

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

The reworked feel is `gulp.throwFeel`: `enabled`, `throwDamage`, `throwSpeed`, `throwRangePx`,
`throwOnPress`, `bufferThrowMs` (a Q press this late in a suck throws on the catch; 0 = off),
`lookPx.<weight>`, `heldLookPx`, `heldAlpha`, `heldRisePx`, `hit.<weight>` (`hitStopMs`, `trauma`,
`kickPx`, `sparks`, `knockbackPx`, `knockbackSpeedScale`, `launchSpeed`), `killStopMs`,
`hitStopCapMs`, `chains`, `bowlDamage`, `contactPx`, `contactFlightPx`, `cues` (`toss`, `kill`),
`breakPitch.<weight>`, `missVolumeDb`, `emptyBurstMs`, `emptyCooldownMs`, `streak`, `star`,
`shards.<hit|miss|wall>`, `thrower`, `rebound` (the sturdy things' prototype) and `enemyAmmo`
(enemies as ammo). The enemy's side is in
`combat`: `verbs.knock` (the knocked-back motion: `flightMs`, `hopPx`, `hopFloor`, the squash and
stretch, `tiltRad`, `afterimages`, `dustEveryPx`, `shakePx`, `shakeMs`, `starScale`, `flash`),
`verbs.launch.maxSpeed` (960), `rules.bowling.chainPasses` and `chainFeel`, `rules.killSendoff`
(`minScale`, `pace`, `minMs`, `maxMs`, `stillMs`, `popScale`, `puff`, `ring`, `puffs` by material,
`cue`, `flash`), `rules.hazards` (`enabled`, `minSpeed`, `fall`, `hole`, `water`, `zone`), the hit
class `landing` (a thrown enemy's own landing).

The Gulp's level in a run: 2 once the run learned `gulp-lift-medium`, 3 once it learned
`gulp-lift-heavy` (RunState abilities, saved). Nothing in the story grants them yet.

## Code

| File | What it does |
|---|---|
| `game/throw/throw_mode.gd` | the mode, the Gulp's level, weights, effects (`weight_in`, `effect_in` for the editor too), the aim help, shape-power ids |
| `game/throw/throw_feel.gd` | the reworked feel's switch and numbers (`is_on`, `toggle`, `hit_block(weight)`, `look_px`, `cue`) |
| `game/throw/throw_impact.gd` | the star burst and ring at the contact point, the puff at the mouth (code-drawn, real time) |
| `game/player/gulp/break_burst.gd`, `gulp_feel.gd` | the shards by cause (`burst(..., options)`); the thrower's strong stretch, lunge and recoil |
| `game/feel/enemy_hit_motion.gd`, `hit_flash_curve.gd`, `daze_stars.gd` | the `KNOCK` motion and the shake in the freeze; the flash's blink; bigger stars |
| `tools/film_throw.gd`, `scripts/godot/film-throw.sh`, `throw-film-sheet.py` | filming a throw frame by frame |
| `game/throw/throw_rebound.gd`, `throw_glow.gd` | a sturdy thing's rebound, landing and catch; the hot glow |
| `game/throw/gulpable_enemy.gd`, `gulped_enemy_look.gd` | a helpless enemy as a suckable, carried and thrown; its picture in the mouth |
| `game/combat/reactions/enemy_hazards.gd` | knocked enemies at ledges, holes, deep water and danger zones |
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

**2026-11-16, the feel rework** (one session, a coordinator and three builders, judged on filmed
throws; nobody has played it with a keyboard yet and the test suite was not run): the reworked
throw, the enemy's knocked-back reaction, chains, the kill's send-off, the toss and kill sounds
and three new material sounds (Sound Picker rounds 11 and 12, the owner's picks), a hard limiter
on the master bus, the rebound and catch prototype, enemies as ammo, and knocked enemies meeting
ledges, holes, deep water and danger zones. Each part's own "not run yet" list is in its section
above. Still to judge by playing: the damage (one pot now kills most light enemies, so ammo
placement decides a room's difficulty), the rebound's catch window, how often enemies as ammo
comes up at Gulp level 1 (a medium enemy needs level 2), and every sound in the mix. A knock or
clang of their own for sturdy things bouncing off an enemy (they play the break cue) is not made.

The older notes below are from the first build.

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
