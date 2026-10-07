shader_type canvas_item;
render_mode blend_disabled;

// A fence's silhouette in the terrain's depth map (docs/godot/FENCES.md; elevation_fences.gd hands
// it to ElevationOcclusion.add_occluder). The vertex colour is the depth texel
// (ElevationOcclusion.encode: the fence's level and how far above its foot line the point is), drawn
// only where the fence's art is opaque, so a body shows through the gaps between the rails. Its
// alpha is written as 0.5 (no blending): the mark of a fence, which cuts a body behind it out
// instead of ghosting it (elevation_occlusion.gdshaderinc). UV as elevation_fence.gdshader's, moved
// by -uv_offset in y for rails and in x for side rails.

uniform sampler2D posts_texture : filter_nearest;
uniform sampler2D rails_texture : filter_nearest, repeat_enable;
uniform sampler2D side_texture : filter_nearest, repeat_enable;
uniform vec2 posts_size = vec2(1.0);
uniform vec2 rails_size = vec2(1.0);
uniform vec2 side_size = vec2(1.0);
uniform float uv_offset = 10000.0;
const float FENCE_MARK = 0.5;

varying vec4 texel;

void vertex() {
	texel = COLOR;
}

void fragment() {
	float alpha;
	if (UV.y < -0.5 * uv_offset) {
		alpha = texture(rails_texture, vec2(UV.x, UV.y + uv_offset) / rails_size).a;
	} else if (UV.x < -0.5 * uv_offset) {
		alpha = texture(side_texture, vec2(UV.x + uv_offset, UV.y) / side_size).a;
	} else {
		alpha = texture(posts_texture, UV / posts_size).a;
	}
	if (alpha < 0.5) {
		discard;
	}
	COLOR = vec4(texel.rgb, FENCE_MARK);
}
