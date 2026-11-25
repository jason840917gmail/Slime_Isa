"""Writes the manifest of Sound Picker round 15: the dungeon mechanisms (the knock target, the ram,
the runaway cart; docs/godot/DUNGEONS.md "Mechanisms"), built on 2026-11-23 as step 1 of the
dungeons 2 and 3 rework (docs/design/2026-11-23-dungeons-2-3-rework.md).

    python scripts/audio/picker/round-15-make.py

Each cue has ONE option so far, "a": the takes the builder shipped as defaults so the mechanisms
are not silent (Magnific sound effects, the prompts below; 115 credits). The round was applied at
once with `round-15-picks.json` (every cue "a", nothing dropped): the owner has not heard or picked
these yet. To let him pick, add options "b" and "c" per cue here, stage the round without `--picks`
and publish the picker page, as the earlier rounds did (docs/TOOLING.md).

The raw downloads are temp/sound-round-15/raw/<file>-a-<n>.mp3 (`urls.json` there maps them to the
Magnific creations).

Second fix round (2026-11-24, review of step 1): the cart's roll gets option "b" (EXTRA below), in
the game since then: a heavier rumble with the wheels' clatter on the joints, cut from
raw/cart-roll-b-1.mp3 (two 5-second looping takes, 50 credits; b-2 swells and drops out in its
middle and is not used) into cut/cart-roll-b-1.src.wav by the session's script (its steady part
from 1.4 s, levelled, the last 0.3 s crossfaded into the start so it loops cleanly). Option "a"
stays for the picker. The tails of ram-windup-2 and ram-ratchet-2 and -3 got a longer curved
fade (60 and 40 ms) in place: they ended cut off.
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
RAW = "temp/sound-round-15/raw"

## (cue id, node, ship, name, where, raw file stem, takes, max length in seconds or None, kind,
##  the label, the prompt)
CUES = [
	("world.knock-target-hit", "KnockTargetHit", "world/knock-target-hit", "Knock target: knocked",
		"A thrown thing (or an arrow, or a blast) knocks the target: it spins and lets its mechanism go",
		"target-hit", 3, 0.5, "oneshot", "Thwack and latch",
		"A thrown clay pot smacks a round wooden practice target hanging on a post: one solid hollow wooden thwack with a short iron latch clack right after, close mic, dry, no reverb, no voice"),
	("world.knock-target-tap", "KnockTargetTap", "world/knock-target-tap", "Knock target: only a tap",
		"The Spear, a Roll or the slime's body touches the target: it does not trip",
		"target-tap", 2, 0.3, "oneshot", "Dull wooden knock",
		"One single dull knock on a thick hollow wooden board, a soft blunt wooden tap, nothing breaks, close mic, dry, no reverb"),
	("world.knock-target-rearm", "KnockTargetRearm", "world/knock-target-rearm", "Knock target: armed again",
		"Its mechanism is wound back: the target snaps upright",
		"target-rearm", 2, 0.3, "oneshot", "Wood-and-iron clack",
		"A wooden board snaps upright and an iron latch clicks shut: one short crisp wood-and-iron clack, mechanical, close mic, dry, no reverb"),
	("world.ram-windup", "RamWindup", "world/ram-windup", "Ram: the shudder",
		"The ram is let go: 0.35 s of shudder before the log swings (the tell)",
		"ram-windup", 2, 0.5, "oneshot", "Timber creak and chains",
		"A heavy timber frame creaks and thick iron chains rattle briefly as a huge hanging log shudders, about to be let go, half a second, close mic, dry"),
	("world.ram-swing", "RamSwing", "world/ram-swing", "Ram: the swing",
		"The log swings out along its lane",
		"ram-swing", 2, 0.55, "oneshot", "Deep whoosh",
		"A huge heavy wooden log swings fast through the air on chains: one deep low whoosh with a faint chain jingle, half a second, no impact, dry"),
	("world.ram-thud", "RamThud", "world/ram-thud", "Ram: the blow",
		"The log reaches the end of its swing, or strikes something on its lane",
		"ram-thud", 3, 0.6, "oneshot", "Boom and clank",
		"An iron-capped battering ram log slams hard to the end of its chains: one deep heavy wooden boom with a short iron clank, punchy, short tail, dry, no reverb"),
	("world.ram-ratchet", "RamRatchet", "world/ram-ratchet", "Ram and cart: the ratchet",
		"The winch pulls the log back (8 s), or the counterweight hauls the cart back: one click each time",
		"ram-ratchet", 3, 0.16, "oneshot", "Iron tick",
		"One single click of a heavy iron ratchet pawl dropping onto a cog wheel tooth, a short dry metallic tick, close mic, no reverb"),
	("world.cart-brake", "CartBrake", "world/cart-brake", "Cart: the brake snaps",
		"The cart's brake is knocked off: the lever snaps back and the chock is kicked away",
		"cart-brake", 2, 0.45, "oneshot", "Clack and scrape",
		"A wooden brake lever snaps back and a wooden wedge is kicked off an iron rail: one sharp wooden clack with a short iron scrape, close mic, dry, no reverb"),
	("world.cart-roll", "CartRoll", "world/cart-roll", "Cart: rolling (a loop)",
		"The cart rolls down its line (the game raises its pitch as it speeds up) and is hauled back",
		"cart-roll", 1, None, "loop", "Rattling wheels and ore",
		"A small loaded iron mine cart rolling fast along iron rails, steady rattling wheels and clattering ore rocks, continuous, close mic, dry, seamless loop"),
	("world.cart-bump", "CartBump", "world/cart-bump", "Cart: the bump",
		"The cart reaches its buffer stop, or rams something",
		"cart-bump", 2, 0.8, "oneshot", "Clang, thud and ore",
		"A loaded mine cart crashes to a dead stop against a wooden buffer: one heavy iron clang and wooden thud, then ore rocks rattling and settling, one second, dry"),
]

## Options after "a", per cue (their takes are ready-cut sources), and the option the game plays when
## it is not "a".
EXTRA = {
	"world.cart-roll": [{"key": "b", "label": "Heavy rumble and joint clatter",
		"note": "Heavy wooden mine cart loaded with ore rolling fast on iron rails in a stone tunnel: deep low rumble of iron wheels, rhythmic clack of the wheels over the rail joints, rocks jostling in the cart, continuous and steady, close mic, dry, no voice, no music (5 s, loop; cut to a 3.3 s loop)",
		"kind": "loop", "even": False, "takes": ["temp/sound-round-15/cut/cart-roll-b-1.src.wav"]}],
}
IN_GAME = {"world.cart-roll": "b"}


def main() -> None:
	cues = []
	for cue_id, node, ship, name, where, stem, takes, max_s, kind, label, prompt in CUES:
		option = {"key": "a", "label": label, "note": prompt, "kind": kind, "even": kind == "oneshot",
			"takes": ["%s/%s-a-%d.mp3" % (RAW, stem, n + 1) for n in range(takes)]}
		if max_s is not None:
			option["max"] = max_s
		cues.append({"id": cue_id, "group": "mechanisms", "name": name, "where": where, "node": node, "ship": ship,
			"inGame": IN_GAME.get(cue_id, "a"), "options": [option] + EXTRA.get(cue_id, [])})
	manifest = {
		"round": "round-15",
		"title": "Sound picker, round 15: the dungeon mechanisms",
		"intro": "The knock target, the ram and the runaway cart (2026-11-23). One option each so far: the builder's defaults, not yet heard by the owner.",
		"takes": "temp/sound-round-15/takes",
		"groups": [{"id": "mechanisms", "name": "The mechanisms", "note": "A throw at the knock target lets the ram or the cart go."}],
		"cues": cues,
	}
	(HERE / "round-15.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
	picks = {
		"round": "round-15",
		"decidedAt": "2026-11-23",
		"source": "The builder's defaults (step 1 of the dungeons 2 and 3 rework): every cue its only option, but the cart's roll its option b (the review of 2026-11-24). Not picked by the owner.",
		"note": "",
		"picks": {cue[0]: IN_GAME.get(cue[0], "a") for cue in CUES},
		"dropped": {},
	}
	(HERE / "round-15-picks.json").write_text(json.dumps(picks, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
	print("round-15.json: %d cues" % len(cues))


if __name__ == "__main__":
	main()
