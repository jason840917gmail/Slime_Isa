extends SceneTree
## Debug: draws the elevation's Sides meshes in false colours by piece kind (vertex colour r):
## wall red (side share: more yellow), corner stone green, foot blue (water cyan), lower fill grey,
## top fill white, top edge magenta; half see-through so overlaps show (ALPHA env, default 0.55).
var _t := 0.0
var _done := false
const SHADER := """
shader_type canvas_item;
uniform float alpha = 0.55;
varying vec4 c;
void vertex() { c = COLOR; }
void fragment() {
	float k = c.r;
	vec3 col;
	if (k < 0.25) col = mix(vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), k / 0.2);
	else if (k < 0.4) col = vec3(0.0, 1.0, 0.0);
	else if (k < 0.52) col = vec3(0.0, 0.2, 1.0);
	else if (k < 0.57) col = vec3(0.0, 1.0, 1.0);
	else if (k < 0.65) col = vec3(0.4);
	else if (k < 0.8) col = vec3(1.0);
	else col = vec3(1.0, 0.0, 1.0);
	// a back edge (b 1) darker
	if (k > 0.45 && k < 0.57 && c.b > 0.5) col *= 0.4;
	if (k < 0.25) {
		// fibres: stripes along u; courses: lines across v
		float fu = fract(UV.x / 24.0);
		float fv = fract(UV.y / 32.0);
		col = mix(col * 0.5, vec3(1.0), step(0.85, fu)) ;
		col = mix(col, vec3(0.0, 0.0, 0.0), step(0.9, fv));
	}
	COLOR = vec4(col, alpha);
}
"""

func _initialize() -> void:
	change_scene_to_file.call_deferred("res://game/dev/playground.tscn")

func _process(delta: float) -> bool:
	_t += delta
	if not _done and _t > 1.5:
		_done = true
		var sh := Shader.new()
		sh.code = SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		var a := OS.get_environment("ALPHA")
		mat.set_shader_parameter(&"alpha", float(a) if not a.is_empty() else 0.55)
		for e: Node in get_root().find_children("Elevation", "", true, false):
			var sides := e.get_node_or_null(^"Sides")
			if sides == null:
				continue
			for c: Node in sides.get_children():
				if c is MeshInstance2D:
					(c as MeshInstance2D).material = mat
	return false
