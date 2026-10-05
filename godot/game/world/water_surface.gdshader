// Animated water over the ground layer's water tiles (visual only). A line-for-line port of the
// fragment program in Phaser's features/world/WaterSurfaceLayer.ts:39-109; the maths and
// constants are unchanged (docs/godot/specs/water.md section 3), plus one interim step
// (`smooth_water_ground`, spec 6.1) until terrain blending is ported.
//
// One quad covers the water area of the ground layer, drawn by water_surface.gd. A mask with one
// texel per tile (r = shallow, g = deep), linearly filtered, says where water is. The shader
// re-samples the seamless water ground sheets with a moving refraction, crossing caustics, sun
// glints and shoreline foam; deep water is darker and slower with broad swells.
//
// Time is the engine's TIME (real seconds, keeps running through a hit-stop pause, like Phaser's
// `game.loop.getDuration()`). Phaser blends premultiplied (ONE, ONE_MINUS_SRC_ALPHA) with
// `vec4(color * alpha, alpha)`; Godot's default mix blend with `vec4(color, alpha)` gives the
// same pixel.
shader_type canvas_item;

// One texel per tile: r = shallow, g = deep (WaterSurfaceLayer.ts:165-181), clamped at the edge.
uniform sampler2D water_mask : filter_linear, repeat_disable;
// The seamless 1216 px water ground sheets, repeating every texture_period world pixels.
uniform sampler2D shallow_texture : filter_linear, repeat_enable;
uniform sampler2D deep_texture : filter_linear, repeat_enable;
// Mask size in tiles (columns, rows).
uniform vec2 grid_size = vec2(1.0, 1.0);
uniform float tile_size = 64.0;
uniform float texture_period = 1216.0;
// Interim, while terrain blending is not ported (water spec 6.1): under a water tile the ground
// layer draws the raw `water` or `deep-water` sheet with a hard edge between them, which shows
// through the 10-18 % transparent surface as tile steps. Phaser draws there its blended terrain.
// When on, pixels on a water tile composite a smooth ground (the same two sheets at the same
// texel the tile shows, mixed by the deep factor) and draw opaque; everything else is unchanged.
// Turn off once the terrain blend is ported.
uniform bool smooth_water_ground = true;

// Pixel position relative to the ground layer's origin (Phaser's `px`, y down).
varying vec2 layer_px;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	layer_px = VERTEX;
}

void fragment() {
	vec2 px = layer_px;
	vec4 m = texture(water_mask, (px / tile_size) / grid_size);
	float wet = m.r + m.g;
	float edge = noise(px * 0.035) * 0.22 + noise(px * 0.09) * 0.1 - 0.16;
	float body = wet + edge;
	if (body < 0.3) {
		discard;
	}
	float deep = smoothstep(0.25, 0.85, m.g / max(wet, 0.001));
	float t = TIME;

	vec2 uv = px / texture_period;
	vec2 wobble1 = vec2(sin(px.y * 0.034 + t * 1.25), cos(px.x * 0.029 + t * 1.05)) * 0.0055;
	vec2 wobble2 = vec2(sin((px.x + px.y) * 0.019 - t * 0.85), cos((px.x - px.y) * 0.017 + t * 0.7)) * 0.0045;

	// Shallow: two copies of the caustic texture drift across each other.
	vec3 s1 = texture(shallow_texture, uv + vec2(t * 0.011, t * 0.006) + wobble1).rgb;
	vec3 s2 = texture(shallow_texture, uv * 0.87 + vec2(-t * 0.008, t * 0.010) + wobble2 + 0.37).rgb;
	float caustic = max(0.0, min(luma(s1), luma(s2)) - 0.42) * 2.4;
	vec3 shallow = mix(s1, s2, 0.5) * 0.92 + vec3(0.75, 0.95, 1.0) * caustic;

	// Deep: slow, dark, broad swells.
	vec3 d1 = texture(deep_texture, uv * 0.72 + vec2(t * 0.004, t * 0.0025) + wobble1 * 0.7).rgb;
	vec3 d2 = texture(deep_texture, uv * 0.58 + vec2(-t * 0.003, t * 0.0045) + wobble2 * 0.7 + 0.61).rgb;
	float swell = sin(px.x * 0.0045 + px.y * 0.0031 - t * 0.55) * 0.5 + 0.5;
	vec3 deep_color = (d1 + d2) * 0.5 + vec3(0.02, 0.05, 0.09) * swell;

	vec3 color = mix(shallow, deep_color, deep);

	// Sun glints: a few soft four-point sparkles twinkling, mostly in shallow water.
	vec2 cell = floor(px / 9.0);
	float h = hash(cell);
	vec2 centre = (cell + 0.25 + 0.5 * vec2(hash(cell + 7.1), hash(cell + 3.7))) * 9.0;
	vec2 d = abs(px - centre);
	float star = max(0.0, 1.0 - length(d) / 2.2) + max(0.0, 1.0 - (d.x * 3.0 + d.y) / 4.5) * 0.5 + max(0.0, 1.0 - (d.y * 3.0 + d.x) / 4.5) * 0.5;
	float twinkle = pow(max(0.0, sin(t * 2.1 + h * 60.0)), 10.0);
	color += vec3(1.0, 0.98, 0.9) * step(0.985, h) * twinkle * star * (1.0 - deep * 0.75) * 0.85;

	// Foam lapping at the shore.
	float shore = 1.0 - smoothstep(0.5, 0.95, body);
	float lap = sin(t * 1.4 + noise(px * 0.02) * 6.2832) * 0.5 + 0.5;
	float foam = shore * smoothstep(0.55, 0.85, noise(px * 0.09 + vec2(t * 0.5, -t * 0.35)) * 0.7 + lap * 0.45);
	color = mix(color, vec3(0.93, 0.98, 1.0), foam * 0.6);

	float alpha = smoothstep(0.3, 0.62, body) * mix(0.82, 0.9, deep);
	if (smooth_water_ground) {
		ivec2 tile = clamp(ivec2(floor(px / tile_size)), ivec2(0), ivec2(grid_size) - 1);
		vec4 own = texelFetch(water_mask, tile, 0);
		if (own.r + own.g > 0.5) {
			// A water tile shows its sheet at px mod 1216 (sheet-wrap), i.e. at uv.
			vec3 ground = mix(texture(shallow_texture, uv).rgb, texture(deep_texture, uv).rgb, deep);
			color = mix(ground, color, alpha);
			alpha = 1.0;
		}
	}
	// COLOR holds the vertex colour (the node's modulate), so fading the node still works.
	COLOR = vec4(color, alpha) * COLOR;
}
