// Animated water over the ground layer's water tiles (visual only). A line-for-line port of the
// fragment program in Phaser's features/world/WaterSurfaceLayer.ts:39-109 (the maths live in
// water_surface.gdshaderinc, shared with the shoreline edge tiles; docs/godot/specs/water.md
// section 3), plus one interim step (`smooth_water_ground`, spec 6.1).
//
// One quad covers the water area of the ground layer, drawn by water_surface.gd.
//
// Time is the engine's TIME (real seconds, keeps running through a hit-stop pause, like Phaser's
// `game.loop.getDuration()`). Phaser blends premultiplied (ONE, ONE_MINUS_SRC_ALPHA) with
// `vec4(color * alpha, alpha)`; Godot's default mix blend with `vec4(color, alpha)` gives the
// same pixel.
shader_type canvas_item;

#include "res://game/world/water_surface.gdshaderinc"

// Under a water tile the ground layer draws the raw `water` or `deep-water` sheet with a hard
// edge between them, which shows through the 10-18 % transparent surface as tile steps (Phaser
// drew its blended terrain there). When on, pixels on a water tile composite a smooth ground (the
// same two sheets at the same texel the tile shows, mixed by the deep factor) and draw opaque;
// everything else is unchanged. The shoreline edge tiles draw the same composite.
uniform bool smooth_water_ground = true;

// Pixel position relative to the ground layer's origin (Phaser's `px`, y down).
varying vec2 layer_px;

void vertex() {
	layer_px = VERTEX;
}

void fragment() {
	vec2 px = layer_px;
	float deep;
	vec4 surface = water_surface_at(px, TIME, deep);
	if (surface.a <= 0.0) {
		discard;
	}
	vec3 color = surface.rgb;
	float alpha = surface.a;
	if (smooth_water_ground) {
		ivec2 tile = clamp(ivec2(floor(px / tile_size)), ivec2(0), ivec2(grid_size) - 1);
		vec4 own = texelFetch(water_mask, tile, 0);
		if (own.r + own.g > 0.5) {
			color = mix(water_ground_at(px, deep), color, alpha);
			alpha = 1.0;
		}
	}
	// COLOR holds the vertex colour (the node's modulate), so fading the node still works.
	COLOR = vec4(color, alpha) * COLOR;
}
