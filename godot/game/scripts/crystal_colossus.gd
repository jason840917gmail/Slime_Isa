extends "res://game/enemy/patterned_enemy.gd"
class_name CrystalColossusScript
## Scene script `game.crystal-colossus` (`character.crystal-colossus`; roadmap 12.4; Chapter 3's
## boss, docs/godot/DUNGEONS.md "The Crystal Colossus (roadmap 12.4)" and "The crystal fight"; step 2
## of docs/design/2026-11-23-dungeons-2-3-rework.md, "The Crystal Colossus"): a hulking golem of icy
## blue crystal grown round Pearl 3, part beast. His arena (game/crystal_mine/colossus_arena.gd: the
## rebuilt Mine's M15 and the Colossus lab, game/dev/bosses/colossus-lab.tscn) rings him with four
## braziers and gives him its runaway carts. **The crystal fight** (the owner, 2026-11-25: "colossus
## have 3 phases like the 3 crystals in his body"): his health (the scene's `max_health`, 180) is
## three crystals of rose quartz in his body, a third each (`crystal_share`), each under an armour
## plate (L his right shoulder, C his breastplate, R his left shoulder), drawn on his bare body
## (game/bosses/colossus_look.gd; the scene's old sheet is blanked): plates and crystals are his health
## bar in sight, a live crystal glowing and pulsing (over a dark room's darkness too), a dead one dark
## slate and cracked for good. A phase is one crystal, in a fixed order (CRYSTAL_ORDER: the shoulder on
## the screen's left, the other shoulder, then the chest): a cart bursts its plate (no harm), then the
## Spear and thrown things destroy the bare crystal. The crystal fight replaced his plate fight (the
## plates were his health, then a core; 2026-11-24 to 25), which replaced his first fight, built for
## the one-scene Mine on 2026-10-17 (a weak spot that opened while all four braziers burned), gone with
## that world on 2026-11-25 (docs/archive/2026-11-25-old-hollow-and-mine.md).
##
## - **Walk:** he plods at the slime (`walkSpeed`), only as far as his own floor goes (a slime at a void
##   dip's edge is not followed over it); touching him hurts (`contactDamage`).
## - **Stomp:** within `stompRangePx` of the slime, or every `stompEveryMs` anyway, he lifts a crystal
##   foot (the tell, `raiseMs`) while a dark ring grows round his feet, then stomps: the slime's feet
##   in the ring (`stompRx` x `stompRy`) take `stompDamage`; the screen shakes. A stomp puts a brazier
##   out only as below ("His stomps put braziers out only when he is dousing").
## - **Nothing hurts a plate; only this phase's plate heats.** Standing within a lit brazier's ring (its
##   light, `light_radius` round its flame, measured to his feet), this phase's shoulder plate glows
##   hot: brittle; while all the braziers burn, anywhere (the other plates stay cold: the one that
##   glows is the one the cart takes). As it heats a burst of embers flies off it, it flashes and
##   `FireIgnite` sounds; while hot embers rise off it and the knock target of the cart line he stands
##   on glows (its cart ready, the target armed); as it cools, steam. The breastplate never heats on
##   the floor. The first clang off a cold shoulder plate in a fight shows `clang_hint_text` over him
##   and makes the unlit brazier nearest him flicker (the owner, 2026-11-24: the player must see what
##   changed, and be told why a cart failed).
## - **The runaway cart** (game/crystal_mine/ram_cart.gd; the hook `on_mechanism_hit(&"cart", cart)`)
##   only ever strikes this phase's plate, whichever side it meets him from (a spark where it meets
##   him; the owner, 2026-11-25: the first two blows take the shoulders in order). Brittle, the plate
##   shatters for good: the shards, a flash, a roar, no harm (its crystal is bare); he staggers
##   `burstStaggerMs`. Cold, it clangs and he staggers (`staggerMs`, the stomp sheet's last frame). With
##   this phase's plate already gone (its crystal bare, still live) it clangs off his rock and staggers
##   him: a free window. The breastplate bursts only on his back (below). The cart waits against him
##   (`hold_for_kick`); his feet back, furious (a roar), he turns to it and kicks it back up its line
##   into the tunnel it came from (`kickMs`; it rolls home over `kickBackMs`; the owner, 2026-11-24).
##   One that struck him as he lay he kicks as he gets up; if he falls or leaves, it is hauled home as
##   ever (`let_go`).
## - **The bare crystal:** a Spear hit on this phase's crystal, bare and showing to the hitter, hurts
##   (`shapes.spear.baseDamage`); a thrown thing (a pot, a rock, a stunned mite) `thrownShare` of one; a
##   crystal shows where the art draws it (SHOWS_FROM: a shoulder's from his front, his back and its own
##   side; the chest's from his front and both sides; on his back every one faces the sky: a deliberate
##   change, 2026-11-25, from the plate fight's "a side whose plate is gone", which his turning to face
##   the slime left almost out of reach). A hit never takes more than the crystal has left: each phase
##   ends at its third. Every other hit clinks: the Spear's own clink, a spark off a plate or grit off a
##   dead crystal or his rock, and at the phase's first clink a line (`plated_hint_text` while this
##   phase's crystal wears its plate, else `dead_hint_text` or `crystal_hint_text`) and the thing to hit
##   flashing under an arrow, following him.
## - **A crystal destroyed:** rose shards burst from it, a roar, the burst's shake; it shows dark and
##   cracked for good, and he staggers `crystalBreakStaggerMs`. The next phase starts: after the first
##   shoulder he walks on; after the second he makes for his wall (his last phase); the chest's is his
##   fall.
## - **His leap** (the owner, 2026-11-24: the fight felt slow, he "does not have a jump or a charge to
##   follow you"): a slime more than `hopFarPx` from him for `hopAfterMs` while he walks, and he
##   crouches (`hopCrouchMs`, a ring marking where he lands) and leaps at it (`hopAirMs`), landing
##   `hopShortPx` short of it (at most `hopMaxPx` a leap, kept on his floor): `hopDamage` to a slime
##   in the ring, never a brazier out; again at most every `hopCooldownMs`.
## - **His quake** (the owner, the same day: "the queke last 5 secodns and it make damage over time
##   the way to avoid it is by climbing . a warning have to be issue by colossus"): every
##   `quakeEveryMs` (the first `quakeFirstMs` after he wakes; sooner while he rages), the slime
##   on the floor, he warns `quakeWarnMs`: a roar and the ground's creak, reared (foot and fists up)
##   and trembling harder, the screen rumbling, while glowing cracks run out from his feet over his
##   whole floor and the climb walls up his wall light up (game/bosses/colossus_quake.gd). Then he
##   pounds the floor `quakeMs` (a pound every `quakePoundMs`, craters popping over the floor): a slime
##   on his floor takes `quakeTickDamage` every `quakeTickMs` (no knockback); a slime climbing is
##   safe. A cart's blow stops it (he staggers).
## - **Falling rocks** (the owner, the same day: the pots run out; "colossus need to make rocks or
##   cristals on every single attack they fall from the roof in ramdom spots making damage if they
##   fall on you, thy never block the rails"): every stomp (`debrisPerStomp`; a landing from his wall
##   is one), every leap's landing (`debrisPerHop`) and every `debrisEveryPounds`-th pound of a quake
##   shakes rocks loose from the roof (`debris_kinds`): each falls on a free spot of his floor, never
##   by a cart's rails, him, a brazier, a knock target or another thing to throw, its shadow growing
##   (game/bosses/colossus_debris.gd, `debrisFallMs`); a slime under it takes `debrisDamage`; it lies
##   there as a liftable to throw; at most `debrisMax` lie at once (the oldest crumbles).
## - **His stomps put braziers out only when he is dousing** (the owner, the same day: "it should
##   only happen after all braziers are on and after colossus had receive damage, or a long period of
##   time to allow time for the player to make mistakes"): hurt while every brazier burns (a plate
##   burst counts, though it costs him no health), he douses:
##   each stomp (and a landing from his wall) puts out the lit one nearest him, until none burns.
##   Else a stomp puts one out only once `douseAfterMs` has passed with no brazier lit or put out (the
##   wait starts again at each one lit or put out, and at the fight's start: the owner, "the player
##   have 45 seconds after lighting a brazier to make his move"). Dousing, a stomp puts out
##   `stompPutsOut` and a landing `landPutsOut` (twice that while he rages); after the long wait,
##   one (candle.gd `put_out_near`, the braziers' `stomp_puts_out`: the Shardback's Den rehearsed it).
## - **His last phase** (both shoulder crystals dead, his chest's left; the owner, 2026-11-24: "the
##   last phase he stay on the vines and only comes down to do the quake them goes up again , he does
##   not wander around ... so the player knows he have to climb and do something"): on his feet he goes
##   straight up his wall (`_last_phase`), at the climb spot nearest the slime, and stays there (no `climbMs`
##   leap down): his mites as on any climb (below), and a rock at the slime every `wallRockEveryMs`
##   (the first `wallRockFirstMs` up), thrown from his hand in an arc to where it is (`_throw_rock`): it
##   hits there, on the floor or up the roots ("you are not safe anywhere"), and lies as a rock to throw
##   (on the floor, off the rails) or shatters (on the wall, by the rails). He comes down only for his
##   quake (leaping to the middle of his floor) and goes back up after it.
## - **The wall:** he climbs only in his last phase (at once after his second shoulder crystal's
##   stagger, and whenever he is on his feet): he leaps onto the north wall of his arena at the climb
##   spot nearest the slime (the arena's `climb_spots`) and clings there (not solid; his pose up the face),
##   throwing a Crystal Mite down every `throwEveryMs` (`character.crystal-mite`: it drops in near the
##   slime behind its shadow, and on a slime climbing above its spot; `mitesPerClimb`, at most
##   `maxMites` alive). (Put up his wall before his last phase, as only a film could, he leaps down
##   where the slime stands after `climbMs`, a ring marking the spot: the landing is a stomp.)
## - **His claws: the Feral skin's exam** (the Pearl mid-dungeon plan, 2026-10-17): roots run up the
##   wall beside each climb spot, and a slime climbing them strikes his gripping claws with the Spear
##   (the strike while clinging, player.gd `_climb_strike`): while he clings his hurtbox rides up the
##   face with his pose, and only a Spear hit from a climbing slime reaches it. `clawHits` such hits and
##   he loses his grip: he crashes down from the wall over `fallMs`, across the nearest of the arena's
##   `crash_carts` lines (the lab's run down the room from under his climb spots; `fallDropPx` out from
##   the wall with none), with no landing stomp (no brazier goes out), and lies on his back
##   `plateFallStunMs` (long enough for the slime to drop from the roots and the cart to come from the
##   far wall's tunnel): his breastplate shows hot there (the fall cracked it; on the floor it never
##   glows) and that cart takes it; the Spear and thrown things hurt his chest crystal from every side
##   while he lies. Then he gets up and goes back up his wall; the next fall, the chest is already bare.
##   His chest crystal destroyed, he falls for good.
## - **His rage** (from phase `rageFromPhase`: 2, once a crystal is dead; not the Pearl's rage,
##   EnragedLook): he walks and stomps faster, throws more mites, quakes sooner and, dousing, puts out
##   twice the braziers a landing; his last phase adds the wall's rocks.
## Sounds by name (silent until staged): `ColossusStomp`, `ColossusRoar` (the wake, a burst, a crystal
## destroyed, the leap), `ColossusShatter`, `ColossusClang`.
##
## Numbers: `crystal-colossus` in game/data/enemy-types.json.
##
## Owner: dungeons (the Crystal Mine).

const CandleScript := preload("res://game/world/fire/candle.gd")
const FireFx := preload("res://game/world/fire/fire_fx.gd")
const FireTargets := preload("res://game/world/fire/fire_targets.gd")
const ColossusLook := preload("res://game/bosses/colossus_look.gd")
const ColossusShards := preload("res://game/bosses/colossus_shards.gd")
const ColossusQuake := preload("res://game/bosses/colossus_quake.gd")
const ColossusDebris := preload("res://game/bosses/colossus_debris.gd")
const HintCue := preload("res://game/feel/hint_cue.gd")
## His falling rocks: the mechanisms' group (their lines and lanes are kept clear), the knock targets'
## (the Bow's), the landing's sound, how many spots a drop tries before it gives up.
const MECHANISMS_GROUP := &"knock_mechanisms"
const TARGETS_GROUP := &"bow_targets"
const CUE_DEBRIS := &"DropLand"
## His last phase's rock thrown from the wall: its toss.
const CUE_ROCK_THROW := &"ThrowToss"
const DEBRIS_TRIES := 24
## His plates' heat cues (the owner, 2026-11-24: the player must see something change): the
## sound as his plates heat, the embers that burst from each plate then and rise off one every
## HEAT_EMBER_EVERY_MS while they glow, the steam as they cool; the glow on the knock target of the
## cart line he stands hot on (its colour, size, pulse, how near the line his feet must be); the
## clang hint: how long its line and pointers last, how high over the slime its line stands, how many
## times each unlit brazier flashes under its arrow (game/feel/hint_cue.gd); drawn over a dark room's
## darkness (dark_room.gd's OVERLAY_Z is 45).
const CUE_HEAT := &"FireIgnite"
const HEAT_EMBERS := 7
const HEAT_EMBER_EVERY_MS := 200.0
const COOL_STEAM := 6
const TARGET_GLOW := Color(1.0, 0.78, 0.35)
const TARGET_GLOW_SCALE := 0.8
const TARGET_PULSE_MS := 380.0
const ON_LINE_PX := 90.0
const HINT_MS := 6000.0
const HINT_LIFT := 96.0
const HINT_FLASHES := 3
const OVER_THE_DARK_Z := 46
## The quake: the stone breaking as a crater pops (every other one), the warning's creak, the climb
## walls' group (their roots are the safe place), how far from a climb spot a climb wall counts as his
## wall's, his tremble while he warns (radians of lean at its end), how often the warning's rumble
## shakes the screen (ms).
const CUE_QUAKE_BREAK := &"BreakStone"
const CUE_CREAK := &"GroundCreak"
const CLIMB_WALLS := &"climb_walls"
const QUAKE_ROOTS_NEAR_PX := 260.0
const QUAKE_TREMBLE := 0.035
const QUAKE_RUMBLE_EVERY_MS := 240.0

const PHASE_WAIT := "wait"
const PHASE_WALK := "walk"
const PHASE_RAISE := "raise"
const PHASE_STOMP := "stomp"
const PHASE_RECOVER := "recover"
const PHASE_LEAP_UP := "leap-up"
const PHASE_CLING := "cling"
const PHASE_LEAP_DOWN := "leap-down"
## His claws struck loose: the crash down from the wall, then the stun.
const PHASE_FALL := "fall"
const PHASE_STUNNED := "stunned"
## Rocked by the cart (a clang, a burst).
const PHASE_STAGGER := "stagger"
## Furious, he kicks the cart that struck him back up its line.
const PHASE_KICK := "kick"
## His leap at a slime far from him: the crouch (on the floor), then the leap (in the air: nothing
## reaches him, a cart passes under him).
const PHASE_HOP_CROUCH := "hop-crouch"
const PHASE_HOP := "hop"
## His quake: the warning (reared, trembling, the floor cracking from his feet, the climb walls lit),
## then the floor shaking under his pounding; only a climbing slime is safe.
const PHASE_QUAKE_WARN := "quake-warn"
const PHASE_QUAKE := "quake"
## Up his wall or in the air (the leap up, the cling, the leap down, the fall off the wall, his leap):
## drawn at ABOVE_THE_WALL_Z, over the tunnel doorways (ram_cart.gd's mouths, z 2) and the root
## climbs; on the floor at 0 (sorted by his feet as before).
const UP_PHASES: Array[String] = ["leap-up", "cling", "leap-down", "fall", "hop"]
const ABOVE_THE_WALL_Z := 3
const PHASE_DEAD := "dead"
## Where the chips fly off his gripping claws as they are struck, from his centre (art units are world
## units here).
const CLAW_GLOW_AT := Vector2(0, -170)
const MITE_SCENE := "character.crystal-mite"
## Its own wind-up sound (Sound Picker round 13, 2026-11-21; it played the slime's SlamWindup before).
const CUE_RAISE := &"ColossusRaise"
const CUE_CLINK := &"HitBlocked"
const CUE_CRACK := &"BreakGlass"
## His own cues (Sound Picker round 16; silent until staged in global.tscn).
const CUE_PLATE_STOMP := &"ColossusStomp"
const CUE_PLATE_ROAR := &"ColossusRoar"
const CUE_SHATTER := &"ColossusShatter"
const CUE_CLANG := &"ColossusClang"
const SHARDS := &"stone-chip"
const DUST := &"dodge-dust"
const SPARK := &"hit-spark"
const CLANG_TINT := Color("#d6f2ff")
const ZONE_NAME := "StompZone"
const ZONE_TINT := Color(0.32, 0.05, 0.02, 0.5)
const LAND_TINT := Color(0.12, 0.08, 0.2, 0.55)
## His leap: where he lands, a warm ring bright enough to read in a dark room (the leap's tell; a dark
## one is lost on the dark floor).
const HOP_TINT := Color(0.95, 0.42, 0.16, 0.55)
## His plates (L his right shoulder, C his breastplate, R his left shoulder; each over the crystal of
## the same name) and the side of him that has none.
const PLATE_NAMES: Array[String] = ["L", "C", "R"]
const SIDE_BACK := "back"
## The crystals' fixed order, one a phase (the owner, 2026-11-25: the arms, then the chest while
## climbing): the shoulder on the screen's left when he faces the viewer (L), the other (R), then his
## chest. Flip the two shoulders here; the chest stays last (the wall phase is built on it).
const CRYSTAL_ORDER: Array[String] = ["L", "R", "C"]
const CHEST := "C"
## Which crystals show to a hit from each side of him (as the art draws them): a shoulder's on its
## front, its back and its own side; the chest's on his front and both sides.
const SHOWS_FROM := {"C": ["L", "R", "C"], "back": ["L", "R"], "L": ["L", "C"], "R": ["R", "C"]}
## A crystal destroyed: its shards' tint (the burst's cold shards, rose), the grit off a dead one.
const CRYSTAL_SHARDS := Color(1.0, 0.55, 0.75)
## Where a clinked hit sparks: this far from his centre toward the hitter (presentation).
const CLINK_OUT_PX := 40.0
## His look (presentation): ground walked per walk frame; a new facing wins once its way leads the
## other by this factor; the cling shifts its grip every this long; the crash lies in its dust this
## long, then the dazed frames swap every this long; the share of the raise before he rears, of the
## leap before he springs, of the recovery he stays bent after the slam.
const WALK_STEP_PX := 11.0
const FACING_LEAD := 1.2
const CLING_SHIFT_MS := 600.0
const CRASH_FRAME_MS := 420.0
const DAZE_FRAME_MS := 450.0
const RAISE_REAR := 0.4
const LEAP_CROUCH := 0.3
const RECOVER_SLAM := 0.45
## The kick (presentation): the share of `kickMs` he winds up (leaning back) before his foot meets
## the cart, and how far he leans back and into it (radians).
const KICK_AT := 0.5
const KICK_LEAN_BACK := 0.07
const KICK_LEAN_IN := 0.1
## His fall for good: each of the topple's frames shows this long (the crash's for longer), the first
## raised this far (its art is anchored on his middle: he is still falling).
const DEATH_TOPPLE_MS := 260.0
const DEATH_TOPPLE_RISE := 70.0
## His ground shadow's half axes, standing and lying.
const SHADOW_STAND := Vector2(70.0, 20.0)
const SHADOW_LYING := Vector2(100.0, 26.0)
## Where a damage number rises from: this far over his feet (his picture's top).
const NUMBER_RISE := 190.0

## A plate burst (its crystal bare; no harm to his health). Payload {"plate", "by" (the node's name),
## "hp" (after)}.
signal plate_burst(payload: Dictionary)
## The cart clanged off a cold plate (or his rock: "plate" empty). Payload {"plate", "by"}.
signal plate_clanged(payload: Dictionary)
## A crystal destroyed (dark for good; the next phase starts, or he falls). Payload {"crystal", "by"
## (the hit's weapon), "hp" (after), "phase" (the phase now)}.
signal crystal_broken(payload: Dictionary)

## The liftable kinds his blows shake loose from the roof (one at random a rock), and the weight they
## land as (light: any Gulp lifts them, as the Lair's mud balls; their kinds' own weights are medium
## and heavy).
@export var debris_kinds: PackedStringArray = PackedStringArray(["ore-rock", "crystal-cluster", "geode"])
@export var debris_weight: String = "light"
## The line over him the first time in a fight a cart clangs off a cold plate (the unlit brazier
## nearest him flickers with it).
@export var clang_hint_text: String = "Too cold to crack. Heat it in a brazier's light!"
## The line over the slime at the first clink of a phase (a Spear hit or a throw that meets no bare
## live crystal), the thing to hit flashing under an arrow: while this phase's crystal still wears its
## plate; once it is bare (the hit met a dead crystal, or plate or rock).
@export var plated_hint_text: String = "The plate holds. Crack it with a hot cart!"
@export var dead_hint_text: String = "That crystal is dead. Strike the glowing one!"
@export var crystal_hint_text: String = "Strike the glowing crystal!"

## The arena (game/crystal_mine/colossus_arena.gd sets these as it places him): the spots on
## the north wall's foot he climbs from (old centres), its braziers, whose rings make his plates
## brittle, and the runaway carts whose lines he crashes across when his claws are struck loose (the
## nearest).
var climb_spots: Array[Vector2] = []
var braziers: Array[Node] = []
var crash_carts: Array[Node2D] = []

var _stomp_ready_at := 0.0
var _zone: GroundShadowLook
var _air_from := Vector2.ZERO
var _air_to := Vector2.ZERO
var _cling_at := Vector2.ZERO
var _next_throw_at := 0.0
var _thrown := 0
var _mites: Array[Node] = []
var _mask := 0
var _rng := RandomNumberGenerator.new()
## His claws: Spear hits from a climbing slime this climb, and the last hit's activation (one count a
## strike).
var _claw_hits := 0
var _claw_activation: Variant = null
## His hurtbox's authored position (it rides up the face with his pose while he clings).
var _area_home := Vector2.ZERO
## The plates he still wears, the way he faces (down, up, left or right: the art's), his look, the
## ground walked (the walk frames), a leap owed (his second shoulder crystal destroyed), how long the
## stagger lasts, until when the cling shows its throw, his hurtbox's shape (his own copy), lying.
var _plates := {"L": true, "C": true, "R": true}
var _turned := Vector2.DOWN
var _look: ColossusLook
var _walk_px := 0.0
var _leap_due := false
var _stagger_ms := 0.0
var _throw_pose_until := 0.0
var _hurt_box: RectangleShape2D
var _lying := false
## The cart that struck him, held where it stopped until he kicks it back, and whether this kick has
## met it.
var _kick_cart: Node2D
var _kicked := false
## When he fell for good (his topple's frames run from it).
var _dead_at := -1.0
## His leap: since when the slime has been far from him (-1: it is not), when he may leap next, where
## this leap lands (his feet).
var _far_since := -1.0
var _hop_ready_at := 0.0
var _hop_to := Vector2.ZERO
## His dousing (`_step_douse`): his stomps put braziers out one after another (hurt while all
## burned); since when no brazier was lit or put out (the long wait), which burned then; the harm
## count at the last step (a rise is a hurt).
var _dousing := false
var _douse_clock_from := 0.0
var _lit_states: Array[bool] = []
var _douse_harm := -1
## His crystals (the three-crystal fight): each one's health left (his health is their sum); his harm
## so far (each plate burst and each crystal hit: the dousing reads it); the phase whose first clink
## gave its line (one line a phase), and the last clinked hit's activation (one clink a strike).
var _crystal_hp := {"L": 0.0, "C": 0.0, "R": 0.0}
var _harm := 0
var _clink_hinted_phase := 0
var _clink_activation: Variant = null
var _clinks := 0
## The clink's hint (its arrow and glow, following him) and the crystal whose plate or crystal it
## flashes.
var _clink_cue: Node2D
var _clink_cue_on := ""
## His quake: when he may start the next, the next pound, the last pound (its slam
## frame), the next crater, the warning's next rumble, the next harm to a slime on the floor, and the
## harms dealt in this one (the films read it).
var _quake_ready_at := 0.0
var _quake_next_pound := 0.0
var _quake_last_pound := -INF
var _quake_next_crack := 0.0
var _quake_next_rumble := 0.0
var _quake_next_tick := 0.0
var _quake_hits := 0
## The quake's look (game/bosses/colossus_quake.gd, while it lasts), the craters popped and the pounds
## struck so far.
var _quake_look: Node2D
var _quake_craters := 0
var _quake_pounds := 0
## His falling rocks: those on their way down ({"at", "kind", "lands_at", "look"}) and
## those lying on his floor (oldest first; gone ones are dropped as they are found).
var _debris_due: Array[Dictionary] = []
var _debris: Array[Node2D] = []
## His last phase: when he throws his next rock from his wall.
var _next_rock_at := INF
## His plates' heat cues: brittle at the last step, the next rising ember, the glow on the
## target of the line he stands hot on (and that target), the clang hint given in this fight.
var _was_brittle := false
var _next_ember_at := 0.0
var _target_glow: Sprite2D
var _clang_hinted := false


func _ready() -> void:
	super()
	_rng.seed = 7311
	for crystal: String in PLATE_NAMES:
		_crystal_hp[crystal] = crystal_share()
	_setup_plates()
	if damage_area != null:
		_area_home = damage_area.position
	_transition(PHASE_WAIT, Services.now_ms())


func _exit_tree() -> void:
	_clear_zone()
	_let_go_cart()
	for drop: Dictionary in _debris_due:
		var look: Variant = drop.get("look")
		if look is Node and is_instance_valid(look):
			(look as Node).queue_free()
	_debris_due.clear()
	if _target_glow != null and is_instance_valid(_target_glow):
		_target_glow.queue_free()
	super()


# --- the arena's hooks -------------------------------------------------------------------------------

## True while he clings to the wall (out of reach).
func is_on_wall() -> bool:
	return _phase in [PHASE_LEAP_UP, PHASE_CLING]


## Wakes him (the arena, when the slime is in).
func wake() -> void:
	if _phase == PHASE_WAIT:
		_transition(PHASE_WALK, Services.now_ms())
		_cue(CUE_PLATE_ROAR)
		var feel := Services.feel()
		if feel != null:
			feel.shake(500.0, 0.012)
		_stomp_ready_at = Services.now_ms() + pattern("firstStompMs", 1800.0)
		_hop_ready_at = Services.now_ms() + pattern("firstHopMs", 2500.0)
		_quake_ready_at = Services.now_ms() + pattern("quakeFirstMs", 14000.0)
		_douse_clock_from = Services.now_ms()
		_lit_states = _brazier_states()
		_douse_harm = _harm


## Takes away every mite he threw (the fight is reset).
func clear_mites() -> void:
	for mite in _mites:
		if is_instance_valid(mite) and is_instance_valid(mite.get_parent()):
			(mite.get_parent() as Node).queue_free()
	_mites.clear()


## The mites he threw still alive. A mite that died and was freed (the Spear, a throw, a Heavy Roll's
## crush) is a freed object in the list, so each entry is checked as a Variant before it is typed: a
## typed lambda in `filter` fails on a freed object and `filter` then returns an untyped Array.
func live_mites() -> int:
	var alive: Array[Node] = []
	for i in _mites.size():
		var entry: Variant = _mites[i]
		if is_instance_valid(entry) and not (entry as Node).is_queued_for_deletion() and not bool((entry as Node).call(&"is_defeated")):
			alive.append(entry as Node)
	_mites = alive
	return _mites.size()


# --- the pattern -----------------------------------------------------------------------------------

func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	# a leap cut short in its crouch (a cart's blow, any way but its landing) gives his leap back
	if _phase != PHASE_HOP_CROUCH and _phase != PHASE_HOP:
		_restore_leap()
	# Up his wall or in the air he is in front of the wall and all on it: the tunnel doorways (drawn
	# over their carts) and the root climbs (the owner, 2026-11-24: he was "painted behind the doors
	# while jumping and in the vines").
	if body != null:
		body.z_index = ABOVE_THE_WALL_Z if _phase in UP_PHASES else 0
	if _phase != PHASE_WAIT:
		_step_douse(now)
		_step_debris(now, target, engaged)
		_step_heat(now)
	match _phase:
		PHASE_WAIT:
			body.velocity = Vector2.ZERO
			set_look(0.0)
		PHASE_WALK:
			if _last_phase() and not climb_spots.is_empty():
				# his last phase (the owner, 2026-11-24: "he stay on the vines and only comes down to do
				# the quake them goes up again , he does not wander around"): on his feet (up from a
				# fall, a kick, a stagger, a quake) he goes straight back up his wall, or quakes when one
				# is due
				body.velocity = Vector2.ZERO
				if _quake_due_last(now):
					_begin_quake_warn(now)
				else:
					_leap_up(now, _slime_centre(slime))
			elif _slime_climbing():
				# while the slime climbs his wall's roots (engaged or not: a climbing slime is no
				# target) he walks off to the middle of his floor (the owner, 2026-11-24:
				# standing at the wall's foot he left the slime no way down), no leap at it, no quake,
				# his stomps on their own pace (their rocks still fall)
				# (far from it, he leaps there when his leap is ready: the walk is slow)
				_far_since = -1.0
				var middle := _floor_rect().get_center() + (centre - feet())
				if now >= _hop_ready_at and centre.distance_to(middle) > pattern("retreatLeapPx", 140.0):
					_begin_hop(now, middle, 0.0)
				else:
					body.velocity = _velocity_toward(middle, pattern("walkSpeed", 34.0) * _rage(1.25), delta)
					if now >= _stomp_ready_at and elapsed >= pattern("stompEveryMs", 2600.0) / _rage(1.4):
						_raise(now)
			elif engaged:
				# after the slime, but only as far as his own floor goes (a slime at a void dip's edge is
				# not followed over it)
				var goal := _inside_arena(_feet_for(slime)) + (centre - feet())
				body.velocity = _velocity_toward(goal, pattern("walkSpeed", 34.0) * _rage(1.25), delta)
				_contact(target, pattern("contactDamage", 20.0), pattern("contactKnockback", 260.0), pattern("contactReachPx", 70.0))
				if _wants_quake(now):
					_begin_quake_warn(now)
				elif _wants_hop(now, centre, slime):
					_begin_hop(now, slime)
				elif now >= _stomp_ready_at and (centre.distance_to(slime) <= pattern("stompRangePx", 120.0) or elapsed >= pattern("stompEveryMs", 2600.0) / _rage(1.4)):
					_raise(now)
			else:
				body.velocity = Vector2.ZERO
			# the walk shows itself in its frames: no bob
			_walk_facing(delta)
			set_look(0.0)
		PHASE_RAISE:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("raiseMs", 650.0)), 0.0, 1.0)
			set_look(0.0)
			if _zone != null:
				_zone.strength = lerpf(0.2, 1.0, t)
			if t >= 1.0:
				_stomp(now, target, engaged, int(pattern("stompPutsOut", 1.0)))
		PHASE_STOMP:
			body.velocity = Vector2.ZERO
			set_look(0.0)
			if elapsed >= pattern("stompPoseMs", 420.0):
				_transition(PHASE_RECOVER, now)
		PHASE_RECOVER:
			# then he walks on (in his last phase the walk sends him up his wall, or into a quake)
			body.velocity = Vector2.ZERO
			set_look(0.0)
			if elapsed >= pattern("recoverMs", 600.0):
				_transition(PHASE_WALK, now)
		PHASE_STAGGER:
			body.velocity = Vector2.ZERO
			var left := 1.0 - clampf(elapsed / maxf(1.0, _stagger_ms), 0.0, 1.0)
			set_look(0.0, Vector2.ONE, sin(elapsed / 110.0) * 0.03 * left)
			if elapsed >= _stagger_ms:
				if _kick_cart != null and is_instance_valid(_kick_cart) and bool(_kick_cart.call(&"is_held_for_kick")):
					_start_kick(now)
				else:
					_after_rocked(now, slime)
		PHASE_KICK:
			body.velocity = Vector2.ZERO
			var kick_ms := maxf(1.0, pattern("kickMs", 760.0))
			var t := clampf(elapsed / kick_ms, 0.0, 1.0)
			var lean_way := signf(_turned.x)
			if t < KICK_AT:
				set_look(0.0, Vector2.ONE, -KICK_LEAN_BACK * lean_way * t / KICK_AT)
			else:
				if not _kicked:
					_kick(now)
				set_look(0.0, Vector2.ONE, KICK_LEAN_IN * lean_way * (1.0 - (t - KICK_AT) / (1.0 - KICK_AT)))
			if t >= 1.0:
				_after_rocked(now, slime)
		PHASE_HOP_CROUCH:
			body.velocity = Vector2.ZERO
			set_look(0.0)
			var crouch := maxf(1.0, pattern("hopCrouchMs", 350.0))
			if _zone != null:
				_zone.strength = lerpf(0.5, 0.75, clampf(elapsed / crouch, 0.0, 1.0))
			if elapsed >= crouch:
				_begin_air(_hop_to)
				_transition(PHASE_HOP, now)
		PHASE_QUAKE_WARN:
			body.velocity = Vector2.ZERO
			var warn := maxf(1.0, pattern("quakeWarnMs", 2500.0))
			var share := clampf(elapsed / warn, 0.0, 1.0)
			set_look(0.0, Vector2.ONE, sin(elapsed / 38.0) * QUAKE_TREMBLE * share)
			if now >= _quake_next_rumble:
				_quake_next_rumble = now + QUAKE_RUMBLE_EVERY_MS
				var feel := Services.feel()
				if feel != null:
					feel.shake(QUAKE_RUMBLE_EVERY_MS + 60.0, pattern("quakeRumble", 0.006) * share)
				_puff(DUST, _quake_point())
			if elapsed >= warn:
				_begin_quake(now)
		PHASE_QUAKE:
			body.velocity = Vector2.ZERO
			set_look(0.0)
			if now >= _quake_next_pound:
				_quake_pound(now)
			if now >= _quake_next_crack:
				_quake_next_crack = now + pattern("quakeCrackEveryMs", 280.0)
				_quake_crack()
			if now >= _quake_next_tick:
				_quake_next_tick = now + pattern("quakeTickMs", 600.0)
				_quake_tick(target, engaged)
			if elapsed >= pattern("quakeMs", 5000.0):
				_transition(PHASE_RECOVER, now)
				_stomp_ready_at = now + pattern("recoverMs", 600.0) + pattern("afterQuakeStompMs", 800.0)
		PHASE_HOP:
			var air := maxf(1.0, pattern("hopAirMs", 650.0))
			_fly(elapsed, air, 0.0, 0.0, pattern("hopArcPx", 90.0))
			if _zone != null:
				_zone.strength = clampf(0.75 + 0.25 * elapsed / air, 0.75, 1.0)
			if elapsed >= air:
				_hop_land(now, target, engaged)
		PHASE_LEAP_UP:
			_fly(elapsed, pattern("leapUpMs", 700.0), 0.0, pattern("wallLiftPx", 120.0))
			if elapsed >= pattern("leapUpMs", 700.0):
				_transition(PHASE_CLING, now)
				_next_throw_at = now + pattern("firstThrowMs", 900.0)
				_next_rock_at = now + pattern("wallRockFirstMs", 2000.0)
				_thrown = 0
				_grip(true)
		PHASE_CLING:
			body.velocity = Vector2.ZERO
			var sway := sin(elapsed / 260.0) * 3.0
			set_look(pattern("wallLiftPx", 120.0) + sway)
			if now >= _next_throw_at and _thrown < int(pattern("mitesPerClimb", 2.0) * _rage(1.5)) and live_mites() < int(pattern("maxMites", 4.0)):
				_throw_mite(now, target)
			if _last_phase():
				# his last phase: he stays up his wall, a rock at the slime every `wallRockEveryMs`, and
				# comes down only to quake
				if now >= _next_rock_at and now >= _throw_pose_until:
					_throw_rock(now)
				if _quake_due_last(now):
					_leap_down_to(now, _floor_rect().get_center())
			elif elapsed >= pattern("climbMs", 5200.0):
				_leap_down(now, slime)
		PHASE_LEAP_DOWN:
			var air := pattern("leapDownMs", 900.0)
			_fly(elapsed, air, pattern("wallLiftPx", 120.0), 0.0)
			if _zone != null:
				_zone.strength = clampf(elapsed / air, 0.2, 1.0)
			if elapsed >= air:
				_land(now, target, engaged)
		PHASE_FALL:
			# Off the wall, away from it, falling fast (no arc): no ring, no stomp.
			var fall := maxf(1.0, pattern("fallMs", 450.0))
			var t := clampf(elapsed / fall, 0.0, 1.0)
			body.velocity = Vector2.ZERO
			body.global_position = _air_from.lerp(_air_to, t)
			set_look(lerpf(pattern("wallLiftPx", 120.0), 0.0, t * t))
			if t >= 1.0:
				_crash(now)
		PHASE_STUNNED:
			# on his back `plateFallStunMs` (long enough for the slime to drop from the roots and the
			# cart to come from the far wall's tunnel)
			body.velocity = Vector2.ZERO
			var stun := pattern("plateFallStunMs", 4000.0)
			var wobble := sin(elapsed / 70.0) * 0.02 * (1.0 - clampf(elapsed / maxf(1.0, stun), 0.0, 1.0))
			set_look(0.0, Vector2(1.0 + wobble, 1.0 - wobble))
			if elapsed >= stun:
				_get_up(now)


## His rage: from phase `rageFromPhase` on (a crystal dead: 2) he walks and stomps faster, throws more
## mites, quakes sooner and douses double (`factor`).
func _rage(factor: float) -> float:
	return factor if crystal_phase() >= int(pattern("rageFromPhase", 2.0)) else 1.0


## True while he rages (from phase `rageFromPhase` on).
func is_raging() -> bool:
	return _rage(2.0) > 1.0


## True while he lies stunned after his claws lost their grip (his back open to the Spear).
func is_stunned() -> bool:
	return _phase == PHASE_STUNNED


## Spear hits on his claws so far this climb.
func claw_hits() -> int:
	return _claw_hits


## His grip on the wall (`on`: he clings; his hurtbox rides up the face with his pose, so a slime
## climbing beside him reaches his claws) or not (his hurtbox back at his body, as authored).
func _grip(on: bool) -> void:
	if damage_area == null:
		return
	if on:
		_claw_hits = 0
		_claw_activation = null
		damage_area.position = _area_home - Vector2(0.0, pattern("wallLiftPx", 120.0))
		set_hurtbox(true)
	else:
		damage_area.position = _area_home


## A Spear hit from a climbing slime on his gripping claws: a crack; `clawHits` of them and he lets go.
func _claw_hit(request: Dictionary) -> void:
	var activation: Variant = request.get("activation_id")
	if activation != null and activation == _claw_activation:
		return
	_claw_activation = activation
	_claw_hits += 1
	var claws := get_centre() + CLAW_GLOW_AT + Vector2(0.0, 120.0 - pattern("wallLiftPx", 120.0))
	_cue(CUE_CRACK)
	_puff(SHARDS, claws)
	var feel := Services.feel()
	if feel != null:
		feel.shake(160.0, 0.006)
	if _claw_hits >= int(pattern("clawHits", 3.0)):
		_lose_grip(Services.now_ms())


## His claws lose their grip: he crashes down off the wall across the nearest crash cart's line
## (`fallDropPx` out from the wall with none).
func _lose_grip(now: float) -> void:
	_grip(false)
	_clear_zone()
	var drop := _on_crash_line(feet() + Vector2(0.0, pattern("fallDropPx", 70.0)))
	var landing := _inside_arena(drop)
	_begin_air(landing)
	_transition(PHASE_FALL, now)
	_cue(CUE_PLATE_ROAR)


## The crash at the wall's foot: a hard shake and dust, no stomp ring and no brazier out; then the stun,
## on his back.
func _crash(now: float) -> void:
	_end_air()
	_let_go_cart()
	_cue(CUE_PLATE_STOMP)
	_puff(DUST, feet())
	_puff(SHARDS, get_centre())
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("crashShakeMs", 420.0), pattern("crashShake", 0.016))
	_transition(PHASE_STUNNED, now)
	_lie_hurtbox()


## Up again after the stun: he fights on (a cart that struck him as he lay he kicks back first).
func _get_up(now: float) -> void:
	_transition(PHASE_WALK, now)
	_stomp_ready_at = now + pattern("afterReelStompMs", 900.0)
	_turned = Vector2.DOWN
	_stand_hurtbox()
	if _kick_cart != null and is_instance_valid(_kick_cart) and bool(_kick_cart.call(&"is_held_for_kick")):
		_start_kick(now)


## `point` (feet) kept `arenaInsetPx` inside his arena (the point itself without one).
func _inside_arena(point: Vector2) -> Vector2:
	if _arena.is_empty():
		return point
	var inset := pattern("arenaInsetPx", 48.0)
	var x := float(_arena.get("x", point.x))
	var y := float(_arena.get("y", point.y))
	var w := float(_arena.get("w", 0.0))
	var h := float(_arena.get("h", 0.0))
	return Vector2(clampf(point.x, x + inset, x + w - inset), clampf(point.y, y + inset, y + h - inset))


func _raise(now: float) -> void:
	_transition(PHASE_RAISE, now)
	_cue(CUE_RAISE)
	_set_facing(Vector2.DOWN)
	_show_zone(feet(), Vector2(pattern("stompRx", 116.0), pattern("stompRy", 78.0)), ZONE_TINT)


## His stomp (a landing from his wall is one): `put_out` braziers go out while he douses, else one once
## the long wait is over (`_step_douse`), else none.
func _stomp(now: float, target: Dictionary, engaged: bool, put_out: int) -> void:
	_transition(PHASE_STOMP, now)
	_clear_zone()
	_stomp_ready_at = now + pattern("stompPoseMs", 420.0) + pattern("recoverMs", 600.0) + pattern("stompCooldownMs", 1400.0) / _rage(1.4)
	_cue(CUE_PLATE_STOMP)
	_puff(SHARDS, feet())
	_puff(DUST, feet())
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("stompShakeMs", 320.0), pattern("stompShake", 0.012))
	if not _dousing:
		put_out = mini(put_out, 1) if _douse_due(now) else 0
	for i in maxi(0, put_out):
		CandleScript.put_out_near(get_tree(), feet(), Vector2(4000, 4000), true)
	if put_out > 0:
		_douse_clock_from = now
	_ring_hit(target, engaged, pattern("stompDamage", 40.0), pattern("stompKnockback", 340.0))
	_drop_debris(int(pattern("debrisPerStomp", 2.0)))


## A slime whose feet are in the ring round his feet (`stompRx` x `stompRy`) takes `damage`.
func _ring_hit(target: Dictionary, engaged: bool, damage: float, knockback: float) -> void:
	var slime_body := target.get("body") as Node2D
	if not engaged or slime_body == null or damage <= 0.0:
		return
	var offset := slime_body.global_position - feet()
	var rx := maxf(1.0, pattern("stompRx", 116.0))
	var ry := maxf(1.0, pattern("stompRy", 78.0))
	if (offset.x / rx) * (offset.x / rx) + (offset.y / ry) * (offset.y / ry) <= 1.0:
		_route_hit_from(get_centre(), target, damage, knockback)


## A slime (its old centre `slime`) more than `hopFarPx` from him (`centre`) for
## `hopAfterMs` in a row, and his last leap `hopCooldownMs` ago: he leaps after it.
func _wants_hop(now: float, centre: Vector2, slime: Vector2) -> bool:
	if centre.distance_to(slime) <= pattern("hopFarPx", 300.0):
		_far_since = -1.0
		return false
	if _far_since < 0.0:
		_far_since = now
	return now - _far_since >= pattern("hopAfterMs", 1200.0) and now >= _hop_ready_at


## His leap's time back after a leap that never landed (`_begin_hop` puts it off to INF until
## `_hop_land`): a cart's blow in the crouch, or any other way out of it, would else leave him without
## a leap for the rest of the fight. The next comes `hopCooldownMs` from now.
func _restore_leap() -> void:
	if not is_finite(_hop_ready_at):
		_hop_ready_at = Services.now_ms() + pattern("hopCooldownMs", 5000.0)


## He crouches to leap at the slime: he lands `hopShortPx` short of it (at most `hopMaxPx` from where he
## stands, kept on his floor), the ring showing where.
func _begin_hop(now: float, slime: Vector2, short_px: float = -1.0) -> void:
	_far_since = -1.0
	_hop_ready_at = INF
	body.velocity = Vector2.ZERO
	var from := feet()
	var way := _feet_for(slime) - from
	var short := short_px if short_px >= 0.0 else pattern("hopShortPx", 150.0)
	var reach := clampf(way.length() - short, 0.0, pattern("hopMaxPx", 520.0))
	_hop_to = _inside_arena(from + way.normalized() * reach)
	_transition(PHASE_HOP_CROUCH, now)
	_set_facing(Vector2.DOWN)
	_cue(CUE_RAISE)
	_show_zone(_hop_to, Vector2(pattern("stompRx", 116.0), pattern("stompRy", 78.0)), HOP_TINT)


## The leap lands: the slam (a slime in the ring takes `hopDamage`), no brazier out; then he recovers
## as from a stomp and walks on.
func _hop_land(now: float, target: Dictionary, engaged: bool) -> void:
	_end_air()
	set_look(0.0)
	_clear_zone()
	_stand_hurtbox()
	_hop_ready_at = now + pattern("hopCooldownMs", 5000.0)
	_transition(PHASE_STOMP, now)
	_stomp_ready_at = now + pattern("stompPoseMs", 420.0) + pattern("recoverMs", 600.0) + pattern("afterHopStompMs", 300.0)
	_cue(CUE_PLATE_STOMP)
	_puff(SHARDS, feet())
	_puff(DUST, feet())
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("hopShakeMs", 260.0), pattern("hopShake", 0.01))
	_ring_hit(target, engaged, pattern("hopDamage", 20.0), pattern("hopKnockback", 300.0))
	_drop_debris(int(pattern("debrisPerHop", 1.0)))


## Whether his stomps put braziers out. Hurt while every brazier burns (a plate burst or a crystal hit:
## `_harm`, as a burst no longer costs him health), he douses (one a stomp, until none burns). The long
## wait (`douseAfterMs`) starts again whenever a brazier is lit or put out; once it is over his next
## stomp puts one out (`_douse_due`).
func _step_douse(now: float) -> void:
	var states := _brazier_states()
	if states != _lit_states:
		_lit_states = states
		_douse_clock_from = now
	if _douse_harm >= 0 and _harm > _douse_harm and _braziers_lit() >= braziers.size() and not braziers.is_empty():
		_dousing = true
	_douse_harm = _harm
	if _dousing and _braziers_lit() == 0:
		_dousing = false


## True when the long wait is over: `douseAfterMs` with no brazier lit or put out, and one burns.
func _douse_due(now: float) -> bool:
	return now - _douse_clock_from >= pattern("douseAfterMs", 45000.0) and _braziers_lit() > 0


## Whether each of the arena's braziers burns, in their order.
func _brazier_states() -> Array[bool]:
	var out: Array[bool] = []
	for node: Node in braziers:
		out.append(is_instance_valid(node) and node.has_method(&"is_lit") and bool(node.call(&"is_lit")))
	return out


## His quake is due (`quakeFirstMs` after he wakes, `quakeEveryMs` after the last
## one began, sooner while he rages), the slime is on the floor (not up a wall), and his wall has
## climb walls to escape up.
func _wants_quake(now: float) -> bool:
	return now >= _quake_ready_at and not _slime_climbing() and not _quake_roots().is_empty()


## The warning: he roars and rears, trembling harder and harder, the ground creaking; the floor cracks
## from his feet and the climb walls light up (game/bosses/colossus_quake.gd).
func _begin_quake_warn(now: float) -> void:
	_far_since = -1.0
	_quake_hits = 0
	body.velocity = Vector2.ZERO
	_clear_zone()
	var warn := pattern("quakeWarnMs", 2500.0)
	var quake := pattern("quakeMs", 5000.0)
	_quake_ready_at = now + warn + quake + pattern("quakeEveryMs", 22000.0) / _rage(1.3)
	_quake_next_rumble = now
	_transition(PHASE_QUAKE_WARN, now)
	_set_facing(Vector2.DOWN)
	_cue(CUE_PLATE_ROAR)
	_cue(CUE_CREAK)
	var look := ColossusQuake.new()
	look.name = "ColossusQuake"
	look.set(&"boss", self)
	look.set(&"origin", feet())
	look.set(&"floor_rect", _floor_rect())
	look.set(&"warn_ms", warn)
	look.set(&"quake_ms", quake)
	var roots: Array[Node2D] = _quake_roots()
	look.set(&"roots", roots)
	_effects_parent().add_child(look)
	_quake_look = look


## The shaking starts: he pounds the floor from now on.
func _begin_quake(now: float) -> void:
	_transition(PHASE_QUAKE, now)
	_quake_pounds = 0
	_quake_next_pound = now
	_quake_next_crack = now
	_quake_next_tick = now + pattern("quakeFirstTickMs", 250.0)


## One pound: the slam frame, a heavy shake, dust and chips at his feet.
func _quake_pound(now: float) -> void:
	_quake_last_pound = now
	_quake_next_pound = now + pattern("quakePoundMs", 450.0)
	_quake_pounds += 1
	if _quake_pounds % maxi(1, int(pattern("debrisEveryPounds", 2.0))) == 0:
		_drop_debris(1)
	_cue(CUE_PLATE_STOMP)
	_puff(DUST, feet())
	_puff(SHARDS, feet())
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("quakeShakeMs", 300.0), pattern("quakeShake", 0.012))


## A crater pops somewhere on his floor (the quake's look paints it), chips flying, the stone
## breaking every other one.
func _quake_crack() -> void:
	var at := _quake_point()
	if _quake_look != null and is_instance_valid(_quake_look):
		_quake_look.call(&"add_crater", at)
	_puff(SHARDS, at)
	_quake_craters += 1
	if _quake_craters % 2 == 1:
		_cue(CUE_QUAKE_BREAK)


## The shaking hurts a slime on his floor (`quakeTickDamage`, no knockback); one up a wall is safe.
func _quake_tick(target: Dictionary, engaged: bool) -> void:
	if not engaged or _slime_climbing():
		return
	var slime_body := target.get("body") as Node2D
	if slime_body == null or not _floor_rect().grow(8.0).has_point(slime_body.global_position):
		return
	if _route_hit_from(get_centre(), target, pattern("quakeTickDamage", 6.0), 0.0):
		_quake_hits += 1


## A point on his floor away from its edges.
func _quake_point() -> Vector2:
	var rect := _floor_rect().grow(-40.0)
	return Vector2(_rng.randf_range(rect.position.x, rect.end.x), _rng.randf_range(rect.position.y, rect.end.y))


## His floor (global): his arena as the arena gave it.
func _floor_rect() -> Rect2:
	if _arena.is_empty():
		return Rect2(feet() - Vector2(400.0, 300.0), Vector2(800.0, 600.0))
	return Rect2(float(_arena.get("x", 0.0)), float(_arena.get("y", 0.0)), float(_arena.get("w", 0.0)), float(_arena.get("h", 0.0)))


## The climb walls up his wall: those within `QUAKE_ROOTS_NEAR_PX` of one of his climb spots.
func _quake_roots() -> Array[Node2D]:
	var out: Array[Node2D] = []
	if not is_inside_tree():
		return out
	for node: Node in get_tree().get_nodes_in_group(CLIMB_WALLS):
		var wall := node as Node2D
		if wall == null:
			continue
		for spot: Vector2 in climb_spots:
			if wall.global_position.distance_to(spot) <= QUAKE_ROOTS_NEAR_PX:
				out.append(wall)
				break
	return out


## True while the slime climbs a wall (or drops off one).
static func _slime_climbing() -> bool:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	return player != null and is_instance_valid(player) and player.has_method(&"is_climbing") \
		and bool(player.call(&"is_climbing"))


## The harms the shaking dealt in his last quake (the films read it).
func quake_hits() -> int:
	return _quake_hits


# --- his last phase --------------------------------------------------------------------------------

## His last phase: both shoulder crystals dead, his chest's left. He lives up his wall (see the head).
func _last_phase() -> bool:
	return current_crystal() == CHEST and not is_defeated()


## In his last phase a quake is due whatever the slime does (on the roots it is safe: the quake is
## what sends it up them).
func _quake_due_last(now: float) -> bool:
	return now >= _quake_ready_at and not _quake_roots().is_empty()


## The slime's centre now (its old centre), else `fallback`.
func _slime_centre(fallback: Vector2) -> Vector2:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player != null and is_instance_valid(player) and player.has_method(&"get_centre"):
		return player.call(&"get_centre")
	return fallback


## A rock thrown from his wall at where the slime is (the owner, 2026-11-24: "every 5 seconds he
## trhow a rock at you this rock can hit you even in the vines so you are not safe anywhere"): it
## flies from his hand in an arc over `wallRockFlightMs`, its shadow growing where it will land, and
## hits a slime within `wallRockHitPx` there for `wallRockDamage`, climbing or not. Landing on the
## wall (the slime climbing) or by the rails it shatters; on the floor it lies as a rock to throw.
func _throw_rock(now: float) -> void:
	_next_rock_at = now + pattern("wallRockEveryMs", 5000.0)
	var world := Services.world()
	var slime_body: Node2D = world.player_body if world != null else null
	if slime_body == null or not is_instance_valid(slime_body):
		return
	_throw_pose_until = now + pattern("throwPoseMs", 380.0)
	var at := slime_body.global_position
	var shatter := _slime_climbing() or not _floor_rect().has_point(at) \
		or _near_rails(at, pattern("debrisRailClearPx", 72.0))
	var hand := get_centre() - Vector2(0.0, pattern("wallLiftPx", 120.0))
	_fall_at(at, 0.0, {"from": hand, "shatter": shatter, "anywhere": true,
		"fall_ms": pattern("wallRockFlightMs", 800.0), "damage": pattern("wallRockDamage", 10.0),
		"hit_px": pattern("wallRockHitPx", 40.0)})
	_cue(CUE_ROCK_THROW)


# --- his falling rocks -----------------------------------------------------------------------------

## His blow shakes `count` rocks loose from the roof (the owner, 2026-11-24: "colossus need to make
## rocks or cristals on every single attack they fall from the roof in ramdom spots making damage if
## they fall on you, thy never block the rails"): each falls on a free spot of his floor
## (`_debris_spot`), its shadow growing, `debrisStaggerMs` after the last.
func _drop_debris(count: int) -> void:
	if count <= 0 or debris_kinds.is_empty() or is_defeated():
		return
	for i in count:
		var at := _debris_spot()
		if at.is_finite():
			_fall_at(at, pattern("debrisStaggerMs", 180.0) * float(i))


## One rock falls onto `at` (global), starting `delay` ms from now (the films drop one on the slime).
## `options` (his thrown rock, `_throw_rock`): "from" (global: it flies from there in an arc instead
## of falling from the roof), "fall_ms", "damage", "hit_px", "anywhere" (it hits a slime off his floor
## too: up the wall), "shatter" (it breaks where it lands instead of lying there).
func _fall_at(at: Vector2, delay: float, options: Dictionary = {}) -> void:
	if debris_kinds.is_empty():
		return
	var fall := float(options.get("fall_ms", pattern("debrisFallMs", 750.0)))
	var kind := debris_kinds[_rng.randi_range(0, debris_kinds.size() - 1)]
	var look := ColossusDebris.new()
	look.name = "ColossusDebris"
	look.set(&"kind", kind)
	look.set(&"origin", at)
	look.set(&"delay_ms", delay)
	look.set(&"fall_ms", fall)
	look.set(&"fall_px", pattern("debrisFallPx", 420.0))
	if options.get("from") is Vector2:
		look.set(&"from", options["from"])
	_effects_parent().add_child(look)
	var drop := options.duplicate()
	drop.merge({"at": at, "kind": kind, "lands_at": Services.now_ms() + delay + fall, "look": look}, true)
	_debris_due.append(drop)


## The rocks whose fall is over land.
func _step_debris(now: float, target: Dictionary, engaged: bool) -> void:
	for i in range(_debris_due.size() - 1, -1, -1):
		var drop: Dictionary = _debris_due[i]
		if now >= float(drop["lands_at"]):
			_debris_due.remove_at(i)
			_land_debris(drop, target, engaged)


## A rock lands: a slime under it takes `debrisDamage`; it lies there to throw (a liftable of its kind,
## nothing under it); past `debrisMax` lying the oldest crumbles away.
func _land_debris(drop: Dictionary, target: Dictionary, engaged: bool) -> void:
	var look: Variant = drop.get("look")
	if look is Node and is_instance_valid(look):
		(look as Node).queue_free()
	var at: Vector2 = drop["at"]
	var slime_body := target.get("body") as Node2D
	var hits := engaged or bool(drop.get("anywhere", false))
	if hits and slime_body != null and slime_body.global_position.distance_to(at) <= float(drop.get("hit_px", pattern("debrisHitPx", 34.0))):
		_route_hit_from(at, target, float(drop.get("damage", pattern("debrisDamage", 10.0))), pattern("debrisKnockback", 160.0))
	_puff(DUST, at)
	_puff(SHARDS, at)
	var feel := Services.feel()
	if bool(drop.get("shatter", false)):
		# broken where it struck (up the wall, by the rails): nothing left lying
		if feel != null:
			feel.audio_cue(CUE_QUAKE_BREAK)
		return
	var rock := ThrowAmmo.spawn_liftable(str(drop["kind"]), at, {"pop": false, "weight": debris_weight})
	if feel != null:
		feel.audio_cue(CUE_DEBRIS)
	if rock == null:
		return
	_prune_debris()
	_debris.append(rock)
	while _debris.size() > maxi(1, int(pattern("debrisMax", 8.0))):
		_crumble(_debris.pop_front())


## Drops the rocks that are gone (sucked up and thrown, crumbled). A sucked-up rock is a freed object
## in the list, so each entry is checked as a Variant before it is typed.
func _prune_debris() -> void:
	var kept: Array[Node2D] = []
	for i in _debris.size():
		var entry: Variant = _debris[i]
		if is_instance_valid(entry) and not (entry as Node2D).is_queued_for_deletion():
			kept.append(entry as Node2D)
	_debris = kept


## A rock too many: it can no longer be sucked up and crumbles into dust.
func _crumble(rock: Node2D) -> void:
	if rock == null or not is_instance_valid(rock):
		return
	var script_node := rock.get_node_or_null(^"LiftableScript")
	if script_node != null:
		for group: StringName in script_node.get_groups():
			script_node.remove_from_group(group)
	if rock is CollisionObject2D:
		rock.set_deferred(&"collision_layer", 0)
	_puff(DUST, rock.global_position)
	var tween := rock.create_tween().set_parallel(true)
	tween.tween_property(rock, "scale", Vector2(1.2, 0.3), 0.4)
	tween.tween_property(rock, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(rock.queue_free)


## A spot on his floor for a rock: never on or by a cart's rails or a ram's lane (`debrisRailClearPx`),
## nor by him, a brazier, a knock target, another thing to throw or another falling rock; INF when
## none was found.
func _debris_spot() -> Vector2:
	var rect := _floor_rect().grow(-48.0)
	var clear := pattern("debrisClearPx", 56.0)
	for i in DEBRIS_TRIES:
		var at := Vector2(_rng.randf_range(rect.position.x, rect.end.x), _rng.randf_range(rect.position.y, rect.end.y))
		if at.distance_to(feet()) < pattern("debrisClearOfHimPx", 110.0) or _near_rails(at, pattern("debrisRailClearPx", 72.0)):
			continue
		if _near_any(at, braziers, clear + 20.0) or _near_group(at, TARGETS_GROUP, clear + 20.0) \
				or _near_group(at, LiftableScript.GROUP, clear):
			continue
		var taken := false
		for drop: Dictionary in _debris_due:
			if (drop["at"] as Vector2).distance_to(at) < clear:
				taken = true
				break
		if not taken:
			return at
	return Vector2.INF


## True when `at` lies within `clear` of a runaway cart's line (from tunnel to tunnel) or a ram's lane.
func _near_rails(at: Vector2, clear: float) -> bool:
	for node: Node in get_tree().get_nodes_in_group(MECHANISMS_GROUP):
		var mechanism := node as Node2D
		if mechanism == null:
			continue
		if mechanism.has_method(&"lane_rect") and (mechanism.call(&"lane_rect") as Rect2).grow(clear * 0.5).has_point(at):
			return true
		var line: Variant = mechanism.get(&"points")
		if not line is PackedVector2Array:
			continue
		var points := line as PackedVector2Array
		for k in points.size() - 1:
			var a := mechanism.global_position + points[k]
			var b := mechanism.global_position + points[k + 1]
			if Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) < clear:
				return true
	return false


func _near_group(at: Vector2, group: StringName, clear: float) -> bool:
	return _near_any(at, get_tree().get_nodes_in_group(group), clear)


## True when one of `nodes` (or, for a plain node such as a liftable's script, its parent) stands
## within `clear` of `at`.
static func _near_any(at: Vector2, nodes: Array, clear: float) -> bool:
	for node: Variant in nodes:
		if not is_instance_valid(node) or not node is Node:
			continue
		var place := node as Node2D
		if place == null:
			place = (node as Node).get_parent() as Node2D
		if place != null and place.global_position.distance_to(at) < clear:
			return true
	return false


## The rocks lying on his floor now (the films read them).
func get_debris() -> Array[Node2D]:
	_prune_debris()
	return _debris.duplicate()


## How many of the arena's braziers burn.
func _braziers_lit() -> int:
	var lit := 0
	for node: Node in braziers:
		if is_instance_valid(node) and node.has_method(&"is_lit") and bool(node.call(&"is_lit")):
			lit += 1
	return lit


## True while his next stomp puts a brazier out (dousing, or the long wait over).
func is_dousing() -> bool:
	return _dousing or _douse_due(Services.now_ms())


## The time left of the long wait (ms; 0 once it is over).
func douse_wait_left() -> float:
	return maxf(0.0, pattern("douseAfterMs", 45000.0) - (Services.now_ms() - _douse_clock_from))


## Onto the wall at the climb spot nearest the slime (`slime`, its old centre), with a roar.
func _leap_up(now: float, slime: Vector2) -> void:
	_clear_zone()
	var best := climb_spots[0]
	for spot in climb_spots:
		if absf(spot.x - slime.x) < absf(best.x - slime.x):
			best = spot
	_cling_at = best
	_begin_air(_feet_for(_cling_at))
	_transition(PHASE_LEAP_UP, now)
	_turned = Vector2.UP
	_cue(CUE_PLATE_ROAR)


func _leap_down(now: float, slime: Vector2) -> void:
	# Where the slime stands, kept on his arena's floor (a slime up the wall is not under him).
	_leap_down_to(now, _feet_for(slime))


## Down off his wall onto `landing_feet` (kept on his floor), a ring marking it.
func _leap_down_to(now: float, landing_feet: Vector2) -> void:
	var landing := _inside_arena(landing_feet)
	_begin_air(landing)
	_transition(PHASE_LEAP_DOWN, now)
	_turned = Vector2.DOWN
	_show_zone(landing, Vector2(pattern("stompRx", 116.0), pattern("stompRy", 78.0)), LAND_TINT)


func _land(now: float, target: Dictionary, engaged: bool) -> void:
	_end_air()
	set_look(0.0)
	_stomp(now, target, engaged, int(pattern("landPutsOut", 1.0) * _rage(2.0)))
	_stand_hurtbox()


## Airborne: not solid, no hurtbox, nothing collides; the body is moved straight there.
func _begin_air(to_feet: Vector2) -> void:
	_grip(false)
	_air_from = body.global_position
	_air_to = to_feet
	set_solid(false)
	set_hurtbox(false)
	# From the wall (leap down, a fall) the mask is already off: keep the one he walks with.
	if body.collision_mask != 0:
		_mask = body.collision_mask
	body.collision_mask = 0


func _end_air() -> void:
	body.collision_mask = _mask if _mask != 0 else body.collision_mask
	set_solid(true)
	set_hurtbox(true)


## Through the air from `_air_from` to `_air_to` (feet), the pose lifted from `from_lift` to
## `to_lift` with an arc over the way (`arc`, else `leapArcPx`).
func _fly(elapsed: float, air_ms: float, from_lift: float, to_lift: float, arc: float = -1.0) -> void:
	var t := clampf(elapsed / maxf(1.0, air_ms), 0.0, 1.0)
	body.velocity = Vector2.ZERO
	body.global_position = _air_from.lerp(_air_to, t)
	set_look(lerpf(from_lift, to_lift, t) + sin(t * PI) * (arc if arc >= 0.0 else pattern("leapArcPx", 110.0)))


func _throw_mite(now: float, target: Dictionary) -> void:
	_throw_pose_until = now + pattern("throwPoseMs", 380.0)
	_next_throw_at = now + pattern("throwEveryMs", 1300.0)
	_thrown += 1
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	var root := world.instantiate_scene(MITE_SCENE) as Node2D if world != null else null
	if root == null or parent == null:
		return
	var mite: Node = null
	for child: Node in root.get_children():
		if child.has_method(&"configure_arena"):
			mite = child
			break
	if mite == null:
		root.free()
		return
	parent.add_child(root)
	var slime: Vector2 = target.get("centre", get_centre())
	FeetAnchor.place_at_phaser_position(root, slime)
	var no_zones: Array[Dictionary] = []
	mite.call(&"configure_navigation", {}, no_zones)
	mite.call(&"configure_arena", get_arena())
	_mites.append(mite)


func _feet_for(centre: Vector2) -> Vector2:
	return centre - (get_centre() - feet())


func _show_zone(at: Vector2, size: Vector2, tint: Color) -> void:
	_clear_zone()
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return
	_zone = GroundShadowLook.new()
	_zone.name = ZONE_NAME
	_zone.size = size
	_zone.tint = tint
	_zone.strength = 0.2
	parent.add_child(_zone)
	_zone.global_position = at


func _clear_zone() -> void:
	if _zone != null and is_instance_valid(_zone):
		_zone.queue_free()
	_zone = null


func _process(_delta: float) -> void:
	_show_plates(Services.now_ms())
	if _clink_cue != null:
		_follow_clink_cue()


# --- hits ------------------------------------------------------------------------------------------

## His hit rules (the head): the Spear from a climbing slime on his claws while he clings (counted,
## not hurting him); in the air and asleep nothing lands; the Spear and thrown things land only on this
## phase's crystal, bare (its plate gone) and showing to the hitter (`_hit_meets`); everything else
## clinks (the Spear's own clink, a spark off a plate or grit off a dead crystal or his rock, and at the
## phase's first clink a line and the thing to hit flashing).
func _shields(request: Dictionary) -> bool:
	if _phase == PHASE_CLING:
		if has_tag(request, SPEAR_TAG) and _from_climber(request):
			_claw_hit(request)
		return true
	if _phase in [PHASE_WAIT, PHASE_LEAP_UP, PHASE_LEAP_DOWN, PHASE_FALL, PHASE_HOP]:
		return true
	if not has_tag(request, SPEAR_TAG) and not has_tag(request, THROWN_TAG):
		return true
	var from := _hit_from(request)
	var meets := _hit_meets(from)
	if not meets.is_empty() and meets == current_crystal():
		return false
	_clink(request, meets, from)
	return true


## What a Spear hit or a throw from `from` (unit, from him toward it) meets: this phase's crystal's
## name when it is bare and shows that way (it hurts), else "plate", "dead" (a dead crystal) or "rock".
## A crystal shows where the art draws it (SHOWS_FROM: a shoulder's from his front, his back and its
## own side; the chest's from his front and both sides); on his back every one faces the sky.
func _hit_meets(from: Vector2) -> String:
	var current := current_crystal()
	var showing: Array = PLATE_NAMES if _phase == PHASE_STUNNED else SHOWS_FROM.get(_side_of(from), [])
	if not current.is_empty() and current in showing:
		return "plate" if has_plate(current) else current
	for crystal: String in showing:
		if not has_plate(crystal) and crystal_left(crystal) <= 0.0:
			return "dead"
	for crystal: String in showing:
		if has_plate(crystal):
			return "plate"
	return "rock"


## A hit that met no bare live crystal (once a strike): a cyan spark off a plate, grey grit off a dead
## crystal or his rock, where it struck; the phase's first such hit gives its line (`_hint_clink`).
func _clink(request: Dictionary, meets: String, from: Vector2) -> void:
	var activation: Variant = request.get("activation_id")
	if activation != null and activation == _clink_activation:
		return
	_clink_activation = activation
	_clinks += 1
	var at := get_centre() + from * CLINK_OUT_PX
	var feel := Services.feel()
	if meets == "plate":
		if feel != null:
			feel.burst(SPARK, at, from if from != Vector2.ZERO else Vector2.UP, CLANG_TINT, 0.6)
	else:
		_puff(DUST, at)
	if _clink_hinted_phase != crystal_phase():
		_clink_hinted_phase = crystal_phase()
		_hint_clink(meets)


## The phase's first clink: the line over the slime, and the thing to hit flashing under an arrow (a
## hint flashes the thing it is about: docs/GAME_GUIDELINES.md "Hints"), following him: this phase's
## plate while it is on, else its bare crystal.
func _hint_clink(meets: String) -> void:
	var current := current_crystal()
	if current.is_empty():
		return
	var plated := has_plate(current)
	var text := plated_hint_text if plated else (dead_hint_text if meets == "dead" else crystal_hint_text)
	var feel := Services.feel()
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if feel != null and player != null and not text.is_empty():
		feel.hint_text(player, HINT_LIFT, text, &"orange", HINT_MS)
	if _clink_cue != null and is_instance_valid(_clink_cue):
		_clink_cue.queue_free()
	var cue := HintCue.new()
	cue.name = "CrystalHint"
	cue.set(&"flashes", HINT_FLASHES)
	cue.set(&"life_ms", HINT_MS)
	_effects_parent().add_child(cue)
	_clink_cue = cue
	_clink_cue_on = current
	_follow_clink_cue()


## The Spear hits and throws that clinked off him so far (once a strike; the films and tests read it).
func clinks() -> int:
	return _clinks


## The clink's hint follows the thing it flashes (he moves): this phase's plate, else its crystal.
func _follow_clink_cue() -> void:
	if _clink_cue == null or not is_instance_valid(_clink_cue):
		_clink_cue = null
		return
	_clink_cue.global_position = _plate_point(_clink_cue_on) if has_plate(_clink_cue_on) else _crystal_point(_clink_cue_on)


## True when the hit's source is the slime climbing a wall (the Feral skin).
static func _from_climber(request: Dictionary) -> bool:
	var source: Variant = request.get("source")
	return is_instance_valid(source) and source is Node and (source as Node).has_method(&"is_climbing") \
		and bool((source as Node).call(&"is_climbing"))


## The way from his centre toward where `request` came from (unit): its source's centre, else
## against its knock; ZERO when neither says.
func _hit_from(request: Dictionary) -> Vector2:
	var source: Variant = request.get("source")
	if is_instance_valid(source) and source is Node and (source as Node).has_method(&"get_centre"):
		var toward: Vector2 = (source as Node).call(&"get_centre") - get_centre()
		if toward != Vector2.ZERO:
			return toward.normalized()
	var impact: Dictionary = request.get("impact", {})
	var knock: Vector2 = impact.get("knock", Vector2.ZERO)
	return -knock.normalized() if knock != Vector2.ZERO else Vector2.ZERO


func mitigate_damage(input: Dictionary) -> float:
	var request: Dictionary = input.get("request", {})
	var amount := super(input)
	if _kill_hit(request):
		return amount
	# a thrown thing on bare crystal: half a Spear hit, whatever it would do elsewhere
	if has_tag(request, THROWN_TAG) and not has_tag(request, SPEAR_TAG):
		var constants := Services.constants()
		var spear := float(constants.value("shapes.spear.baseDamage", 12.0)) if constants != null else 12.0
		amount = spear * pattern("thrownShare", 0.5)
	# only this phase's crystal takes it, and never past its own share (each phase ends at its third)
	return clampf(amount, 0.0, crystal_left(current_crystal()))


## A hit on this phase's crystal: its share comes off it (a crack, rose chips, the crystal flashing);
## at 0 it is destroyed (`_crystal_breaks`). The chest's last hit is his fall (`_defeat`).
func commit_damage(commit: Dictionary) -> void:
	var crystal := current_crystal()
	super(commit)
	var result: Dictionary = commit.get("result", {})
	var dealt := float(result.get("actual_damage", 0.0))
	if dealt <= 0.0 or crystal.is_empty():
		return
	_harm += 1
	_crystal_hp[crystal] = maxf(0.0, crystal_left(crystal) - dealt)
	if is_defeated():
		return
	_cue(CUE_CRACK)
	_puff(SHARDS, _crystal_point(crystal))
	if _look != null:
		_look.flash_crystal(crystal)
	if crystal_left(crystal) <= 0.0:
		var request: Dictionary = commit.get("request", {})
		_crystal_breaks(crystal, str(request.get("weapon_id", "")))


## A crystal destroyed: rose shards burst from it, a roar, the burst's shake; it shows dead for good
## and he staggers `crystalBreakStaggerMs` (the stomp sheet's last frame). The next phase starts: after
## the second shoulder he makes for his wall once the stagger is over (and the cart is kicked home).
func _crystal_breaks(crystal: String, by: String) -> void:
	_crystal_hp[crystal] = 0.0
	var shards := ColossusShards.burst(_effects_parent(), _crystal_point(crystal), feet().y, false, Vector2.ZERO,
		211 + CRYSTAL_ORDER.find(crystal) * 17)
	if shards != null:
		shards.modulate = CRYSTAL_SHARDS
	_cue(CUE_SHATTER)
	_cue(CUE_PLATE_ROAR)
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("burstShakeMs", 420.0), pattern("burstShake", 0.014))
	crystal_broken.emit({"crystal": crystal, "by": by, "hp": get_damage_state()["hp"], "phase": crystal_phase()})
	if _clink_cue != null and is_instance_valid(_clink_cue):
		_clink_cue.queue_free()
	_clink_cue = null
	if _last_phase() and _phase != PHASE_STUNNED:
		_leap_due = true
	if _phase != PHASE_STUNNED:
		_stagger(pattern("crystalBreakStaggerMs", 1400.0))


func _defeat() -> void:
	if is_defeated():
		return
	_clear_zone()
	_grip(false)
	_end_air()
	clear_mites()
	_let_go_cart()
	_clear_falling_rocks()
	_cue(CUE_CRACK)
	_puff(SHARDS, get_centre())
	var feel := Services.feel()
	if feel != null:
		feel.shake(700.0, 0.016)
	_dead_at = Services.now_ms()
	# his last crystal (the chest) goes dark with him: every plate gone, every crystal dead
	var last := current_crystal()
	for plate: String in PLATE_NAMES:
		_plates[plate] = false
		_crystal_hp[plate] = 0.0
	if _clink_cue != null and is_instance_valid(_clink_cue):
		_clink_cue.queue_free()
	_clink_cue = null
	if not last.is_empty():
		crystal_broken.emit({"crystal": last, "by": "", "hp": 0.0, "phase": crystal_phase()})
	_cue(CUE_SHATTER)
	_cue(CUE_PLATE_ROAR)
	ColossusShards.burst(_effects_parent(), get_centre(), feet().y, false, Vector2.ZERO, 409)
	super()


## The rocks still falling when he falls for good (his step stops, so they would never land and their
## pictures would lie on the floor as rocks nobody can pick up): each look goes with a puff of dust
## where it would have landed.
func _clear_falling_rocks() -> void:
	for drop: Dictionary in _debris_due:
		var look: Variant = drop.get("look")
		if look is Node and is_instance_valid(look):
			(look as Node).queue_free()
		_puff(DUST, drop.get("at", feet()))
	_debris_due.clear()


## His look draws him (`_show_plates`): the scene's old sheet, blanked in `_setup_plates`, takes no
## frame (the base's defeat sets `defeated_frame`).
func set_frame(_index: int) -> void:
	pass


## His look turns him itself (`_turned`): the Visual that holds it is never mirrored.
func face_x(_dx: float) -> void:
	pass


func _damage_number_top() -> float:
	return feet().y - NUMBER_RISE


# --- his crystals ----------------------------------------------------------------------------------

## A crystal's share of his health: his health in three equal parts.
func crystal_share() -> float:
	return max_health / float(CRYSTAL_ORDER.size())


## The crystal of this phase: the first live one in CRYSTAL_ORDER ("" once all are dead).
func current_crystal() -> String:
	for crystal: String in CRYSTAL_ORDER:
		if crystal_left(crystal) > 0.0:
			return crystal
	return ""


## His phase: 1 (the first crystal) to 3 (the chest); 4 once all are dead.
func crystal_phase() -> int:
	var current := current_crystal()
	return CRYSTAL_ORDER.find(current) + 1 if not current.is_empty() else CRYSTAL_ORDER.size() + 1


## Crystal `crystal`'s health left (0: dead, dark for good).
func crystal_left(crystal: String) -> float:
	return float(_crystal_hp.get(crystal, 0.0))


func is_crystal_dead(crystal: String) -> bool:
	return crystal_left(crystal) <= 0.0


## Where crystal `crystal` is drawn now (global): its piece when bare, else its plate's place, else
## his centre.
func _crystal_point(crystal: String) -> Vector2:
	var at := _look.crystal_point(crystal) if _look != null else Vector2.INF
	return at if at != Vector2.INF else _plate_point(crystal)


# --- his plates ------------------------------------------------------------------------------------

## How many plates he still wears.
func plates_left() -> int:
	var count := 0
	for plate: String in PLATE_NAMES:
		if bool(_plates[plate]):
			count += 1
	return count


## True while he wears `plate` ("L", "C" or "R").
func has_plate(plate: String) -> bool:
	return bool(_plates.get(plate, false))


## The plate a cart takes now: this phase's crystal's, while he wears it ("" once it is gone).
func current_plate() -> String:
	var current := current_crystal()
	return current if has_plate(current) else ""


## The way he faces (down, up, left or right: the art's).
func facing() -> Vector2:
	return _turned


## His look (game/bosses/colossus_look.gd; null without a Visual).
func plate_look() -> Node2D:
	return _look


## True while this phase's plate (`current_plate`, the one a cart takes: only it glows) is brittle:
## a shoulder plate standing within a lit brazier's ring, or anywhere while all the braziers burn (the
## owner, 2026-11-24: "when all 4 braziers are on make the plater brittler also"); the breastplate only
## lying on his back after his fall from the wall (the fall cracked it; on the floor it never glows).
func is_brittle() -> bool:
	var plate := current_plate()
	if is_defeated() or plate.is_empty():
		return false
	if _phase == PHASE_STUNNED:
		return plate == CHEST
	if plate == CHEST or _phase in [PHASE_WAIT, PHASE_LEAP_UP, PHASE_CLING, PHASE_LEAP_DOWN, PHASE_FALL, PHASE_HOP]:
		return false
	return in_fire_ring() or _all_braziers_lit()


## True while every one of the arena's braziers burns.
func _all_braziers_lit() -> bool:
	return not braziers.is_empty() and _braziers_lit() >= braziers.size()


# --- his plates' heat cues -------------------------------------------------------------------------

## As this phase's plate heats (a burst of embers off it, a flash, the sound), while it glows (embers
## rising, the target of the cart line he stands on lit up) and as it cools (a puff of steam).
func _step_heat(now: float) -> void:
	var brittle := is_brittle()
	if brittle and not _was_brittle:
		_heat_up()
	elif not brittle and _was_brittle and not is_defeated():
		_cool_down()
	_was_brittle = brittle
	if brittle and now >= _next_ember_at:
		_next_ember_at = now + HEAT_EMBER_EVERY_MS
		FireFx.embers(_plate_point(current_plate()), 2)
	_glow_target(_line_target() if brittle and _phase != PHASE_STUNNED else null, now)


func _heat_up() -> void:
	_cue(CUE_HEAT)
	var plate := current_plate()
	if not plate.is_empty():
		FireFx.embers(_plate_point(plate), HEAT_EMBERS)
		if _look != null:
			_look.flash_plate(plate)
	FireFx.smoke(get_centre(), 3)


func _cool_down() -> void:
	FireFx.smoke(get_centre(), COOL_STEAM)
	var plate := current_plate()
	if not plate.is_empty():
		FireFx.smoke(_plate_point(plate), 2)


## The knock target of the cart line his feet stand on (within ON_LINE_PX of its rails), its cart
## held ready and the target armed: the nearest such; null when none.
func _line_target() -> Node2D:
	var best: Node2D = null
	var nearest := ON_LINE_PX
	for node: Node in get_tree().get_nodes_in_group(MECHANISMS_GROUP):
		var cart := node as Node2D
		if cart == null or not cart.has_method(&"get_knock_target") or str(cart.call(&"state_name")) != "held":
			continue
		var line: Variant = cart.get(&"points")
		if not line is PackedVector2Array:
			continue
		var points := line as PackedVector2Array
		for k in points.size() - 1:
			var gap := Geometry2D.get_closest_point_to_segment(feet(), cart.global_position + points[k],
				cart.global_position + points[k + 1]).distance_to(feet())
			if gap >= nearest:
				continue
			var target := cart.call(&"get_knock_target") as Node2D
			if target != null and (not target.has_method(&"is_armed") or bool(target.call(&"is_armed"))):
				best = target
				nearest = gap
	return best


## A warm glow pulsing over `target`'s disc (over the darkness); hidden with none.
func _glow_target(target: Node2D, now: float) -> void:
	if target == null:
		if _target_glow != null and is_instance_valid(_target_glow):
			_target_glow.visible = false
		return
	if _target_glow == null or not is_instance_valid(_target_glow):
		_target_glow = _glow_sprite()
		_effects_parent().add_child(_target_glow)
	var pulse := 0.5 + 0.5 * sin(now / TARGET_PULSE_MS * TAU)
	_target_glow.visible = true
	_target_glow.global_position = target.call(&"blast_point") if target.has_method(&"blast_point") else target.global_position
	_target_glow.modulate = Color(TARGET_GLOW, 0.35 + 0.4 * pulse)
	_target_glow.scale = Vector2.ONE * TARGET_GLOW_SCALE * (1.0 + 0.12 * pulse)


## A soft additive glow drawn over a dark room's darkness.
static func _glow_sprite() -> Sprite2D:
	var glow := Sprite2D.new()
	glow.name = "ColossusHeatGlow"
	glow.texture = FireFx.glow_texture()
	glow.material = FireFx.additive()
	glow.z_index = OVER_THE_DARK_Z
	glow.z_as_relative = false
	return glow


## The first clang off a cold plate in a fight: the hint over the slime (following it, readable for
## HINT_MS), and every unlit brazier flashes HINT_FLASHES times under a bobbing arrow (a hint flashes
## the thing it is about: docs/GAME_GUIDELINES.md "Hints"), embers rising off its bowl.
func _hint_cold() -> void:
	_clang_hinted = true
	var feel := Services.feel()
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if feel != null and player != null and not clang_hint_text.is_empty():
		feel.hint_text(player, HINT_LIFT, clang_hint_text, &"orange", HINT_MS)
	for node: Node in braziers:
		var candle := node as Node2D
		if candle == null or not is_instance_valid(candle) or not candle.has_method(&"is_lit") or bool(candle.call(&"is_lit")):
			continue
		var offset: Variant = candle.get(&"flame_offset")
		var flame := candle.global_position + (offset as Vector2 if offset is Vector2 else Vector2(0.0, -56.0))
		var cue := HintCue.new()
		cue.name = "BrazierHint"
		cue.set(&"flashes", HINT_FLASHES)
		cue.set(&"life_ms", HINT_MS)
		_effects_parent().add_child(cue)
		cue.global_position = flame
		FireFx.embers(flame, 5)


## True while his feet stand within a lit brazier's ring: its light (candle.gd `light_radius_px`:
## its `light_radius`, 150 in his arena, else its kind's radius from the data) round its flame. The arena's braziers; without them, every candle a stomp
## puts out.
func in_fire_ring() -> bool:
	var at := feet()
	var list: Array = braziers
	if list.is_empty() and is_inside_tree():
		list = get_tree().get_nodes_in_group(CandleScript.GROUP).filter(func(n: Node) -> bool: return bool(n.get(&"stomp_puts_out")))
	for node: Variant in list:
		if not is_instance_valid(node) or not (node as Node).has_method(&"is_lit") or not bool((node as Node).call(&"is_lit")):
			continue
		var radius := float((node as Node).call(&"light_radius_px")) if (node as Node).has_method(&"light_radius_px") \
			else float((node as Node).get(&"light_radius"))
		if radius <= 0.0:
			radius = FireTargets.lantern_number("candle.lightRadiusPx", 300.0)
		var flame := (node as Node2D).global_position + ((node as Node).get(&"flame_offset") as Vector2)
		if at.distance_to(flame) <= radius:
			return true
	return false


## For the films and tests: he wears only the plates in `on`, and each crystal has the health in
## `crystals` ({"L": 0.0, ...}: 0 dead; one not named whole); his health follows (their sum), and the
## phase's first clink gives its line again.
func stage_crystals(on: Array, crystals: Dictionary = {}) -> void:
	var total := 0.0
	for plate: String in PLATE_NAMES:
		_plates[plate] = plate in on
		_crystal_hp[plate] = clampf(float(crystals.get(plate, crystal_share())), 0.0, crystal_share())
		total += crystal_left(plate)
	_hp = total
	_clink_hinted_phase = 0
	health_changed.emit(_health_payload())


## A dungeon mechanism's blow (game/dungeon/mechanism_strike.gd calls it instead of damage). Only the
## runaway cart does anything, and only to this phase's plate (the owner's fixed order: the first two
## blows take the shoulders, whichever side the cart meets him from; it sparks where it meets him):
## brittle, it bursts; cold, it clangs off it and he staggers. With this phase's plate already gone it
## clangs off his rock and staggers him. The breastplate bursts only on his back (after his fall from
## the wall); standing, it clangs.
func on_mechanism_hit(kind: StringName, source: Node) -> void:
	if is_defeated() or kind != &"cart":
		return
	if _phase in [PHASE_WAIT, PHASE_LEAP_UP, PHASE_CLING, PHASE_LEAP_DOWN, PHASE_FALL, PHASE_HOP]:
		return
	var along := _line_way(source)
	var plate := current_plate()
	if _phase == PHASE_STUNNED:
		if is_brittle():
			_burst(plate, along, source)
		else:
			_impact_spark(along, source)
		# he kicks it back as he gets up
		if not is_defeated():
			_hold_cart(source as Node2D)
		return
	if plate.is_empty():
		_clang("", along, source)
	elif is_brittle():
		_impact_spark(along, source)
		_burst(plate, along, source)
	else:
		_clang(plate, along, source)
	# furious, he will kick it back once he has his feet again
	if not is_defeated() and _phase == PHASE_STAGGER:
		_hold_cart(source as Node2D)


## A spark where the cart meets him (his rock, on its side of him).
func _impact_spark(along: Vector2, cart: Node) -> void:
	var from := -along if along != Vector2.ZERO else (((cart as Node2D).global_position - feet()).normalized() if cart is Node2D else Vector2.DOWN)
	var feel := Services.feel()
	if feel != null:
		feel.burst(SPARK, get_centre() + from * CLINK_OUT_PX, from, CLANG_TINT, 0.8)


## The side of him (as he faces) that `from` (unit, from him toward it) meets: "C" his front, "L" his
## right, "R" his left, "back".
func _side_of(from: Vector2) -> String:
	var best := SIDE_BACK
	var best_dot := (-_turned).dot(from)
	for plate: String in PLATE_NAMES:
		var dot := _plate_normal(plate).dot(from)
		if dot > best_dot:
			best = plate
			best_dot = dot
	return best


## The way plate `plate` faces from him, as he faces now: C his front, L his right, R his left.
func _plate_normal(plate: String) -> Vector2:
	var right := Vector2(-_turned.y, _turned.x)
	if plate == "L":
		return right
	if plate == "R":
		return -right
	return _turned


## A brittle plate shatters for good: the shards, a flash, a roar; its crystal is bare (no harm to his
## health: only the crystal's hits take it) and he staggers (not on his back).
func _burst(plate: String, along: Vector2, by: Node) -> void:
	if plate.is_empty() or not has_plate(plate):
		return
	var at := _plate_point(plate)
	_plates[plate] = false
	ColossusShards.burst(_effects_parent(), at, feet().y, true, along, 101 + plates_left() * 17)
	_cue(CUE_SHATTER)
	_cue(CUE_PLATE_ROAR)
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("burstShakeMs", 420.0), pattern("burstShake", 0.014))
	flash_hit()
	_harm += 1
	plate_burst.emit({"plate": plate, "by": str(by.name) if by != null else "", "hp": get_damage_state()["hp"]})
	if _phase != PHASE_STUNNED:
		_stagger(pattern("burstStaggerMs", 1800.0))


## A cold plate (or his rock: `plate` empty, this phase's plate already gone) clangs under the blow:
## sparks, a white flash on the plate, and he staggers. The first clang off a cold shoulder plate in a
## fight gives the cold hint (the breastplate never heats on the floor: no hint there).
func _clang(plate: String, along: Vector2, by: Node) -> void:
	var at := _plate_point(plate) if not plate.is_empty() else get_centre()
	_cue(CUE_CLANG)
	var feel := Services.feel()
	if feel != null:
		feel.burst(SPARK, at, -along if along != Vector2.ZERO else Vector2.UP, CLANG_TINT, 1.0)
		feel.shake(pattern("clangShakeMs", 200.0), pattern("clangShake", 0.007))
	if _look != null and not plate.is_empty():
		_look.flash_plate(plate)
	plate_clanged.emit({"plate": plate, "by": str(by.name) if by != null else ""})
	_stagger(pattern("staggerMs", 1100.0))
	if not plate.is_empty() and plate != CHEST and not _clang_hinted:
		_hint_cold()


## Rocked on his feet for `ms` (the stomp sheet's last frame, facing the viewer): a stomp on the way is
## cut short (no brazier goes out).
func _stagger(ms: float) -> void:
	_clear_zone()
	_restore_leap()
	_stagger_ms = ms
	_transition(PHASE_STAGGER, Services.now_ms())
	_set_facing(Vector2.DOWN)
	body.velocity = Vector2.ZERO


## The cart that struck him (standing) waits where it stopped until he kicks it back.
func _hold_cart(cart: Node2D) -> void:
	if cart == null or not cart.has_method(&"hold_for_kick"):
		return
	if _kick_cart != null and _kick_cart != cart:
		_let_go_cart()
	_kick_cart = cart
	cart.call(&"hold_for_kick")


## The held cart goes back to its haul back (he is down, up his wall, gone).
func _let_go_cart() -> void:
	if _kick_cart != null and is_instance_valid(_kick_cart) and _kick_cart.has_method(&"let_go"):
		_kick_cart.call(&"let_go")
	_kick_cart = null


## Furious, he turns to the cart and draws his foot back (a roar).
func _start_kick(now: float) -> void:
	_kicked = false
	var toward: Vector2 = (_kick_cart.call(&"cart_point") as Vector2) - feet() if _kick_cart.has_method(&"cart_point") else Vector2.DOWN
	if absf(toward.x) >= absf(toward.y):
		_set_facing(Vector2.RIGHT if toward.x > 0.0 else Vector2.LEFT)
	else:
		_set_facing(Vector2.DOWN if toward.y > 0.0 else Vector2.UP)
	_transition(PHASE_KICK, now)
	_cue(CUE_PLATE_ROAR)


## His foot meets the cart: it rolls back up its line, fast (`kickBackMs`).
func _kick(_now: float) -> void:
	_kicked = true
	var cart := _kick_cart
	_kick_cart = null
	if cart == null or not is_instance_valid(cart):
		return
	var at: Vector2 = cart.call(&"cart_point") if cart.has_method(&"cart_point") else cart.global_position
	if bool(cart.call(&"kick_back", pattern("kickBackMs", 1200.0))):
		_cue(CUE_PLATE_STOMP)
		_puff(DUST, at)
		var feel := Services.feel()
		if feel != null:
			feel.shake(pattern("kickShakeMs", 260.0), pattern("kickShake", 0.01))


## Rocked (and the cart kicked home): to his wall when his second shoulder crystal was destroyed, else
## he walks on.
func _after_rocked(now: float, slime: Vector2) -> void:
	if _leap_due and not climb_spots.is_empty():
		_leap_due = false
		_leap_up(now, slime)
	else:
		_transition(PHASE_WALK, now)
		_stomp_ready_at = now + pattern("afterReelStompMs", 900.0)


## Where plate `plate` is drawn now (global); his centre when the frame hides it.
func _plate_point(plate: String) -> Vector2:
	var at := _look.plate_point(plate) if _look != null else Vector2.INF
	return at if at != Vector2.INF else get_centre()


func _effects_parent() -> Node:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	return parent if parent != null else body.get_parent()


## The way the cart's line runs where the cart is now (unit; ZERO for a node with no line).
static func _line_way(cart: Node) -> Vector2:
	var line: Variant = cart.get(&"points") if cart != null else null
	if not line is PackedVector2Array or (line as PackedVector2Array).size() < 2:
		return Vector2.ZERO
	var points := line as PackedVector2Array
	var at: Vector2 = points[0]
	if cart.has_method(&"cart_point"):
		at = (cart.call(&"cart_point") as Vector2) - (cart as Node2D).global_position
	var best := Vector2.ZERO
	var nearest := INF
	for i in points.size() - 1:
		if points[i] == points[i + 1]:
			continue
		var gap := Geometry2D.get_closest_point_to_segment(at, points[i], points[i + 1]).distance_squared_to(at)
		if gap < nearest:
			nearest = gap
			best = (points[i + 1] - points[i]).normalized()
	return best


## `point` (feet) moved onto the nearest crash cart's line (its nearest point on it); `point` without
## one.
func _on_crash_line(point: Vector2) -> Vector2:
	var best := point
	var nearest := INF
	for cart: Node2D in crash_carts:
		if cart == null or not is_instance_valid(cart):
			continue
		var line: Variant = cart.get(&"points")
		if not line is PackedVector2Array or (line as PackedVector2Array).size() < 2:
			continue
		var points := line as PackedVector2Array
		for i in points.size() - 1:
			var on := Geometry2D.get_closest_point_to_segment(point, cart.global_position + points[i],
				cart.global_position + points[i + 1])
			if on.distance_squared_to(point) < nearest:
				nearest = on.distance_squared_to(point)
				best = on
	return best


## His set-up (`_ready`): the scene's old sheet off (the Visual draws nothing, scaled to the art's
## size), his look under it, his own hurtbox shape, a shadow on the ground.
func _setup_plates() -> void:
	if visual != null:
		visual.texture = null
		visual.hframes = 1
		visual.vframes = 1
		visual.frame = 0
		visual.flip_h = false
		visual.offset = Vector2.ZERO
		visual.scale = Vector2.ONE / ColossusLook.px_per_unit()
		_look = ColossusLook.new()
		_look.name = "PlateLook"
		visual.add_child(_look)
	if damage_area != null:
		for child: Node in damage_area.get_children():
			var holder := child as CollisionShape2D
			if holder != null and holder.shape is RectangleShape2D:
				_hurt_box = (holder.shape as RectangleShape2D).duplicate() as RectangleShape2D
				holder.shape = _hurt_box
				holder.position = Vector2.ZERO
				break
	_stand_hurtbox()
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_STAND


## His hurtbox standing: his footprint and lower body (the cart meets it on its rails, the Spear from
## every side), wide seen from the front or back, narrower from the side.
func _stand_hurtbox() -> void:
	_lying = false
	if _hurt_box == null:
		return
	var side := absf(_turned.x) > 0.5
	_hurt_box.size = Vector2(pattern("plateHurtSide", 110.0) if side else pattern("plateHurtFront", 150.0), pattern("plateHurtHeight", 110.0))
	_area_home = Vector2(0.0, -pattern("plateHurtRise", 45.0))
	if _phase != PHASE_CLING:
		damage_area.position = _area_home
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_STAND


## His hurtbox lying on his back: his whole length round his feet (the middle of him).
func _lie_hurtbox() -> void:
	_lying = true
	if _hurt_box == null:
		return
	_hurt_box.size = Vector2(pattern("lyingHurtW", 180.0), pattern("lyingHurtH", 90.0))
	damage_area.position = Vector2(0.0, -pattern("lyingHurtRise", 10.0))
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_LYING


func _set_facing(way: Vector2) -> void:
	if way == _turned:
		return
	_turned = way
	if not _lying:
		_stand_hurtbox()


## The walk's facing (the art's four ways: down, up, left, right), from the way he moves; a new way
## wins once it leads the other by FACING_LEAD, so a slant does not flicker.
func _walk_facing(delta: float) -> void:
	var velocity := body.velocity
	if velocity.length() <= WALK_SPEED_THRESHOLD:
		return
	_walk_px += velocity.length() * delta
	if absf(velocity.y) > absf(velocity.x) * FACING_LEAD:
		_set_facing(Vector2.DOWN if velocity.y > 0.0 else Vector2.UP)
	elif absf(velocity.x) > absf(velocity.y) * FACING_LEAD:
		_set_facing(Vector2.RIGHT if velocity.x > 0.0 else Vector2.LEFT)


## The look for now: the animation and frame of his phase, his plates' states.
func _show_plates(now: float) -> void:
	if _look == null:
		return
	var key := "walk-down"
	var index := 1
	var mirrored := false
	var rise := 0.0
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_WALK:
			key = "walk-side" if absf(_turned.x) > 0.5 else ("walk-up" if _turned.y < 0.0 else "walk-down")
			mirrored = _turned.x < -0.5
			index = int(_walk_px / WALK_STEP_PX) % 4 if body.velocity.length() > WALK_SPEED_THRESHOLD else 1
		PHASE_RAISE:
			key = "stomp"
			index = 0 if elapsed < pattern("raiseMs", 650.0) * RAISE_REAR else 1
		PHASE_STOMP:
			key = "stomp"
			index = 2
		PHASE_RECOVER:
			if elapsed < pattern("recoverMs", 600.0) * RECOVER_SLAM:
				key = "stomp"
				index = 2
		PHASE_STAGGER:
			key = "stomp"
			index = 3
		PHASE_KICK:
			# a foot drawn back, then driven at the cart: his stride in profile (the stomp's raise and
			# lift seen from the front, the walk away from behind)
			var wind_up := elapsed < pattern("kickMs", 760.0) * KICK_AT
			if absf(_turned.x) > 0.5:
				key = "walk-side"
				mirrored = _turned.x < 0.0
				index = 1 if wind_up else 0
			elif _turned.y < 0.0:
				key = "walk-up"
				index = 1 if wind_up else 0
			else:
				key = "stomp"
				index = 0 if wind_up else 1
		PHASE_LEAP_UP:
			key = "leap-cling"
			index = 0 if elapsed < pattern("leapUpMs", 700.0) * LEAP_CROUCH else 1
		PHASE_CLING:
			key = "leap-cling"
			index = 3 if now < _throw_pose_until else 2 + int(elapsed / CLING_SHIFT_MS) % 2
		PHASE_LEAP_DOWN, PHASE_HOP:
			key = "stomp"
			index = 1
		PHASE_HOP_CROUCH:
			# the leap's crouch, facing the viewer
			key = "leap-cling"
			index = 0
		PHASE_QUAKE_WARN:
			# reared, foot and fists up: the tell, held
			key = "stomp"
			index = 1
		PHASE_QUAKE:
			# pounding: the slam just after each pound, reared between
			key = "stomp"
			index = 2 if now - _quake_last_pound < pattern("quakePoundMs", 450.0) * 0.5 else 1
		PHASE_FALL:
			key = "fall"
			index = 0
		PHASE_STUNNED:
			key = "fall"
			index = 1 if elapsed < CRASH_FRAME_MS else 2 + int((elapsed - CRASH_FRAME_MS) / DAZE_FRAME_MS) % 2
		PHASE_DEAD:
			# he topples back (the fall off the wall's first two frames), then lies
			var down := now - _dead_at
			key = "fall"
			index = 0 if down < DEATH_TOPPLE_MS else (1 if down < DEATH_TOPPLE_MS * 2.5 else 2)
			rise = DEATH_TOPPLE_RISE if index == 0 else 0.0
	var hot := is_brittle()
	var hot_plate := current_plate()
	var states := {}
	var crystals := {}
	for plate: String in PLATE_NAMES:
		states[plate] = ColossusLook.GONE if not has_plate(plate) else (ColossusLook.HOT if hot and plate == hot_plate else ColossusLook.COLD)
		crystals[plate] = ColossusLook.DEAD if is_crystal_dead(plate) else ColossusLook.LIVE
	_look.position = Vector2(0.0, -rise * ColossusLook.px_per_unit())
	_look.show_pose(key, index, mirrored, states, crystals)
