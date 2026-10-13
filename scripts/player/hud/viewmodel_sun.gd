extends DirectionalLight3D

## The weapon viewmodel renders in its own World3D, so the map's sun does not
## reach it. This light mirrors the world's sun (group "sun") so the gun picks
## up the same direction, colour and energy as everything else.

var _source: DirectionalLight3D


func _process(_delta: float) -> void:
	if _source == null:
		_source = get_tree().get_first_node_in_group("sun") as DirectionalLight3D
		if _source == null:
			return
	global_transform = _source.global_transform
	light_color = _source.light_color
	light_energy = _source.light_energy
