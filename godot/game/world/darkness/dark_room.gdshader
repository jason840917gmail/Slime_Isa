// A dark room's darkness (game/world/darkness/dark_room.gd; docs/godot/DARKNESS.md): one overlay over
// the room's rectangle, dark everywhere but in soft holes around up to MAX_LIGHTS light sources.
// Lights are in the overlay's local pixels (x, y, radius). Compatibility renderer (WebGL 2) safe:
// a fixed-size uniform array and a loop bounded by a constant.
shader_type canvas_item;

const int MAX_LIGHTS = 16;

uniform vec4 lights[16];
uniform int light_count = 0;
// The darkness where no light reaches (0..1).
uniform float darkness : hint_range(0.0, 1.0) = 0.92;
// How far inside its radius a light starts to fade (px).
uniform float soft_px = 40.0;
// The darkness's colour, and the warm tint at the edge of a lit hole.
uniform vec3 dark_color : source_color = vec3(0.02, 0.02, 0.05);
uniform vec3 warm_color : source_color = vec3(1.0, 0.55, 0.2);
uniform float warm_share = 0.12;
// The room's own fade: 1 dark, 0 lit for good.
uniform float fade = 1.0;
// The overlay's size in px (the soft border at the rectangle's edge).
uniform vec2 size = vec2(256.0, 256.0);
uniform float edge_px = 24.0;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	float lit = 0.0;
	float warm = 0.0;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) {
			break;
		}
		vec4 light = lights[i];
		float radius = max(light.z, 1.0);
		float d = distance(local_px, light.xy);
		float inner = max(radius - soft_px, radius * 0.35);
		float hole = 1.0 - smoothstep(inner, radius, d);
		lit = max(lit, hole);
		// A warm rim just inside the edge of each hole.
		warm = max(warm, hole * (1.0 - hole) * 4.0);
	}
	vec2 to_edge = min(local_px, size - local_px);
	float border = smoothstep(0.0, edge_px, min(to_edge.x, to_edge.y));
	float alpha = darkness * (1.0 - lit) * fade * border;
	vec3 color = mix(dark_color, warm_color, warm * warm_share);
	COLOR = vec4(color, alpha + warm * warm_share * 0.5 * fade * border * (1.0 - lit * 0.5));
}
