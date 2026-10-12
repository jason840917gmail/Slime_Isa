shader_type canvas_item;
render_mode blend_mul;

// The shadows raised ground casts on lower ground (docs/godot/ELEVATION.md). The light comes from
// the upper left, high: shadows fall to the right and a little down, as long as SHADOW_UNITS per
// level of height, so a level-3 hill casts three times the shadow of a level-1 one. North and
// west of a hill there is none; along a south wall's foot a thin contact band; inside a hole the
// rim casts onto the floor along its west side. Elevation draws this over the ground near every
// drop (vertex colour a = the ground's level) before the walls; each pixel looks back towards the
// light through the depth map (elevation_occlusion.gd, ground-layer space) for ground high enough
// to shade it (elevation_cast_shadow.gdshaderinc, which a ramp's slope shares). Soft at its far end
// and sides. Vertex colour r = how much of it the ground takes (0 just beyond a ramp's open end,
// where the cliff comes down to the ground: elevation_ramp.gd `shadow_take`; 1 elsewhere).

#include "res://game/world/elevation/elevation_cast_shadow.gdshaderinc"

varying vec2 local;
varying float level;
varying float take;

void vertex() {
	local = VERTEX;
	level = COLOR.a * 8.0 - 4.0;
	take = COLOR.r;
}

void fragment() {
	COLOR = vec4(vec3(1.0 - strength * take * cast_shade(local, level)), 1.0);
}
