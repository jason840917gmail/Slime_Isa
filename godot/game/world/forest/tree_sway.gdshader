shader_type canvas_item;
// Canopy sway for the big forest trees (docs/godot/FORESTS.md, docs/assets/AMBIENT_ANIMATION.md).
// Each pixel row shifts sideways by an amount that is 0 up to `hinge` above the tree's foot and
// grows toward the crown, plus a small ripple travelling up through the leaves: the trunk and roots
// stay put, so the tree bends instead of rocking. The sprite's origin must be its foot (offset =
// -foot, as ForestLayer and the forest tree scenes set it). Every tree starts at its own phase,
// taken from where it stands, so one material serves them all (and they batch). Real time:
// presentation only.

// Shift at `reach` texture px above the hinge (texture px); taller trees sway a little more.
uniform float amplitude = 5.0;
// Texture px above the foot where the bend starts (the visible trunk).
uniform float hinge = 70.0;
uniform float reach = 400.0;
// Sway cycles per second.
uniform float speed = 0.3;

varying float height;
varying float phase;
varying vec4 tint;

void vertex() {
	height = -VERTEX.y;
	vec2 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	phase = fract(sin(dot(floor(origin), vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
	tint = COLOR;
}

void fragment() {
	float weight = pow(max(height - hinge, 0.0) / reach, 1.4);
	float t = TIME * speed * 6.2831853 + phase;
	float shift = amplitude * weight * (sin(t) + 0.25 * sin(2.0 * t + height * 0.03));
	COLOR = texture(TEXTURE, UV - vec2(shift * TEXTURE_PIXEL_SIZE.x, 0.0)) * tint;
}
