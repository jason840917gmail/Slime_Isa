shader_type canvas_item;

// Flights of stairs (docs/godot/ELEVATION.md "Stairs"), drawn by Elevation from
// elevation_stairs.gd's faces, back to front in one mesh per colour, so one material serves every
// face and UV.y picks what it is: kind = round(UV.y / 4096), the rest is the kind's own coordinate.
//   1  a tread of a side or back flight: UV.x texture px, UV.y 0 … 1 from its back to its nosing;
//   2  a riser (never seen: they face away from the camera; drawn as a tread);
//   3  blocks (a side wall's faces): UV in blocks (BLOCK world units);
//   5  a side wall's top: UV.x texture px, UV.y 0 … 1 across;
//   7  a flight painted whole (a front flight's steps, notch and frame; a side flight): UV 0 … 1
//      over the piece, vertex colour b which piece (elevation_stairs.gd PIECE_ORDER[b · 8]).
// The painted kit (scripts/art/build-stairs-kit.py, owner 2026-11-06: the concepts Front A and
// West C) is drawn as painted, recoloured to `tint`, the stone of the wall the flight is cut into:
// colour = tint · the texture over its mean (`keep_colour` of its own hue shifts, the rest of its
// light and dark only). No joint lines are drawn: the kit's stones have their own.
// Vertex colour: r = light / 2 (the face's shade by the way it looks, contact shadows), g = height
// in levels ((L + 4) / 32, elevation_light.gdshaderinc).

#include "res://game/world/elevation/elevation_light.gdshaderinc"

uniform sampler2D tread_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D block_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D front_1_texture : source_color, repeat_disable, filter_linear;
uniform sampler2D front_2_texture : source_color, repeat_disable, filter_linear;
uniform sampler2D side_2_1_texture : source_color, repeat_disable, filter_linear;
uniform sampler2D side_1_1_texture : source_color, repeat_disable, filter_linear;
uniform sampler2D side_1_2_texture : source_color, repeat_disable, filter_linear;
uniform sampler2D diag_1_texture : source_color, repeat_disable, filter_linear;
uniform sampler2D diag_2_texture : source_color, repeat_disable, filter_linear;
uniform vec2 tread_size = vec2(567.0, 48.0);
uniform vec2 block_size = vec2(396.0, 396.0);
// Mean colour of each texture (build-stairs-kit.py prints them; a piece's over its opaque texels).
uniform vec3 tread_mean = vec3(0.761, 0.452, 0.221);
uniform vec3 block_mean = vec3(0.726, 0.399, 0.197);
uniform vec3 front_1_mean = vec3(0.663, 0.397, 0.203);
uniform vec3 front_2_mean = vec3(0.625, 0.361, 0.181);
uniform vec3 side_2_1_mean = vec3(0.717, 0.439, 0.217);
uniform vec3 side_1_1_mean = vec3(0.700, 0.429, 0.214);
uniform vec3 side_1_2_mean = vec3(0.744, 0.460, 0.239);
uniform vec3 diag_1_mean = vec3(0.645, 0.371, 0.172);
uniform vec3 diag_2_mean = vec3(0.640, 0.350, 0.184);
// How much of the kit's own hue shifts the recolouring keeps (0: only its light and dark).
uniform float keep_colour = 0.85;
uniform vec3 tint : source_color = vec3(0.7, 0.42, 0.2);
// Texture px per world unit (elevation_stairs.gd PX), and a block's side (world units).
uniform float px_per_unit = 3.0;
uniform float block_units = 16.0;
uniform float cap_light = 1.04;
// A front flight's piece is painted lit, as the cliff's rock: this light instead of the face's (the
// stone tint is a worn slab's, lighter than the wall).
uniform float piece_light = 0.88;
// The set's own wall style (elevation_stairs.gd make_material): its pieces as painted, not recoloured.
uniform float as_painted = 0.0;

const float KIND_OFFSET = 4096.0;

varying vec4 data;

void vertex() {
	data = COLOR;
}

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// `stone` (a texel of the kit) in `tint`.
vec3 recolour(vec3 stone, vec3 mean) {
	vec3 by_channel = stone / max(mean, vec3(0.02));
	float by_light = lum(stone) / max(lum(mean), 0.02);
	return tint * mix(vec3(by_light), by_channel, keep_colour);
}

void fragment() {
	float kind = floor((UV.y + KIND_OFFSET * 0.5) / KIND_OFFSET);
	vec2 uv = vec2(UV.x, UV.y - kind * KIND_OFFSET);
	float light = data.r * 2.0;
	vec3 colour;
	float alpha = 1.0;
	if (kind < 2.5) {
		colour = recolour(texture(tread_texture, vec2(uv.x / tread_size.x, clamp(fract(uv.y), 0.01, 0.99))).rgb, tread_mean);
	} else if (kind < 4.5) {
		colour = recolour(texture(block_texture, uv * block_units * px_per_unit / block_size).rgb, block_mean);
	} else if (kind < 5.5) {
		colour = recolour(texture(tread_texture, vec2(uv.x / tread_size.x, clamp(uv.y, 0.01, 0.99))).rgb, tread_mean);
		light *= cap_light;
	} else {
		// The piece: elevation_stairs.gd PIECE_ORDER[floor(b · 8)].
		vec2 at = clamp(uv, vec2(0.002), vec2(0.998));
		float piece = floor(data.b * 8.0);
		vec4 stone;
		vec3 mean;
		if (piece < 0.5) {
			stone = texture(front_1_texture, at);
			mean = front_1_mean;
		} else if (piece < 1.5) {
			stone = texture(front_2_texture, at);
			mean = front_2_mean;
		} else if (piece < 2.5) {
			stone = texture(side_2_1_texture, at);
			mean = side_2_1_mean;
		} else if (piece < 3.5) {
			stone = texture(side_1_1_texture, at);
			mean = side_1_1_mean;
		} else if (piece < 4.5) {
			stone = texture(side_1_2_texture, at);
			mean = side_1_2_mean;
		} else if (piece < 5.5) {
			stone = texture(diag_1_texture, at);
			mean = diag_1_mean;
		} else {
			stone = texture(diag_2_texture, at);
			mean = diag_2_mean;
		}
		colour = mix(recolour(stone.rgb, mean), stone.rgb, as_painted);
		// Painted lit; a face turned from the light darker (vertex colour r, elevation_stairs.gd).
		light = piece_light * data.r * 2.0;
		alpha = stone.a;
	}
	COLOR = vec4(colour * light * level_light(decode_level(data.g)), alpha);
}
