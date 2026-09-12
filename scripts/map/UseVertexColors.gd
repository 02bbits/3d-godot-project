extends Node

func _ready() -> void:
	for child in find_children("*", "MeshInstance3D"):
		for i in child.get_surface_override_material_count():
			var mat = child.get_surface_override_material(i)
			if mat is StandardMaterial3D and not mat.vertex_color_use_as_albedo:
				mat.vertex_color_use_as_albedo = true
		for i in child.mesh.get_surface_count():
			var mat = child.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and not mat.vertex_color_use_as_albedo:
				var dupe = mat.duplicate()
				dupe.vertex_color_use_as_albedo = true
				child.set_surface_override_material(i, dupe)
