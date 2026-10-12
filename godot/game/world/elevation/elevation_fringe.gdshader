shader_type canvas_item;

// A ground's cliff fringe (docs/godot/ELEVATION.md): a seamless strip
// (scripts/art/build-elevation-art.py) laid along a cliff top's border (lip: tufts, soil and roots
// hanging over a wall; rim: the same tufts along an edge without a wall, the soil and roots cut
// away; elevation_rims.gd) or along a wall's foot (foot: tufts growing up the wall). UV x = px of
// art along the strip, UV y = the strip's edge row + 2 · (world units past the edge). The strip's
// own ground fades into the real ground beside it. Vertex colour: r = shadow strength, g = outward
// distance from the edge ((d + 64) / 128, world units), b = rim (1: cut below `rim_cut`), a = the
// ground's level ((level + 4) / 8, elevation_light.gdshaderinc). Beyond the art the fringe casts a
// soft shadow (on the wall top under a lip, up the wall base above a foot); a foot also darkens its
// own ground near the wall. A ramp's foot (RampFeet) ends on the face's top edge, where the art's cut
// fern tips would draw a ruled line: its material sets `top_fade` (art rows, 0 = off) to fade out
// the art's top rows, and `fade_by_b`: colour b is then its opacity (it fades in as the face grows
// from nothing at the ramp's top end) instead of the rim flag.

#include "res://game/world/elevation/elevation_light.gdshaderinc"

uniform sampler2D strip : source_color, repeat_enable, filter_linear;
uniform vec2 strip_size = vec2(564.0, 160.0);
uniform float shadow_width = 22.0;
uniform float inner_shade = 0.0;
uniform float inner_width = 14.0;
// Art row below which a rim shows nothing (the lip's soil band starts at its edge row, 96).
uniform float rim_cut = 104.0;
uniform float rim_fade = 8.0;
uniform float top_fade = 0.0;
uniform bool fade_by_b = false;

varying vec4 data;

void vertex() {
	data = COLOR;
}

void fragment() {
	bool inside = UV.y >= 0.0 && UV.y <= strip_size.y;
	vec2 uv = vec2(UV.x / strip_size.x, clamp(UV.y, 0.5, strip_size.y - 0.5) / strip_size.y);
	vec4 art = texture(strip, uv);
	float alpha = inside ? art.a : 0.0;
	if (fade_by_b) {
		alpha *= data.b * smoothstep(0.0, top_fade, UV.y);
	} else {
		alpha *= 1.0 - data.b * smoothstep(rim_cut - rim_fade, rim_cut, UV.y);
	}
	float d = data.g * 128.0 - 64.0;
	vec3 rgb = art.rgb * level_light(decode_level(data.a));
	rgb *= 1.0 - inner_shade * (1.0 - smoothstep(0.0, inner_width, -d)) * step(d, 0.0);
	float shadow = data.r * (1.0 - smoothstep(0.0, shadow_width, d)) * step(0.0, d);
	float out_alpha = alpha + shadow * (1.0 - alpha);
	vec3 out_rgb = out_alpha > 0.0 ? rgb * alpha / out_alpha : vec3(0.0);
	COLOR = vec4(out_rgb, out_alpha);
}
