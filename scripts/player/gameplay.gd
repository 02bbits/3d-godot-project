extends CharacterBody3D
## Gameplay glue swapped onto the Jeheno addon FPS controller.
## Root mirror-follows the addon Controller body so enemies (group "player",
## take_damage), the gun and the HUD keep working unchanged.

const GUN_SCENE := preload("res://guns.tscn")
const HUD_SCRIPT := preload("res://scripts/player/HUD.gd")

const STAMINA_MAX := 100.0

var health := 100.0
var dead := false
var weapon := Weapon.new()

@onready var controller: Node3D = $Controller
@onready var camera: Camera3D = $Controller/CameraHolder/Camera
@onready var gun: Node3D = _build_gun()
@onready var hud: Control = _build_hud()


func _ready() -> void:
	add_to_group("player")
	weapon.setup(gun.get_node("Anim"), gun.get_node("Barrel"), camera)
	hud.update(health, STAMINA_MAX, weapon.ammo, weapon.reserve)


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
			get_tree().reload_current_scene()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if weapon.shoot(get_parent()):
			hud.update(health, STAMINA_MAX, weapon.ammo, weapon.reserve)
	elif event is InputEventKey and event.keycode == KEY_R and event.pressed:
		weapon.reload()


func _physics_process(delta: float) -> void:
	weapon.tick(delta)
	if controller:
		global_transform = controller.global_transform
	hud.update(health, STAMINA_MAX, weapon.ammo, weapon.reserve)


func take_damage(amount: float) -> void:
	if dead:
		return
	health = maxf(health - amount, 0.0)
	hud.update(health, STAMINA_MAX, weapon.ammo, weapon.reserve)
	if health <= 0.0:
		_die()


func _die() -> void:
	dead = true
	controller.set_process(false)
	controller.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_death()


func _build_gun() -> Node3D:
	var gun := Node3D.new()
	gun.name = "Gun"
	camera.add_child(gun)

	var mesh := GUN_SCENE.instantiate()
	mesh.name = "Mesh"
	mesh.position = Vector3(0.31, -0.2, -0.71)
	mesh.scale = Vector3(0.01, 0.01, 0.01)
	gun.add_child(mesh)

	var anim := AnimationPlayer.new()
	anim.name = "Anim"
	anim.root_node = anim.get_path_to(gun)
	gun.add_child(anim)
	var lib := AnimationLibrary.new()
	lib.add_animation("shoot", _simple_anim("Mesh:position", 0.25, Vector3.ZERO, Vector3(0, 0, 0.1)))
	lib.add_animation("reload", _simple_anim("Mesh:rotation", 0.4, Vector3.ZERO, Vector3(0, 0.5, 0)))
	anim.add_animation_library(&"", lib)

	var barrel := RayCast3D.new()
	barrel.name = "Barrel"
	barrel.position = Vector3(0.31, -0.2, -1.41)
	gun.add_child(barrel)
	return gun


func _simple_anim(path: NodePath, dur: float, rest: Vector3, mid: Vector3) -> Animation:
	var a := Animation.new()
	var track := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(track, path)
	a.track_insert_key(track, 0.0, rest)
	a.track_insert_key(track, dur * 0.5, mid)
	a.track_insert_key(track, dur, rest)
	return a


func _build_hud() -> Control:
	var hud := Control.new()
	hud.name = "GameHUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var stats := VBoxContainer.new()
	stats.name = "Stats"
	stats.anchor_top = 1.0
	stats.anchor_bottom = 1.0
	stats.offset_left = 16.0
	stats.offset_top = -120.0
	stats.offset_right = 240.0
	stats.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("separation", 3)
	hud.add_child(stats)

	stats.add_child(_label("HealthLabel", Color(0, 1, 0.6), 12, "HEALTH:"))
	stats.add_child(_bar("Health", Color(0, 1, 0.6)))
	stats.add_child(_label("StaminaLabel", Color(0.25, 0.8, 1), 12, "STAMINA:"))
	stats.add_child(_bar("Stamina", Color(0.25, 0.8, 1)))
	var ammo := _label("Ammo", Color(1, 0.8, 0.2), 14, "")
	ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats.add_child(ammo)

	var death := ColorRect.new()
	death.name = "DeathOverlay"
	death.visible = false
	death.color = Color(0.3, 0, 0, 0.6)
	death.set_anchors_preset(Control.PRESET_FULL_RECT)
	death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(death)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death.add_child(center)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)

	var title := _label("Title", Color(1, 0.25, 0.25), 96, "YOU DIED")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := _label("Hint", Color(1, 1, 1), 24, "Press Left Click or Space to restart")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	hud.set_script(HUD_SCRIPT)
	add_child(hud)
	return hud


func _label(node_name: String, color: Color, font_size: int, text: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(node_name: String, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.name = node_name
	b.custom_minimum_size = Vector2(200, 14)
	b.max_value = 100.0
	b.value = 100.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(color, 0.07)
	bg.border_color = color
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	bg.set_corner_radius(CORNER_BOTTOM_RIGHT, 10)
	b.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	fill.set_corner_radius(CORNER_BOTTOM_RIGHT, 10)
	b.add_theme_stylebox_override("fill", fill)
	return b
