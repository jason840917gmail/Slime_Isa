extends RefCounted
## Triangles of one elevation mesh being built (docs/godot/ELEVATION.md): positions, UVs and vertex
## colours, appended three at a time. Packed arrays only grow in place through their owner, so the
## builders keep these objects in dictionaries and add through `add`.
##
## Owner: world (elevation).

var vertices := PackedVector2Array()
var uvs := PackedVector2Array()
var colors := PackedColorArray()


func add(vertex: Vector2, uv: Vector2, color: Color) -> void:
	vertices.append(vertex)
	uvs.append(uv)
	colors.append(color)


## One triangle with the same UV and colour at its three corners.
func add_flat(points: PackedVector2Array, uv: Vector2, color: Color) -> void:
	for point in points:
		add(point, uv, color)


func is_empty() -> bool:
	return vertices.is_empty()


func to_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
