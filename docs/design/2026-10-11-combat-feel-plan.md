# Combat Feel: Combos, Reactions and Juice

*Status: a plan to discuss, on branch `exp/body-shapes` only. Nothing is built. Written 2026-10-11 from the owner's idea (3-hit combos where only the last hit knocks back, a reaction profile per enemy, much shorter cooldowns, fun hits), a survey of the combat code, research into other games and game feel, two designers and a checker. Goes with the [body-shapes plan](2026-10-11-body-shapes-plan.md). All values are starting values for the grey box; every number goes into `game-constants.json` or the enemy data, never into code. Built since as the body-shapes prototype ([BODY_SHAPES.md](../godot/BODY_SHAPES.md)); the owner's playtest of 2026-10-12 changed several rules and numbers of sections 3-8: [section 11](#11-owner-playtest-2026-10-12) lists them, and where it differs from the sections above, it wins.*

## 1. The idea in five lines

1. Every attack is a chain of 3 steps (the Hammer has 2). Steps 1-2 **hold** the enemy in place. The last step **launches** it.
2. Every enemy has a **reaction profile**. One shared function reads the profile and decides what each hit, charge and ability does to that enemy. So one enemy breaks the Roll, and another is bowled aside.
3. Holds keep the enemy in reach, so the time between presses drops from 760-1300 ms to 170-460 ms.
4. Three rules stop endless stun-locks: after two holds the enemy breaks free, a 400 ms wake guard follows every launch, and heavy enemies have armor and poise.
5. Every hit should be fun to see and hear: a short freeze, a white flash, a squash, sparks along the hit and a rising sound. The finisher adds a tumble, a wall splat or a pop.

## 2. Ideas taken from other games

| Game | Mechanic | What we take |
|---|---|---|
| Hades (Stygian Blade) | Strike, Chop, Thrust (20 / 25 / 30). Only the Thrust knocks back. Armored elites ignore stun until their armor bar breaks. Hitting a wall adds damage. | The 3-hit rule as it is. Armor and poise for heavy enemies. The wall splat. |
| Cult of the Lamb | Players complain that knockback on early hits pushes enemies out of range before the finisher. | Hits 1-2 never move the body. The finisher reaches further and takes a step. |
| Streets of Rage 4 | Spaced single jabs keep resetting the chain and lock an enemy forever. | The hold cap: two holds, then the enemy breaks free. |
| Kingdom Hearts II/III (Revenge Value) | An enemy hit many times without acting bursts out of the combo. | Break-free moves: counter-slash, hop back, skitter. |
| Super Smash Bros., Sakurai's columns | Weak hits flinch in place and strong hits tumble. Hit-stop grows with damage and has a cap. The victim shakes while frozen. Kirby's "boss stop" slows the last blow. | Hold below a threshold, launch above it. Hit-stop by step and shape. Victim jitter. The room-clear slow motion. |
| Dead Cells | Light hits only delay a heavy enemy's attack. The last hit of many combos is a sure crit. | Armor pushes a wind-up 60 ms later. The finisher looks and sounds like a crit. |
| Elden Ring, Sekiro | A hidden stance meter. Breaking it opens a big window. | Poise for heavy enemies. A daze meter for bosses (one clod empties Fatty's). |
| Monster Hunter | Hit-stop depends on weapon weight. Wrong hits bounce off hard parts. | Shape weight sets the hit-stop. The clink with a recoil. |
| Hollow Knight | A nail swing about every 0.41 s. The Knight recoils on every hit. | A short cadence. The slime recoils 6 px on a finisher and 24 px on a clink. |
| Zelda (A Link to the Past, Minish Cap), Enter the Gungeon | Pegasus Boots plow through small enemies and bonk off walls. A dodge roll into an enemy headbutts it. | One Roll outcome per enemy: bowl, bonk or break. |
| Kirby | The inhale pulls small enemies in. A spat star hits through them. | The suck tugs light enemies. A launched enemy bowls over others. |
| God of War (2018) | Reactions show where the blow came from. Audio carries the weight more than shake. | The Spear jolts back, the Axe twists sideways, the Hammer flattens. Layered hit sounds. |
| Vlambeer (Nuclear Throne), Celeste source | A white frame, tiny freezes, layered material sounds, debris that stays. Shake along the hit. Squash grows with speed. | A white flash, then the tint. Material sounds. Splats that stay 4-8 s. Directional shake. |
| Squirrel Eiserloh, GDC 2016 | "Trauma" shake: events add trauma, shake = trauma², smooth noise. | Replaces today's camera shake, which drops a new shake while one runs. |
| Hyper Light Drifter, Death's Door | Melee hits refill the special meter. | Hits give energy back for charges. |

## 3. The hit model

**Words used below**
- **Step**: one press of Attack. **Contact**: the moment a step's hitbox can hit.
- **Cancel point**: the moment the next step may start. A press during a step, from its first active frame, waits and fires at the cancel point.
- **Link window**: 150 ms after the cancel point (the same as today's input buffer). A press inside it still continues the chain. A later press starts again at step 1.
- **Hold**: the enemy stops where it is. Only its picture moves.
- **Launch**: the enemy flies away.
- **Tier** (1-3): how hard a hit is to absorb. **Poise**: how much a hit drains from a heavy enemy's poise pool.

**Impact classes.** Both the player side and the enemy side use this list.

| Class | Sent by | Tier | Poise | Last? |
|---|---|---|---|---|
| `tap` | Spear and Axe steps 1-2 | 1 | 1 | no |
| `finisher` | Spear and Axe step 3 | 2 | 2 | yes |
| `smash` | Hammer Thud, Hammer BOOM | 3 | 4 | Thud no, BOOM yes |
| `charge` | Lunge, Spin ticks, Quake centre | 3 | 3 | Spin ticks 1-2 no |
| `ring` | Slam ring, BOOM ring, Quake cracks | 2 | 2 | yes |
| `slam` | Slam centre | 3 | 3 | yes |
| `thrown` | Pots, bricks, clods | 2 | 2 | yes |
| `roll` | Roll body hit (later) | 2 | 1 | yes |
| `suck` | Q burst cone (no damage) | 1 | 0 | — |

**What every hit carries.** A new `hit` Dictionary at the top level of the damage request. It must not go inside `impact`, because the resolver rebuilds `impact`.

| Field | Meaning |
|---|---|
| `class`, `step`, `last` | The class. The step is 1-3 in a chain and 0 for abilities. `last` is true on the last step of a chain or charge |
| `tier`, `poise` | From the class; a step may override them |
| `shape`, `tags` | `spear` / `axe` / `hammer` / `""`, plus the tags `weapon`, `spear`, `cut`, `crush`, `slam`, `thrown`, `roll` |
| `hold_ms` | How long a hold lasts. The player side computes it from the timing (section 4) |
| `launch_speed`, `hop_px` | This step's launch |
| `knock` | Spear: along the aim. Axe steps 1-2: along the sweep. Everything else: from the slime or the impact point to the target. Today it is the swing's cardinal direction |
| `counts_as_hold` | false for rings, throws and the suck |

The hit also carries one effect, `{"effect_id": "impact", "potency": 1}`. With it, a hit with 0 damage (a clod on Fatty's body) still counts as accepted and reaches the reaction. The old `knockback` effect stays only for enemy hits on the player and for the legacy weapons until the cut-over.

**What the enemy answers (verbs)**

| Verb | What happens | Stun | Body moves | Cancels its attack |
|---|---|---|---|---|
| **H** Hold | Stops. The art nudges 4 px along the hit and springs back in 120 ms | `hold_ms` (360-670) | no | yes |
| **B** Bounce | A hold with a 10 px art hop | the ring's hold (500-700) | no | yes |
| **K** Knockback | Slides and leans back | 380 ms | `launch_speed` × knockbackScale | yes |
| **L** Launch | Tumbles: spin, hop, afterimages. Can wall-splat and bowl others | 460 ms | the same speed | yes |
| **S** Stagger | A long stun in place | 800 ms (900 when poise breaks) | no | yes |
| **D** Knockdown | Falls over and takes ×1.5 damage | 1200 ms | no | yes |
| **Z** Daze | Stars orbit its head; its weak point opens | 1200 ms | no | yes |
| **A** Armor | Damage and a flash only. Drains poise. Pushes its wind-up 60 ms later (200 ms at most) | none | no | no |
| **C** Clink | No damage. The slime recoils 24 px, 30 ms hit-stop, the chain resets | none | no | no |
| **P** / **R** | Suck (not used: the owner decided the suck never pulls live enemies; kept for a later upgrade) | — | — | — |
| Roll: bowl / bonk / break | Bowl: launched sideways and the Roll goes on. Bonk: both bounce (today's rule). Break: the Roll stops, and the slime is thrown back and hurt | | | |

The enemy writes `result.reaction = {verb, slime: none|recoil|bounce|pass|break, recoil_px, feel}`. `PlayerCombat.on_outcome` reads it for the shapes, and `strike_area` reads it for the abilities. They play the slime's recoil and the feel once per swing.

**The owner's rule, in one place.** A hit with `last == false` never moves the body. If the profile says K or L, a non-last hit becomes a hold. This one rule covers Spear and Axe steps 1-2, the Hammer Thud and the Spin ticks. The old +120 base shove goes away for the player's hits.

## 4. The combos per shape

**The hold formula.** Hold = (cancel point − this contact) + 150 ms link window + the next step's last contact frame + 40 ms margin, capped at 700 ms. So even a press at the very end of the link window lands while the enemy is still held. When a step is retuned, its hold follows. Hit-stop pauses SimClock, so a freeze never eats a hold or a link window.

Damage = base × 1.2 (attack 12) × the step's scale. Crit is rolled once per swing (5 %, ×1.75).

**Spear: jab, jab, lunging jab** (base 12)

| Step | Wind-up / active / recovery (ms) | Cancel point | Contact (after press) | Damage | Hold | Knockback | Hit-stop | Slime step | Reach | Effects |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 Jab | 50 / 60 / 120 | 170 | 50-110 | 14 | 360-420 | none | 30 | 4 px | line 110 × 14 | 5 sparks, pitch 1.0 |
| 2 Jab | 50 / 60 / 120 | 170 | 50-110 | 16 | 430-490 | none | 35 | 4 px | line 110 × 14 | 7 sparks, pitch 1.12 |
| 3 Lunging jab | 90 / 90 / 220 | rest 150 | 90-180 | 21 | — | launch 420 along the aim (about 95 px) | 75 | 18 px | line 132 × 14 | 14 sparks and a ring, trauma 0.45, 5 px kick, pitch 1.26 and a thump |

**War Axe: sweep, backswing, cleave** (base 15)

| Step | Wind-up / active / recovery | Cancel point | Contact | Damage | Hold | Knockback | Hit-stop | Slime step | Area | Effects |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 Sweep | 80 / 110 / 150 | 250 | 80-190 | 18 | 420-530 | none, twists along the sweep | 40 | 6 px | 140°, r60, clockwise | 6 sparks, pitch 1.0 |
| 2 Backswing | 60 / 110 / 150 | 230 | 60-170 | 21 | 520-630 | none, twists the other way | 45 | 4 px | 140°, r60, the same clip backwards | 7 sparks, pitch 1.12 |
| 3 Cleave | 140 / 130 / 230 | rest 150 | 140-270 | 27 | — | launch 400 from the slime (about 91 px) | 90 | 12 px | 180°, r66 | 14 sparks and a ring, trauma 0.45, 5 px kick, pitch 1.26 |

**Hammer: Thud, BOOM** (base 30). Two steps keep its weight. The slime stands still, and each step hits on its impact frame only.

| Step | Wind-up / active / recovery | Cancel point | Contact | Damage | Hold | Knockback | Hit-stop | Area | Effects |
|---|---|---|---|---|---|---|---|---|---|
| 1 Thud | 260 / 80 / 300 | 460 | 260 | 36 | 670, flattened | none | 80 | r48, 48 px ahead | trauma 0.3, debris, flatten 1.3 / 0.6 |
| 2 BOOM | 280 / 100 / 400 | rest 200 | 280 | 54 | — | launch 380 with a 16 px hop (about 86 px). Ring r72: 18 damage, bounce 500 | 120 | r48, plus ring r72 | trauma 0.6, 5 px kick, cracks |

**One chain at a glance**

| Shape | Contacts at (ms) | Chain + rest | Damage | Per second | The plan's taps with today's combo |
|---|---|---|---|---|---|
| Spear | 50, 220, 430 | 890 ms | 51 | 57 | about 50 |
| Axe | 80, 310, 620 | 1130 ms | 66 | 58 | about 48 |
| Hammer | 260, 740 | 1440 ms | 90 (+18 ring) | 62 | about 36 |

**Charges (hold A).** The press still strikes step 1, as in Zelda. If A is still held 250 ms after the press, the goo ring fills after the step ends. A charge ends the chain.

| Charge | Ring | Energy | Class | Hit |
|---|---|---|---|---|
| Spear Lunge | 600 ms | 15 | `charge` | Line 170 × 18, pierces, 25 damage, launch 460 (about 105 px). The slime darts 40 px in 120 ms. Hit-stop 90, trauma 0.45, 6 px kick |
| Axe Spin | 900 ms | 20 | `charge` | 360°, r72. Three ticks 120 ms apart: 13 and 13 (holds of 300 ms by the owner's rule), then 22 with launch 380. Hit-stop 20 / 20 / 85, trauma 0.5 |
| Hammer Quake | 1000 ms | 25 | `charge` + `ring` | Centre r56: 72 damage, launch 420 with a 20 px hop. Cracks out to r120: 18 damage, bounce 700. Hit-stop 150, trauma 0.75 |

**Abilities as impact classes**

| Attack | Class | Damage | On a light enemy | Feel |
|---|---|---|---|---|
| Slam centre (inner half of the ellipse) | `slam` | 40 (+25 % in the Stone form) | launch 380 with a 16 px hop | hit-stop 110 (Stone 140), trauma 0.7 (Stone 0.8) |
| Slam ring | `ring` | 24 | bounce, held 600 ms, so a chain can follow | the same freeze |
| Thrown liftable | `thrown` | 20 × material | daze 1.2 s | hit-stop 50, trauma 0.2 |
| Roll (later) | `roll` | 10 | bowl: launch 320 sideways, the Roll goes on | 25 ms per pin; each pin's pitch ×1.12 |
| Suck burst | `suck` | 0 | nothing: the suck never pulls live enemies (owner, 2026-10-11) | none |

**What ends a chain:** no press in time, a clink, being hit, a shape switch, Q, the Slam, the Roll or a door. A whiff does not. Each step re-aims, so step 2 can hit another enemy. From the cancel point the slime may walk out of steps 1-2. The finisher cannot be walked out of.

**Energy:** hits give no energy back (owner, 2026-10-11). Instead an enemy may drop an **energy shard** when it dies (`combat.energyShard`: a drop chance and an amount); training dummies never drop one.

**Do the numbers fit?**
- **Hold against gap.** Each hold is the longest possible gap to the next contact plus 40 ms. Spear steps 1→2 have gaps of 110-380 ms against holds of 360-420. Axe steps 2→3 have gaps of up to 590 against holds of 520-630. Today every hit stuns 330-513 ms, which depends on knockback. Now each hold is set by its step.
- **Finisher distance.** The slide decays ×0.94 per 60 Hz step. So a body covers about 0.21 × speed in a 380 ms knockback and 0.23 × speed in a 460 ms launch.
  - Spear launch 420: about 95 px on a light enemy.
  - The same hit as knockback: about 62 px on the orb-weaver (×0.7), 49 px on the swordsman (×0.55) and 18 px on the Clod (×0.2).
  - A kill launch (×1.3) goes about 124 px. Speed is capped at 600 px/s.
  - After a launch the Spear's 110 px still reaches, and the wake guard stops an instant re-lock.
- **Cooldowns.** Today there are 760-1300 ms between swings. Now there are 170-460 ms between steps and 150-200 ms of rest after a finisher. With the base lowered to 12 / 15, damage per second stays within about 20 % of the plan's taps with today's combo.
- **Kills.**
  - A 40 HP archer or spider dies on the first finisher with either shape: the two Spear jabs total 30 and the two Axe hits total 39.
  - The Squint (32 HP) dies on the Spear finisher inside one 900 ms daze. Because of this, its daze gets no damage bonus.
  - The orb-weaver (70) and the brawler (55) need a few more hits, or a thrown pot first.
- **Openings.**
  - Fatty's 700 ms eye fits one Spear chain (51), and his 1.6 s dizzy fits two. That is about as many openings as the plan has.
  - The Clod's 700 ms daze fits a Spear chain (finisher at 430 ms) and, just, an Axe chain (620).
  - The Matron's 3 s crash would let in about 200 Axe damage, two thirds of her HP, and could skip her floor phase. Default: a 2 s crash (about 130) and no damage bonus.
  - The Warden's Slam topple from the dungeons plan (2.5 s, ×2) can let in about 300 damage against its 160 HP. It stays as that room's reward; check it in the grey box.

## 5. Enemy reaction profiles

The "reaction function" is one shared function, `HitReaction.decide(profile, hit, state)`, which reads each enemy's profile. An enemy with phases tells it which phase it is in. Bosses can still override `_react_to_damage`, as Fatty and the Matron do today.

**The fields**

| Field | Meaning | Default |
|---|---|---|
| `weight` | tiny, light, medium, heavy or boss. Picks the default reactions below | — |
| `material` | goo, worm, chitin, mud or stone. Picks the sparks, sound and death | — |
| `knockbackScale` | Multiplies K and L speed | 1 − today's `knockbackResist` |
| `hitstunScale` | Multiplies holds and stuns. A value below 1 logs a warning, because chains can break | 1 |
| `holdCap`, `breakFree` | Holds in a row before it breaks free, and the move it uses: push, counter-slash, hop-back, skitter or skitter-spit | 2, push |
| `poise`, `breakVerb` | Heavy and boss: the pool that A hits drain, and what happens at 0 | heavy: 4, stagger 900 |
| `states` | One entry per phase of its script: armor tier, `open`, `damageTaken`, class overrides | — |
| `parts` | One entry per hurtbox: a gate (tags, and the states in which it is open) | — |
| `classes`, `byTag`, `immune` | Overrides per class and per tag (e.g. `cut`), and the classes that clink | — |
| `roll`, `suck` | bowl / bonk / break; pulled / resist / none | from weight |

Layers merge in this order: weight defaults, then `enemy-types.json` `reactions`, then the scene's `reaction_overrides`.

**How `decide` picks a verb, in order**
1. **Clink:** the class is immune, or the hurtbox's gate is shut. A gated hit that the profile maps to daze or knockdown still happens, with 0 damage.
2. **Wake guard:** within 400 ms after a launch, push or break-free ends, the hit deals damage and a flash, nothing more.
3. **State armor:** if the hit's tier is at or below the current phase's armor, the result is A.
4. **Class verb:** from `byTag`, then the state's `classes`, then the enemy's `classes`, then the weight defaults.
5. **Poise:** an A drains poise. At 0 the enemy plays its break verb, and poise refills 1 per second after 1.2 s without a hit.
6. **The owner's rule:** a non-last hit turns K or L into H.
7. **Hold cap:** a 3rd hold in a row becomes the break-free move.
8. **Apply:** the stun takes the longer of the old and new values. The enemy's attack is cancelled for every verb except A and C.

**Defaults by weight**

| Weight | Taps | Finisher | Charge | Hammer Thud / BOOM | Thrown | Slam centre / ring | Roll | Suck |
|---|---|---|---|---|---|---|---|---|
| tiny | L (dies) | L | L | L / L | L | L / L | bowl | P |
| light | H | L | L | H / L | Z 1.2 s | L / B | bowl | P |
| medium | H | K | L | H / L | D 1.2 s | L / B | bonk | R |
| heavy | A | A | S | S / S | S 500 ms | D 1.5 s ×2 / S 500 ms | break | R |
| boss | A | A | A | A | A | A | break | R |

**The matrix.** The Suck column is void since the owner's answer (the suck never pulls live enemies). The cells show the enemy's normal phase; the last column gives its own rules and open phases. Key: H hold, B bounce, K knockback, L launch, S stagger, D knockdown, Z daze, A armor, C clink, P pulled, R resist. "—" means the player never meets that pairing in Release 1: the Slam comes from Fatty, and Release 1 has no Roll. The frog is decoration and has no hurtbox.

| Enemy | Taps | Finisher | Charge | Thud / BOOM | Thrown | Slam centre / ring | Roll (later) | Suck | Its own rule |
|---|---|---|---|---|---|---|---|---|---|
| Worm swordsman (medium, worm, ×0.55) | H; A during its wind-up | K, cancels its swing | L | H / L | D 1 s | L / B | break: its blade blocks, 10 damage to the slime | R | Wind-up armor 1: taps cannot stop its swing, the finisher can. Breaks free with a counter-slash |
| Worm archer (light, worm) | H | L | L | H / L | Z 1.2 s | L / B | bowl | P, cancels its draw | Breaks free by hopping back 60 px |
| Worm brawler (light, worm, ×0.9) | H; A during its 250 ms lunge | L | L | H / L | Z 1.2 s | L / B | bonk, then it is dazed 800 ms | P | Lunge armor 2. Roll into its lunge to beat it |
| Slime-spider (light, goo) | H, big wobble | L | L | H / L | Z 1.2 s | L / B | bowl | P | Breaks free by skittering aside |
| Orb-weaver (medium, chitin, ×0.7) | H | K | L | H / L | D 1.2 s, on its back | L / B | bonk | R | Breaks free: skitters back and spits |
| Clod Stomper (heavy, mud, ×0.2, poise 4) | A, mud chips | A | S | S / S | S 500 ms | D 1.5 s ×2 / S | break | R | Crouch and air: armor 4, everything is A (as today). Dazed 700 ms after its stomp: taps H, finisher K |
| Squint (medium, mud, 32 HP) | C | C | C | D / D | D 1.5 s, eye opens | D / Z 900 ms | bonk | R | The eye takes only the Spear, and only while dazed (900 ms after its slam) or down. Then taps H, and the finisher L ends the daze. Two jabs plus the finisher kill it |
| Big Squint (heavy, mud, 96 HP) | C | C | C | D / D | D 1.5 s | D / Z 1.1 s | break | R | The same eye rule. Dazed 1.1 s after its second stomp. While open: taps H, finisher K |
| Fatty One Eye (boss, goo, 140 HP) | Open eye + Spear: blink and belly jiggle (A); else C | Open eye: big jiggle | Lunge on the open eye: big jiggle; else C | C | Phase 2 clod: Z 1.6 s, eye wide open | — | break: the slime boings back ×2 | R | Never moves. Blocked while airborne or contact-hopping (as today). In phase 2 the eye squints shut after each landing (C). A new Body hurtbox takes no damage but lets a clod count |
| Orb-Weaver Matron (boss, chitin, 300 HP) | A, belly jiggle | A, legs buckle | A | A | A | A; in her 1.3 s volley rest the Slam centre staggers her 600 ms | — | none | Crashed and dizzy: taps and finisher H (a jiggle in place), no damage bonus |
| Silk Lurker (light, chitin, 30 HP) | Hanging: swings on its thread like a piñata. Floor: H | Hanging: big swing. Floor: L | L | H / L | D 1.2 s | D / D | bowl | Hanging: swings toward the slime. Floor: P | The Axe's `cut` drops it: D 1.2 s, ×1.5 damage |
| Broodling (tiny, goo, 8 HP) | pops | pops | pops | pops | pops | pops | bowl, like pins | P, then dazed 600 ms | Every hit kills it. Pop streak: each pop within 1 s plays 2 semitones higher (at most 6 steps) |
| Brood Warden (heavy, chitin, 160 HP, poise 6, ×0) | A | A | S | S / S | S 400 ms | During its rear-up: D 2.5 s ×2 (plan); else S / A | break | R | Sweeps: armor 3. Planted 1.2 s after the double sweep: taps and finisher H |
| Training dummy | switchable preset: light, medium, heavy or boss | | | | | | | | For tuning. It gives no energy |

## 6. Juice

**By hit step**

| Effect | Taps (steps 1-2) | Finisher | Charges, Hammer, Slam | Made with |
|---|---|---|---|---|
| Hit-stop, once per swing (+10 ms per extra target, at most +30; total cap 160) | Spear 30 / 35, Axe 40 / 45, Thud 80 | Spear 75, Axe 90, BOOM 120 | Lunge 90, Spin 20 / 20 / 85, Quake 150, Slam 110 (Stone 140) | code |
| Flash | White for 1 frame (17 ms), then the hurt tint fades over 90 ms | White for 50 ms, then the tint over 120 ms | as the finisher | shader (HitFlash `flash_amount` curve) |
| Victim body | Squash 0.86 along the hit and 1.12 across, held in the freeze, springs back in 150 ms. Jitters ±2 px during the freeze | Stretch 1.25 / 0.82 for 120 ms, 360° spin, 12 px hop and one bounce, 2-3 afterimages, landing squash 1.3 / 0.75 | Thud: flattened 1.3 / 0.6. Slam: 16 px hop | code |
| Direction | The Spear jolts straight back; the Axe skews along the sweep | the same, bigger | radial | code |
| Sparks | 5-7 in a ±30° cone along the hit, tinted by material | 14, plus an impact ring (r6 to 28 in 120 ms) | debris and dust in the ground's colour | code (ParticleFx cone and tint) |
| Sound | Shape whoosh + shape impact + the victim's material. Impact pitch 1.0, then 1.12 (±3 %) | Pitch 1.26, a 60-90 Hz thump and a short tail | boom + crack | pitch: code; new takes: sound work |
| Camera | none | trauma 0.45, 5 px kick along the hit | Thud 0.3, BOOM 0.6, Slam 0.7 (Stone 0.8), Quake 0.75 | code (trauma shake) |
| Number | small and white | big and yellow, pops from 1.5 to 1.0 in 100 ms | big and yellow | code |
| Slime | strike squash 1.08 / 0.94 for 120 ms | recoils 6 px | stands still | code |

**By weight class**

| Moment | Tiny, light | Medium | Heavy, boss | Made with |
|---|---|---|---|---|
| Taps | Squash at 1.5× the amplitude with an elastic return over 260 ms. Spiders wobble; worms bunch up like an accordion | squash 0.9 / 1.1 | a 2 px shake; mud chips (Clod); belly jiggle (Fatty, the Matron), reusing the dummy's damped wobble | code |
| Finisher | the full tumble | leans back, skid dust | a clank. A poise break throws chunks off the sprite (`break_burst` on its own frame) | code |
| Daze | Stars orbit the head (`fx-sparkle`); it sways | same | same; the eye opens | code; the open eye is art |
| Break-free tell | a yellow-white outline flash for 350 ms, a goo puff and a grunt | same | — | shader, code, sound |
| Death | Goo pop and a puddle; the Broodling pop streak | kill launch and a dust puff | mud shatters (`break_burst`); bosses as today | code |

**Special moments (all code)**
- **Kill:** +30 ms hit-stop and a launch ×1.3. The enemy dies where it lands.
- **Wall splat:** a launched enemy that hits a wall, rock, tree or fence faster than 140 px/s squashes flat (0.6 / 1.3 for 100 ms). It gets +50 ms hit-stop, trauma 0.25, and 40 % of the finisher's damage again, bounces back 24 px and is dazed 800 ms. Once per chain.
- **Bowling:** a launched enemy that hits another passes on 60 % of its speed. Both take 4 damage.
- **Clink:** a spark at the tip, the tip flashes white for 1 frame, a dry high tick, the slime bounces 24 px.
- **Room clear** (dungeon rooms, ambushes, bosses): a 160 ms freeze, then 400 ms of stutter slow motion (2 of every 3 physics steps paused by the hit-stop reason), and the music drops 3 dB for 300 ms.
- **Goo splats** stay on the ground for 4-8 s.
- **Reduce motion:** no freezes, shake, kick or stutter. Squash plays at 35 %.

**Needs drawn art or sound.** Until the poses exist, today's `knockback-<facing>` frame stands in.
- Knockdown poses for worms, spiders and the Warden.
- Dizzy eyes for the Squints, Fatty and the Clod.
- The swordsman's block pose.
- The Lurker hanging and falling.
- Optional hurt faces: worms' eyes bulge, spiders curl their legs.
- New sound takes through the audio bake: material layers (goo, worm squelch, chitin crack, mud splat, stone clack), an impact per shape and step, the finisher thump, the pop and the clink tick.
- Splat decals, only if code-drawn blobs look cheap.

## 7. Anti-frustration rules

1. **Hits 1-2 never move the body.** The rule lives in one place (section 3).
2. **Holds follow the timing.** They come from the hold formula, capped at 700 ms.
3. **Two holds, then it breaks free.** Each enemy counts holds in a row. The 3rd becomes its break-free move: a push at half the finisher's speed, or its own move with 350 ms of armor and a visible tell. The count clears on a launch, or after 700 ms without a hold. Holds from rings, throws and the suck do not count. Neither do holds during a daze, a knockdown or an open phase, because that phase's own timer ends them. This stops the spaced-jab lock from Streets of Rage 4.
4. **Wake guard.** For 400 ms after a launch, push or break-free ends, hits deal damage and a flash only. The enemy always gets a turn.
5. **Stuns never add up.** The longer one wins.
6. **Heavy enemies and bosses** absorb low-tier hits (A). Their wind-up only slips 60 ms per hit, 200 ms at most. Poise breaks into a 900 ms stagger.
7. **The finisher always connects.** The Spear gains 22 px of reach and an 18 px step; the Axe gains 180° and a 12 px step.
8. **Crowds don't stall.** Hit-stop plays once per swing, never once per target, and stays short on steps 1-2.
9. **A wrong tool always clinks:** a spark, a tick and a recoil. It is never silent, so the abilities get the clink too.

## 8. Data and code changes

Paths are under `godot/game/`.

**`data/game-constants.json`**
- `combat.chain`: `linkMs` 150, `holdMarginMs` 40, `holdCapMs` 700, `chargeStartMs` 250, `restMs` {spear 150, axe 150, hammer 200}, `finisherRecoilPx` 6, `clink` {recoilPx 24, recoilMs 120, hitStopMs 30}, `hitStop` {extraTargetMs 10, extraTargetCapMs 30, killMs 30, capMs 160}. Energy shards: `combat.energyShard` {dropChance, amount, pickupRadiusPx}.
- `combat.hits`: the impact-class table (tier, poise).
- `combat.verbs`: hold {nudgePx 4, nudgeMs 120}, bounce {hopPx 10}, knockback {stunMs 380}, launch {stunMs 460, maxSpeed 600, spinDeg 360, hopPx 12}, stagger 800, knockdown {1200, damageTaken 1.5}, daze 1200, armor {windupPushMs 60, maxMs 200}, pulled {speed 180, stopPx 40, holdMs 300}, resist {slidePx 12}. These replace enemy.gd's `HIT_*` literals.
- `combat.weights`: the five weight defaults.
- `combat.rules`: holdCap 2, holdResetMs 700, wakeGuardMs 400, breakFreeArmorMs 350, pushSpeedScale 0.5, poiseRegenDelayMs 1200, poiseRegenPerS 1, poiseBreakMs 900, killLaunchScale 1.3, wallSplat {minSpeed 140, damageShare 0.4, hitStopMs 50, trauma 0.25, dazeMs 800, bouncePx 24, perChain 1}, bowling {speedShare 0.6, damage 4, minSpeed 140 (a body bowls only a standing enemy it moves into at this speed or more; one in flight is never bowled again)}, popStreak {windowMs 1000, semitones 2, maxSteps 6}, rollBowlPassMs 300.
- `combat.roomClear` and `combat.trauma` {maxOffsetPx 18, exponent 2, decayPerS 2.0, directionalShare 0.6, noiseHz 25}.
- `shapes.<id>`: tags, baseDamage, and `chain[]` steps (id, class, clip, windupMs, activeMs, recoveryMs, cancelAtMs, damageScale, launchSpeed, stepPx, reach or arc, knock mode, walkCancel, hitStopMs, trauma, kickPx, pitch, sparks), plus `charge`.
- `abilities.squashSlam.inner` / `.outer`, `gulp.throwHit`, `gulp.suckTug`, `character.player.movement.rollHit`. The literals in `slam_sequence.gd` move here.

**`data/enemy-types.json`**
- A `reactions` block per type.
- New types: orb-weaver, clod-stomper, fatty-one-eye, orb-weaver-matron, squint, big-squint, silk-lurker, broodling, brood-warden.
- It becomes read at runtime through GameConstants. Today nothing reads it.
- `data/weapons.json` is retired when the shapes block lands.

**Scene exports on EnemyScript:** `enemy_type`, `reaction_overrides`, and `extra_hurtboxes` (part name → NodePath, e.g. Fatty's `Body`).

| File | Change |
|---|---|
| New `combat/shape_controller.gd` | The chain state on `Services.now_ms()`: step, queued press, link deadline, rest and charge ring. Computes `hold_ms`. Steps the slime through ArcadeMover velocity. Resets the chain. Replaces `equip()` and `combo_counter.gd` |
| New `combat/chain_step.gd` | A typed RefCounted for one step |
| New `combat/hit_reaction.gd` | The pure static `decide(profile, hit, state)` |
| New `combat/reaction_profile.gd` | Merges the three layers, caches them per type, and warns when `hitstunScale` < 1 |
| New `combat/reaction_state.gd` | Per enemy: hold count, poise, wake guard, splats, timers |
| New `feel/enemy_hit_motion.gd` | PROCESS_MODE_ALWAYS. Owns the sprite's offset, scale, rotation and skew: nudge, squash, tumble, and the real-time jitter during a freeze. `ClodStomper._set_lift` goes through it |
| `scripts/weapon.gd` | One plan per step, with the hitbox rotated to the aim. `_resolve_contact` writes `hit` and the `impact` effect instead of `knockback`, with the knock set by the step's mode |
| `combat/player_combat.gd` | Damage from `damageScale`. `on_outcome`: hit-stop once per swing, trauma, kick, sparks and pitch. The crit feel moves here from `try_attack`. Clink recoil and chain reset |
| `combat/damage_router.gd`, `damage_resolver.gd` | No change: unknown top-level keys survive, and the result already returns to the caller |
| `scripts/enemy.gd` | `can_receive_damage` answers `immune` on a clink. `mitigate_damage` applies the part gate and `damageTaken`. `_react_to_damage` = decide, then apply, and writes `result.reaction`. HurtSfx plays only when damage > 0. New hooks `_reaction_phase()`, `roll_response(dir, speed)`, `apply_suck(from, delta)`. Wall splat and bowling from the mover's collider |
| `scripts/clod_stomper.gd`, `fatty.gd`, `matron.gd` | Report their phase through `_reaction_phase()`. On Fatty, the eye part gate replaces `acceptedSources [spear]` and `knockback: immune`, and a new Body hurtbox is added |
| `scripts/training_dummy.gd` | A switchable reaction preset |
| `player/abilities/ability_world.gd` | `strike_area(..., hit, on_outcome)`: effects come from `hit`, and the callback gives the Slam, throws and the Roll the clink |
| `player/abilities/slam_sequence.gd`, `ability_definitions.gd`; `player/gulp/thrown_object.gd`, `mouth.gd`; `player/roll/player_roll.gd` | Pass their `hit` blocks. The mouth tugs enemies in its cone. The Roll asks the collider for bowl, bonk or break |
| `shared/arcade_mover.gd` | Keeps the last collider in the body meta `arcade_collider` |
| `feel/game_feel.gd` | `play_hit(spec, direction)`, `add_trauma`, `kick`, `room_clear()`. The old PRESETS become wrappers |
| `world/world_camera.gd` | Trauma shake (FastNoiseLite, real time). The old `shake(ms, intensity)` maps onto trauma |
| `feel/particle_fx.gd` | `emit_burst(preset, pos, direction, tint, count_scale)`; new presets `finisher-spark`, `mud-chunk`, `stone-chip`, `silk-tuft` |
| `player/squash_stretch.gd`, `feel/hit_flash.gd`, `feel/floating_text_layer.gd` | Squash and stretch for enemies with victim presets, the white-then-tint curve, the pop for finisher numbers |

**Fixes that come with this:**
- The crit feel plays on a real hit, not at swing start.
- Dummies, resources and refused hits no longer advance the combo.
- Refused ability hits clink instead of failing silently.
- A new shake is no longer dropped while another runs.
- The knock direction follows the step.

**Docs:** update `docs/godot/specs/combat.md`, `enemy.md`, `boss.md`, `matron.md` and `abilities.md`, and this plan's "taps inside 600 ms" line.

**Tests:** `test_combat`'s drift check (22-36 px) and the combo tests must change. None run until the owner asks.

## 9. What to try first in the grey box

In `game/dev/playground.tscn` with `?shapes`:

1. **Late links.** Dummy on "light". Chain each shape, pressing at the very end of the link window. Every step must land while the dummy is held.
2. **Mash against spaced jabs.** With spaced jabs, the 3rd hold must turn into a break-free, and the enemy must act.
3. **Finisher and follow-up.** Launch an archer (about 95 px) and an orb-weaver (about 62 px). Does the next chain start without a walk? Does the wake guard feel fair, or like "my hits stopped working"?
4. **The swordsman's wind-up.** Taps do not stop its swing; the finisher does.
5. **A crowd.** Axe through 5 Broodlings: one freeze per swing, and the pop streak's rising pitch.
6. **Feel switches.** A dev key for each layer (freeze, flash, squash, jitter, trauma, kick, sparks, pitch) to compare it on and off.
7. **Ability setups.** A pot dazes, then a Spear chain. A Slam ring bounce, then a chain.
8. **Wall splat and bowling** in the playground park.
9. **Openings.** The Squint's 900 ms daze (the Spear finisher kills it), Fatty's 700 ms eye, the Clod's 700 ms daze.
10. **Web export.** Frame time with 6 tumbling enemies, sparks and the trauma shake; then reduce motion on.

## 10. The owner's answers (2026-10-11)

1. **Chapter 1 enemies die within one combo.** An enemy that needs more than one full combo does
   not belong in Chapter 1; it moves to a later chapter. (One Spear combo is 14 + 16 + 21 = 51.)
2. **Base damage:** lowered to 12 (Spear) and 15 (War Axe); the Hammer stays at 30.
3. **Abilities set up combos:** yes. The Slam's outer ring bounces enemies in place; a thrown pot
   dazes light enemies and knocks medium ones down.
4. **The suck and live enemies:** no. The suck never pulls a live enemy.
5. **Energy back from hits:** no. Enemies may drop an energy shard when they die, with a chance.
6. **Damage numbers:** yes: small on steps 1-2, a big pop on the finisher, and a setting to hide
   them.

Also decided by default (the owner can still change them): a shape switch resets the chain;
walking cancels steps 1-2 from their cancel point; the Hammer has two steps; the wall splat goes
into the grey box; the room-clear slow motion plays only in dungeon rooms, ambushes and boss
fights; no "BREAK" word, only sound and chunks; boss openings get no damage bonus, and the
Matron's first crash is 2 s; the Roll hooks are built now and used when the Roll ships.

The owner asked on 2026-10-11 to start building, as independent of the old systems as possible,
so everything can be tested in the playground: [BODY_SHAPES.md](../godot/BODY_SHAPES.md).

## 11. Owner playtest (2026-10-12)

The owner played the grey box in the playground ([BODY_SHAPES.md](../godot/BODY_SHAPES.md),
checklist), mostly against the pen's enemies rather than the dummies. Four builders worked his
notes in the same day; nothing has run since (every script compiles). Old -> new numbers below are
`game-constants.json` and `enemy-types.json` values unless the line names a code const.

**What he said**

1. Spear: a little more time between hits would feel better. The last hit of every chain should
   load (a visible preparation) like a charged attack, and each step should look different (for the
   Axe: step 1 swings down, step 2 swings up, the last one prepares, hops a little and chops down).
2. Spear look: a thin shaft that forms an arrowhead at the tip on the attack (his sketch: a long
   thin shaft shooting at the target, speed streaks along it, a pointed head).
3. Hitting an enemy does not stop its attack, and it must; the stun should be a little longer.
4. The War Axe looks better than the Spear but is still too fast, and it does not stop enemies from
   walking at the slime or attacking.
5. The Hammer is good but needs small steps forward like the others, most of all on the last hit.
6. The training dummies look great (kept as they are).
7. Charging: the attack must fire on the key's release, so holding the key never strikes first;
   while charging, the slime walks at half speed.
8. The Axe's charged Spin hits too many times: one hit, in a full circle.
9. Energy must stop refilling by itself, so it is a scarce resource.
10. The Roll must also fire on the release: a tap rolls without charging, only a hold charges (the
    charged roll could become an upgrade).
11. The juice panel's keys 1-0 should play each effect so he can see it (he could not see the
    freeze), not switch it on and off.

**What changed**

| # | Change | Old -> new |
|---|---|---|
| 1 | Slower Spear chain | jab and jab-2 `recoveryMs` 120 -> 170, `cancelAtMs` 170 -> 240; `combat.chain.restMs.spear` 150 -> 210 |
| 1 | The last step loads (`anticipation` on every chain's last step: the slime's art pulls back and squashes, then springs into the strike; the body never rises) | Spear lunging jab `windupMs` 90 -> 220, `recoveryMs` 220 -> 250, `cancelAtMs` 400 -> 560, `stepFromMs` / `stepToMs` (new) 160 / 260, anticipation (new) pull 160 ms, 6 px back, 4 px push, squash 0.84 / 1.12 |
| 1 | Each step moves its own way | jab 1 straight; jab 2 from `sidePx` (new) 12 beside the aim line (its hit line moves with it); the finisher retracts into the body and glints, then thrusts long with its 18 px step |
| 2 | The Spear's look (`shape_visuals.gd` consts) | the 14-18 px spike and 3 speed lines of 28 px -> a 5 px shaft (6 on the finisher and the Lunge), a barbed arrowhead 20 x 13 (24 x 16), barbs 5 px, 4 / 5 speed streaks of 30 / 44 px fading in 70 ms; the finisher's 10 px nub and 8 px glint (60 ms) |
| 3 | Longer stuns (`combat.verbs`) | knockback 380 -> 500, launch 460 -> 600, stagger 800 -> 1050, daze 1200 -> 1550 ms; knockdown 1200 unchanged |
| 3 | Longer holds (`combat.chain`) | `holdMarginMs` 40 -> 140 (it also covers the tap's own press now that a tap fires on its release), `holdCapMs` 700 -> 900. Holds: Spear jab 360-420 -> 530-590, jab-2 430-490 -> 730-790; Axe sweep -> 595-725, backswing -> 730-860; Hammer Thud 670 -> 770; last steps up to 900 |
| 3 | Other stuns | `combat.rules.poiseBreakMs` 900 -> 1150, `wallSplat.dazeMs` 800 -> 1050; `combat.weights` light thrown daze 1200 -> 1550, heavy thrown and ring stagger 500 -> 650, heavy `breakVerb` stagger 900 -> 1150; `enemy-types` clod-stomper `breakVerb` 900 -> 1150, worm-brawler `rollDazeMs` 800 -> 1050 |
| 3, 4 | Hits stop attacks. Holds already cancelled a swing before its impact and froze the enemy (no chase, no new attack) for the whole stun; what the owner saw was wind-up armor, the wake guard, the break-free and the Clod's armor | worm-swordsman `states.windup` armor 1 -> none, worm-brawler `states.windup` armor 2 -> none (armor only on heavy enemies and bosses); a wall splat's daze now cancels the attack too |
| 3 | The hold count (section 7, rule 3) | `combat.rules.holdResetMs` 700 (after the last hold landed) -> `holdResetFreeMs` 300 (free time after the last counted hold ended, `ReactionState.hold_until_ms`), so holds as long as the gap between spaced jabs cannot hide a stun-lock |
| 4 | Slower War Axe | sweep `windupMs` 80 -> 100, `activeMs` 110 -> 130, `recoveryMs` 150 -> 160, `cancelAtMs` 250 -> 325; backswing `windupMs` 60 -> 80, `activeMs` 110 -> 130, `cancelAtMs` 230 -> 300; `restMs.axe` 150 -> 195 |
| 1, 4 | The Axe's down, up and chop | the sweep comes down from a raised head, the backswing swings up (a 16 px height cue); cleave -> **chop**: `windupMs` 140 -> 260, `activeMs` 130 -> 90, `recoveryMs` 230 -> 300, `cancelAtMs` 500 -> 650, `arcDeg` 180 -> 110, `radius` 66 -> 70, `chop` (new: the whole sector at once), `stepFromMs` / `stepToMs` 90 / 260, anticipation pull 90 ms, 4 / 3 px, squash 0.86 / 1.12, hop `jumpPx` 28 landing on the contact frame; a small shock ring and dust (`show_chop`) |
| 5 | Hammer steps | Thud `stepPx` 0 -> 8 (160-260 ms); BOOM `stepPx` 0 -> 20 (170-280 ms), anticipation pull 170 ms, 6 / 5 px, squash 0.86 / 1.14, its head lifted 1.35x higher |
| 7 | Attacks fire on the release | a press only records its time and aim; let go before `chargeStartMs` 250 it is a tap (the chain step fires then, or waits for the cancel point or the rest; the link window is judged at the press); held 250 ms it arms the ring and nothing strikes; let go full: the charge and its energy; let go earlier: the ring drains, no attack, no energy |
| 7 | Half speed while charging | `combat.chain.chargeWalkScale` (new) 0.5, while the ring fills or waits full |
| 8 | The Spin hits once | `ticks` (0.72 / 0.72 / 1.22 at 0 / 120 / 240 ms: 13 + 13 + 22) and `holdMs` 300 removed; `damageScale` 2.2 (40 damage), `launchSpeed` 380, `hitStopMs` 85, `sparks` 8 -> 12: the full r72 circle swept round from the aim, one hit-stop and one number per target |
| 9 | No energy regen in the rework mode | `character.player.rework.energyRegenPerSecond` (new) 0; the classic `stats.energyRegenPerSecond` 8 stays. Energy shards, items and a respawn refill it; F5 fills it in the playground |
| 10 | The Roll fires on the release | `character.player.rework` (new): `rollTapMs` 200; the quick roll (no spin-up) `quickRollDistancePx` 165 in `quickRollMs` 330, `quickRollEndSpeedShare` 0.5 (about 667 -> 333 px/s), `quickRollInvulnerabilityMs` 250, `quickRollEnergy` 0; a hold charges only with the `roll-charge` upgrade (the testbed lends it): the spin-up while held, the launch at the release; the Roll's cooldown from the press 960 -> 580 ms in the rework mode |
| 11 | The juice panel plays effects | 1-0 play a layer once on the nearest dummy or enemy within 200 px (the finisher's value, then "shown 4x" 600 ms later); Shift + 1-0 switch it. In a hit-stop the sparks and the numbers now hold too (`GameFeel.picture_speed()` 0.08; 1/3 in the room clear's stutter); before they ran on |

**Open for the owner**

- The wake guard (`combat.rules.wakeGuardMs` 400) is kept: for 400 ms after a knockback or launch
  stun ends, hits only deal damage and flash. With the 600 ms launch it ends about a second after a
  finisher, so the first hits of an instant second chain land as armor. If "my hits do nothing
  after a finisher" comes back, this is the knob (for example 250).
- The Spin's one hit is 40 damage (the three ticks were 48 per target).
- A tap Roll costs no energy (`quickRollEnergy` 0); the charged roll still drains 12 per second
  while held, and that energy no longer comes back by itself.
- A press in a step's wind-up is still dropped, and the wind-up now starts at the tap's release, so
  fast mashing (a new press within the step's 50-260 ms wind-up after a release) can drop a tap;
  holding such a press does not charge either.
- The walk clip plays at its normal speed while the slime walks at half speed during a charge.
- In the moba scheme (swing button) and the click scheme (Shift + order button) an attack press has
  no held state: always a tap, never a charge (as before this round).
