# Goo Bomb, Lantern and Ability Secrets

*Status: built in the playground (rework mode), merged into main on 2026-10-15; the decisions of
2026-10-15 and 2026-10-16 changed parts of it (dated notes below). Written
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

*2026-10-16 (owner, open question 94): the Goo Bomb is Chapter 2's key tool in Release 1. Where it
comes from is open question 95.*

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
  - *Changed 2026-10-16 (owner): rubble heaps break under the Heavy skin's Roll instead, so the
    blast stops breaking them once that Roll is built (roadmap 7.8, 7.10); the code still breaks
    them today. The bomb keeps cracked walls and cracked ground, and the chain stays (open
    question 57).*
  - Feel: a flash, a big shake, a hit-stop, the goo burst, a shockwave ring, pebbles and goo blobs,
    and a goo splat on the ground that fades.
- **Only its own fuse sets it off** (owner, 2026-10-15): no ability needs another ability, so the
  Lantern's flame passes a bomb by. A bomb caught in another bomb's blast still goes off
  (open question 57; the owner kept the chain on 2026-10-16).
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
  - It lights candles, sconces and braziers and burns dry things. It does not set off bombs
    (owner, 2026-10-15).
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
- *Changed 2026-10-16 (owner, open question 72): standing dry things burn; a rotten trunk lying
  across a path is the Heavy Roll's.*
- *Changed again 2026-10-16 (owner, open questions 84 and 93): the Lantern burns dry plant growth
  (deadthorn, hay, dry roots, old banners), and the grey old tree a Heavy Roll knocked down once it
  lies there as dry wood. Rotten planks, plank barricades, old fences and rotten mine timbers move
  to the Heavy Roll. The build burns only deadthorn hedges so far.*

## 3. Secrets: one kind of lock per power

The rule for the player: **every power opens a kind of barrier no other power opens.** A barrier
says what it needs in its refusal line, so a player who comes back later knows what to bring.

**Each thing is told apart** (owner, 2026-10-16, open question 77): "each thing must be told
apart; different things never look alike; sacrifice options for clarity". A small loose thing
lying in the way (a loose rock, a rubble heap, a rotten trunk across a path) is the Heavy Roll's, a
big single boulder the Hammer's, and a standing tree, a dead one included, the War Axe's. When a
new lock would look like another, it changes or it goes.

*Changed 2026-10-16 (owner, open questions 92 and 93): one look per power, by what the thing is.
The **War Axe** owns living, green things (trees in leaf, bushes, leafy vines, webs, tethers). The
**Heavy Roll** owns old dead or built things that lie or lean in the way (grey leaning old trees,
rotten trunks across a path, old fences, plank barricades, rotten mine timbers, loose rocks,
rubble heaps). The **Lantern** owns dry plant growth (deadthorn, hay, dry roots, old banners) and
the wood the Roll knocked down. The **Hammer** keeps big single boulders. Climbable walls show
thick roots and rocky handholds, and the Axe's vines are leafy curtains in front of an opening
(open question 86). The War Axe and Stretch Lash wait for the next release, so their locks are
come-back secrets in Release 1 (open question 94).*

| Power | Its locks (only it opens them) | The barrier it beats |
|---|---|---|
| **Goo Bomb** | **Cracked walls** in cliffs and dungeon walls hide caves and rooms. **Cracked ground** hides holes and caves below (owner, 2026-10-15). (Rubble heaps went to the Heavy skin's Roll on 2026-10-16; the build still has the bomb break them. In the playground the islet's prize moves behind a cracked rock face: open question 72.) **Mud dams**: blow the cracked dam and the pond drains, showing the stair, chest or cave mouth that lay underwater. **Bomb over water**: suck the bomb and throw it across a river or a fence onto an island's cracked rock. The fuse is the timer. **The Gobbler**, a rock-eating toad asleep in a cave mouth, swallows whatever is thrown in: feed it a bomb, and it burps up treasure and hops away. **Powder kegs**: chains of kegs that blow a whole wall | Walls, rock, water held back, distance |
| **Lantern** | **Dark rooms**: only the ember shows the floor, and the holes in it. **Shadow paths**: faint glow-moss on a hidden ledge over a black pit, seen only in the ember's light. **Candles, sconces and braziers**: light them all to open doors, or race timed candles; the Crystal Colossus's four braziers bare his weak spot while all of them burn (owner, 2026-10-16). **Dry blockers**: deadthorn hedges on old roads, hay heaps over hatches, old banners hiding doors, dry root plugs, and the old tree a Heavy Roll knocked down, once it lies there as dry wood (rotten mine timbers went to the Heavy Roll on 2026-10-16: open questions 84 and 93). **Gloomlings**: shadow blobs that weapons pass through. They shrink from the light and scuttle off what they sit on (a switch, a key). **Frost and ice** (hold to melt; later) | Darkness, dry blight, cold |
| **Spear** | **Eye latches**: a thrust to the stone pupil opens the door. **Through bars**: only a thrust fits between the bars of a grate, to hit the switch or cut the cord behind it. **Puff-pods**: a thrust pops the floating seed bladders that block narrow passages | Precise points, bars |
| **War Axe** | **Webs, vines, bushes and tethers** (as planned; the Feral skin's climbing walls also show vines: open question 86). **Fell a dead tree**: a leaning dead tree on a riverbank falls across the water as a log bridge. Standing trees, dead ones included, are the Axe's (owner, 2026-10-16, open question 77); the old tree a Heavy Roll would knock down is open question 84. **Cut ropes**: they hold drawbridges, cages, chandeliers and sacks, which then fall (a bridge drops, a friend goes free, loot spills). *Changed 2026-10-16 (owner, open questions 86, 93 and 94): the Axe owns living, green things only (trees in leaf, bushes, leafy vines hanging in front of an opening, webs, tethers); grey leaning old trees are the Heavy Roll's, so the dead tree above is no longer the Axe's lock. Climbable walls show roots and handholds, not vines. The War Axe waits for the next release: in Release 1 its locks are come-back secrets, and the Spear cuts webs with the Silk skin* | Green and silk, water to cross |
| **Hammer** | **Big single boulders and ice armour** (as planned; no harvesting in Release 1, owner 2026-10-15; small loose rocks are the Heavy Roll's, owner 2026-10-16, open question 77). **Pegs**: hammer one down and its neighbours pop up (Zelda's peg puzzle). **Seesaw catapults**: hammer one end of a log seesaw, and the stone on the other end flies up onto a high ledge's plate | Single heavy things, height |
| ~~**Squash Slam**~~ | Removed (owner, 2026-10-15: it had no job of its own). Its shake-downs went to the Heavy skin's Roll, and cracked ground to the Goo Bomb | |
| **Mouth (suck and throw)** | **Fog and spore clouds**: the slime inhales a cloud that blocks a passage and can spit it out elsewhere. **Silk Reel**: light things over water, holes and bars | Light things, air |
| **Skins** (from the Pearls; replaced the Swallow forms on 2026-10-15) | **Heavy** (Pearl 1): sinks the heavy plates and moves statues, pedestals and blocks; its Roll shakes loose what sits on a wall or a tree it hits, and breaks the small loose things lying in its way: loose rocks, **rubble heaps** (many loose rocks that choke cave mouths, wells and tunnels) and rotten trunks across a path, with a strong shake; it does not push enemies away (owner, 2026-10-16, open questions 61 and 77). It also knocks down or breaks old dead or built things that lie or lean in the way: grey leaning old trees, old fences, plank barricades, rotten mine timbers (open question 93). **Silk** (Pearl 2): passes web walls, webs no longer slow it, and its shapes cut webs (in Release 1 the Spear, open question 94), opening web walls for good and freeing what is wrapped in silk; a web-wall maze leads to the Crystal Caverns (open question 81), and a second one into Gloop Forest from the Wilds (open question 87). **Feral** (Pearl 3, owner, 2026-10-16): climbs some walls it could not climb before while interact is held, claws showing, and its Spear hits twice as fast. A climbable wall has vines and irregularities; the slime climbs up and down, and a fall costs nothing (open question 68; the Axe's vines are open question 86). *Changed 2026-10-16: a climbable wall shows thick roots and rocky handholds, never beside a heavy block (open questions 86 and 91), and a hill only Feral climbs leads from the Wilds into the Crystal Caverns (open question 87).* **Swim** (a later Pearl): deep water; the deep-water secrets are come-back secrets for it, and the Swim form's scene mechanics become its permanent deep-water power (open question 75) | Plates, heavy things, loose rock, webs, walls to climb, deep water |
| **Roll** | **Falling slabs** (owner, 2026-10-16): loose slabs and crumbling bridges that fall too fast to walk across but slowly enough to roll across, and come back after 10 s, over lava, spikes or the void. Chapter 1's slabs cross the void and spikes, lava waits for a fire region, and a slab falls a set time after it is touched, so quick rolls in a row cross it and walking never does (open questions 70 and 71). **Quicksand** crosses only at speed. **Gate races**: beat a closing gate, like the old Thorn Guard gate of Fatty's Lair, which drops shut too fast to walk through. (Bonking trees and walls to drop prizes, and breaking loose rocks, rubble heaps and old trunks, needs the Heavy skin; so does knocking down grey leaning old trees and breaking old fences, plank barricades and rotten mine timbers, open question 93.) | Speed |
| **Goo Boomerang** (planned) | Switches out of reach and around corners, two in one throw. Bells. Keys fetched from islands. **Fire carried** from a lit candle to a far one. **Pinwheels**: a hit spins a wind wheel that lifts a gate for a few seconds | Reach around corners |
| **Stretch Lash** (planned; it waits for the next release, owner, 2026-10-16, open question 94) | **Hook rings** over chasms. **Heavy pulls** (heavy things pull the slime to them). **Loose bricks**: pull one out of a wall, and a niche opens or water runs | Chasms, walls with a loose stone |
| **Bow** (planned, an Ability Box power; owner, 2026-10-16) | On press the slime aims in the direction it is moving, on release it shoots that way, and the arrow does not change direction. Each arrow costs energy. **Far targets** in a straight line across gaps and water, such as eye switches on far walls and a target hit while it passes; the arrow carries no fire. **Far enemies** that cannot be reached otherwise, and **enemies that open doors** when they die, as in Zelda (open question 76). Burr gives it in Release 1's Chapter 3, when the slime comes back to the West village after Chapter 2 (open questions 85 and 94) | Distance in a straight line |

**No combos of two abilities** (owner, 2026-10-15): no ability needs another ability, and "depth
from combos" was dropped. A power may still use a thing in the world, such as the boomerang
carrying a lit candle's fire. *Open since 2026-10-16: the owner wants a few combos used wisely,
such as a Heavy Roll that knocks an old tree down into dry wood the Lantern burns (open question
84).* *Answered 2026-10-16 (owner, open question 84): the main path never needs a combo. A few
optional secrets may combine a skin and an ability, and each looks clearly different. A Heavy
Roll knocks down a grey, leafless, leaning old tree, made of old material the Axe cannot cut, and
the Lantern burns it once it lies there as dry wood.*

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
  root-rock plateau shows the decals on another wall style.* *Planned (owner, 2026-10-16, open
  question 72): the islet's prize moves behind a cracked rock face, the bomb's lock, and the heap
  by the map's edge waits for a Heavy Roll.*
- **Lantern corner:** a dark room with four candles that light it while they burn (a minute each), a deadthorn hedge
  hiding a nook, and a few enemies to burn.
- **Heavy corner:** two vaults on the east edge south of the Lantern corner: one behind a timed heavy
  plate the Stone slime must run from, one whose plate stays down only under a pushed pedestal, a
  spare statue to push and pull, and stone essences
  ([BODY_SHAPES.md](../godot/BODY_SHAPES.md#heavy-plates-and-heavy-blocks-2026-10-14)).
- Both powers are in the playground's box, and the F9 panel can refill energy.
