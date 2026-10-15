shader_type canvas_item;
// The door iris (game/world/iris_transition.gd): a full-screen colour with a round hole of
// `radius` screen units centred on `centre`. UV * `rect_size` is the fragment's position on the
// rect, so the hole stays round on any window shape. Compatibility renderer / WebGL 2 safe.

uniform vec4 colour : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec2 centre = vec2(512.0, 512.0);
uniform vec2 rect_size = vec2(1024.0, 1024.0);
uniform float radius = 4096.0;
// Width of the anti-aliased rim, in screen units.
uniform float softness = 1.5;

void fragment() {
	float d = distance(UV * rect_size, centre);
	float cover = smoothstep(radius - softness, radius + softness, d);
	COLOR = vec4(colour.rgb, colour.a * cover);
}
