"""Writes scripts/audio/picker/round-14.json, Sound Picker round 14 (2026-11-22): the Carnivore Plant's
own sounds.

    python scripts/audio/picker/round-14-make.py

The owner, 2026-11-22, on the Carnivore Plant (docs/godot/BESTIARY.md "38. Carnivore Plant"): "use the
sound play to give me some sound for here". She borrowed the Cocoon Mimic's, the Gulp's and the
slime's cues until now. Every option is a Magnific (ElevenLabs) sound effect prompt of four takes
(temp/sound-round-14/raw/<cue short>-<option>-<n>.mp3; ids.json maps them to the creations, urls.json
to their downloads), trimmed to its loudest event by prep-takes.py; "now" is what the game played
before.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RAW = "temp/sound-round-14/raw"
LIB = "godot/asset/audio/sfx/library"

GROUPS = [
    {"id": "plant", "name": "The Carnivore Plant",
     "note": "Every sound the plant makes, from her tell to her burp. Until now she borrowed the Cocoon Mimic's, the Gulp's and the slime's sounds."},
]


def lib(*names: str) -> list[str]:
    return [f"{LIB}/{name}" for name in names]


INHALE = lib("player/goo-inhale-1.wav", "player/goo-inhale-2.wav", "player/goo-inhale-3.wav")
PLOP = lib("player/goo-plop-1.wav", "player/goo-plop-2.wav", "player/goo-plop-3.wav")
PTOO = lib("player/goo-ptoo-1.wav", "player/goo-ptoo-2.wav", "player/goo-ptoo-3.wav")

## (cue id, name, where, node, ship, max seconds, now label, now takes, [(label, note), x3])
CUES = [
    ("enemy.plant-open", "Plant: jaws open (the tell)", "Something comes near her pot: she rears up and opens her jaws wide, 0.35 s before she snaps",
     "PlantOpen", "enemy/plant-open", 0.6, "Now: the Cocoon Mimic's wrap (a goo inhale)", INHALE,
     [("Hungry hiss", "A wet hiss as her slimy jaws peel open"),
      ("Stem and jaws creak", "Her woody stem creaks and her sticky jaws creak wide open"),
      ("Greedy growl", "A short greedy gurgling growl from a leafy throat")]),
    ("enemy.plant-snap", "Plant: snap", "Her jaws snap shut on the slime, an enemy, or nothing",
     "PlantSnap", "enemy/plant-snap", 0.5, "Now: the Cocoon Mimic's grab (a goo plop)", PLOP,
     [("Wet chomp", "One big wet crunchy chomp"),
      ("Flytrap snap", "A sharp leafy snap and thorn teeth clacking together"),
      ("Clack and squelch", "A hard woody clack, then a short squelch")]),
    ("enemy.plant-munch", "Plant: munch", "Each chew: the slime in her mouth (one chew, 30 damage), or an enemy she eats (two munches)",
     "PlantMunch", "enemy/plant-munch", 0.4, "Now: the Cocoon Mimic's grab (a goo plop)", PLOP,
     [("Crunchy munch", "One crunchy munch"),
      ("Squishy chew", "One squishy wet chew"),
      ("Leafy gnash", "One quick gnash with a leafy rustle")]),
    ("enemy.plant-swallow", "Plant: swallow", "She swallows an enemy she ate (her head tipped back, a bulge down her stem)",
     "PlantSwallow", "enemy/plant-swallow", 0.7, "Now: the Gulp's throat (a goo inhale)", INHALE,
     [("Big gulp", "One big deep wet gulp"),
      ("Lump down the stem", "A gloopy sliding gulp going down"),
      ("Throaty gulp and creak", "A throaty gulp and a woody creak of her stem")]),
    ("enemy.plant-burp", "Plant: burp", "After the swallow, before she falls asleep digesting (\"Burp!\")",
     "PlantBurp", "enemy/plant-burp", 0.8, "Now: the slime's burp (GulpBurp)", lib("player/burp-1.wav", "player/burp-2.wav", "player/burp-3.wav"),
     [("Deep burp", "One deep satisfied burp"),
      ("Bubbly leafy burp", "A bubbly wet burp with a rustle of leaves"),
      ("Smug burp and chuckle", "A short smug burp and a little wicked chuckle")]),
    ("enemy.plant-spit", "Plant: spit the slime out", "She spits the slime far away after chewing it",
     "PlantSpit", "enemy/plant-spit", 0.6, "Now: the Cocoon Mimic's spit (a goo ptoo)", PTOO,
     [("Big wet ptooey", "One big wet spit"),
      ("Goo blast", "A gooey splattering spit burst"),
      ("Cough and spit", "A hacking leafy cough and a wet spit")]),
    ("enemy.plant-doze", "Plant: dozes off", "A thrown thing hits her: she falls asleep for 5 s",
     "PlantDoze", "enemy/plant-doze", 1.0, "Now: the sleep breath (SleepBreath)", lib("player/sleep-breath.wav"),
     [("Woozy yawn", "A woozy sigh and a long sleepy yawn"),
      ("Droop and snore", "Leaves rustling down and a soft deep snore"),
      ("Dizzy wheeze", "A dizzy wobbly wheeze sliding down into a sleepy hum")]),
    ("enemy.plant-burn", "Plant: burnt", "The Lantern's flame burns her (only fire kills her)",
     "PlantBurn", "enemy/plant-burn", 1.8, "Now: a goo ptoo (FireIgnite) and a soft splat", PTOO + lib("world/break-soft-1.wav"),
     [("Flame and shriek", "A whoosh of flame, crackling leaves and a shrill shriek fading out"),
      ("Sizzle and wilting groan", "A fierce sizzle and crackle and a long wilting groan"),
      ("Burst and crumble", "A fire burst, dry crackles and brittle leaves crumbling to ash")]),
]


def short(cue_id: str) -> str:
    """The raw files' prefix: `open` for enemy.plant-open."""
    return cue_id.split(".", 1)[1].removeprefix("plant-")


def main() -> None:
    cues = []
    for cue_id, name, where, node, ship, max_s, now_label, now_takes, options in CUES:
        prefix = short(cue_id)
        built = []
        for key, (label, note) in zip("abc", options):
            built.append({"key": key, "label": label, "note": note, "kind": "oneshot", "max": max_s, "even": True,
                          "takes": [f"{RAW}/{prefix}-{key}-{n}.mp3" for n in range(1, 5)]})
        built.append({"key": "now", "label": now_label, "note": "What the game played before this round", "kind": "oneshot",
                      "takes": now_takes})
        cues.append({"id": cue_id, "group": "plant", "name": name, "where": where, "node": node, "ship": ship,
                     "inGame": "a", "rhythm": 1200, "rhythmLabel": "▶ Repeat", "options": built})
    manifest = {
        "round": "round-14",
        "title": "Sound picker, round 14: the Carnivore Plant",
        "intro": ("The Carnivore Plant's own sounds (2026-11-22, after your note: \"use the sound play to give me some sound "
                  "for here\"). Each moment has three new ideas with four takes each (the game picks one at random each time; "
                  "drop the takes you do not like), and \"Now\", what it played before. The game plays option A of each "
                  "meanwhile. Pick one per sound, or choose Neither and say how it should sound."),
        "takes": "temp/sound-round-14/takes",
        "groups": GROUPS,
        "cues": cues,
    }
    out = ROOT / "scripts/audio/picker/round-14.json"
    out.write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote", out, len(cues), "cues")


main()
