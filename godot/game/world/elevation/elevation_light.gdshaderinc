// Light by height (docs/godot/ELEVATION.md), shared by the elevation shaders: the ground of a
// hole and the lower courses of its walls get darker with every level of depth, so a pit reads
// as deep; level 0 and above keep their colour.

const float DEPTH_DARKEN = 0.13;
const float DARKEST = 0.5;

float level_light(float level) {
	return level < 0.0 ? max(DARKEST, 1.0 + DEPTH_DARKEN * level) : 1.0;
}

// Levels travel in vertex colours as (level + 4) / 8.
float decode_level(float channel) {
	return channel * 8.0 - 4.0;
}
