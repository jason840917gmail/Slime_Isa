shader_type canvas_item;

// The water under a shoreline edge tile (docs/godot/TERRAIN_LAB.md): TerrainEdges fills a dual-grid
// tile with water wherever water is the lowest ground at that corner, then draws the land's edge
// tiles over it. It draws exactly what the water surface draws there (the shared maths of
// water_surface.gdshaderinc, the same mask and sheets, the opaque water ground under it), so the
// shore meets the open water without a seam. Opaque: where the surface does not reach (inside a
// land cell's rounded-off corner) the water ground shows.

#include "res://game/world/water_surface.gdshaderinc"

// The ground layer's global position: the water mask and sheets are anchored to its cell (0, 0).
uniform vec2 ground_origin = vec2(0.0);

varying vec2 layer_px;
varying vec4 tint;

void vertex() {
	// TileMapLayer draws in quadrants with their own origins: go through world space.
	layer_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - ground_origin;
	tint = COLOR;
}

void fragment() {
	float deep;
	vec4 surface = water_surface_at(layer_px, TIME, deep);
	vec3 color = mix(water_ground_at(layer_px, deep), surface.rgb, surface.a);
	COLOR = vec4(color, texture(TEXTURE, UV).a) * tint;
}
