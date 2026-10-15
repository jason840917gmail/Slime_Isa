shader_type canvas_item;
// Canopy sway for the big forest trees (docs/godot/FORESTS.md, docs/assets/AMBIENT_ANIMATION.md).
// Each pixel row shifts sideways by an amount that is 0 up to `hinge` above the tree's foot and
// grows toward the crown, one slow even swing (a ripple travelling up the leaves made big canopies
// wobble like jelly): the trunk and roots stay put, so the tree bends instead of rocking. The
// sprite's origin must be its foot (offset = -foot, as BigTrees.configure sets it). Every tree
// starts at its own phase, taken from where it stands, so one material serves them all (and they
// batch). Real time: presentation only. The sprites use mipmapped filtering (BigTrees.configure),
// or the half-size leaf outlines shimmer as rows shift and the view moves.
//
// The phase is a smooth function of the position, never a hash of it: with the game's pixel
// snapping (world_camera.gd at whole zooms) MODEL_MATRIX's origin moves by a fraction of a pixel
// as the camera moves, and a hash of floor(origin) then jumped every tree to a new random phase
// (the sway "reset" whenever the screen moved). Smooth, a sub-pixel move changes the phase by a
// few hundredths of a radian; neighbouring trees still differ by a radian or more, like gusts
// travelling through the wood.

// Shift at `reach` texture px above the hinge (texture px); taller trees sway a little more.
uniform float amplitude = 4.0;
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
	phase = dot(origin, vec2(0.021, 0.013)) + 2.0 * sin(dot(origin, vec2(0.0071, -0.0093)));
	tint = COLOR;
}

void fragment() {
	float weight = pow(max(height - hinge, 0.0) / reach, 1.4);
	float t = TIME * speed * 6.2831853 + phase;
	float shift = amplitude * weight * sin(t);
	COLOR = texture(TEXTURE, UV - vec2(shift * TEXTURE_PIXEL_SIZE.x, 0.0)) * tint;
}
