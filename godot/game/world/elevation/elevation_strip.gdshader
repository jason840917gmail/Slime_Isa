shader_type canvas_item;

// A cliff lip or foot (docs/godot/ELEVATION.md): one ground's straight terrain edge tile laid
// along an elevation edge by Elevation. UV is the tile's own pixel (0..128; the boundary runs
// through its middle); vertex colour r = shadow strength, g = outward distance from the edge
// ((d + 64) / 128, world units), b = tile index / 15, a = the ground's level ((level + 4) / 8: the
// ground of a hole darkens with depth, elevation_light.gdshaderinc). As in terrain_edge.gdshader the tile's alpha
// says where the ground covers, its colour is the painted rim, and `rim_weight` where the rim
// shows; elsewhere the ground's own sheet is drawn in world space, so the strip continues the
// ground it comes from without a seam. Outside the art the strip casts a soft shadow (under a lip
// on the wall, beside a rim, up the foot of a wall); a foot also darkens its own ground near the
// wall (`inner_shade`).

#include "res://game/world/elevation/elevation_light.gdshaderinc"

uniform sampler2D edge_tiles : source_color, filter_linear;
uniform sampler2D rim_weight : filter_linear;
uniform vec2 atlas_size = vec2(528.0);
uniform sampler2D ground_texture : source_color, repeat_enable, filter_linear;
// World units covered by one repeat of the ground sheet (19 cells x 64 units).
uniform float ground_period = 1216.0;
// The ground layer's global position: the sheet is anchored to its cell (0, 0).
uniform vec2 ground_origin = vec2(0.0);
// How far the shadow reaches beyond the edge (world units).
uniform float shadow_width = 22.0;
uniform float inner_shade = 0.0;
uniform float inner_width = 12.0;

varying vec2 world;
varying vec4 data;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - ground_origin;
	data = COLOR;
}

void fragment() {
	float tile = floor(data.b * 15.0 + 0.5);
	vec2 origin = vec2(2.0 + mod(tile, 4.0) * 132.0, 2.0 + floor(tile / 4.0) * 132.0);
	vec2 atlas_uv = (origin + clamp(UV, vec2(0.5), vec2(127.5))) / atlas_size;
	bool inside = UV.x >= 0.0 && UV.y >= 0.0 && UV.x <= 128.0 && UV.y <= 128.0;
	vec4 art = texture(edge_tiles, atlas_uv);
	float rim = texture(rim_weight, atlas_uv).r;
	float alpha = inside ? art.a : 0.0;
	float d = data.g * 128.0 - 64.0;
	vec3 ground = texture(ground_texture, world / ground_period).rgb;
	ground *= 1.0 - inner_shade * (1.0 - smoothstep(0.0, inner_width, -d)) * step(d, 0.0);
	vec3 painted = mix(ground, art.rgb, rim) * level_light(decode_level(data.a));
	float shadow = data.r * (1.0 - smoothstep(0.0, shadow_width, d)) * step(0.0, d);
	float out_alpha = alpha + shadow * (1.0 - alpha);
	vec3 out_rgb = out_alpha > 0.0 ? painted * alpha / out_alpha : vec3(0.0);
	COLOR = vec4(out_rgb, out_alpha);
}
