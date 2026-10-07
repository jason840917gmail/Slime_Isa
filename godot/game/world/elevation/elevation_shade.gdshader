shader_type canvas_item;
render_mode blend_mul;

// Darkens the ground of holes by their depth (docs/godot/ELEVATION.md): Elevation draws every
// uncovered tri below level 0 with this, its level in vertex colour r ((level + 4) / 8). The
// ground layer draws the plain ground under it; walls, feet and lips apply the same light
// themselves (elevation_light.gdshaderinc).

#include "res://game/world/elevation/elevation_light.gdshaderinc"

varying float light;

void vertex() {
	light = level_light(decode_level(COLOR.r));
}

void fragment() {
	COLOR = vec4(vec3(light), 1.0);
}
