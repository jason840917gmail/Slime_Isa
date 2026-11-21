shader_type canvas_item;

// Glimmerhill asleep (docs/godot/VILLAGERS.md "Asleep until its Pearl comes home"; owner 2026-11-19:
// "shader first"): the part of town under this rectangle greyed and darkened. town_sleep.gd draws it
// over the world (above the ground, props and villagers; the HUD is a layer of its own) right after a
// BackBufferCopy, so the screen texture holds everything drawn under it this frame. `strength` 1 is
// fully asleep, 0 untouched (the fade as the part wakes). The rectangle's inner sides (those not on
// the world's edge) fade over `edge_soft` (left, top, right, bottom; 0 = a hard side), and a soft
// circle round the slime keeps its colour (`clear_at`, `clear_radius`; radius 0 = none).
// Works in the Compatibility renderer (WebGL 2): screen texture read with textureLod at level 0.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength = 1.0;
uniform float grey = 0.82;
uniform float darken = 0.42;
uniform vec3 tint = vec3(0.8, 0.86, 1.0);
uniform vec2 rect_size = vec2(2048.0, 2048.0);
uniform vec4 edge_soft = vec4(0.0);
uniform vec2 clear_at = vec2(-100000.0, -100000.0);
uniform float clear_radius = 0.0;
uniform float clear_soft = 30.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float side(float distance_in, float soft) {
	return soft > 0.0 ? clamp(distance_in / soft, 0.0, 1.0) : 1.0;
}

void fragment() {
	vec3 under = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	float luma = dot(under, vec3(0.299, 0.587, 0.114));
	vec3 asleep = mix(under, vec3(luma) * tint, grey) * (1.0 - darken);
	float amount = strength;
	amount *= side(local_pos.x, edge_soft.x) * side(local_pos.y, edge_soft.y);
	amount *= side(rect_size.x - local_pos.x, edge_soft.z) * side(rect_size.y - local_pos.y, edge_soft.w);
	if (clear_radius > 0.0) {
		float away = distance(local_pos, clear_at);
		amount *= smoothstep(max(0.0, clear_radius - clear_soft), clear_radius, away);
	}
	COLOR = vec4(mix(under, asleep, clamp(amount, 0.0, 1.0)), 1.0);
}
