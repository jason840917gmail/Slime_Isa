shader_type canvas_item;

// Flights of stairs (docs/godot/ELEVATION.md "Stairs"), drawn by Elevation from
// elevation_stairs.gd's faces, back to front in one mesh, so one material serves every face and
// UV.y picks its texture: kind = round(UV.y / 4096) (0 tread, 1 riser, 2 coping, 3 wall), the
// rest is the kind's own coordinate. UV.x is texture px (2 per world unit); a tread's and a
// coping's v runs 0 … 1 across one row, a riser's counts rows (one per rise) and the wall's is px.
// Vertex colour: r = light / 2 (the face's shade by the way it looks, contact shadows, the
// nosing's light), g = height in levels ((L + 4) / 8, elevation_light.gdshaderinc), b and a =
// where on the face (0 … 1 both ways): a dark joint line runs along every face's border.

#include "res://game/world/elevation/elevation_light.gdshaderinc"

uniform sampler2D tread_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D riser_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D coping_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D wall_texture : source_color, repeat_enable, filter_linear;
uniform vec2 tread_size = vec2(304.0, 43.0);
uniform vec2 riser_size = vec2(278.0, 43.0);
uniform vec2 coping_size = vec2(278.0, 43.0);
uniform vec2 wall_size = vec2(416.0, 256.0);
uniform vec4 line_color : source_color = vec4(0.20, 0.13, 0.08, 0.55);
// Joint line width (screen px).
uniform float line_width = 1.2;

const float KIND_OFFSET = 4096.0;

varying vec4 data;

void vertex() {
	data = COLOR;
}

void fragment() {
	float kind = floor((UV.y + KIND_OFFSET * 0.5) / KIND_OFFSET);
	vec2 uv = vec2(UV.x, UV.y - kind * KIND_OFFSET);
	vec3 stone;
	if (kind < 0.5) {
		stone = texture(tread_texture, vec2(uv.x / tread_size.x, clamp(uv.y, 0.01, 0.99))).rgb;
	} else if (kind < 1.5) {
		stone = texture(riser_texture, vec2(uv.x / riser_size.x, uv.y)).rgb;
	} else if (kind < 2.5) {
		stone = texture(coping_texture, vec2(uv.x / coping_size.x, clamp(uv.y, 0.01, 0.99))).rgb;
	} else {
		stone = texture(wall_texture, uv / wall_size).rgb;
	}
	float light = data.r * 2.0 * level_light(decode_level(data.g));
	vec2 across = min(data.ba, 1.0 - data.ba) / max(fwidth(data.ba), vec2(1.0e-5));
	float line = 1.0 - smoothstep(line_width * 0.5, line_width + 0.5, min(across.x, across.y));
	COLOR = vec4(mix(stone * light, line_color.rgb, line * line_color.a), 1.0);
}
