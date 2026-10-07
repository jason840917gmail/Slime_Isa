// Hiding a body behind higher ground (docs/godot/ELEVATION.md), for the shaders of bodies that walk
// the world (hit_flash.gdshader, form_skin.gdshader). Elevation (elevation_occlusion.gd) renders the
// terrain's depth once into `elevation_depth` and sets these uniforms on every tracked body; without
// them (no elevation in the world) nothing changes.
//
// Depth is the ground position (world y) of what a pixel shows, as in 3D with the camera looking
// north and down: ground of level L at screen y lies at y + 64·L; a wall shows its plane, the
// depth of its top edge. A body's pixel is hidden where the terrain drawn at it is nearer (deeper)
// than the body's feet by more than a margin: a hill hides a body walking behind it, a hole's near
// rim hides a body under it. A hidden pixel shows as a ghost: the body's own colour mixed with
// `elevation_silhouette_color`, at `elevation_silhouette` opacity (the player's ghost is stronger).
//
// Texel: r = level ((L + 4) / 8), g = (dy + 128) / 512 where depth = y − dy + 64·L (dy: how far
// below the wall's top edge, or past a rim's edge), b = 1 terrain, 0.5 a structure (stairs: it hides
// like terrain; the cast shadows read its height, level − dy / 64), 0 = level-0 ground (outside the
// map's elevated part). a = 0.5 marks a fence (fences/elevation_fences.gd, docs/godot/FENCES.md): a
// body behind one is cut out where the fence stands instead of ghosted, so the fence shows in front
// of it whichever of the two Y-sorts first (a body behind a fence on higher ground sorts after it).
//
// The including shader sets `elevation_world` in vertex() (`elevation_world_position(VERTEX,
// MODEL_MATRIX)`) and passes its colour through `elevation_occlude(COLOR)` last in fragment().

uniform sampler2D elevation_depth : filter_nearest, repeat_disable;
// World rect the depth map covers: origin xy, size zw (zw = 0: no elevation).
uniform vec4 elevation_rect = vec4(0.0);
// The body's depth: its feet's world y + 64 · its level.
uniform float elevation_body_depth = 0.0;
uniform float elevation_silhouette = 0.0;
uniform vec4 elevation_silhouette_color : source_color = vec4(0.28, 0.36, 0.55, 1.0);
// How much of the tint the ghost takes (the rest is the body's own colour).
const float ELEVATION_GHOST_TINT = 0.45;

const float ELEVATION_LEVEL_UNITS = 64.0;
// Terrain only hides a body's pixel when it is nearer than its feet by more than this (the sprite
// reaches a little below its feet).
const float ELEVATION_MARGIN = 12.0;

varying vec2 elevation_world;

vec2 elevation_world_position(vec2 vertex, mat4 model) {
	return (model * vec4(vertex, 0.0, 1.0)).xy;
}

// The depth of the terrain drawn at `world`; a huge negative value where it never hides anything.
float elevation_terrain_depth(vec2 world) {
	vec2 uv = (world - elevation_rect.xy) / elevation_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return world.y;
	}
	vec4 texel = texture(elevation_depth, uv);
	if (texel.b < 0.25) {
		return world.y;
	}
	float level = floor(texel.r * 8.0 - 4.0 + 0.5);
	float dy = texel.g * 512.0 - 128.0;
	return world.y - dy + level * ELEVATION_LEVEL_UNITS;
}

// True when what is drawn at `world` in the depth map is a fence (texel alpha 0.5).
bool elevation_is_fence(vec2 world) {
	vec2 uv = (world - elevation_rect.xy) / elevation_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return false;
	}
	float alpha = texture(elevation_depth, uv).a;
	return alpha > 0.25 && alpha < 0.75;
}

vec4 elevation_occlude(vec4 color) {
	if (elevation_rect.z <= 0.0) {
		return color;
	}
	if (elevation_terrain_depth(elevation_world) <= elevation_body_depth + ELEVATION_MARGIN) {
		return color;
	}
	if (elevation_is_fence(elevation_world)) {
		return vec4(color.rgb, 0.0);
	}
	vec3 ghost = mix(color.rgb, elevation_silhouette_color.rgb, ELEVATION_GHOST_TINT);
	return vec4(ghost, color.a * elevation_silhouette);
}
