class_name MuzzleEffect


# ============================================================================
# PLASMA MUZZLE EFFECT
# ============================================================================
#
# All visual elements use the SAME fade curve.
#
# Fade curve:
#
#       1.0 ─────╮
#               │╲
#               │ ╲
#               │  ╲
#               │   ╲____
#       0.0 ───────────────
#
# Quintic smoothstep:
#
#     6t^5 - 15t^4 + 10t^3
#
# This gives:
#
#     - smooth beginning
#     - smooth middle
#     - smooth ending
#     - no abrupt final disappearance
#
# ============================================================================


# ============================================================================
# MAIN
# ============================================================================

static func spawn(
	parent: Node3D,
	pos: Vector3,
	forward: Vector3
) -> void:

	forward = forward.normalized()

	_spawn_light(parent, pos)
	_spawn_core(parent, pos, forward)
	_spawn_corona(parent, pos, forward)
	_spawn_shock_ring(parent, pos, forward)
	_spawn_energy_filaments(parent, pos, forward)
	_spawn_plasma_particles(parent, pos, forward)


# ============================================================================
# SHARED SMOOTH FADE
# ============================================================================

static func _smooth_fade(t: float) -> float:
	"""
	Quintic smoothstep.

	0.0 -> 1.0

	Starts slowly.
	Accelerates naturally.
	Ends slowly.

	This is used by every effect element.
	"""

	t = clampf(t, 0.0, 1.0)

	return 6.0 * pow(t, 5.0) \
		- 15.0 * pow(t, 4.0) \
		+ 10.0 * pow(t, 3.0)


static func _fade_value(
	start_value: float,
	end_value: float,
	t: float
) -> float:

	var curve := _smooth_fade(t)

	return lerpf(
		start_value,
		end_value,
		curve
	)


# ============================================================================
# LIGHT
# ============================================================================

static func _spawn_light(
	parent: Node3D,
	pos: Vector3
) -> void:

	var light := OmniLight3D.new()

	light.light_color = Color(
		0.35,
		0.82,
		1.0
	)

	light.light_energy = 8.0
	light.omni_range = 4.5

	parent.add_child(light)
	light.global_position = pos

	var duration := 0.28

	var tween := parent.create_tween()

	# Fade the light using exactly the same curve.
	tween.tween_method(
		func(t: float) -> void:
			light.light_energy = _fade_value(
				8.0,
				0.0,
				t
			),
		0.0,
		1.0,
		duration
	)

	tween.tween_callback(
		light.queue_free
	)


# ============================================================================
# MAIN PLASMA CORE
# ============================================================================

static func _spawn_core(
	parent: Node3D,
	pos: Vector3,
	forward: Vector3
) -> void:

	var core := MeshInstance3D.new()

	var sphere := SphereMesh.new()

	sphere.radius = 0.075
	sphere.height = 0.15

	sphere.radial_segments = 16
	sphere.rings = 8

	core.mesh = sphere

	core.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)

	var mat := _create_plasma_material(
		Color(0.72, 0.96, 1.0),
		35.0
	)

	core.material_override = mat

	parent.add_child(core)

	core.global_position = pos

	core.look_at(
		pos + forward,
		Vector3.UP
	)


	# ------------------------------------------------------------
	# INITIAL SIZE
	# ------------------------------------------------------------

	core.scale = Vector3(
		0.25,
		0.25,
		0.18
	)


	var tween := parent.create_tween()


	# ------------------------------------------------------------
	# EXPANSION
	#
	# This happens quickly, but the fade itself remains smooth.
	# ------------------------------------------------------------

	tween.tween_method(
		func(t: float) -> void:

			var curve := _smooth_fade(t)

			var size = lerp(
				0.25,
				0.70,
				curve
			)

			var depth = lerp(
				0.18,
				0.48,
				curve
			)

			core.scale = Vector3(
				size,
				size,
				depth
			),

		0.0,
		1.0,
		0.025
	)


	# ------------------------------------------------------------
	# CONTRACT
	# ------------------------------------------------------------

	tween.tween_method(
		func(t: float) -> void:

			var curve := _smooth_fade(t)

			var size = lerp(
				0.70,
				0.45,
				curve
			)

			var depth = lerp(
				0.48,
				0.30,
				curve
			)

			core.scale = Vector3(
				size,
				size,
				depth
			),

		0.0,
		1.0,
		0.055
	)


	# ------------------------------------------------------------
	# FINAL SMOOTH FADE
	# ------------------------------------------------------------

	tween.tween_method(
		func(t: float) -> void:

			var curve := _smooth_fade(t)

			var size = lerp(
				0.45,
				0.01,
				curve
			)

			var depth = lerp(
				0.30,
				0.01,
				curve
			)

			core.scale = Vector3(
				size,
				size,
				depth
			)

			mat.emission_energy_multiplier = lerp(
				35.0,
				0.0,
				curve
			),

		0.0,
		1.0,
		0.20
	)


	tween.tween_callback(
		core.queue_free
	)


# ============================================================================
# CORONA
# ============================================================================

static func _spawn_corona(
	parent: Node3D,
	pos: Vector3,
	forward: Vector3
) -> void:

	var corona := MeshInstance3D.new()

	var sphere := SphereMesh.new()

	sphere.radius = 0.11
	sphere.height = 0.22

	sphere.radial_segments = 16
	sphere.rings = 8

	corona.mesh = sphere

	corona.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)

	var mat := _create_plasma_material(
		Color(0.18, 0.70, 1.0),
		24.0
	)

	corona.material_override = mat

	parent.add_child(corona)

	corona.global_position = pos

	corona.look_at(
		pos + forward,
		Vector3.UP
	)

	corona.scale = Vector3(
		0.12,
		0.12,
		0.20
	)


	var tween := parent.create_tween()


	# Small bloom.
	tween.tween_method(
		func(t: float) -> void:

			var curve := _smooth_fade(t)

			var scale = lerp(
				0.12,
				0.55,
				curve
			)

			var depth = lerp(
				0.20,
				0.80,
				curve
			)

			corona.scale = Vector3(
				scale,
				scale,
				depth
			),

		0.0,
		1.0,
		0.045
	)


	# Final unified fade.
	tween.tween_method(
		func(t: float) -> void:

			var curve := _smooth_fade(t)

			var scale = lerp(
				0.55,
				0.01,
				curve
			)

			var depth = lerp(
				0.80,
				0.01,
				curve
			)

			corona.scale = Vector3(
				scale,
				scale,
				depth
			)

			mat.emission_energy_multiplier = lerp(
				24.0,
				0.0,
				curve
			),

		0.0,
		1.0,
		0.22
	)


	tween.tween_callback(
		corona.queue_free
	)


# ============================================================================
# SHOCK RING
# ============================================================================

static func _spawn_shock_ring(
	parent: Node3D,
	pos: Vector3,
	forward: Vector3
) -> void:

	var ring := MeshInstance3D.new()

	var torus := TorusMesh.new()

	torus.inner_radius = 0.035
	torus.outer_radius = 0.065

	torus.rings = 12
	torus.ring_segments = 6

	ring.mesh = torus

	ring.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)

	var mat := _create_plasma_material(
		Color(0.30, 0.80, 1.0),
		10.0
	)

	ring.material_override = mat

	parent.add_child(ring)

	ring.global_position = pos

	ring.look_at(
		pos + forward,
		Vector3.UP
	)

	ring.scale = Vector3(
		0.08,
		0.08,
		0.08
	)


	var tween := parent.create_tween()


	# Expand.
	tween.tween_method(
		func(t: float) -> void:

			var curve := _smooth_fade(t)

			var scale = lerp(
				0.08,
				1.0,
				curve
			)

			ring.scale = Vector3(
				scale,
				scale,
				scale
			),

		0.0,
		1.0,
		0.10
	)


	# Continue expanding while fading.
	tween.tween_method(
		func(t: float) -> void:

			var curve := _smooth_fade(t)

			var scale = lerp(
				1.0,
				1.18,
				curve
			)

			ring.scale = Vector3(
				scale,
				scale,
				scale
			)

			mat.emission_energy_multiplier = lerp(
				10.0,
				0.0,
				curve
			),

		0.0,
		1.0,
		0.15
	)


	tween.tween_callback(
		ring.queue_free
	)


# ============================================================================
# ENERGY FILAMENTS
# ============================================================================

static func _spawn_energy_filaments(
	parent: Node3D,
	pos: Vector3,
	forward: Vector3
) -> void:

	var basis := _make_basis(forward)

	var filament_count := randi_range(
		4,
		6
	)

	for i in filament_count:

		_create_filament(
			parent,
			pos,
			forward,
			basis
		)


static func _create_filament(
	parent: Node3D,
	pos: Vector3,
	forward: Vector3,
	basis: Basis
) -> void:

	var filament := MeshInstance3D.new()

	var cylinder := CylinderMesh.new()

	cylinder.top_radius = 0.003
	cylinder.bottom_radius = 0.009

	cylinder.height = 0.28

	cylinder.radial_segments = 5

	filament.mesh = cylinder

	filament.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)

	var mat := _create_plasma_material(
		Color(
			randf_range(0.35, 0.55),
			randf_range(0.80, 0.95),
			1.0
		),
		randf_range(6.0, 12.0)
	)

	filament.material_override = mat

	parent.add_child(filament)

	filament.global_position = pos


	var direction := (
		forward
		+ basis.x * randf_range(-0.40, 0.40)
		+ basis.y * randf_range(-0.40, 0.40)
	).normalized()


	var distance := randf_range(
		0.15,
		0.42
	)


	var target := (
		pos
		+ direction * distance
	)


	filament.look_at(
		target,
		basis.y
	)


	filament.scale = Vector3(
		1.0,
		1.0,
		randf_range(0.15, 0.35)
	)


	var duration := randf_range(
		0.18,
		0.25
	)


	var tween := parent.create_tween()


	# ------------------------------------------------------------
	# MOVEMENT
	# ------------------------------------------------------------

	tween.tween_method(
		func(t: float) -> void:

			var curve := _smooth_fade(t)

			filament.global_position = pos.lerp(
				target,
				curve
			),

		0.0,
		1.0,
		duration
	)


	# ------------------------------------------------------------
	# SCALE + ENERGY USE SAME CURVE
	# ------------------------------------------------------------

	tween.parallel().tween_method(
		func(t: float) -> void:

			var curve := _smooth_fade(t)

			var amount = lerp(
				1.0,
				0.02,
				curve
			)

			filament.scale = Vector3(
				amount,
				amount,
				amount
			)

			mat.emission_energy_multiplier = lerp(
				10.0,
				0.0,
				curve
			),

		0.0,
		1.0,
		duration
	)


	tween.tween_callback(
		filament.queue_free
	)


# ============================================================================
# PLASMA PARTICLES
# ============================================================================

static func _spawn_plasma_particles(
	parent: Node3D,
	pos: Vector3,
	forward: Vector3
) -> void:

	var basis := _make_basis(forward)

	# Keep it compact.
	for i in 12:

		var particle := MeshInstance3D.new()

		var sphere := SphereMesh.new()

		sphere.radius = 0.018
		sphere.height = 0.036

		sphere.radial_segments = 6
		sphere.rings = 4

		particle.mesh = sphere

		particle.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)

		var mat := _create_plasma_material(
			Color(
				randf_range(0.35, 0.75),
				randf_range(0.80, 1.0),
				1.0
			),
			randf_range(3.0, 7.0)
		)

		particle.material_override = mat

		parent.add_child(particle)

		particle.global_position = pos


		var direction := (
			forward
			+ basis.x * randf_range(-0.50, 0.50)
			+ basis.y * randf_range(-0.50, 0.50)
		).normalized()


		var distance := randf_range(
			0.15,
			0.50
		)


		var target := (
			pos
			+ direction * distance
		)


		particle.look_at(
			target,
			basis.y
		)


		var particle_size := randf_range(
			0.35,
			0.70
		)


		particle.scale = Vector3(
			particle_size,
			particle_size,
			particle_size * randf_range(
				1.5,
				2.5
			)
		)


		var duration := randf_range(
			0.18,
			0.25
		)


		var tween := parent.create_tween()


		# ------------------------------------------------------------
		# MOVEMENT
		# ------------------------------------------------------------

		tween.tween_method(
			func(t: float) -> void:

				var curve := _smooth_fade(t)

				particle.global_position = pos.lerp(
					target,
					curve
				),

			0.0,
			1.0,
			duration
		)


		# ------------------------------------------------------------
		# SCALE + ENERGY
		# SAME CURVE
		# ------------------------------------------------------------

		tween.parallel().tween_method(
			func(t: float) -> void:

				var curve := _smooth_fade(t)

				var amount = lerp(
					1.0,
					0.02,
					curve
				)

				particle.scale = Vector3(
					particle_size,
					particle_size,
					particle_size * randf_range(
						1.5,
						2.5
					)
				) * amount

				mat.emission_energy_multiplier = lerp(
					5.0,
					0.0,
					curve
				),

			0.0,
			1.0,
			duration
		)


		tween.tween_callback(
			particle.queue_free
		)


# ============================================================================
# MATERIAL
# ============================================================================

static func _create_plasma_material(
	color: Color,
	energy: float
) -> StandardMaterial3D:

	var mat := StandardMaterial3D.new()

	mat.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
	)

	mat.albedo_color = color

	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy

	mat.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)

	mat.blend_mode = (
		BaseMaterial3D.BLEND_MODE_ADD
	)

	mat.cull_mode = (
		BaseMaterial3D.CULL_DISABLED
	)

	return mat


# ============================================================================
# BASIS
# ============================================================================

static func _make_basis(
	forward: Vector3
) -> Basis:

	var up := Vector3.UP

	if abs(forward.dot(up)) > 0.95:
		up = Vector3.RIGHT

	var right := (
		forward.cross(up)
	).normalized()

	up = (
		right.cross(forward)
	).normalized()

	return Basis(
		right,
		up,
		-forward
	)
