shader_type canvas_item;

// Flights of stairs (docs/godot/ELEVATION.md "Stairs"), drawn by Elevation from
// elevation_stairs.gd's faces, back to front in one mesh per colour, so one material serves every
// face and UV.y picks what it is: kind = round(UV.y / 4096), the rest is the kind's own coordinate.
//   0  a front flight's steps, flat on the cliff's face: UV.x texture px along it, UV.y steps down
//      from the top edge; each step a riser (its top, in the shadow of the nosing above) then a
//      tread (lit, its nosing light at the bottom);
//   1  a tread and 2 a riser of a side or back flight: UV.x texture px, UV.y 0 … 1 across the tread
//      / rows of risers;
//   3  blocks (a side wall's faces): UV in block units, every other row shifted half a block;
//   4  a post: UV.x 0 … 1 across it from its left, UV.y block rows;
//   5  a side wall's top: UV.x texture px, UV.y 0 … 1 across.
// Everything is the stairs kit's stone in `tint`, the colour of the road or ground the flight leads
// to: the textures give only their grain (luminance over its mean). Vertex colour: r = light / 2
// (the face's shade by the way it looks, contact shadows, the nosing's light), g = height in levels
// ((L + 4) / 8, elevation_light.gdshaderinc), b and a = where on the face (0 … 1 both ways): a dark
// joint line runs along every face's border.

#include "res://game/world/elevation/elevation_light.gdshaderinc"

uniform sampler2D tread_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D riser_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D block_texture : source_color, repeat_enable, filter_linear;
uniform vec2 tread_size = vec2(304.0, 43.0);
uniform vec2 riser_size = vec2(278.0, 43.0);
uniform vec2 block_size = vec2(278.0, 43.0);
// Mean luminance of the tread, riser and block textures.
uniform vec3 grain_mean = vec3(0.524, 0.379, 0.508);
// How much of the textures' grain shows (0: flat colour).
uniform float grain = 0.35;
uniform vec3 tint : source_color = vec3(0.6, 0.6, 0.55);
uniform vec4 line_color : source_color = vec4(0.10, 0.09, 0.07, 0.6);
// Joint line width (screen px).
uniform float line_width = 1.2;
// A front flight's step (texture px tall: one rise): the riser's share of it from the top, the
// riser's light and how dark it is right under the nosing above, the tread's light at its back and
// front, the nosing's share and light.
uniform float rise_px = 32.0;
uniform float riser_part = 0.42;
uniform float riser_light = 0.6;
uniform float under_nosing = 0.42;
uniform float tread_back = 0.9;
uniform float tread_front = 1.04;
uniform float nosing_part = 0.14;
uniform float nosing_light = 1.16;
// A block (texture px tall), its bevel (share of a block) and the bevel's light on its top, left,
// bottom and right.
uniform float block_px = 32.0;
uniform float bevel = 0.14;
uniform vec4 bevel_light = vec4(1.18, 1.08, 0.70, 0.84);
uniform float cap_light = 1.08;

const float KIND_OFFSET = 4096.0;

varying vec4 data;

void vertex() {
	data = COLOR;
}

float grain_of(vec3 stone, float mean) {
	return mix(1.0, dot(stone, vec3(0.299, 0.587, 0.114)) / mean, grain);
}

void fragment() {
	float kind = floor((UV.y + KIND_OFFSET * 0.5) / KIND_OFFSET);
	vec2 uv = vec2(UV.x, UV.y - kind * KIND_OFFSET);
	float face = data.r * 2.0;
	float light = face;
	float stone = 1.0;
	float groove = 0.0;
	if (kind < 0.5) {
		float k = floor(uv.y);
		float f = uv.y - k;
		if (f < riser_part) {
			float r = f / riser_part;
			stone = grain_of(texture(riser_texture, vec2(uv.x / riser_size.x + k * 0.31, r * riser_part * rise_px / riser_size.y)).rgb, grain_mean.y);
			light = face * riser_light * mix(under_nosing, 1.0, smoothstep(0.0, 0.4, r));
		} else {
			float r = (f - riser_part) / (1.0 - riser_part);
			stone = grain_of(texture(tread_texture, vec2(uv.x / tread_size.x + k * 0.37, 0.1 + r * (1.0 - riser_part) * rise_px / tread_size.y)).rgb, grain_mean.x);
			// A tread is a top: lit whatever way the face looks.
			light = r > 1.0 - nosing_part ? nosing_light : mix(tread_back, tread_front, smoothstep(0.0, 0.5, r));
		}
	} else if (kind < 1.5) {
		stone = grain_of(texture(tread_texture, vec2(uv.x / tread_size.x, clamp(uv.y, 0.01, 0.99))).rgb, grain_mean.x);
	} else if (kind < 2.5) {
		stone = grain_of(texture(riser_texture, vec2(uv.x / riser_size.x, uv.y)).rgb, grain_mean.y);
	} else if (kind < 4.5) {
		vec2 b = uv;
		float row = floor(b.y);
		if (kind < 3.5) {
			b.x += 0.5 * mod(row, 2.0);
		} else {
			b.x = clamp(b.x, 0.0, 0.999);
		}
		vec2 f = fract(b);
		vec2 cell = floor(b);
		stone = grain_of(texture(block_texture, vec2((f.x * block_px + cell.x * 61.0 + row * 37.0) / block_size.x, f.y * block_px / block_size.y)).rgb, grain_mean.z);
		if (f.y < bevel) {
			light *= bevel_light.x;
		} else if (f.y > 1.0 - bevel) {
			light *= bevel_light.z;
		} else if (f.x < bevel) {
			light *= bevel_light.y;
		} else if (f.x > 1.0 - bevel) {
			light *= bevel_light.w;
		}
		// The mortar between blocks: a line a pixel wide.
		vec2 px = max(fwidth(b), vec2(1.0e-5));
		vec2 to_edge = min(f, 1.0 - f) / px;
		if (kind > 3.5) {
			to_edge.x = 1.0e3;
		}
		groove = 1.0 - smoothstep(0.5, 1.5, min(to_edge.x, to_edge.y));
	} else {
		stone = grain_of(texture(block_texture, vec2(uv.x / block_size.x, clamp(uv.y, 0.01, 0.99))).rgb, grain_mean.z);
		light *= cap_light;
	}
	vec3 colour = tint * stone * light * level_light(decode_level(data.g));
	vec2 across = min(data.ba, 1.0 - data.ba) / max(fwidth(data.ba), vec2(1.0e-5));
	float line = max(1.0 - smoothstep(line_width * 0.5, line_width + 0.5, min(across.x, across.y)), groove);
	COLOR = vec4(mix(colour, line_color.rgb, line * line_color.a), 1.0);
}
