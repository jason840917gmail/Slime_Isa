// The goo inside a HUD console orb (game/ui/console/goo_orb.gd): a glass globe filled up to `level`
// with a gradient goo, a wobbling surface with a bright rim, bubbles rising and a highlight at the
// upper left. Drawn on a square ColorRect; `radius` is the globe's radius in UV (0.5 = the edge).
shader_type canvas_item;

uniform float level : hint_range(0.0, 1.0) = 1.0;
uniform vec4 top_color : source_color = vec4(1.0, 0.5, 0.47, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.59, 0.09, 0.19, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.77, 0.73, 1.0);
uniform vec4 glass_color : source_color = vec4(0.08, 0.106, 0.118, 0.88);
uniform float radius = 0.48;
uniform float seed = 0.0;

float hash(float n) {
	return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p) / radius;
	float inside = 1.0 - smoothstep(0.985, 1.0, d);
	float x = p.x / radius;
	float surface = 0.5 + radius - 2.0 * radius * level
		+ (sin(x * 5.0 + TIME * 1.6 + seed) * 0.012 + sin(x * 1.7 - TIME * 1.1) * 0.01) * radius * 2.0;
	float liquid = step(surface, UV.y) * step(0.001, level);
	float t = clamp((UV.y - (0.5 - radius)) / (2.0 * radius), 0.0, 1.0);
	vec3 goo = mix(top_color.rgb, bottom_color.rgb, t);
	goo *= 1.0 - 0.5 * pow(clamp(d, 0.0, 1.0), 3.0);
	goo *= 1.0 + 0.22 * clamp(-(p.x + p.y) / (radius * 1.4), -1.0, 1.0);
	// Bubbles rising from the bottom to the surface.
	float bubbles = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float speed = 0.05 + 0.06 * hash(fi + 3.0);
		float rise = fract(hash(fi + 7.0) + TIME * speed);
		vec2 c = vec2(0.5 + (hash(fi) - 0.5) * radius * 1.3, mix(0.5 + radius * 0.9, surface, rise));
		float r = radius * (0.03 + 0.05 * hash(fi + 11.0));
		float ring = 1.0 - smoothstep(0.0, r * 0.35, abs(length(UV - c) - r));
		bubbles = max(bubbles, ring * step(c.y, 0.5 + radius) * step(surface + r, c.y));
	}
	goo = mix(goo, rim_color.rgb, bubbles * 0.6);
	vec3 glass = glass_color.rgb * (1.0 - 0.35 * d * d);
	vec3 color = mix(glass, goo, liquid);
	float meniscus = (1.0 - smoothstep(0.0, radius * 0.05, abs(UV.y - surface))) * step(0.001, level) * step(level, 0.999);
	color = mix(color, rim_color.rgb, meniscus * 0.65);
	vec2 h = (p - vec2(-0.36, -0.42) * radius) / (vec2(0.30, 0.17) * radius);
	color = mix(color, vec3(1.0), 0.55 * exp(-dot(h, h)));
	COLOR = vec4(color, mix(glass_color.a, 1.0, liquid) * inside);
}
