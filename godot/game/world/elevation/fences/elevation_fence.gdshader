shader_type canvas_item;

// A fence along a hill's rim (docs/godot/FENCES.md), drawn by elevation_fences.gd in pieces that
// Y-sort with bodies. Posts come from `posts_texture` (UV = px of the atlas), rails from
// `rails_texture` (UV = (world x · 2, row px): it repeats along every front and diagonal run, which
// shears it) and the upper rail seen from above from `side_texture` (UV = (column px, ground y · 2),
// east and west runs). Vertex colour: r = shade (the way the run's face looks), g = how far the
// point lies below its piece's foot line ((dy + 128) / 512 world units, as the depth map), b = kind
// (0 post, 0.5 rails, 1 side), a = level ((level + 4) / 8, elevation_light.gdshaderinc). A fence
// pixel behind nearer terrain (a higher hill in front of it) is not drawn; fences in holes darken
// with depth like the cliffs.

#include "res://game/world/elevation/elevation_light.gdshaderinc"
#include "res://game/world/elevation/elevation_occlusion.gdshaderinc"

uniform sampler2D posts_texture : source_color, filter_linear;
uniform sampler2D rails_texture : source_color, repeat_enable, filter_linear;
uniform sampler2D side_texture : source_color, repeat_enable, filter_linear;
uniform vec2 posts_size = vec2(1.0);
uniform vec2 rails_size = vec2(1.0);
uniform vec2 side_size = vec2(1.0);

varying vec4 data;

void vertex() {
	data = COLOR;
	elevation_world = elevation_world_position(VERTEX, MODEL_MATRIX);
}

void fragment() {
	vec4 art;
	if (data.b < 0.25) {
		art = texture(posts_texture, UV / posts_size);
	} else if (data.b < 0.75) {
		art = texture(rails_texture, UV / rails_size);
	} else {
		art = texture(side_texture, UV / side_size);
	}
	float level = floor(decode_level(data.a) + 0.5);
	if (elevation_rect.z > 0.0) {
		float dy = data.g * 512.0 - 128.0;
		float depth = elevation_world.y - dy + level * ELEVATION_LEVEL_UNITS;
		if (elevation_terrain_depth(elevation_world) > depth + ELEVATION_MARGIN) {
			discard;
		}
	}
	COLOR = vec4(art.rgb * data.r * level_light(level), art.a);
}
