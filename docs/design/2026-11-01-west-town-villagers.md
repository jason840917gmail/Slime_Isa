# West town villagers and animals (proposal, 2026-11-01)

> **Status: built and placed in the town.** The owner took all of them ("All of them",
> 2026-11-01), added three sisters and their parents (V23 to V27), asked for five kinds of bird that
> fly, a room behind each door and a pond. All 27 villagers and 20 animals and 27 rooms are
> built and placed in the four chunks of the town's new layout (where each stands:
> [docs/godot/VILLAGERS.md](../godot/VILLAGERS.md#where-they-are)). Names, looks, colours and lines
> can still change.

The West village's town (chunks `west-village-a4`, `-b4`, `-a5`, `-b5`; houses, gardens and props
from the [town set](../../asset/Originals/town/README.md)) gets 10 to 20 slime villagers and its
animals. The owner asked for three kinds of villager (indoors in their house or shop, outside at a
post, walking around town) and for pets and animals such as pigs, dogs, butterflies and birds.

Pictures (style roughs, GPT 2.5, `asset/Originals/town/villagers/`):

- `board/west-town-villagers-board.jpg`: the 22 villagers, numbered.
- `board/west-town-animals-board.jpg`: the 12 animals, numbered.
- `board/west-town-life-mockup.jpg` (and `-plaza-2x.jpg`): the roughs at game scale on the town
  set's test layout (`asset/Originals/town/concepts/west-town-render-3.jpg`, 1 px per world unit).
  Villagers stand 70 units tall (Burr and Yoi are 68 to 73), kids 50. A bubble over a door shows
  who is inside. The town's houses are not placed in the chunk scenes yet, so these places are a
  starting point, not final.

## The story they fit

The town is the West village's Release 1 part ([World](../story/03-world.md#the-west-village)): Burr
the gatekeeper's house, a few more houses, a shop that sells potions and food ingredients, a game to
play and a secret that teaches a simpler potion. Burr went to fight Fatty One Eye and has not come
back; young Burr waits at home. No new slime has been born in years, so the town is curious about
the newborn. The roads past the Thorn Guard posts are closed, so travellers are stuck here.

## Villagers

| # | Name | Role | Kind | Where | Look |
|---|---|---|---|---|---|
| V1 | Dollop | Shopkeeper (potions, food ingredients) | Indoor | General store, behind the counter (the store was repainted with a front door on 2026-11-12: a building needs a door to have a room) | Plump honey-orange, red-and-cream striped apron, paper shop cap, a green goo jar |
| V2 | Burble | Innkeeper of the Bubbling Mug | Indoor | Inn, behind the bar | Big plum-purple, bushy white eyebrows, towel on the shoulder, a foamy mug |
| V3 | Crumb | Baker | Indoor | Twin mushroom house (or a pumpkin house) | Cream-yellow, floury chef's hat, a pumpkin pie |
| V4 | Mayor Wobbleton | The mayor | Indoor | Town hall | Teal, small top hat, gold monocle, green sash with the sprout badge |
| V5 | Bobbin | Tailor | Indoor | Two flats, her shop upstairs | Pink, round spectacles, measuring tape, pincushion hat, scissors |
| V6 | Auntie Suds | Bathhouse keeper | Indoor | Goo bathhouse | Mint green, striped towel turban, a wooden bucket and brush |
| V7 | Dune | A traveller stuck in town | Indoor | Inn, at a table | Sandy tan, orange travel scarf, brass goggles, big backpack |
| V8 | Granny Thistle | Herbalist, the town's secret potion | Indoor | Jelly dome house (or the snail shell) | Lilac, green knitted shawl, tiny glasses, a basket of herbs |
| V9 | Sprig | Gardener | Post | The hedge gardens | Leaf green, wide straw hat, watering can |
| V10 | Dot | Gossip | Post | A bench by the goo fountain | Peach, cream shawl, knitting |
| V11 | Dab | Gossip | Post | The other bench | Lavender, flowered bonnet, a hand at her mouth |
| V12 | Bram | Apprentice Thorn Guard | Post | The town gate | Steel blue, a helmet too big for him, red sash, wooden spear |
| V13 | Zing | Runs the throwing game | Post | The game booth | Lemon yellow, striped vest, boater hat, bow tie, rings |
| V14 | Plum | Fruit seller | Post | A market stall on the plaza | Plum purple, green headscarf, apron with apples |
| V15 | Gramps Reel | Old fisher | Post | A pond or stream bank (the town has no water yet) | Grey-blue, bucket hat with flies, white moustache, rod |
| V16 | Penny | Mail carrier | Walker (route) | Mailbox to mailbox | Coral red, blue postal cap, satchel of letters |
| V17 | Old Sedge | Walks his pup Biscuit (A2) | Walker (route) | The streets | Moss green, flat cap, white moustache, walking stick |
| V18 | Wick | Lamplighter | Walker (route) | Lamp to lamp | Midnight blue, cap, a pole with a goo jar |
| V19 | Tansy | Shopper | Walker (area) | The market and the shops | Apricot orange, polka-dot headscarf, a basket of vegetables |
| V20 | Fizz | Kid playing tag | Walker (small area) | By the fountain | Small, fizzy lime, propeller beanie |
| V21 | Tad | Kid playing tag | Walker (small area) | By the fountain | Small, sky blue, paper boat hat, a ball, a bandage |
| V22 | Young Burr | Burr's son (story NPC) | Post | The gatekeeper's house yard | Small, olive like his father, a pot for a helmet, a rusty key |
| V23 | Isa | The oldest of three sisters: clever, always learning and exploring | Walker (area) | All over town, from their home | Kid, the tallest sister; look A or B on `board/sisters-board.jpg` |
| V24 | Dany | The middle sister, the kindest; follows Isa in all her mischief | Walker (follows Isa) | Wherever Isa goes | Kid, a little shorter |
| V25 | Gavy | The youngest: always running, jumping, climbing, off to the pig pen, the hens and the water; her parents run after her | Walker (fast, wide area) | The risky spots: the pen, the hens, the water | Kid, the smallest |
| V26 | Dan | The sisters' father, always running after Gavy | Walker (follows Gavy) | Wherever Gavy goes | Big sturdy turquoise, scruffy dark hair, short beard, blue checked scarf |
| V27 | May | The sisters' mother, at home making dinner, always smiling | Indoor | The family home's kitchen | Coral-rose, long black hair with a flower, a cream apron, a spoon and a pot of soup |

The owner added the three sisters on 2026-11-01 ("there are 3 sisters that live together") and
their parents ("add Dan the father that always chase after gavy, and mom May who stay at home making
dinner"). His picks: the sisters as on `board/family-board.jpg` C (look B with a colour each and hair
of jelly: Isa slim and tall with long straight hair to her waist, Dany chubby with long curly hair,
Gavy small with short hair in two buns and Asian features), the parents take 2.

Colours to settle if picked: V8 and V11 are both lilac; V1, V19 and Elder Plop are all orange; V16
is close to Pip's red.

### Lines

Three each, in `npc-definitions.json` once built.

- **V1 Dollop:** "Welcome to Dollop's! Potions on the left, mushrooms on the right, and no sampling
  the goo jars." / "Coins? The worms drop them when you bonk them. Don't ask me where they get
  them." / "A red potion puts the bounce back in a slime. Take two if you're the brave sort."
- **V2 Burble:** "Welcome to the Bubbling Mug! Warmest goo cider this side of the Wellspring." / "A
  newborn? Here? Pull up a stool, little one. Everybody wants to meet you." / "The rooms are full of
  travellers. The roads past the Thorn Guard posts are shut, so nobody's leaving."
- **V3 Crumb:** "Mind the flour! Oh, too late. You look like a little sugar bun now." / "Pumpkin
  pie, fresh from the oven. The secret is a pinch of moss. Don't tell anyone." / "Burr bought two
  buns every morning. I still bake his... just in case."
- **V4 Mayor Wobbleton:** "Ahem! Mayor Wobbleton, at your service. Welcome to the finest village in
  the west." / "Our gatekeeper went off to fight that one-eyed brute. Most irregular. I have filed a
  complaint." / "If you see Burr out there, tell him the town needs him. And that his paperwork is
  late."
- **V5 Bobbin:** "Hold still while I measure you! Oh... you can't, can you. You're all wobble." / "A
  scarf, a bow, a little hat: every slime looks better with one good accessory." / "I'm sewing
  banners for the day the Pearls come home. A bit early, maybe. I like to be ready."
- **V6 Auntie Suds:** "Welcome to the goo baths, dearie. Warm jelly, warm heart." / "A good soak
  takes the dents out of any slime. Even the ones from worm bites." / "The steam comes from deep
  under the hill. Some say the Wellspring's roots run all the way here."
- **V7 Dune:** "Dune's the name. I came up the desert road, just before the Thorn Guard shut it." /
  "Past the dunes lives a worm as long as a river. Gorge's general, they say. I didn't stay to ask."
  / "When the roads open again I'll show you the way. Until then: another cider, Burble!"
- **V8 Granny Thistle:** "Oh my, a newborn! I haven't seen one since my own grandchildren." /
  "Herbs, mushrooms, a drop of dew... a potion needs no forge if you know the old ways." / "Bring me
  a red mushroom and a sprig of mint some day, and I'll show you a little secret." (The secret potion
  itself is a story piece for later.)
- **V9 Sprig:** "Careful where you bounce! These carrots took all summer." / "The worms dig up my
  beds at night. I put a scarecrow out, but it's not very scary, is it?" / "Plants like a little
  talk. And a lot of water. Mostly the water."
- **V10 Dot:** "Have you heard? Burr went after Fatty One Eye all by himself. Brave or silly, I
  can't decide." / "And now a newborn slime bubbling about the place! Wait till I tell Dab." / "Don't
  mind me, dear. I just knit and I listen. Mostly I listen."
- **V11 Dab:** "Psst. Dot says the mayor is afraid of chickens. You didn't hear it from me." / "A
  newborn! From the Wellspring? Oh, I must sit down. I am sitting down. Oh, good." / "Young Burr
  hasn't stopped rolling about since his father left. Bless him."
- **V12 Bram:** "Halt! Oh, you're a slime. Carry on. I mean: state your business! ...Carry on." /
  "Apprentice Thorn Guard Bram, West gate. Yoi says I get a real spear when I stop dropping this
  one." / "Nothing gets past me. Except the chickens. The chickens get past me a lot."
- **V13 Zing:** "Step right up! Three throws, three targets, one prize!" / "Got a good gulp on you?
  Swallow it, aim it, let it fly!" / "Nobody has beaten the high score. Mostly because I keep
  changing it." (The game itself is not part of this work.)
- **V14 Plum:** "Fresh apples! Juicy plums! Er, I'm Plum. The plums are just plums." / "The orchard
  is over the hill, past where the worms dig. I go early, before they wake up." / "Have an apple,
  little one. Newborns need their vitamins."
- **V15 Gramps Reel:** "Caught a fish once as big as the inn. Well. As big as the inn's door." /
  "Lily over in Slimeshire? I taught her everything. Except patience. Nobody can teach that." /
  "Fish bite best when you're not looking. So I don't look. I nap."
- **V16 Penny:** "Mail! Mail for... nobody. Nobody writes to Burr's house any more." / "Every letter
  gets there. Rain, wind, worms. Mostly worms these days." / "A letter from Slimeshire for the
  mayor! He'll read it, frown and file it. He always does."
- **V17 Old Sedge:** "Biscuit, heel! Heel! ...He never heels." / "We walk the town twice a day,
  Biscuit and I. Keeps the old jelly moving." / "In my day the Thorn Guard marched these streets. Now
  it's young Bram and his spear."
- **V18 Wick:** "Every goo lamp needs a top-up. Forty-two lamps. I've named them all." / "This one's
  Gloria. She flickers when she's happy." / "The glow goo comes from the fountain. Don't drink it.
  Trust me."
- **V19 Tansy:** "Carrots, cabbage, a loaf from Crumb's... what am I forgetting? Oh! Everything
  else." / "Dollop's prices went up again. It's the worms, she says. Everything's the worms." / "Mind
  my basket, dear, I've only got the two arms. Well. Sort of arms."
- **V20 Fizz:** "Tag! You're it! ...Hey, no fair, you can't roll away!" / "Are you really new? Like,
  brand new? Can you do a trick?" / "When I grow up I'm going to be a Thorn Guard like Bram. But
  better at holding the spear."
- **V21 Tad:** "I've got the ball, so I make the rules. Rule one: I win." / "Young Burr rolls faster
  than anybody. He says his dad taught him." / "This bandage? Chicken attack. Don't laugh."
- **V22 Young Burr:** "My dad went to fight Fatty One Eye. He said he'd be back by supper. That was
  ages ago." / "He taught me a trick before he left. Want to see? You curl up, and you ROLL!" / "If
  you find him... tell him I've been practising." (His Roll lesson and its ceremony are story work
  for later; these lines stand in until then.)
- **V23 Isa:** "I'm Isa! Did you know the fountain's goo glows brighter when it rains? I measured
  it." / "I've read every book in the town hall. Twice. Now I'm making a map of everything." / "Dany,
  come on! There's a cave behind the gardens and nobody has written it down yet!"
- **V24 Dany:** "Hi! I'm Dany. You look new. Do you want a hug? Slimes give the best hugs." /
  "Wherever Isa goes, I go. Somebody has to carry the plasters." / "I picked this flower for you!
  Well, for whoever came by first. That's you!"
- **V25 Gavy:** "Can't stop! I'm racing the chickens!" / "I climbed the pig pen! And the fountain!
  And almost the inn! Don't tell Mum." / "Bet you can't catch me! Nobody can! Not even Dad!"
- **V26 Dan:** "Gavy! Gavy, come back! ...Hello there. Have you seen a small orange blur go by?" /
  "Three girls. One of them climbs everything. I haven't sat down since spring." / "Isa reads, Dany
  hugs, Gavy runs. And I run after Gavy. It works. Mostly."
- **V27 May:** "Welcome, little one! Dinner's nearly ready. There's always a bowl for a guest." /
  "Isa's off exploring, Dany's following her, and Dan is chasing Gavy. Same as every evening." /
  "Mushroom soup tonight. Gavy says she hates mushrooms. She has seconds every time."

## Animals

| # | Animal | What it does | Where |
|---|---|---|---|
| A1 | Pig and piglets | Snuffle, trot about the pen, the piglets after their mother | A pen with a picket fence (the `fences` layer) |
| A2 | Biscuit the pup | Trots at Old Sedge's heels (V17), wags, barks once when the slime comes near | With Old Sedge, or a yard of its own |
| A3 | Cat | Naps (breathing, tail flick); strolls off when the slime comes close, lies down again | A porch, a bench, a doorstep |
| A4 | Hen and chicks | Peck and wander; scatter when the slime runs or rolls through | A yard or the gardens |
| A5 | Sheep | Graze and wander; the bell clinks | A meadow pen |
| A6 | Duck and ducklings | Paddle a loop on the water, the ducklings in a line (like the fish's paths) | A pond (the town has no water yet) |
| A7 | Butterflies (orange, blue, yellow) | Flutter over the flowers on looping paths; never collide | Gardens and flower beds |
| A8 | Robin | Hops and pecks; flies off when the slime comes near, lands again later | Lawns and paths |
| A9 | Doves | Two to four on the plaza; burst up and fly off near the slime | The plaza and the fountain |
| A10 | Snail | Crawls along very slowly; hides in its shell when touched | Hedges and walls |
| A11 | Hedgehog | Snuffles about; curls into a ball near the slime | The gardens |
| A12 | Squirrel | Sits by a tree, then darts to the next one | Trees at the town's edge |

Already in the game and placeable: bees on the beehive (town set), frogs on lily pads, fish. There
is no night yet, so fireflies would only suit shady spots, like the Wellspring's.

Ideas in the spirit of the Gulp's playful twists (only if he wants them): Biscuit fetches what the
slime throws; hens flap off when the Gulp sucks near them; the cat hisses at a suck and stalks off.

## How it would be built

- **Villagers** are scenes, one per villager (`game/scenes/characters/villagers/<id>.tscn`, scene id
  `character.villager-<id>` in `scene_index.json`), built like the existing NPCs: a CharacterBody2D
  with `NpcScript` (`game/scripts/npc.gd`), a name tag, and their lines in `npc-definitions.json`.
- **Placed by hand:** the Scenery dock gets **Villagers** and **Animals** categories (by picture,
  like Enemies); a drop goes under a `Villagers` or `Animals` node of the world. Nothing is spawned
  by code.
- **Walkers** wander in an area the owner drags: a circle of their own around where they stand (as
  placed enemies have), or a shared `npc-wander` area. Route walkers (Penny, Wick, Old Sedge) follow
  a line of points he drags in the editor.
- **Animals** share one behaviour script (wander in an area, the reaction to the slime: run off, fly
  off, curl up or hide; an idle loop), moved only through `ArcadeMover.move`, with their numbers
  (speeds, flee distance, pauses) in `game-constants.json`.
- **Art:** GPT 2.5 with a transparent background, the existing villagers as the style reference,
  packed at 2 px per world unit. Every villager gets a key-pose sheet (front idle, blink, talking)
  and an idle loop (blink and a soft jelly breath); walkers also get 3-direction, 4-step walks
  (side, toward, away; left mirrors the side, the side prompts in strict profile). Walking animals
  get the same walks; birds and butterflies get flight frames.
- **Indoor villagers need rooms:** each indoor villager's building gets a room world behind its door
  (door pairs as in [CONVENTIONS.md](../godot/CONVENTIONS.md), like level-1's
  `rooms/c4/slime-home.tscn`).

The art cost 107 generations, about 6,950 Magnific credits (the roughs 390 of them).

## The owner's answers (2026-11-01)

1. All the villagers and animals, plus the sisters and their parents (V23 to V27).
2. "A room behind each door, we can improve the rooms later": 27 rooms, one behind every house
   door: the shop, the inn, the bakery, the town hall, the tailor, the bathhouse, the herbalist and
   the family home with their villagers, and 19 empty homes furnished by kind ("Yes, build them").
3. "Add a pond": passed to the town-set session, which is rebuilding the town's layout.
4. "The bird need to fly as well, I need 5 different types of birds": the robin, the dove, the
   bluebird, the goldfinch and the swallow; they take off and fly about now and then, the swallow
   never lands.
