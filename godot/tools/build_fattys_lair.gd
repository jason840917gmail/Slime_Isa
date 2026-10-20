extends SceneTree
## RETIRED (owner, 2026-10-18): Fatty's Lair is in place and its scenes are the source of truth; they
## are edited in the editor. Since 2026-10-18 every room is its own world (docs/godot/DUNGEON_ROOMS.md
## "Fatty's Lair: one world per room"), with no shell: this tool, which wrote a shell and rooms laid
## side by side, writes nothing and refuses to run.
##
## Its builder (the room tables that give the rooms' intent, the kit's placement, the interior walls'
## first paint) was removed on 2026-10-19 as dead code; it is in the history:
##
##     git show 0a6b9954:godot/tools/build_fattys_lair.gd
##
## Owner: dungeons (Fatty's Lair).


func _initialize() -> void:
	print("build_fattys_lair: retired. Fatty's Lair is one world per room, edited in the editor")
	print("(docs/godot/DUNGEON_ROOMS.md); its old builder is in git history (0a6b9954). Nothing written.")
	quit(1)
