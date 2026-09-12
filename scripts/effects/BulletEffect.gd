class_name BulletEffect


static func spawn(parent: Node3D, pos: Vector3, color: Color) -> void:
	_spawn_light(parent, pos, color)
	_spawn_flash(parent, pos, color)
	_spawn_debris(parent, pos, color)
	_spawn_smoke(parent, pos)


static func _spawn_light(parent: Node3D, pos: Vector3, color: Color) -> void:
	var light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 12.0
	light.omni_range = 7.0
	parent.add_child(light)
	light.global_position = pos

	var tween = parent.create_tween()
	tween.tween_property(light, "light_energy", 14.0, 0.05)
	tween.tween_property(light, "light_energy", 0.0, 0.65).set_ease(Tween.EASE_OUT)
	tween.tween_callback(light.queue_free)


static func _spawn_flash(parent: Node3D, pos: Vector3, color: Color) -> void:
	var flash = MeshInstance3D.new()
	flash.mesh = SphereMesh.new()
	flash.scale = Vector3.ONE * 0.15
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 8.0
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = mat

	parent.add_child(flash)
	flash.global_position = pos

	var tween = parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * randf_range(1.2, 1.8), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.3).set_delay(0.05)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.3).set_delay(0.05)
	tween.chain().tween_callback(flash.queue_free)


static func _spawn_debris(parent: Node3D, pos: Vector3, color: Color) -> void:
	for i in 28:
		var node = MeshInstance3D.new()
		node.mesh = SphereMesh.new()
		var start_scale = randf_range(0.04, 0.14)
		node.scale = Vector3.ONE * start_scale
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 6.0
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		node.material_override = mat

		parent.add_child(node)
		node.global_position = pos

		var dir = Vector3(randf_range(-1, 1), randf_range(-1, 1) * 0.6 + 0.3, randf_range(-1, 1)).normalized()
		var dist = randf_range(0.6, 2.2)
		var duration = randf_range(0.5, 0.9)
		var delay = randf_range(0.0, 0.08)

		var tween = parent.create_tween()
		tween.set_parallel(true)
		tween.tween_interval(delay)
		tween.tween_property(node, "global_position", pos + dir * dist, duration).set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(node, "scale", Vector3.ONE * start_scale * 0.2, duration).set_delay(delay).set_ease(Tween.EASE_IN)
		tween.tween_property(mat, "emission_energy_multiplier", 0.0, duration * 0.8).set_delay(delay + duration * 0.2)
		tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.6).set_delay(delay + duration * 0.4)
		tween.chain().tween_callback(node.queue_free)


static func _spawn_smoke(parent: Node3D, pos: Vector3) -> void:
	for i in 6:
		var smoke = MeshInstance3D.new()
		smoke.mesh = SphereMesh.new()
		smoke.scale = Vector3.ONE * randf_range(0.15, 0.3)
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.2, 0.2, 0.5)
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		smoke.material_override = mat

		parent.add_child(smoke)
		smoke.global_position = pos + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.3), randf_range(-0.2, 0.2))

		var smoke_dir = Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)).normalized()
		var tween = parent.create_tween()
		tween.set_parallel(true)
		tween.tween_property(smoke, "global_position", smoke.global_position + smoke_dir * randf_range(0.5, 1.2), 1.0).set_ease(Tween.EASE_OUT)
		tween.tween_property(smoke, "scale", smoke.scale * 2.0, 1.0)
		tween.tween_property(mat, "albedo_color:a", 0.0, 1.0)
		tween.chain().tween_callback(smoke.queue_free)
