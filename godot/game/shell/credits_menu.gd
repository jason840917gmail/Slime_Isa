extends "res://game/shell/shell_menu.gd"
## The credits, opened from the title (Phaser `features/shell/CreditsSurfacePort.ts`,
## `ui/credits.scene.json`, text from `content/credits/credits.json`). One block per section: the
## heading in capitals, then one line per entry ("name  ·  detail  ·  license").
##
## The sections are kept here until the converter copies credits.json to generated/data; the
## "Built with" section names the Godot port's engine instead of Phaser's libraries.
##
## Owner: shell.

## content/credits/credits.json sections: {heading, entries: [{name, detail?, license?}]}.
const SECTIONS: Array[Dictionary] = [
	{"heading": "Slime Isa", "entries": [{"name": "Created by Daniel, Isa and Dany6"}]},
	{"heading": "Art", "entries": [{"name": "Characters, props, interiors, grounds and world art",
		"detail": "Made by the Slime Isa team with AI image tools (ChatGPT, Magnific and others)"}]},
	{"heading": "Music", "entries": [{"name": "Home Town", "detail": "Juhani Junkala, JRPG Pack 2: Towns",
		"license": "CC0 1.0"}]},
	{"heading": "Sound effects", "entries": [
		{"name": "RPG Audio, Impact Sounds, Interface Sounds, Music Jingles", "detail": "Kenney", "license": "CC0 1.0"},
		{"name": "80 CC0 creature SFX (#1 and #2), 40 CC0 water/splash/slime SFX", "detail": "rubberduck", "license": "CC0 1.0"},
		{"name": "Swishes Sound Pack", "detail": "artisticdude", "license": "CC0 1.0"},
		{"name": "Generated sound effects", "detail": "Magnific (ElevenLabs sound effects), made for Slime Isa"},
		{"name": "Synthesized effects and ambience", "detail": "Made for Slime Isa (scripts/audio/cues.mjs)"},
	]},
	{"heading": "Fonts", "entries": [
		{"name": "Source Sans 3", "detail": "Adobe", "license": "SIL Open Font License 1.1"},
		{"name": "Noto Sans Symbols 2", "detail": "The Noto Project Authors", "license": "SIL Open Font License 1.1"},
	]},
	{"heading": "Built with", "entries": [
		{"name": "Godot Engine", "detail": "godotengine.org", "license": "MIT"},
	]},
]

@onready var text_label: Label = $Panel/Margin/Rows/Scroll/Text
@onready var close_button: Button = $Panel/Margin/Rows/Bottom/Close


func _ready() -> void:
	super()
	close_button.pressed.connect(close)


func refresh() -> void:
	text_label.text = credits_text(SECTIONS)


## `creditsText()` (CreditsSurfacePort.ts:22-27).
static func credits_text(sections: Array[Dictionary]) -> String:
	var blocks := PackedStringArray()
	for section: Dictionary in sections:
		var lines := PackedStringArray([str(section["heading"]).to_upper()])
		for entry: Dictionary in section["entries"]:
			var parts := PackedStringArray()
			for key: String in ["name", "detail", "license"]:
				if not str(entry.get(key, "")).is_empty():
					parts.append(str(entry[key]))
			lines.append("  ·  ".join(parts))
		blocks.append("\n".join(lines))
	return "\n\n".join(blocks)
