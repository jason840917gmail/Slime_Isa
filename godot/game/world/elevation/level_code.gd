extends RefCounted
## How a level and a depth travel to the elevation shaders (docs/godot/ELEVATION.md "Levels in
## colours"): in a mesh's vertex colours and in the depth map's texels (elevation_occlusion.gd),
## both 8 bits a channel. elevation_code.gdshaderinc reads them back (`decode_level`, `decode_dy`):
## change the numbers in both.
##
## - A level (whole, or a slope's height in levels): (level + 4) / 32, so −4 … 28. Until 2026-11-12
##   it was (level + 4) / 8, which ended at level 4 (the owner: "more than 10 levels" for the walls
##   of climbable chunks).
## - A depth `dy` (world units below a wall's top edge, or past a rim's edge): (dy + 128) / 1536,
##   so −128 … 1408: a wall from the highest level (16) to the lowest (−3) is 1216 tall. (512
##   until 2026-11-12: six courses.) A texel's step is 6 units; the hiding of bodies allows 12
##   (elevation_occlusion.gdshaderinc ELEVATION_MARGIN).
##
## Owner: world (elevation).

const LEVEL_OFFSET := 4.0
const LEVEL_SPAN := 32.0
const DY_OFFSET := 128.0
const DY_SPAN := 1536.0


## A level (or a height in levels) as a colour channel.
static func of(level: float) -> float:
	return (level + LEVEL_OFFSET) / LEVEL_SPAN


## A depth below a top edge (world units) as a colour channel.
static func dy(depth: float) -> float:
	return clampf((depth + DY_OFFSET) / DY_SPAN, 0.0, 1.0)


## Back from a colour channel (as the shaders read them): the level, the depth.
static func level_from(channel: float) -> float:
	return channel * LEVEL_SPAN - LEVEL_OFFSET


static func dy_from(channel: float) -> float:
	return channel * DY_SPAN - DY_OFFSET
