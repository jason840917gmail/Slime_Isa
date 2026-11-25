"""Writes the manifest of Sound Picker round 16: the reworked bosses' own sounds (the Orb-Weaver
Matron and the Crystal Colossus), made on 2026-11-24 in step 2 of the dungeons 2 and 3 rework
(docs/design/2026-11-23-dungeons-2-3-rework.md "The bosses"), with their new frames.

    python scripts/audio/picker/round-16-make.py
    python scripts/audio/prep-takes.py scripts/audio/picker/round-16.json
    python scripts/audio/picker/build-picker.py scripts/audio/picker/round-16.json temp/sound-round-16/sound-picker-round-16.html

Magnific sound effects (ElevenLabs), two takes per option, the prompts below; 230 credits. Not
staged in the game: the fights that play them are not built yet. When they are, stage the round with
the owner's picks (`stage-round.py --picks`), which also writes the players.

The raw downloads are temp/sound-round-16/raw/<file>-<option>-<n>.mp3 (`urls.json` there maps them
to the Magnific creations).
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
RAW = "temp/sound-round-16/raw"

## (cue id, node, ship, name, where, raw file stem, max length in seconds, options: (key, label, prompt))
CUES = [
	("boss.matron-hiss", "MatronHiss", "boss/matron-hiss", "Matron: the hiss",
		"Hanging high in round 2, before she spits or dives; her cocoon's threat in rounds 1 and 3",
		"matron-hiss", 2.0, [
			("a", "Long raspy hiss",
				"A giant spider queen hissing a threat from above: a long harsh raspy hiss with wet clicking mandibles, menacing, close mic, dry, no reverb, no human voice, no music"),
			("b", "Chitter into a hiss",
				"A huge spider rearing up to strike: rapid dry chittering clicks of chitin fangs rising into a sharp sputtering hiss, insect, menacing, close mic, dry, no human voice, no music"),
		]),
	("boss.matron-shriek", "MatronShriek", "boss/matron-shriek", "Matron: the shriek",
		"The ram catches her mid-dive, a blast tears her cocoon, the last blow",
		"matron-shriek", 2.0, [
			("a", "Shrill screech",
				"A giant spider monster struck hard and shrieking in pain: a harsh shrill screeching chitter, insect-like, raw and furious, about one second, close mic, dry, no human voice, no music"),
			("b", "Grating rasp",
				"A huge beetle-like spider screams: a grating, rasping high screech with clattering chitin, monstrous, short, close mic, dry, no human voice, no music"),
		]),
	("boss.matron-impact", "MatronImpact", "boss/matron-impact", "Matron: she lands",
		"Her dive lands, or she crashes to the floor on her back after the ram",
		"matron-impact", 1.4, [
			("a", "Fleshy thud and chitin",
				"A huge heavy spider body crashes onto a stone floor from a height: one heavy fleshy thud with a dry crunch of chitin shell and legs clattering on stone, dry, no reverb, no voice"),
		]),
	("boss.colossus-stomp", "ColossusStomp", "boss/colossus-stomp", "Colossus: the stomp",
		"His stomp lands (it puts out the nearest brazier); also his landing from the wall",
		"colossus-stomp", 1.4, [
			("a", "Rock boom and crystal",
				"A giant stone golem stomps one huge foot on a rocky cave floor: one massive deep low boom of rock on rock with crunching gravel and a few crystal shards tinkling, dry, short tail, no voice"),
			("b", "Earth-shaking thump",
				"An enormous rock giant slams his foot down: a deep earth-shaking thump with a gravelly crunch and pebbles bouncing, heavy sub bass, dry, no reverb, no voice"),
		]),
	("boss.colossus-roar", "ColossusRoar", "boss/colossus-roar", "Colossus: the roar",
		"He wakes, a plate bursts, he leaps onto the wall",
		"colossus-roar", 2.6, [
			("a", "Grinding boulder roar",
				"A huge golem made of rock and crystal roars in anger: a deep grinding rumbling roar like boulders scraping together, gravelly and resonant with a faint glassy ring, monstrous, no human voice, no music"),
		]),
	("boss.colossus-shatter", "ColossusShatter", "boss/colossus-shatter", "Colossus: a plate bursts",
		"The cart hits a brittle (glowing) plate: it shatters for good",
		"colossus-shatter", 1.6, [
			("a", "Glassy crack and shards",
				"A thick slab of crystal armour shatters from a blow: one bright loud glassy crack bursting into many crystal shards scattering and tinkling on a stone floor, close mic, dry, no voice"),
			("b", "Hot crystal burst",
				"A big block of hot brittle crystal explodes: a sharp crack and crunch with a glassy burst and a short hiss of heat, shards raining on stone, close mic, dry, no voice"),
		]),
	("boss.colossus-clang", "ColossusClang", "boss/colossus-clang", "Colossus: a cold plate clangs",
		"The cart hits a cold plate: it holds, and he staggers",
		"colossus-clang", 1.0, [
			("a", "Ringing crystal clang",
				"A heavy iron mine cart rams a thick crystal armour plate on a stone golem: one deep ringing crystal clang with a heavy iron knock, the crystal ringing briefly, dry, no voice"),
		]),
]
TAKES = 2


def main() -> None:
	cues = []
	for cue_id, node, ship, name, where, stem, max_s, options in CUES:
		cues.append({"id": cue_id, "group": cue_id.split("-")[0].split(".")[1], "name": name, "where": where,
			"node": node, "ship": ship, "inGame": "a",
			"options": [{"key": key, "label": label, "note": prompt, "kind": "oneshot", "even": True,
				"takes": ["%s/%s-%s-%d.mp3" % (RAW, stem, key, n + 1) for n in range(TAKES)], "max": max_s}
				for key, label, prompt in options]})
	manifest = {
		"round": "round-16",
		"title": "Sound picker, round 16: the two bosses",
		"intro": "The Orb-Weaver Matron's and the Crystal Colossus's own sounds (2026-11-24), for their reworked fights. Not in the game yet.",
		"takes": "temp/sound-round-16/takes",
		"groups": [
			{"id": "matron", "name": "The Orb-Weaver Matron", "note": "She hangs, spits and dives; the ram flings her to the wall."},
			{"id": "colossus", "name": "The Crystal Colossus", "note": "Three crystal plates; a cart breaks a hot one and clangs off a cold one."},
		],
		"cues": cues,
	}
	(HERE / "round-16.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
	print("round-16.json: %d cues" % len(cues))


if __name__ == "__main__":
	main()
