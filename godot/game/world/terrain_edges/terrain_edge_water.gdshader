shader_type canvas_item;

// The water under a shoreline edge tile (docs/godot/TERRAIN_LAB.md): TerrainEdges fills a dual-grid
// tile with water wherever water is the lowest ground at that corner, then draws the land's edge
// tiles over it. It draws exactly what the water surface draws there (the shared maths of
// water_surface.gdshaderinc, the same mask and sheets, the opaque water ground under it), so the
// shore meets the open water without a seam. Opaque: where the surface does not reach (inside a
// land cell's rounded-off corner) the water ground shows.
//
// Along deep water it also draws the bank (docs/godot/specs/water.md §11): the tile is one of the
// 16 bank shapes (water-bank-shapes.png, by which of the corner's cells are land; r = how far down
// the bank's face, 1 = 0.5 at the waterline, g = the face's sideness and way, b = the bank near),
// and the earth strip runs along the face in world space: along x on a front wall, along y on a
// side wall. The land's edge tiles cover the bank's top. The bank tapers out where the water turns
// shallow, its waterline wobbles, and the surface's own shore foam gives way to foam lapping at
// its foot.

#include "res://game/world/water_surface.gdshaderinc"

// The ground layer's global position: the water mask and sheets are anchored to its cell (0, 0).
uniform vec2 ground_origin = vec2(0.0);
// The bank's earth strip (water-bank-earth.png): periodic along x, the face top to bottom plus
// `bank_foot` of it under the waterline, `bank_density` px a unit. (It repeats along y too, which
// the fragment keeps off: its clear foot would blend into its opaque top.)
uniform sampler2D bank_texture : filter_linear, repeat_enable;
uniform float bank_density = 2.0;
uniform float bank_foot = 0.1;
// Along a side wall the strip runs this many times faster: the wall is seen edge-on.
uniform float bank_side_rate = 2.0;
// The light of a side wall (the light comes from the upper left): with the land on its left it
// faces east, in shade; with the land on its right it faces west, lit. TerrainEdges sets both to
// the cliffs' side light (elevation_sides.gd SHADE_EAST, SHADE_WEST); a front face keeps the
// earth strip's own light.
uniform float bank_shade_east = 0.6;
uniform float bank_shade_west = 1.04;
// The waterline's wobble (a share of the face), the darkening of the water under the bank and the
// strength of the foam at its foot.
uniform float bank_wobble = 0.12;
uniform float bank_shadow = 0.25;
uniform float bank_foam = 0.6;

varying vec2 layer_px;
varying vec4 tint;

void vertex() {
	// TileMapLayer draws in quadrants with their own origins: go through world space.
	layer_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - ground_origin;
	tint = COLOR;
}

void fragment() {
	vec4 shape = texture(TEXTURE, UV);
	float rho = shape.r * 2.0;
	float side_signed = shape.g * 2.0 - 1.0;
	float side = abs(side_signed);
	float wall = smoothstep(0.35, 0.65, side);
	// Deep water only: the deep share of the water around, 1 inside deep water.
	float taper = smoothstep(0.35, 0.85, water_deep_share(water_mask_at(layer_px)));

	float deep;
	vec4 surface = water_surface_shaped(layer_px, TIME, 1.0 - shape.b * taper, 0.0, deep);
	vec3 color = mix(water_ground_at(layer_px, deep), surface.rgb, surface.a);

	// No bank on the land (under its edge tile) or along shallow water.
	float limit = 0.0;
	if (rho > 0.0 && taper > 0.0) {
		limit = taper * (1.0 + bank_wobble * mix(water_line_wobble(layer_px.x), water_line_wobble(layer_px.y + 517.0), wall));
	}
	if (limit > 0.05) {
		float v = rho / limit;
		float along = mix(layer_px.x, layer_px.y, wall);
		// The bank's shadow on the water under it (less under a side wall).
		color *= 1.0 - bank_shadow * (1.0 - smoothstep(1.0, 1.45, v)) * (1.0 - 0.5 * side) * step(1.0, v);
		if (v < 1.0 + bank_foot) {
			vec2 size = vec2(textureSize(bank_texture, 0));
			// Half a texel short of the strip's top and foot: it repeats along x only.
			float tv = clamp(v / (1.0 + bank_foot), 0.5 / size.y, 1.0 - 0.5 / size.y);
			// Only the strip a pixel shows: along x on a front face, along y on a side wall.
			vec4 front_earth = wall < 1.0 ? texture(bank_texture, vec2(layer_px.x * bank_density / size.x, tv)) : vec4(0.0);
			vec4 wall_earth = wall > 0.0 ? texture(bank_texture, vec2(layer_px.y * bank_density * bank_side_rate / size.x, tv)) : vec4(0.0);
			vec4 earth = mix(front_earth, wall_earth, wall);
			float light = mix(1.0, side_signed < 0.0 ? bank_shade_east : bank_shade_west, smoothstep(0.2, 0.8, side));
			color = mix(color, earth.rgb * light, earth.a);
		}
		// Foam lapping at the waterline: broken into patches that come and go along it.
		color = mix(color, WATER_FOAM, water_line_foam(along, v, TIME) * bank_foam);
	}
	COLOR = vec4(color, shape.a) * tint;
}
