"""Writes scripts/audio/picker/round-13.json, Sound Picker round 13 (2026-11-21): the Dung Roller's own
sounds, and a sound of its own for every moment that played the slime's SlamWindup bubble.

    python scripts/audio/picker/round-13-make.py

The owner, 2026-11-21: "we need to work on the sound effects of the beetle i dont like it", then, on
SlamWindup (a slime bubble shared by the Slam, the Goo Bomb, the Hammer, the ore lift and ten
enemies' wind-ups): "why is use that much i don't like at all, lets pick sound for all those".
Every option is a Magnific (ElevenLabs) sound effect prompt of four takes
(temp/sound-round-13/raw/<cue short>-<option>-<n>.mp3, ids.json and ids2.json map them to the
creations), trimmed to its loudest event by prep-takes.py; "now" is what the game played before.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RAW = "temp/sound-round-13/raw"
LIB = "godot/asset/audio/sfx/library"
SYNTH = "godot/asset/audio/sfx/synth"
WINDUP = [f"{LIB}/player/slam-windup.ogg"]

GROUPS = [
    {"id": "beetle", "name": "The Dung Roller",
     "note": "Every sound the beetle makes. Until now it borrowed the slime's: the bubble wind-up (its brace and its fury), the Roll's whoosh and bonk, a synth pop, a generic hit and a soft splat."},
    {"id": "windups", "name": "Enemy wind-ups (they all played the bubble)",
     "note": "Each enemy's tell before it attacks. All of them played the slime's SlamWindup bubble; each gets its own now. \"Now\" is that bubble, for comparison."},
    {"id": "slime", "name": "The slime and the mine (they played the bubble too)",
     "note": "The Slam's rise, the Goo Bomb forming, the Hammer's swing and the Crystal Mine's ore lift also played SlamWindup."},
]

## (cue id, group, name, where, node, ship, max seconds, now label, now takes, [(label, note), x3])
CUES = [
    ("enemy.dung-brace", "beetle", "Beetle: brace", "At each end of its track it walks round its ball and braces against it (every few seconds while it patrols); also the lean-back before each furious dash",
     "DungBrace", "enemy/dung-brace", 0.5, "Now: the slime's bubble (SlamWindup)", WINDUP,
     [("Chitin clicks", "Spiky legs gripping the floor: quick dry clicks and a tiny shell creak"),
      ("Shell creak and grunt", "Its shell creaking as it leans into the ball, a soft insect grunt"),
      ("Feet scrape", "Six spiky feet digging into the dirt for grip: one short gritty scrape")]),
    ("enemy.dung-push", "beetle", "Beetle: push off", "It pushes off and the ball starts rolling",
     "DungPush", "enemy/dung-push", 0.6, "Now: the slime's Roll whoosh", [f"{LIB}/player/roll-launch-{n}.wav" for n in (1, 2, 3)],
     [("Heavy roll-off", "A heavy mud ball starting to roll on stone: a low thud and a short grind"),
      ("Mud shove", "A short thick squelch and a low push into the ball"),
      ("Gritty rumble", "A big dirt ball lurching forward: a short crunching rumble")]),
    ("enemy.dung-bump", "beetle", "Beetle: ball bumps a wall", "Its ball runs into a wall, a fence or a rock and it turns back; also a furious dash that hits a wall",
     "DungBump", "enemy/dung-bump", 0.6, "Now: the slime's Roll bonk", [f"{LIB}/player/roll-bonk-{n}.wav" for n in (1, 2, 3)],
     [("Mud thud", "One dull earthy thud on stone, a few crumbs falling"),
      ("Wet splat-thud", "One soft thick splat-thud"),
      ("Dry clod knock", "A hard dry clod knocking stone, a puff of dust")]),
    ("enemy.dung-fury", "beetle", "Beetle: furious", "The Gulp stole its ball: it stamps, red and steaming, before it charges",
     "DungFury", "enemy/dung-fury", 0.8, "Now: the slime's bubble (SlamWindup)", WINDUP,
     [("Angry hiss", "A sharp short insect hiss with clicking mandibles"),
      ("Angry chitter", "Rapid furious chittering and a short buzz of its wing cases"),
      ("Stamping feet", "Quick little stomps on the dirt and an angry click")]),
    ("enemy.dung-charge", "beetle", "Beetle: dash", "Each furious dash at the slime (every second or so while it rages)",
     "DungCharge", "enemy/dung-charge", 0.6, "Now: the slime's Roll whoosh", [f"{LIB}/player/roll-launch-{n}.wav" for n in (1, 2, 3)],
     [("Leg skitter", "A rapid skitter of six legs on stone"),
      ("Wing-case whirr", "A short whirring buzz of its wing cases flaring as it lunges"),
      ("Claw scrape lunge", "A quick scrape of claws on dirt and a short whoosh")]),
    ("enemy.dung-ball", "beetle", "Beetle: ball back", "It takes its ball back, or finishes kneading a new one",
     "DungBall", "enemy/dung-ball", 0.45, "Now: a synth pop (DropPop)", [f"{SYNTH}/resource/drop-pop-{n}.wav" for n in (1, 2)],
     [("Mud pats", "Two quick soft pats on a ball of wet mud"),
      ("Mud squish", "A soft satisfying squish of mud pressed into shape"),
      ("Soft thump", "A dirt ball set down: one soft dull thump")]),
    ("enemy.dung-hurt", "beetle", "Beetle: hurt", "A hit lands on the beetle (from behind, or any hit once it has lost its ball)",
     "DungHurt", "enemy/dung-hurt", 0.45, "Now: the generic dull hit", [f"{SYNTH}/weapon/hit-dull-{n}.wav" for n in (1, 2)],
     [("Shell clack", "One hollow clack on its hard shell"),
      ("Knock and squeak", "A crunchy shell knock and a tiny insect squeak"),
      ("Nut thunk", "A dull thunk, like knocking on a hard nut")]),
    ("enemy.dung-death", "beetle", "Beetle: beaten", "It is beaten and flops onto its back",
     "DungDeath", "enemy/dung-death", 1.0, "Now: the soft splat", [f"{LIB}/world/break-soft-1.wav"],
     [("Crack and flop", "Its shell cracks and it flops onto its back, legs scrabbling"),
      ("Squeal and topple", "A small falling squeal and a soft thud as it tips over"),
      ("Crunchy pop", "A crunchy shell pop and a soft puff of dust")]),

    ("enemy.boar-scrape", "windups", "Bramble Boar: scrape", "It lowers its head and scrapes the ground before its charge",
     "BoarScrape", "enemy/boar-scrape", 0.8, "Now: the bubble", WINDUP,
     [("Scrape and snort", "Two gritty hoof scrapes and a short angry snort"),
      ("Hoof scrape", "One long gritty scrape kicking up dirt"),
      ("Snort and grunt", "A short angry snort and grunt")]),
    ("enemy.warden-windup", "windups", "Brood Warden: blades back", "The armoured spider pulls its scythe blades back before a sweep",
     "WardenWindup", "enemy/warden-windup", 0.7, "Now: the bubble", WINDUP,
     [("Blade scrape and hiss", "A sharp scrape of hard blades and a hiss"),
      ("Steely shing", "Two chitin blades sliding against each other"),
      ("Leg clicks and chitter", "Armoured legs clicking and a low menacing chitter")]),
    ("enemy.stomper-crouch", "windups", "Clod Stomper: crouch", "The mud golem crouches before it stomps",
     "StomperCrouch", "enemy/stomper-crouch", 0.7, "Now: the bubble", WINDUP,
     [("Mud squelch and pebbles", "A thick muddy squelch and pebbles rattling"),
      ("Earthy groan", "A low earthy grunt with a squish"),
      ("Clay creak", "Wet clay creaking and stretching")]),
    ("enemy.colossus-raise", "windups", "Crystal Colossus: raise", "The crystal golem lifts a fist before he stomps or slams",
     "ColossusRaise", "enemy/colossus-raise", 0.9, "Now: the bubble", WINDUP,
     [("Crystal grind", "Deep crystalline grinding and creaking"),
      ("Ice crack and rumble", "Ice crystals scraping and cracking over a low rumble"),
      ("Glassy growl", "A deep growl with glassy crackles")]),
    ("enemy.prism-charge", "windups", "Prism Eye and Watcher Eye: charge", "The crystal eye gathers its beam before it fires",
     "PrismCharge", "enemy/prism-charge", 0.9, "Now: the bubble", WINDUP,
     [("Rising glassy hum", "A short rising glassy hum that swells"),
      ("Ringing shimmer", "A crystal humming and ringing, a rising shimmer"),
      ("Power-up whine", "A quick rising whine with sparkling tinkles")]),
    ("enemy.chucker-windup", "windups", "Rock Chucker: heave", "The worm on the cliff heaves a boulder over its head before it throws",
     "ChuckerWindup", "enemy/chucker-windup", 0.8, "Now: the bubble", WINDUP,
     [("Grunt and stone grind", "A strained grunt and stone grinding"),
      ("Rock lift scrape", "A gritty stone scrape and a heave"),
      ("Effortful growl", "A short effortful growl")]),
    ("enemy.shardback-rear", "windups", "Shardback: rear up", "The crystal tortoise rears up before its slam",
     "ShardbackRear", "enemy/shardback-rear", 0.9, "Now: the bubble", WINDUP,
     [("Shell creak and clinks", "A heavy shell creak and crystal shards clinking"),
      ("Deep shell grind", "A huge shell lifting with a deep grinding creak"),
      ("Tired old grunt", "An old tortoise's deep grunt as it heaves itself up")]),
    ("enemy.squint-rear", "windups", "Squint and Big Squint: rear", "The armoured burrow beast rears up before it leaps",
     "SquintRear", "enemy/squint-rear", 0.8, "Now: the bubble", WINDUP,
     [("Plates grind and growl", "Clay armour plates grinding and a low growl"),
      ("Visor clatter", "Clay plates clacking open, a short stony clatter"),
      ("Growl and scuff", "A low rumbling growl and a scuff of dirt")]),
    ("enemy.thornball-curl", "windups", "Thornball: curl up", "The hedgehog curls into its spiked ball before it rolls (and when it cowers from a Goo Bomb)",
     "ThornballCurl", "enemy/thornball-curl", 0.6, "Now: the bubble", WINDUP,
     [("Quill rustle and huff", "A quick prickly rustle of quills and a little huff"),
      ("Quills bristle", "Stiff quills bristling all at once: a short rattling rustle"),
      ("Grumpy huff", "A short angry huff and snuffle")]),

    ("player.slam-rise", "slime", "Slam: rise", "The slime springs up for a Slam (the Stone form's and the shapes')",
     "SlamRise", "player/slam-rise", 0.6, "Now: the bubble", WINDUP,
     [("Rubbery boing", "A short stretchy rubbery boing rising in pitch"),
      ("Wobbly stretch", "A quick wobbly stretch and a rising whoosh"),
      ("Spring wind-up", "A short rising coil boing")]),
    ("player.goo-bomb-cast", "slime", "Goo Bomb: forming", "The slime forms a Goo Bomb inside it (the charge before the spit)",
     "GooBombCast", "player/goo-bomb-cast", 0.8, "Now: the bubble", WINDUP,
     [("Fuse in goo", "A short sizzle and a soft gooey squish"),
      ("Goo kneading", "A short wet squelchy churn, no bubbles"),
      ("Bomb armed", "A quick tick-tick and a soft spark crackle")]),
    ("player.hammer-swing", "slime", "Hammer: swing", "The Hammer shape swings (the melee mode, and the Hammer's power)",
     "HammerSwing", "player/hammer-swing", 0.6, "Now: the bubble", WINDUP,
     [("Deep whoosh", "One deep whoosh of a heavy wooden hammer"),
      ("Mallet swoosh", "A short low swoosh with a creak of the handle"),
      ("Wind-up whoosh", "A rising whoosh that ends sharply")]),
    ("world.ore-lift-ride", "slime", "Ore lift: ride", "The Crystal Mine's ore lift takes the slime up or down",
     "OreLiftRide", "world/ore-lift-ride", 1.8, "Now: the bubble", WINDUP,
     [("Pulley and chains", "A rope pulley creaks, chains rattle, the cage clunks into motion"),
      ("Rails rumble", "A rumble of iron wheels on rails and wooden creaks"),
      ("Winch ratchet", "A ratchet clicking and a rope groaning under load")]),
]


def short(cue_id: str) -> str:
    """The raw files' prefix: `brace` for enemy.dung-brace, `boar` for enemy.boar-scrape."""
    name = cue_id.split(".", 1)[1]
    return name.split("-")[1] if name.startswith("dung-") else name.split("-")[0].replace("goo", "bomb").replace("ore", "lift")


def main() -> None:
    cues = []
    for cue_id, group, name, where, node, ship, max_s, now_label, now_takes, options in CUES:
        prefix = short(cue_id)
        built = []
        for key, (label, note) in zip("abc", options):
            built.append({"key": key, "label": label, "note": note, "kind": "oneshot", "max": max_s, "even": True,
                          "takes": [f"{RAW}/{prefix}-{key}-{n}.mp3" for n in range(1, 5)]})
        built.append({"key": "now", "label": now_label, "note": "What the game played before this round", "kind": "oneshot",
                      "takes": now_takes})
        cues.append({"id": cue_id, "group": group, "name": name, "where": where, "node": node, "ship": ship,
                     "inGame": "a", "rhythm": 1200, "rhythmLabel": "▶ Repeat", "options": built})
    manifest = {
        "round": "round-13",
        "title": "Sound picker, round 13: the beetle and the bubble",
        "intro": ("The Dung Roller's own sounds, and a sound of its own for every moment that played the slime's SlamWindup "
                  "bubble (2026-11-21, after your notes: \"we need to work on the sound effects of the beetle\" and \"SlamWindup "
                  "why is use that much ... lets pick sound for all those\"). Each moment has three new ideas with four takes "
                  "each (the game picks one at random each time; drop the takes you do not like), and \"Now\", what it played "
                  "before. The game plays option A of each meanwhile. Pick one per sound, or choose Neither and say how it "
                  "should sound."),
        "takes": "temp/sound-round-13/takes",
        "groups": GROUPS,
        "cues": cues,
    }
    out = ROOT / "scripts/audio/picker/round-13.json"
    out.write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote", out, len(cues), "cues")


main()
