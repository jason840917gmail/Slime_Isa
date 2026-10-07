shader_type canvas_item;

// A cliff wall (docs/godot/ELEVATION.md), drawn by Elevation from its covered tris. UV is
// (world x, depth below the wall's top edge + the course of its level) in world units, so the
// seamless wall texture (scripts/art/build-elevation-walls.py: one stone course per level) runs on
// across every tri, bends at the corners of a diagonal face and stacks its courses per level.
// Vertex colour: r shades the face by the way it looks (south-west faces catch the light),
// g = the height of the point in levels ((level + 4) / 8: walls in a hole darken with depth),
// b = depth below the top edge / 256 (the lip's shadow at the top).

#include "res://game/world/elevation/elevation_light.gdshaderinc"

uniform sampler2D wall_texture : source_color, repeat_enable, filter_linear;
// The texture's size in world units (2 px of art per unit).
uniform vec2 wall_size = vec2(208.0, 128.0);
// Shadow right under the top edge, and how far down it fades (world units).
uniform float top_shadow = 0.35;
uniform float top_shadow_depth = 14.0;

varying vec4 data;

void vertex() {
	data = COLOR;
}

void fragment() {
	vec3 rock = texture(wall_texture, UV / wall_size).rgb;
	float depth = data.b * 256.0;
	float light = data.r * level_light(decode_level(data.g));
	light *= 1.0 - top_shadow * (1.0 - smoothstep(0.0, top_shadow_depth, depth));
	COLOR = vec4(rock * light, 1.0);
}
