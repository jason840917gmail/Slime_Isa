extends RefCounted
## Whether a sound made at a world point is heard: the slime hears what it could see (owner,
## 2026-10-17: steps were heard at Fatty's Lair's entrance from Bone Marchers walking two rooms
## away). Global cues (GameFeel.audio_cue) carry no position, so an enemy anywhere in a world would
## otherwise sound as if beside the slime. A point is heard inside the camera's view grown by
## `combat.hearing.cueMarginPx`, and, in a world with camera rooms, only inside the room the view
## keeps to (Zelda: the other screens are silent). Without a camera everything is heard.
##
## Owner: audio.

const Services := preload("res://game/shared/services.gd")
const MARGIN_KEY := "combat.hearing.cueMarginPx"


## True when a sound at `at` (world coordinates) should play.
static func heard(at: Vector2) -> bool:
	var world := Services.world()
	if world == null or world.camera == null or not is_instance_valid(world.camera):
		return true
	var camera := world.camera
	if camera.room.has_area() and not camera.room.has_point(at):
		return false
	var constants := Services.constants()
	var margin := constants.number(MARGIN_KEY) if constants != null else 0.0
	return camera.view_rect().grow(margin).has_point(at)
