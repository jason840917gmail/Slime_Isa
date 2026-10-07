shader_type canvas_item;

// Water at the foot of a cliff wall (docs/godot/ELEVATION.md): Elevation lays this strip along
// every wall foot whose ground is water. The water laps back and forth against the wall: its line
// rises and falls on the rock in a travelling wave, a band of foam rides on it, and the rock it just
// left stays dark and wet. The water itself is the water surface's own (water_surface.gdshaderinc:
// the same mask, sheets and maths), sampled just in front of the wall, so the strip meets the
// open water without a seam. UV.y = height above the foot line (world units, up the wall).

#include "res://game/world/water_surface.gdshaderinc"
#include "res://game/world/elevation/elevation_light.gdshaderinc"

// The ground layer's global position: the water mask and sheets are anchored to its cell (0, 0).
uniform vec2 ground_origin = vec2(0.0);
// The water line on the wall: its mean height, how far it rises and falls, and the wave.
uniform float line_height = 7.0;
uniform float swing = 6.0;
uniform float wave_speed = 1.4;
uniform float wave_length = 150.0;
// Foam on the line and the wet rock above it (world units).
uniform float foam_width = 3.5;
uniform float wet_height = 14.0;
uniform float wet_darkening = 0.45;

varying vec2 layer_px;
varying float level;

void vertex() {
	layer_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - ground_origin;
	level = decode_level(COLOR.a);
}

void fragment() {
	float h = UV.y;
	float x = layer_px.x;
	float t = TIME;
	// Two waves along the wall so the swell never looks like one sliding sine.
	float phase = x / wave_length * 6.2832;
	float wave = sin(t * wave_speed - phase) * 0.65 + sin(t * wave_speed * 0.57 + phase * 1.7 + 1.3) * 0.35;
	float lap = line_height + swing * wave + (water_noise(vec2(x * 0.08, t * 0.6)) - 0.5) * 2.0;
	// The highest the water reached lately (wet rock), lagging behind the wave.
	float reach = line_height + swing + (water_noise(vec2(x * 0.03, t * 0.2)) - 0.5) * 3.0;

	// The water in front of the wall foot, mirrored below the foot line (what the surface draws
	// there), so the strip's water moves like the open water and has no streaks.
	float foot_y = layer_px.y + h;
	vec2 sample_px = vec2(x, foot_y + 14.0 + h);
	float deep;
	vec4 surface = water_surface_at(sample_px, t, deep);
	vec3 water = mix(water_ground_at(sample_px, deep), surface.rgb, max(surface.a, 0.6));
	water *= level_light(level);

	float under = 1.0 - smoothstep(lap - 1.0, lap + 1.0, h);
	float foam_line = 1.0 - smoothstep(0.0, foam_width, abs(h - lap));
	float bubbles = smoothstep(0.62, 0.78, water_noise(vec2(x * 0.16, h * 0.3 - t * 1.2))) * (1.0 - smoothstep(0.0, foam_width * 3.0, lap - h)) * under;
	float foam = clamp(foam_line * (0.55 + 0.45 * water_noise(vec2(x * 0.15 + t, t * 0.8))) + bubbles * 0.35, 0.0, 1.0);
	vec3 colour = mix(water, vec3(0.93, 0.98, 1.0), foam);
	float alpha = max(under * 0.94, foam * (1.0 - smoothstep(lap, lap + foam_width, h)));
	// Below the foot line the strip hands over to the open water drawn under it.
	alpha *= smoothstep(-10.0, -4.0, h);

	// Wet rock above the line: darken whatever is under the strip.
	float wet = (1.0 - under) * (1.0 - smoothstep(lap, max(reach, lap) + wet_height, h)) * wet_darkening;
	float out_alpha = alpha + wet * (1.0 - alpha);
	vec3 out_rgb = out_alpha > 0.0 ? colour * alpha / out_alpha : vec3(0.0);
	COLOR = vec4(out_rgb, out_alpha);
}
