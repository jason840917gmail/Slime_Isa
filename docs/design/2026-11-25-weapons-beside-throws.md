# Weapons beside throws: one combat

**Status: approved by the owner on 2026-11-25** ("yes throws only daze them, approve and start"): the
weapon scale of 0.5, the material table with its three one-weapon materials, the 1.5 s liftable
window, and a thrown thing only dazing a one-weapon enemy (replaced on 2026-11-26: throws hurt all
three, section 4). Being built piece by piece (the table at
the end), each piece read by the reviewer. Written 2026-11-25 from his decision of that day, after he
played `?melee` against the game as it is.

His words: "the only throw route we take a while ago is not that fun, losing a source of damage at all
times like we use to have with the spear axe and hammer is huge." And: "i want to bring it back with
some adjustments in damages and key changes so we don't lose anything we have built on the throw mode
which is incredible. so we are going to move spear axe and hammer to be weapon but with less damages,
they will keep the combos, some monster will be immune to spear or axe or hammer or all weapons what
make throwable still a good source of damage. the weapon will keep their charge attack, on spear lower
the range attack of top. on the keys ... S will stay as roll and D will be ability. Q suck and W
interact." His five answers: E switches weapons and abilities are chosen in the B panel; charge
attacks are free, their cost is the charging time; a combo can stun or incapacitate so enemies can be
sucked up and thrown, and enough hits kill; keys only stays, the other schemes go; the Spear's upward
strike reaches much farther than its others and gets shorter.

## What exists today (checked in the code, 2026-11-25)

- **Two modes on one base.** The body shapes are always on. "Throw mode" is a switch on top
  (`gulp.throwCombat.enabled`, off with `?melee`): on, the attack key does nothing, the shapes are
  energy powers in the Ability Box, E opens an ability carousel, and thrown things have weights,
  effects, the new feel and enemies as ammo. Off, the attack key strikes, E cycles shapes, and a throw
  is a plain 20 with none of that.
- **`project.godot` passes `-- --melee`** to every run from the editor since the owner set it on
  2026-11-25 to try the melee game (uncommitted; it goes when the switch goes). The web build and the
  launch options play throw mode. The test suite plays with throw mode off; only
  `test_throw_combat.gd` turns it on.
- **Damage today.** A light throw 40, medium 72, heavy 120. Spear jab 14, 16, finisher 21, Lunge 25;
  Axe 18, 21, chop 27, Spin 40; Hammer thud 36, boom 54, Quake 72. Most enemies have 20 to 40 health:
  one light throw or three Spear jabs.
- **Charges cost energy in both modes** (15, 20, 25) after their ring (0.85 s, 1.15 s, 1.25 s held).
- **A weapon's stun never makes an enemy liftable.** Only a stun from a thrown hit does.
- **Immunity is per enemy script.** Eleven enemies already refuse some hits (the Bulwark clinks the
  Spear, the Jelly shocks every weapon, the Carnivore Plant takes only thrown things), each by its own
  code. There is no shared "immune to the Spear" rule in the data.
- **The Spear's reach is measured from the slime's centre**, 28 units above its feet. Facing up its
  tip lands 138 units from its feet; facing down, 82. The Axe's and the Hammer's up strikes were
  shortened for this on purpose; the Spear's never was. Its wall check also starts at the feet, so
  facing up it pokes 28 units through a wall.
- **Keys.** The default scheme is still `keyboard` (WASD, mouse buttons); keys only is one of five.

## The combat after this plan

One game, no switch. Everything throw mode built stays on, and the weapon comes back beside it.

| Verb | Key | What it is |
|---|---|---|
| Move | arrows | |
| Attack | **A** | the current weapon: tap for its combo, hold for its charge |
| Roll | **S** | as today |
| Ability | **D** | the ability chosen in the bag |
| Gulp | **Q** | suck, throw, swallow, spit, as today |
| Interact | **W** | talk, open, grab, cling |
| Switch weapon | **E** | Spear, Axe, Hammer |
| Bag | **B** | weapons, abilities and skins are chosen here |

### 1. Weapons deal less

One number scales every weapon hit, `shapes.weaponDamageScale`, **proposed 0.5**:

| | Today | Proposed | Against a 40-health enemy |
|---|---|---|---|
| Spear jab, jab, finisher | 14, 16, 21 | 7, 8, 10 | two full combos |
| Spear Lunge (charge) | 25 | 13 | |
| Axe sweep, backswing, chop | 18, 21, 27 | 9, 11, 14 | a combo and a sweep |
| Axe Spin (charge) | 40 | 20 | |
| Hammer thud, boom | 36, 54 | 18, 27 | one combo |
| Hammer Quake (charge) | 72 | 36 | |
| Light, medium, heavy throw | 40, 72, 120 | unchanged | one light throw |

So the throw stays the heavy hit (one throw is worth a whole Spear combo and a half), and the weapon
is the hit that is always there. The combos, their timing, knocks and reactions do not change.

### 2. Charges are free

The charges lose their energy cost; holding the key through the ring is the price. Energy then pays
only for abilities (Slam 35, Goo Bomb 20, Lantern 10, Bow 6) and the charged Roll. The shape powers
leave the Ability Box, which holds true abilities only.

### 3. A combo sets up the throw

A combo's finisher or a charge that lands leaves the enemy **dazed and liftable** for a short window
(proposed 1.5 s; a heavy enemy when its poise breaks), if the Gulp's level lifts its weight. Q then
sucks it up and it is thrown as ammo, as a thrown hit allows today. Plain taps never do. Bosses are
never liftable. Enough weapon hits still kill.

### 4. Immunity the player can read

A shared rule in the data: each enemy type has a **material**, and each weapon has materials it cannot
hurt. A refused hit clinks as today (sparks, recoil, the combo broken); the first one against a
material shows a line and flashes the enemy.

| Material | Spear | Axe | Hammer | Thrown | Enemies (first pass) |
|---|---|---|---|---|---|
| flesh | hurts | hurts | hurts | hurts | the worms, spiders, Boar, Hopper, Rook Thief, Pick Mole, Glint Bat, Ledge Raven, Caterpillar, Popworm |
| shell | **clinks** | hurts | hurts | hurts | Worm Bulwark (as today), Shardback, Clod Stomper, Thorn Guard |
| bone | **clinks** | hurts | hurts | hurts | Bone Leaper, Bone Thrower, Bone Marcher |
| crystal | hurts | **clinks** | hurts | hurts | Crystal Crawler, Crystal Mite, Rock Chucker |
| silk | hurts | hurts | **clinks** | hurts | Egg Sac, Cocoon Mimic, Silk Lurker |
| plant | **clinks** | hurts | **clinks** | hurts | Spitcap, Thornball |
| untouchable | **clinks** | **clinks** | **clinks** | hurts | Jelly Bouncer (shocks), Carnivore Plant (as today) |

Enemies with their own rule keep it (the Squints' visor, the Pipe Worm, the Dung Roller's back, the
Gloomling, the Prism Eye, every boss). The table is a first pass for the owner to change.

**One-weapon enemies** (owner, 2026-11-25: "there have to be enemies that only one weapon hurt them,
maybe for later chapters so the later weapons like axe and hammer have a real use"). Three more
materials, each hurt by one weapon only:

| Material | Spear | Axe | Hammer | Thrown | Reads as |
|---|---|---|---|---|---|
| bark | clinks | **hurts** | clinks | hurts (owner, 2026-11-26) | wood and thorn: only a blade cuts it |
| iron | clinks | clinks | **hurts** | hurts (owner, 2026-11-26) | plate and stone: only a crushing blow dents it |
| eye | **hurts** | clinks | clinks | hurts (owner, 2026-11-26) | a small weak point: only a point reaches it |

- ~~A thrown thing dazes such an enemy but does not hurt it (approved)~~: replaced on 2026-11-26.
  **Throws hurt them** (the owner, of the Clod Stompers: "Keep them Hammer-only", then "but why throw
  dont hurt them? they should take damage from throws"; then of all three: "when i said only ona
  weapon hurt them that does not include throws, the rule is only for weapons, spear axe and hammer"):
  the one-weapon rule decides only among the Spear, the Axe and the Hammer, and a thrown thing hurts
  bark, iron and eye as it hurts flesh (the hit's damage, its knock, a wall splat, a bowl). The table's
  `thrown` column, its lines and the "dazes" path in the code went with it.
- ~~Only its weapon (2026-11-26): the abilities clink too (arrows, the Goo Bomb, the Lantern's flame,
  the Roll, slams)~~: the reviewer's reading, not the owner's words; replaced the same day. **The
  abilities hurt them** (asked "Should arrows, the Goo Bomb and the other abilities hurt one-weapon
  enemies too?", the owner, 2026-11-26: "Yes, they hurt", then "until i decide otherwise"). It is his
  decision for now: going back means a per-material rule refusing the abilities again (what the
  removed `only` key did). So the rule is only this: of the Spear, the
  Axe and the Hammer, one hurts and the two others clink; everything else hurts as on a flesh enemy. The
  rows are plain `refuses` rows (bark: spear, crush; iron: spear, cut; eye: cut, crush); the `only`
  key, `lines.ability` and the code's one-weapon branch went. The Thorn Guard's Heavy Roll kill stands
  again, and an open Squint takes arrows, a blast, the flame, the Roll and slams (new against 2026-10-22,
  the owner told and agreeing).
- **Never before its weapon.** A one-weapon enemy stands on a chapter's main way only after that
  weapon is earned; earlier it may guard a secret to come back for. The build checks where each
  weapon is earned before placing any.
- The rule goes in with piece 4; the enemies come with their chapters. **Among today's enemies**
  (the owner, 2026-11-26: "one wepon follow your suggestion"): the Thorn Guard is bark (the Axe
  only), the Clod Stomper iron (the Hammer only), the Squints eye (the Spear only among the weapons;
  open, a throw hurts them as before). Piece 4 checks where each of
  the three stands against where its weapon is earned, and moves or swaps any that stand on a main
  way too early. New enemies for the later chapters are designed to it:
  each chapter after a weapon is earned gets at least one enemy that only that weapon hurts.

### 5. The Spear's upward strike

Its up strikes are shortened so the tip lands as far from the slime's feet as it does sideways (jab
110 to 82.5 units from the centre, finisher 132 to 104.5, the Lunge 170 to 142.5: the centre is 27.56 above
the feet, so the "about 100" first written here would have left the up tip 18 units long), and the
wall check is measured from where the reach is. Shown to the owner before and after, side by side, in
all four directions, before it is kept.

**Facing down too** (the owner, 2026-11-26: "match the spear down reach with the sides"): the down
strikes are lengthened the same way, so the tip lands as far from the feet in all four directions.

### 6. Keys only

The four other schemes go (about 1,800 lines: the click-to-move routes, orders, pointer facing, the
F2 switch, the Settings button, two test files). The keys above become the game's only layout. The
ability carousel goes; the bag's Abilities row already puts an ability on the key.

## What changes for bosses

They count Spear hits that used to cost energy. With free hits at half damage their length comes out
close to today's (the Colossus's crystal: 60 health, two and a half Spear combos; Fatty's eye: a combo
per opening), but each is re-filmed and tuned: Fatty One Eye, the Matron, the Colossus, the Brood
Warden, the Shardback, the Bulwark, the Big Squint. A thrown thing on a boss stays 6.

**Measured (piece 6, 2026-11-26).** Fatty's eye shuts after any hit that lands, so it takes one hit an
opening, not a combo: at half damage each phase needed six Lunges instead of three. Five fights left
their openings and moved by one data value each; the Colossus and the Bulwark did not
([the table](2026-11-24-health-and-damage.md#the-bosses-and-mini-bosses-one-combats-piece-6)).

## What is lost, and what it costs

- The rule "no ammo = flee" and the tension that every throw counts.
- The shape powers as abilities (their charges live on the weapon instead).
- The four mouse schemes, for good.
- The damage grid of 2026-11-24 is re-read with weapons in it.
- Tests: the suite plays with throw mode off today. With one combat, every test about throws, lifting
  and the Gulp runs against the throw rules (weights, 40 damage, levels), and the scheme tests go.
  Expect a wide test round.
- Texts: the prologue's hints, the Controls list, the bag's cards and a dozen hint lines name keys or
  the old modes; they read the key bindings, so most follow by themselves.

## The build, in pieces

Each ends in a film or a picture for the owner and a code read before the next.

| Piece | What | Shown |
|---|---|---|
| 1 | The Spear's up reach and wall check. **Built 2026-11-25**, awaiting the read: up `hit_reach` jab 82.5, finisher 104.5, Lunge `upReach` 142.5, and (owner: "match the spear down reach with the sides") down jab 137.5, finisher 159.5, Lunge `downReach` 197.5 (tip 110 / 132 / 170 from the feet in every direction); the wall ray measured from the line's origin ([BODY_SHAPES.md](../godot/BODY_SHAPES.md#the-spears-reach-2026-11-25)) | the four directions before and after (`output/combat/spear-reach/`) |
| 2 | One combat: the attack on A beside the throw rules, charges free, weapons out of the Ability Box, the new keys, E cycling weapons, the HUD's weapon slot, the carousel gone, `?melee` and the editor's run argument gone, the weapon damage scale. **Built 2026-11-25/26**, awaiting the read: `shapes.weaponDamageScale` 0.5 in `ShapeDefs.damage`; charges without `energy`; `power_strike` and the carousel removed (`fire_charge` kept for the film tools); one keys-only `LAYOUT`, the default for a fresh settings file; the bag's top row titled Weapons; texts follow ([THROW_COMBAT.md](../godot/THROW_COMBAT.md#one-combat-2026-11-25)) | `output/combat/one-combat/`: the strip (five checks, all PASS), the GIF, the HUD, the bag and the Controls list |
| 3 | A combo's daze makes an enemy liftable. **Built 2026-11-26**, awaiting the read: `combat.rules.weaponDaze.windowMs` 1500 for a combo's last step (the hit's `last`: the Spear's lunging jab, the Axe's chop, the Hammer's BOOM) or a charge, on the throw's helpless path (EnemyReactions `_note_weapon_daze`, `_start_weapon_daze`); a heavy enemy on a poise break, a boss never, taps never; the first daze of a run shows the Gulp's hint and flashes the enemy (`weapon_daze_hint.gd`) | `output/combat/combo-daze/film/`: the strip (seven checks, all PASS, the Hammer's BOOM among them) and the GIF |
| 4 | Materials and immunity, the first-clink line. **Built 2026-11-26**, awaiting the read: `reactions.hitMaterial` for every non-boss type and `combat.materials` (refuses, thrown, lines), applied in `HitReaction.gate` (`material_gate`); the Squints' tag rule and the Bulwark's `spear` clink folded in; the Shardback brittle is flesh (its fight keeps the Spear); a throw on bark, iron or eye dazes, no harm, not liftable, and the abilities clink on them (both replaced 2026-11-26: throws and abilities hurt all three, section 4) ([BESTIARY.md](../godot/BESTIARY.md#materials-2026-11-25-one-combat-piece-4)) | `output/combat/materials/film/`: the strip (ten materials, all PASS) and the GIF |
| 5 | The other schemes removed. **Built 2026-11-26**, awaiting the read: the four mouse schemes' code (`game/player/mouse/` but `key_bindings.gd`, `pointer_aim.gd`: about 1,540 lines), the player's orders, pointer facing and pointer aim (about 480 lines), F2 (`control_scheme_next`), the `control_scheme` setting and the Settings window's Mouse button, `input.mouse` in the data, the scheme branches in the Controls list, hints, prompts and windows, the click orders' `reaches` checks, and `test_mouse_controls.gd` / `test_mouse_paths.gd` (615 lines; `test_keys_only.gd` keeps what the keys-only scheme itself needs); `?aimhelp` stays (the throw rules'); the experiment's doc archived ([MOUSE_CONTROLS.md](../godot/MOUSE_CONTROLS.md)) | `output/combat/keys-only/`: the Controls list and the HUD |
| 6 | Bosses re-filmed and tuned, the damage grid doc, the tests, the docs. **Built 2026-11-26**, awaiting the read: each fight measured against the old 25-damage Lunge; five moved by one data value each in `enemy-types.json` (Fatty's `parts.eye.damageTaken` 2, the Big Squint's `states.open.damageTaken` 1.3, the Matron's `states.fight` / `volley-telegraph` / `volley-rest` 1.35, the Brood Warden's `states.planted` / `knocked` 1 to 1.6, the Shardback's `pattern.brittleDamageTaken` 1.6 to 2.5); the Colossus and the Bulwark untouched; `tests/test_boss_spear.gd`; `film_colossus.gd`'s claw strikes on A (they still pressed Q); the damage grid re-read ([its last section](2026-11-24-health-and-damage.md#with-weapons-the-one-combat-2026-11-26)) | the Crown's round1, ram-catch, round3 (`output/dungeon-rework/hollow/crown-films/p6-*`), the arena's phases (`output/dungeon-rework/mine/arena-films/p6-phase1`, `-phase2`, `-phase3b`), `output/combat/bosses/warden-ram`, `.../shardback`, `output/enemy-ways/p6-bulwark-wall`; Fatty and the Big Squint have no film tool |

## For the owner's yes

1. The weapon scale of 0.5.
2. The material table, and the three one-weapon materials.
3. The 1.5 s liftable window after a finisher or a charge.
4. Whether a thrown thing hurts a one-weapon enemy or only dazes it (answered 2026-11-26: it hurts).
