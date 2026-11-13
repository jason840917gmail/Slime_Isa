shader_type canvas_item;

// Lightens the ground of raised tops by their height (docs/godot/ELEVATION.md, owner 2026-11-06:
// "light the upper levels ... so the optical effect is better"): Elevation draws every uncovered tri
// above level 0 with this ("Shade" group, key "tops"), its level in vertex colour r ((level + 4) / 32).
// The ground layer has drawn the plain ground under it; this reads it back and multiplies it by the
// level's light (elevation_light.gdshaderinc), which a multiply blend cannot do above 1. The walls,
// their edges and feet, ramps and stairs apply the same light themselves.

#include "res://game/world/elevation/elevation_light.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

varying float light;

void vertex() {
	light = level_light(decode_level(COLOR.r));
}

void fragment() {
	COLOR = vec4(level_lit(textureLod(screen_texture, SCREEN_UV, 0.0).rgb, light), 1.0);
}
