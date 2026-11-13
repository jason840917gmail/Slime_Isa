// Light by height (docs/godot/ELEVATION.md), shared by the elevation shaders: the ground of a
// hole and the lower courses of its walls get darker with every level of depth, so a pit reads
// as deep; 0.2 a level since 2026-10-31 (the owner: lower levels "a little darker" for "a better
// optical illusion of deep"; 0.13 before). Since 2026-11-06 the levels above 0 get lighter the same
// way (the owner: "light the upper levels ... so the optical effect is better", as the rooms' pits
// read deep), RAISE_LIGHTEN a level, at most BRIGHTEST: a hill's top, the upper courses of its walls,
// its edges, ramps and stairs (the top's own ground through elevation_top_light.gdshader). The
// floor trim in rooms takes it too (game/world/interior/interior_trim.gdshader).

const float DEPTH_DARKEN = 0.2;
const float DARKEST = 0.5;
const float RAISE_LIGHTEN = 0.08;
const float BRIGHTEST = 1.24;
// A colour lifted above 1 eases off as it nears white (`level_lit`), so snow keeps its detail:
// c · light / (1 + c · (light − 1) · LIFT_SOFT).
const float LIFT_SOFT = 0.6;

float level_light(float level) {
	return level < 0.0 ? max(DARKEST, 1.0 + DEPTH_DARKEN * level) : min(BRIGHTEST, 1.0 + RAISE_LIGHTEN * level);
}

// `colour` (ground drawn on a top or its edge) in `light` (level_light): darkened as it is; lifted
// less the nearer it is to white.
vec3 level_lit(vec3 colour, float light) {
	if (light <= 1.0) {
		return colour * light;
	}
	return colour * light / (1.0 + colour * (light - 1.0) * LIFT_SOFT);
}

// Levels travel in vertex colours as elevation_code.gdshaderinc reads them (`decode_level`).
#include "res://game/world/elevation/elevation_code.gdshaderinc"
