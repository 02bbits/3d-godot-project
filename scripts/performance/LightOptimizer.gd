class_name LightOptimizer

extends Node

# Attach anywhere in the scene tree. On startup it retunes every Light3D:
# shadows off (the #1 perf killer on dense maps), energy/range capped, and
# distance-faded so far-away lights cost nothing.
# Flip disable_shadows to true if you have a fast GPU and want dynamic shadows.

@export var disable_shadows := true
@export var max_light_energy := 4.0
@export var max_omni_range := 25.0
@export var max_spot_range := 30.0


func _ready() -> void:
	_walk(self)


func _walk(node: Node) -> void:
	for child in node.get_children():
		_apply(child)
		_walk(child)


func _apply(node: Node) -> void:
	if node is DirectionalLight3D:
		node.shadow_enabled = not disable_shadows
		return
	var light := node as Light3D
	if light == null:
		return
	light.shadow_enabled = false
	light.light_energy = minf(light.light_energy, max_light_energy)
	if node is OmniLight3D:
		var omni := node as OmniLight3D
		omni.omni_range = minf(omni.omni_range, max_omni_range)
		_enable_distance_fade(omni)
	elif node is SpotLight3D:
		var spot := node as SpotLight3D
		spot.spot_range = minf(spot.spot_range, max_spot_range)
		_enable_distance_fade(spot)


func _enable_distance_fade(light: Light3D) -> void:
	light.distance_fade_enabled = true
	light.distance_fade_begin = 0.65
	light.distance_fade_length = 0.35