// The animated water of Phaser's features/world/WaterSurfaceLayer.ts:39-109, shared by the water
// surface (water_surface.gdshader) and the shoreline edge tiles (terrain_edges/
// terrain_edge_water.gdshader), so both draw the same pixel at the same place. The maths and
// constants are unchanged from Phaser (docs/godot/specs/water.md section 3).
//
// A mask with one texel per tile (r = shallow, g = deep), linearly filtered, says where water is.
// The water ground sheets are re-sampled with a moving refraction, crossing caustics, sun glints
// and shoreline foam; deep water is darker and slower with broad swells. `px` is a pixel position
// relative to the ground layer's origin (Phaser's `px`, y down); `t` is the time in seconds.

// One texel per tile: r = shallow, g = deep (WaterSurfaceLayer.ts:165-181), clamped at the edge.
uniform sampler2D water_mask : filter_linear, repeat_disable;
// The seamless 1216 px water ground sheets, repeating every texture_period world pixels.
uniform sampler2D shallow_texture : filter_linear, repeat_enable;
uniform sampler2D deep_texture : filter_linear, repeat_enable;
// Mask size in tiles (columns, rows).
uniform vec2 grid_size = vec2(1.0, 1.0);
uniform float tile_size = 64.0;
uniform float texture_period = 1216.0;

float water_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float water_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(water_hash(i), water_hash(i + vec2(1.0, 0.0)), f.x), mix(water_hash(i + vec2(0.0, 1.0)), water_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float water_luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// The surface at `px`: rgb = its colour, a = its alpha (0 where Phaser discards: off the water).
// `deep` receives the deep-water factor (0 shallow .. 1 deep) at `px`.
vec4 water_surface_at(vec2 px, float t, out float deep) {
	vec4 m = texture(water_mask, (px / tile_size) / grid_size);
	float wet = m.r + m.g;
	deep = smoothstep(0.25, 0.85, m.g / max(wet, 0.001));
	float edge = water_noise(px * 0.035) * 0.22 + water_noise(px * 0.09) * 0.1 - 0.16;
	float body = wet + edge;
	if (body < 0.3) {
		return vec4(0.0);
	}

	vec2 uv = px / texture_period;
	vec2 wobble1 = vec2(sin(px.y * 0.034 + t * 1.25), cos(px.x * 0.029 + t * 1.05)) * 0.0055;
	vec2 wobble2 = vec2(sin((px.x + px.y) * 0.019 - t * 0.85), cos((px.x - px.y) * 0.017 + t * 0.7)) * 0.0045;

	// Shallow: two copies of the caustic texture drift across each other.
	vec3 s1 = texture(shallow_texture, uv + vec2(t * 0.011, t * 0.006) + wobble1).rgb;
	vec3 s2 = texture(shallow_texture, uv * 0.87 + vec2(-t * 0.008, t * 0.010) + wobble2 + 0.37).rgb;
	float caustic = max(0.0, min(water_luma(s1), water_luma(s2)) - 0.42) * 2.4;
	vec3 shallow = mix(s1, s2, 0.5) * 0.92 + vec3(0.75, 0.95, 1.0) * caustic;

	// Deep: slow, dark, broad swells.
	vec3 d1 = texture(deep_texture, uv * 0.72 + vec2(t * 0.004, t * 0.0025) + wobble1 * 0.7).rgb;
	vec3 d2 = texture(deep_texture, uv * 0.58 + vec2(-t * 0.003, t * 0.0045) + wobble2 * 0.7 + 0.61).rgb;
	float swell = sin(px.x * 0.0045 + px.y * 0.0031 - t * 0.55) * 0.5 + 0.5;
	vec3 deep_color = (d1 + d2) * 0.5 + vec3(0.02, 0.05, 0.09) * swell;

	vec3 color = mix(shallow, deep_color, deep);

	// Sun glints: a few soft four-point sparkles twinkling, mostly in shallow water.
	vec2 cell = floor(px / 9.0);
	float h = water_hash(cell);
	vec2 centre = (cell + 0.25 + 0.5 * vec2(water_hash(cell + 7.1), water_hash(cell + 3.7))) * 9.0;
	vec2 d = abs(px - centre);
	float star = max(0.0, 1.0 - length(d) / 2.2) + max(0.0, 1.0 - (d.x * 3.0 + d.y) / 4.5) * 0.5 + max(0.0, 1.0 - (d.y * 3.0 + d.x) / 4.5) * 0.5;
	float twinkle = pow(max(0.0, sin(t * 2.1 + h * 60.0)), 10.0);
	color += vec3(1.0, 0.98, 0.9) * step(0.985, h) * twinkle * star * (1.0 - deep * 0.75) * 0.85;

	// Foam lapping at the shore.
	float shore = 1.0 - smoothstep(0.5, 0.95, body);
	float lap = sin(t * 1.4 + water_noise(px * 0.02) * 6.2832) * 0.5 + 0.5;
	float foam = shore * smoothstep(0.55, 0.85, water_noise(px * 0.09 + vec2(t * 0.5, -t * 0.35)) * 0.7 + lap * 0.45);
	color = mix(color, vec3(0.93, 0.98, 1.0), foam * 0.6);

	float alpha = smoothstep(0.3, 0.62, body) * mix(0.82, 0.9, deep);
	return vec4(color, alpha);
}

// The water ground under the surface at `px`: the shallow and deep sheets at the texel a water
// tile shows there (sheet-wrap: px mod 1216), mixed by the deep factor.
vec3 water_ground_at(vec2 px, float deep) {
	vec2 uv = px / texture_period;
	return mix(texture(shallow_texture, uv).rgb, texture(deep_texture, uv).rgb, deep);
}
