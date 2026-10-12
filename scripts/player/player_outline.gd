class_name PlayerOutline
extends RefCounted

## The outline around opponents: the robot meshes of remote copies get an
## inverted-hull overlay (resources/ui/player_outline.tres, shader
## scripts/player/shader/outline.gdshader); your own copy never does.
## The robot is flat-shaded, so each mesh is swapped for a cached copy whose
## TANGENT holds the smoothed normal (the average over vertices sharing a
## position) for the hull to grow along. The robot uses no normal maps, so
## its tangents are free; skinning moves them like normals.

const MATERIAL := preload("res://resources/ui/player_outline.tres")
const WELD := 0.0001 # vertices closer than this share a smoothed normal

static var _smoothed := {} # source mesh -> copy with smoothed normals in TANGENT


## Shows or hides the outline on every robot mesh under `model` (the gun in
## the hand is outside it).
static func set_enabled(model: Node, enabled: bool) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if enabled:
			mesh_instance.mesh = _smoothed_copy(mesh_instance.mesh)
		mesh_instance.material_overlay = MATERIAL if enabled else null


static func _smoothed_copy(mesh: Mesh) -> Mesh:
	if not (mesh is ArrayMesh) or _smoothed.values().has(mesh):
		return mesh
	if _smoothed.has(mesh):
		return _smoothed[mesh]
	var source := mesh as ArrayMesh
	var copy := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		arrays[Mesh.ARRAY_TANGENT] = _smoothed_normals(arrays[Mesh.ARRAY_VERTEX],
				arrays[Mesh.ARRAY_NORMAL])
		copy.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], {},
				source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		copy.surface_set_material(surface, source.surface_get_material(surface))
		copy.surface_set_name(surface, source.surface_get_name(surface))
	_smoothed[mesh] = copy
	return copy


# tangent array (x, y, z, w per vertex) holding each vertex's smoothed normal
static func _smoothed_normals(vertices: PackedVector3Array,
		normals: PackedVector3Array) -> PackedFloat32Array:
	var sums := {}
	for i in vertices.size():
		var key := vertices[i].snapped(Vector3.ONE * WELD)
		sums[key] = sums.get(key, Vector3.ZERO) + normals[i]
	var tangents := PackedFloat32Array()
	tangents.resize(vertices.size() * 4)
	for i in vertices.size():
		var smooth: Vector3 = sums[vertices[i].snapped(Vector3.ONE * WELD)].normalized()
		if smooth.is_zero_approx():
			smooth = normals[i]
		tangents[i * 4] = smooth.x
		tangents[i * 4 + 1] = smooth.y
		tangents[i * 4 + 2] = smooth.z
		tangents[i * 4 + 3] = 1.0
	return tangents
