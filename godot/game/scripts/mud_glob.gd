extends "res://game/scripts/spore_seed.gd"
class_name MudGlobScript
## Scene script `game.mud-glob` (docs/godot/BESTIARY.md "Pipe Worm"): the Pipe Worm's mud glob, an
## enemy projectile the Gulp can catch, as the Spitcap's seed (game/scripts/spore_seed.gd, whose
## suckable contract it keeps): sucked in, the mouth holds {"kind": GLOB_KIND, "texture",
## "art_px", "material"}; thrown back, its hit carries the tag GLOB_KIND, which kills a Pipe Worm
## at once (pipe_worm.gd `_kill_hit`), even hidden in its pipe, and hits anything else as a soft
## thrown thing.
##
## Owner: enemy builder.

## The held kind and the tag its throw carries.
const GLOB_KIND := "mud-glob"
const GLOB_TEXTURE := "res://asset/MAPS/enemies/64x64-mud-glob.webp"
## The glob's drawn size in its 64 px picture.
const GLOB_ART_PX := 56.0


func suck_info() -> Dictionary:
	return {"kind": GLOB_KIND, "essence": "", "variant": 0, "texture": GLOB_TEXTURE, "art_px": GLOB_ART_PX,
		"material": MATERIAL}
