"""Writes scripts/audio/picker/round-3.json, the Sound Picker round 3 manifest (run from temp/sound-round-3)."""
import glob
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LIB = "godot/asset/audio/sfx/library"
SYN = "godot/asset/audio/sfx/synth"


def rel(paths):
    return [Path(p).resolve().relative_to(ROOT).as_posix() for p in paths]


def cut(name):
    return rel(sorted(glob.glob(str(HERE / "cut" / f"{name}-*.src.wav"))))


def raw(name):
    return rel(sorted(glob.glob(str(HERE / "raw" / f"{name}-*.mp3"))))


def existing(pattern):
    return sorted(Path(p).relative_to(ROOT).as_posix() for p in glob.glob(str(ROOT / pattern)))


GROUPS = [
    {"id": "steps", "name": "Steps on each ground", "note": "A step plays each time the slime lands in its walk cycle, about every 0.54 s. Walk plays nine steps in that rhythm with the game's small pitch changes."},
    {"id": "water", "name": "Water and swimming", "note": "Shallow water is walkable; deep water needs the Frog form, which swims. A stroke plays once per swim cycle (about every 1.1 s)."},
    {"id": "slime", "name": "Gulp forms and the lash", "note": "Transforming used to play only the eat sound, and the lash was silent after the throw."},
    {"id": "world", "name": "Puzzles, doors and the training dummy", "note": "These played no sound at all."},
    {"id": "talk", "name": "Dialogue", "note": "A soft blip as each letter appears (at most about twelve a second). Keep silent is a real option."},
    {"id": "wired", "name": "Made earlier, now played", "note": "These sounds were picked in rounds 1 and 2 but nothing in the game played them. They play now; choose Neither for any that should change."},
]

STEP_NOTES = {
    "a": "Real steps on the ground, cut from a generated walk",
    "b": "A slime hopping on the ground, cut from a generated hop",
    "r2": "The round-2 take you kept (never heard in game until now)",
}

GROUNDS = [
    # (cue, name, where, round-2 files or None)
    ("grass", "Grass", "Meadows and Slimeshire (grass-a, grass-b)", "footstep/grass-*.wav"),
    ("forest", "Forest floor", "Gloop Forest earth and moss (forest-floor, forest-moss)", "footstep/forest-*.wav"),
    ("leaves", "Autumn leaves", "Emberleef's amber ground (amberleaf-ground)", None),
    ("sand", "Sand", "Desert sand (sanddessert-ground)", "footstep/sand-*.wav"),
    ("snow", "Snow", "Frozen ground (frozen-ground)", "footstep/snow-*.wav"),
    ("stone", "Stone tiles", "Town cobble and tiles (town-cobble)", "footstep/stone-*.wav"),
    ("cave", "Cave floor", "Caverns (cavern-floor, rock-wall)", None),
    ("crystal", "Crystal floor", "Crystal Caverns (crystal-floor)", None),
    ("wood", "Wooden floor", "House interiors (wood-floor)", None),
    ("soft", "Earth floor", "Mushroom houses (mushroom earth, clover and plain floors)", None),
]
FOOTSTEP_NODE = {"grass": "Grass", "forest": "Forest", "leaves": "Leaves", "sand": "Sand", "snow": "Snow", "stone": "Stone",
                 "cave": "Cave", "crystal": "Crystal", "wood": "Wood", "soft": "Soft"}
SLICE_NAME = {"stone": "tiles"}

cues = []
for cue, name, where, r2 in GROUNDS:
    base = SLICE_NAME.get(cue, cue)
    options = [
        {"key": "a", "label": "Footsteps", "note": STEP_NOTES["a"], "kind": "step", "takes": cut(f"{base}-walk")},
        {"key": "b", "label": "Slime hops", "note": STEP_NOTES["b"], "kind": "step", "takes": cut(f"{base}-slime")},
    ]
    if r2:
        options.append({"key": "r2", "label": "Round 2 take", "note": STEP_NOTES["r2"], "kind": "step", "existing": True, "takes": existing(f"{LIB}/{r2}")})
    cues.append({"id": f"footstep.{cue}", "group": "steps", "name": name, "where": where, "rhythm": 540,
                 "node": f"Footsteps/{FOOTSTEP_NODE[cue]}", "ship": f"footstep/{cue}", "inGame": "r2" if r2 else "a", "options": options})


def oneshot(cue_id, group, name, where, node, ship, a, b, max_s=None, extra=None, in_game="a"):
    options = [
        {"key": "a", "label": a[0], "note": a[1], "kind": "oneshot", "takes": a[2]},
        {"key": "b", "label": b[0], "note": b[1], "kind": "oneshot", "takes": b[2]},
    ]
    for option in options:
        if max_s:
            option["max"] = max_s
    if extra:
        options.append(extra)
    return {"id": cue_id, "group": group, "name": name, "where": where, "node": node, "ship": ship, "inGame": in_game, "options": options}


cues.append({"id": "footstep.water", "group": "water", "name": "Wading", "where": "Each step in shallow water (water)", "rhythm": 540,
             "node": "Footsteps/Shallow", "ship": "footstep/water", "inGame": "r2", "options": [
                 {"key": "a", "label": "Wading steps", "note": "Light splash and slosh, cut from a generated wade", "kind": "step", "takes": cut("shallow-walk")},
                 {"key": "b", "label": "Slime splashes", "note": "A slime hopping through shallow water", "kind": "step", "takes": cut("shallow-slime")},
                 {"key": "r2", "label": "Round 1 take", "note": "The splash picked in round 1 (never played until now)", "kind": "step", "existing": True, "takes": existing(f"{LIB}/footstep/water-*.ogg")},
             ]})
cues.append(oneshot("player.water-enter", "water", "Into the shallows", "Walking from land into shallow water", "Footsteps/WaterEnter", "player/water-enter",
                    ("Light splash", "A small creature stepping into a pond", raw("water-enter-a")),
                    ("Slime plop", "A bubbly cartoon splash-plop", raw("water-enter-b")), max_s=0.9))
cues.append(oneshot("player.water-exit", "water", "Out of the water", "Climbing out of water onto land", "Footsteps/WaterExit", "player/water-exit",
                    ("Slosh and drips", "One slosh and a few drips", raw("water-exit-a")),
                    ("Slime drips", "A wet squelch and cute drips", raw("water-exit-b")), max_s=1.0))
cues.append(oneshot("player.swim-enter", "water", "Starting to swim", "The Frog form slipping into deep water", "Footsteps/SwimEnter", "player/swim-enter",
                    ("Gentle plunge", "A plunge with a swirl of bubbles", raw("swim-enter-a")),
                    ("Slime bloop", "A round cartoon bloop and rising bubbles", raw("swim-enter-b")), max_s=1.2))
cues.append({"id": "player.swim-stroke", "group": "water", "name": "Swimming strokes", "where": "Each swim cycle in deep water", "rhythm": 1084, "rhythmLabel": "▶ Swim",
             "node": "Footsteps/Swim", "ship": "player/swim-stroke", "inGame": "a", "options": [
                 {"key": "a", "label": "Paddle strokes", "note": "Soft swirling splashes, cut from a generated swim", "kind": "step", "max": 0.7, "takes": cut("swim-strokes")},
                 {"key": "b", "label": "Gloopy strokes", "note": "Bubbly slime paddling", "kind": "step", "max": 0.7, "takes": cut("swim-slime")},
             ]})

cues.append(oneshot("player.gulp-transform", "slime", "Transforming", "Gulping at a spot or from the wheel turns the slime into a form (the eat sound still plays too)", "GulpTransform", "player/gulp-transform",
                    ("Gooey shimmer", "A wet squelch with a rising sparkle", raw("gulp-transform-a")),
                    ("Bubbly pop", "A gloopy wobble that pops with a chime", raw("gulp-transform-b")), max_s=1.4))
cues.append(oneshot("player.gulp-wear-off", "slime", "Form wears off", "The form's time runs out (\"The form wore off\")", "GulpWearOff", "player/gulp-wear-off",
                    ("Deflating sparkle", "A soft deflate, a small pop and falling sparkle", raw("gulp-wear-off-a")),
                    ("Rubbery shrink", "A wobbly deflate and a tiny pop", raw("gulp-wear-off-b")), max_s=1.4))
cues.append(oneshot("player.burp", "slime", "Burp", "Pressing Q away from a spot ends the form with \"Burp!\"", "GulpBurp", "player/burp",
                    ("Cute burp", "A short funny creature burp", raw("gulp-burp-a")),
                    ("Bubbly burp", "A wet gurgle with a little pop", raw("gulp-burp-b")), max_s=0.8))
cues.append(oneshot("player.lash-catch", "slime", "Lash catches", "The tendril hooks a post, wall or pickup", "LashCatch", "player/lash-catch",
                    ("Sticky slap", "A wet thwap that sticks", raw("lash-catch-a")),
                    ("Elastic twang", "A rubbery twang and thwack", raw("lash-catch-b")), max_s=0.6))
cues.append(oneshot("player.lash-miss", "slime", "Lash misses", "The tendril catches nothing and snaps back", "LashMiss", "player/lash-miss",
                    ("Wet slurp back", "A stretch and a quick slurp", raw("lash-miss-a")),
                    ("Sproing", "A cartoon rubber-band zip", raw("lash-miss-b")), max_s=0.7))
cues.append(oneshot("player.fall", "slime", "Dropping into a hole", "Climbing down the hole a Heavy slime cracked open", "FallDown", "player/fall",
                    ("Whistle and plop", "A falling whistle and a distant gloopy thump", raw("fall-hole-a")),
                    ("Slide down", "A sliding scrape with pebbles and a soft landing", raw("fall-hole-b")), max_s=1.8))

cues.append(oneshot("world.plate-press", "world", "Pressure plate down", "A Heavy slime presses a plate", "PlatePress", "world/plate-press",
                    ("Stone clunk", "A deep clunk with a click", raw("plate-press-a")),
                    ("Puzzle click", "A soft thunk and a bright click", raw("plate-press-b")), max_s=0.8))
cues.append(oneshot("world.plate-release", "world", "Pressure plate up", "The plate rises when the weight leaves", "PlateRelease", "world/plate-release",
                    ("Stone clack", "A lighter clack and click", raw("plate-release-a")),
                    ("Soft tock", "A short tock and reverse click", raw("plate-release-b")), max_s=0.6))
cues.append(oneshot("world.gate-open", "world", "Gate opens", "A gate opens from a plate, a bell or a key", "GateOpen", "world/gate-open",
                    ("Stone gate", "A rumbling stone grind ending in a thud", raw("gate-open-a")),
                    ("Wooden gate", "A creak, a latch and a soft knock", raw("gate-open-b")), max_s=2.2))
cues.append(oneshot("world.door", "world", "Using a door", "Entering or leaving a house, hut or ladder", "DoorUse", "world/door",
                    ("Cottage door", "A latch click and a warm creak", raw("door-open-a")),
                    ("Wooden hatch", "A latch clack and a soft thump", raw("door-open-b")), max_s=1.4))
cues.append(oneshot("world.dummy-hit", "world", "Training dummy hit", "Any weapon hitting the training dummy", "DummyHit", "world/dummy-hit",
                    ("Straw thump", "A dry thump with a straw rustle", raw("dummy-hit-a")),
                    ("Sack thud", "A soft solid thud with a wooden knock", raw("dummy-hit-b")), max_s=0.7))
cues.append(oneshot("world.ground-creak", "world", "Cracked ground creaks", "A Heavy slime standing on cracked ground (\"creak...\")", "GroundCreak", "world/ground-creak",
                    ("Low creak", "A creaking crackle with crumbling pebbles", raw("ground-creak-a")),
                    ("Sharp cracks", "Dry cracks spreading with a dusty crumble", raw("ground-creak-b")), max_s=1.4))

cues.append({"id": "ui.talk-blip", "group": "talk", "name": "Text typing", "where": "Letters appearing in the dialogue box", "rhythm": 85, "rhythmLabel": "▶ Type",
             "node": "TalkBlip", "ship": "ui/talk-blip", "inGame": "a", "options": [
                 {"key": "a", "label": "Soft pop", "note": "A gentle rounded blip", "kind": "oneshot", "max": 0.12, "takes": raw("talk-blip-a")},
                 {"key": "b", "label": "Wooden tick", "note": "A tiny wooden bead tap", "kind": "step", "takes": cut("talk-blip-b")},
                 {"key": "s", "label": "Keep silent", "note": "No typing sound", "takes": []},
             ]})


def wired(cue_id, name, where, node, pattern):
    return {"id": cue_id, "group": "wired", "name": name, "where": where, "node": node, "inGame": "e", "options": [
        {"key": "e", "label": "Current take", "note": "Picked in an earlier round", "kind": "oneshot", "existing": True, "takes": existing(pattern)}]}


cues += [
    wired("world.gate-unlock", "Key unlocks a gate", "Using the right key on a locked gate (the gate-open sound follows)", "GateUnlock", f"{LIB}/world/gate-unlock.ogg"),
    wired("world.gate-locked", "Gate is locked", "Trying a locked gate without its key", "GateLocked", f"{LIB}/world/gate-locked.ogg"),
    wired("player.coin", "Coins", "Gaining coins: enemy loot, purple berries, quest rewards", "Coin", f"{LIB}/player/coin-*.ogg"),
    wired("resource.drop-pop", "Loot pops out", "Each pile flying out of a tree, rock or enemy", "DropPop", f"{SYN}/resource/drop-pop-*.wav"),
    wired("resource.drop-land", "Loot lands", "Each pile landing on the ground", "DropLand", f"{SYN}/resource/drop-land-*.wav"),
    wired("player.potion-drink", "Drinking a potion", "Using a health or energy potion (the heal sound follows)", "PotionDrink", f"{SYN}/player/potion-drink.wav"),
    wired("player.web-struggle", "Stuck in a web", "Pushing to move while a spider web holds the slime", "WebStruggle", f"{LIB}/player/web-struggle.ogg"),
    wired("player.sleep-breath", "Sleeping", "Snoring in bed until woken (loops)", "SleepBreath", f"{LIB}/player/sleep-breath.wav"),
    wired("player.rested", "Fully rested", "Health is full while sleeping", "Rested", f"{SYN}/player/rested.wav"),
    wired("weapon.hit-dull", "Dull hit", "Hits with the goo gauntlet, axes and pickaxes (they had no impact sound)", "HitDull", f"{SYN}/weapon/hit-dull-*.wav"),
    wired("weapon.hit-blocked", "Blocked hit", "A hit that does nothing (Fatty in the air, an immune target)", "HitBlocked", f"{LIB}/weapon/hit-blocked-*.ogg"),
    wired("world.save", "Game saved", "Saving to a slot", "Save", f"{LIB}/world/save.ogg"),
    wired("ui.toast", "New quest available", "The \"New quest available\" notice", "Toast", f"{LIB}/ui/toast.ogg"),
    wired("ui.shell-menu", "Pause and settings menus", "Opening and closing the pause, settings, save, credits and game-over menus (the menu sounds the game windows already use)", "MenuOpen", f"{SYN}/ui/open.wav"),
]

manifest = {"round": "round-3", "takes": "temp/sound-round-3/takes", "groups": GROUPS, "cues": cues}
out = ROOT / "scripts" / "audio" / "picker" / "round-3.json"
out.write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
missing = [(c["id"], o["key"]) for c in cues for o in c["options"] if o["key"] != "s" and not o["takes"]]
print(f"{len(cues)} cues, {sum(len(o['takes']) for c in cues for o in c['options'])} takes; missing: {missing}")
