extends Node3D

## Map flyover (scenes/worlds/map_camera.tscn) shown behind the modifier draft:
## circles the current map from outside its edge so players can read the arena
## they are about to fight in. world.gd starts it when the draft opens and
## stops it once the countdown respawn is hidden behind the wipe. Moved every
## frame, so it opts out of physics interpolation (see spectator.gd).

# seconds for one full circle around the map
@export var orbit_seconds := 70.0
# camera height above the map's centre, as a fraction of its radius
@export var height_ratio := 0.45
# orbit radius as a multiple of the map's radius (>1 stays outside the edge)
@export var distance_ratio := 1.05
# radius used when a map has no measurable geometry
@export var fallback_radius := 40.0

@onready var camera: Camera3D = $Camera

var active := false
var _centre := Vector3.ZERO
var _radius := 40.0
var _angle := 0.0


func start(map: Node3D) -> void:
	var bounds := _bounds_of(map)
	_centre = bounds.get_center()
	_radius = maxf(Vector2(bounds.size.x, bounds.size.z).length() * 0.5, 1.0) \
			if bounds.has_volume() else fallback_radius
	if not active:
		_angle = randf() * TAU
	active = true
	camera.current = true
	_place()


func stop() -> void:
	active = false
	if camera.current:
		camera.current = false


func _process(delta: float) -> void:
	if not active:
		return
	# real time: the last kill's slow motion must not slow the flyover
	_angle += TAU * delta / maxf(Engine.time_scale, 0.01) / orbit_seconds
	_place()


func _place() -> void:
	var offset := Vector3(cos(_angle), 0.0, sin(_angle)) * _radius * distance_ratio
	offset.y = _radius * height_ratio
	look_at_from_position(_centre + offset, _centre)


# GridMap tiles aren't nodes, so measure their used cells; other maps fall back
# to their visual nodes' boxes.
func _bounds_of(map: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for grid: GridMap in map.find_children("*", "GridMap", true, false):
		for cell in grid.get_used_cells():
			var point := grid.to_global(grid.map_to_local(cell))
			bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
			first = false
	for visual: VisualInstance3D in map.find_children("*", "VisualInstance3D", true, false):
		var box := visual.global_transform * visual.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds
