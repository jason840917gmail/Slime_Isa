# Goo Bomb, Lantern and Ability Secrets

*Status: being built on branch `exp/body-shapes` (playground only, rework mode). Written
2026-10-14 from the owner's requests and answers. It goes with the
[power curve](2026-10-11-world-power-curve.md), whose section 4 first planned the Lantern.*

## The owner's words

- **Bomb:** "a cast power: the slime casts for 2 seconds, building a bomb inside him, then puts it
  out from his mouth (the same animation as the spit). The bomb explodes after 3 seconds. You can
  suck it in and throw it as well. It costs 20 energy."
  - Casting: the slime **stands still**. A hit cancels the cast, and then no energy is spent.
  - The blast **hurts enemies around it**, **hurts the slime too**, and **breaks cracked walls and
    rocks**.
  - Held in the mouth, the **fuse keeps running**: throw it fast or it blows in the mouth.
  - Look: a **jelly bomb**, a ball of the slime's own green goo with a glowing core and a small
    sparking leaf fuse. It pulses faster and glows brighter just before it blows.
- **Lantern:** "an ember lights the slime from inside, so it can see in the dark, and it can throw
  small flames to damage and to light candles."
- **Secrets:** "Give the abilities uses that open secrets other abilities can't. Be cool, and
  don't do the same as other abilities. Think of secrets as hidden things behind physical
  barriers: water, cracked walls, holes and so on. Be creative."

## 1. The Goo Bomb (box socket `goo-bombs`, used with F; S in keys-only)

- **Press:** the cast starts. A press with less than 20 energy is refused ("Low energy").
- **The cast (2000 ms):** the charging strikes' loading ring fills over the cast (owner). The
  slime stands still and swells in slow pulses, while a small glowing
  bomb grows inside its jelly body. A hit cancels the cast: no energy is spent, and the bomb
  shrinks away.
- **The spit:** the `spit-<direction>` clip plays in the facing direction. The 20 energy is spent
  here. The bomb pops out of the mouth, hops about one tile ahead and lands (it stops short at a
  wall).
- **The fuse (3000 ms, from the moment the bomb leaves the mouth):** the bomb pulses faster and
  faster (about 2 Hz up to 8 Hz), its core glows brighter, and the leaf fuse sparks. It flashes in
  the last 500 ms.
- **The mouth:** the bomb is a light liftable, so Q sucks it in and a Q tap throws it. The fuse
  keeps running in the mouth. A thrown bomb flies the usual throw and lands, or drops where it hits
  an enemy or a wall; it does not burst on impact.
- **The blast:** a ground ellipse about 176 x 120 around the bomb (wider than tall, as for the
  Slam).
  - Enemies take about the Slam's inner hit and are thrown away from the bomb (rework `hit`).
  - The slime takes damage and a knock if it stands inside the ellipse. A bomb that blows in the
    mouth always hurts the slime.
  - It breaks cracked walls and rubble heaps inside the ellipse, and sets off other bombs after
    about 120 ms (chains).
  - Feel: a flash, a big shake, a hit-stop, the goo burst, a shockwave ring, pebbles and goo blobs,
    and a goo splat on the ground that fades.
- **With the Lantern:** a flame that touches a bomb sets it off at once.
- *As built (numbers in `abilities.gooBomb`, [BODY_SHAPES.md](../godot/BODY_SHAPES.md#the-goo-bomb-2026-10-14)):
  a 600 ms cooldown; the hop is 64 px; the slime takes 18 damage inside the ellipse and 28 in the
  mouth (15 and 25 after its defense); a bomb landing on deep water sinks without a blast.*
- **Cracked walls blend into the existing wall styles** (owner, 2026-10-14). A cracked wall is an
  overlay on a real painted wall: a cliff face of any style, or a built WallLayer wall. Its crack
  decal (`crack-overlay.webp`) becomes a hole decal (`hole-overlay.webp`, grey and tinted with the
  wall's colour), and the passage opens. It is not a separate rock block.
- **A blown wall is a door** (owner): like Zelda's bombed walls, the hole can lead to an indoor
  scene (a cave, a cellar). It has a door's target world and spawn, set in the Inspector.
- **The secret jingle** (owner): opening a secret (a blown wall, a cleared heap, a hole found in
  the ground, a burnt hedge's nook) plays a short "secret found" jingle (cue `SecretFound`). It is
  our own sound, not Zelda's.

## 2. The Lantern (box socket `lantern`, used with F; S in keys-only)

- **The ember** is the Forge's ember inside the body. It survives forms and hits, and the slime
  never holds anything.
- **In dark rooms, for free:** once the Lantern is learned, the slime glows. There is a light
  circle of about 160 px, flickering a little, and the ember shows warm through the jelly.
- **Tap the use key:** puff a small flame (10 energy (owner), about 300 ms cooldown). The ember flares, a
  short spit clip plays, and the flame shoots from the mouth along the aim. It has **a short range,
  right in front of the slime**: about one tile, 72 px (owner).
  - It stops at the first enemy, wall or fire target, or fizzles into smoke at the end of its
    range.
  - On an enemy: a small hit (about a third of a Spear jab).
  - It lights candles, sconces and braziers, burns dry things and sets off bombs at once.
  - In dark rooms the flame is a moving light.
- **Later (not built now):** hold the key on frost or ice to melt it slowly.

**Dark rooms:**
- A `DarkRoom` node in a world scene covers a rectangle. Its darkness is one shader overlay with
  holes around the light sources, with no 2D light per candle (too slow on WebGL 2).
- Light sources: the slime with the Lantern, lit candles, flames, bombs (a small glow) and blasts
  (a flash).
- A room is lit while all of its candles burn, and goes dark again when one of them goes out.
  Lighting it for good is an option per room.

**Candles:** the interior candle, sconce and toadstool-candle props have lit and unlit looks. A fire
target lights them. **They go out after a minute** (`burn_ms`, 60000 by default; owner) and
gutter in their last seconds. 0 keeps one lit for good. A `group` of candles
opens a gate when all of them burn.

**Burnables:** only dry, dead or frozen things burn: deadthorn hedges, hay, old banners, rotten
planks and dry root plugs.
- One takes about 600 ms to burn and spreads to the burnables it touches.
- It stays burnt (a saved flag).
- Grass and living trees never burn: green things are the Axe's.

## 3. Secrets: one kind of lock per power

The rule for the player: **every power opens a kind of barrier no other power opens.** A barrier
says what it needs in its refusal line, so a player who comes back later knows what to bring.

| Power | Its locks (only it opens them) | The barrier it beats |
|---|---|---|
| **Goo Bomb** | **Cracked walls** in cliffs and dungeon walls hide caves and rooms. **Rubble heaps** (many loose rocks) choke cave mouths, wells and tunnels. **Mud dams**: blow the cracked dam and the pond drains, showing the stair, chest or cave mouth that lay underwater. **Bomb over water**: suck the bomb and throw it across a river or a fence onto an island's cracked rock. The fuse is the timer. **The Gobbler**, a rock-eating toad asleep in a cave mouth, swallows whatever is thrown in: feed it a bomb, and it burps up treasure and hops away. **Powder kegs**: chains of kegs that blow a whole wall | Walls, rock, water held back, distance |
| **Lantern** | **Dark rooms**: only the ember shows the floor, and the holes in it. **Shadow paths**: faint glow-moss on a hidden ledge over a black pit, seen only in the ember's light. **Candles, sconces and braziers**: light them all to open doors, or race timed candles. **Dry blockers**: deadthorn hedges on old roads, hay heaps over hatches, old banners hiding doors, rotten mine timbers. **Gloomlings**: shadow blobs that weapons pass through. They shrink from the light and scuttle off what they sit on (a switch, a key). **Frost and ice** (hold to melt; later) | Darkness, dry blight, cold |
| **Spear** | **Eye latches**: a thrust to the stone pupil opens the door. **Through bars**: only a thrust fits between the bars of a grate, to hit the switch or cut the cord behind it. **Puff-pods**: a thrust pops the floating seed bladders that block narrow passages | Precise points, bars |
| **War Axe** | **Webs, vines, bushes and tethers** (as planned). **Fell a dead tree**: a leaning dead tree on a riverbank falls across the water as a log bridge. **Cut ropes**: they hold drawbridges, cages, chandeliers and sacks, which then fall (a bridge drops, a friend goes free, loot spills) | Green and silk, water to cross |
| **Hammer** | **Boulders, stone and iron nodes, ice armour** (as planned). **Pegs**: hammer one down and its neighbours pop up (Zelda's peg puzzle). **Seesaw catapults**: hammer one end of a log seesaw, and the stone on the other end flies up onto a high ledge's plate | Single heavy things, height |
| **Squash Slam** | **Shake-downs**: slam near a tree, a shelf or a ledge, and what sits on top falls (nuts, a nest with a key). **Burrowers**: worms and moles hiding underground pop out, and some hold keys. **Drum switches** (the worm drum). **Cracked ground** in the Stone form (built) | Things above and below |
| **Mouth (suck and throw)** | **Fog and spore clouds**: the slime inhales a cloud that blocks a passage and can spit it out elsewhere. **Silk Reel**: light things over water, holes and bars | Light things, air |
| **Forms (Swallow)** | **Stone**: presses plates and stays put on fast water. **Silk**: slips through web doors. **Swim**: deep water and, with Deep Dive, under logs and lily mats | Plates, webs, deep water |
| **Roll** | **Bonk** trees and walls to drop prizes. **Crumbling bridges and quicksand** cross only at speed. **Gate races**: beat a closing gate | Speed |
| **Goo Boomerang** (planned) | Switches out of reach and around corners, two in one throw. Bells. Keys fetched from islands. **Fire carried** from a lit candle to a far one. **Pinwheels**: a hit spins a wind wheel that lifts a gate for a few seconds | Reach around corners |
| **Stretch Lash** (planned) | **Hook rings** over chasms. **Heavy pulls** (heavy things pull the slime to them). **Loose bricks**: pull one out of a wall, and a niche opens or water runs | Chasms, walls with a loose stone |

**Combos** (two powers, one secret):
- A flame sets off a bomb at once: a cracked wall on a moving raft, or across a gap at the right
  moment.
- The boomerang carries fire.
- A bomb shakes a Gloomling out of a crack, and then the Lantern chases it.

## 4. Heavy plates and heavy blocks (owner's idea, 2026-10-14; built in the playground)

The owner: "heavy can press door interactors on the ground but they don't go down at once, they
are hard to move, so they take 3 seconds to go down, and when totally down is when the door
opens. When the slime moves it releases the button, and this one starts coming up for, let's say,
5 seconds; in that time the player has to be able to cross the gate. That brings another
mechanic other games use: moving heavy objects like pedestals to pass, or to place them on top of
these buttons and keep them pressed. To push something, use W to grab and then move in the
direction the player walks."

- **Heavy plate** (a new kind of pressure plate). Only a heavy weight sinks it: the Stone form, or
  a heavy block.
  - It sinks slowly: 3000 ms from up to fully down. Its door opens only when it is fully down.
  - When the weight leaves, it rises over 5000 ms. The door stays open while the plate is still
    rising and shuts as soon as it is fully up, so the player has those seconds to run through.
  - Stepping back on it while it rises makes it sink again from where it is, with no restart from
    the top.
  - A heavy block left on the plate keeps it down for good.
  - It shows its progress: the plate's sinking art, a grinding sound and a ring or gauge like the
    charge ring.
- **Heavy blocks** (pedestals, statues, iron-banded crates). They are too heavy to suck in.
  - **Only the Stone form moves them** (owner). The plain slime is too light: it grabs, strains
    and says so.
  - **Grab:** hold the interact key next to the block: W in keys-only, and right click held in the
    keyboard + mouse scheme (owner). The slime latches on with its mouth.
  - Then walk to **push** it, or walk away to **pull** it, at a slow speed along the grid (one axis
    at a time, like Zelda's blocks). Let go of the key to release.
  - Blocks stop at walls, holes and other blocks.
  - Uses: weigh down a heavy plate, make steps to a ledge, block a stream or a fan, and cover a
    hole (a block pushed into a hole fills it and becomes floor).
- **The secret this gives the Stone form:** timed doors that only a heavy weight opens, and plates
  that stay down only with a block on them.
- *As built (numbers in `puzzles.heavyPlate` and `puzzles.heavyBlock`,
  [BODY_SHAPES.md](../godot/BODY_SHAPES.md#heavy-plates-and-heavy-blocks-2026-10-14)): the plate
  feels the Stone slime's feet within 30 of its middle and a block's middle within 24; its fixed
  stone base holds a cap that slides 6 down over the sink and up over the rise, showing its lit
  pressed picture at the bottom (owner: only the top moves); the charge ring fills and drains around
  it; the grind is a placeholder cue. A gate shuts when its plate is fully up unless another plate
  of the same gate holds it. Blocks (a stone pedestal and an armor statue) move one 64 cell per move
  in 640 ms after a walk key is held 180 ms toward or away from them; the plain slime strains and
  says "Too heavy... I need to be stone.". Blocks stop at walls, cliffs, rims, holes, stairs, other
  blocks, solid objects and deep water. Filling a hole with a block is not built: the elevation grid
  cannot change a cell's level at run time.*

## 5. What the playground gets now

- **Bomb corner:** a cracked wall in a cliff with a small hidden cave and a chest behind it, a
  rubble heap blocking a path, an islet across water with a cracked rock (throw the bomb over),
  and the light dummies. *Built on the west edge around the lake cliff's west end
  ([BODY_SHAPES.md](../godot/BODY_SHAPES.md#the-goo-bomb-2026-10-14)): the blown wall is the door
  to a small crystal cave with the chest; the islet's "cracked rock" is a rubble heap, and its chest
  appears in the shallows below the islet (the islet has no stairs); a second cracked wall in the
  root-rock plateau shows the decals on another wall style.*
- **Lantern corner:** a dark room with four candles that light it while they burn (a minute each), a deadthorn hedge
  hiding a nook, and a few enemies to burn.
- **Heavy corner:** two vaults on the east edge south of the Lantern corner: one behind a timed heavy
  plate the Stone slime must run from, one whose plate stays down only under a pushed pedestal, a
  spare statue to push and pull, and stone essences
  ([BODY_SHAPES.md](../godot/BODY_SHAPES.md#heavy-plates-and-heavy-blocks-2026-10-14)).
- Both powers are in the playground's box, and the F9 panel can refill energy.
