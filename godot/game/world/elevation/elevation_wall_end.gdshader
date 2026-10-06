shader_type canvas_item;

// The corner stones where a cliff wall ends (docs/godot/ELEVATION.md): a column of rounded stones
// drawn by Elevation over the wall's last stretch, bulging a little past its end. UV.x = px across
// the art (clamped), UV.y = the wall's own v (world units: depth below the top edge + the course
// of its level), so the stones' joints sit on the wall's. The art's alpha shapes the bulge.
// Vertex colour as the wall's: r = shade, g = height in levels ((level + 4) / 8), b = depth / 256.

#include "res://game/world/elevation/elevation_light.gdshaderinc"

uniform sampler2D end_texture : source_color, repeat_enable, filter_linear;
uniform vec2 end_size = vec2(74.0, 256.0);
uniform float top_shadow = 0.35;
uniform float top_shadow_depth = 14.0;

varying vec4 data;

void vertex() {
	data = COLOR;
}

void fragment() {
	vec2 uv = vec2(clamp(UV.x, 0.5, end_size.x - 0.5) / end_size.x, UV.y * 2.0 / end_size.y);
	vec4 stones = texture(end_texture, uv);
	float depth = data.b * 256.0;
	float light = data.r * level_light(decode_level(data.g));
	light *= 1.0 - top_shadow * (1.0 - smoothstep(0.0, top_shadow_depth, depth));
	COLOR = vec4(stones.rgb * light, stones.a);
}
