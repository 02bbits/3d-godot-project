extends Node

## Menu motion: page entrances, button hover/press juice and the main menu's
## intro + idle loops. Purely cosmetic — the menu works the same without it.
## Containers own position/size, so everything here animates scale and
## modulate (around the center via pivot_offset_ratio) and never fights layout.

@onready var menu: Control = get_parent()

var _title_pulse: Tween


func _ready() -> void:
	for button in menu.find_children("*", "Button", true, false):
		_add_juice(button)
	# buttons built later (room rows, settings steppers, ...)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Button and menu.is_ancestor_of(node):
			_add_juice(node))


func play_page(page: Control) -> void:
	page.modulate.a = 0.0
	var tween := page.create_tween().set_parallel()
	tween.tween_property(page, "modulate:a", 1.0, 0.2)
	if page.name == "MainMenu":
		_play_main_menu(page)
		return
	# everything but the main menu: the content rises in with a slight pop
	var content := page.get_child(0) as Control
	if content != null:
		content.pivot_offset_ratio = Vector2(0.5, 0.5)
		content.scale = Vector2(0.96, 0.96)
		tween.tween_property(content, "scale", Vector2.ONE, 0.3) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_main_menu(page: Control) -> void:
	var stack := page.get_node("Center/Stack")
	var icons: Array = stack.get_node("Icons").get_children()
	var titles: Array = stack.get_node("TitleRow").get_children()
	var buttons: Array = stack.get_node("Buttons").get_children()
	var delay := 0.0
	# icons drop in one by one, then idle (bob + blink)
	for icon in icons:
		icon.animate = true
		_pop_in(icon, delay, Vector2(0.2, 0.2), 0.45)
		delay += 0.08
	for title in titles:
		_pop_in(title, delay, Vector2(0.6, 0.6), 0.5)
		delay += 0.1
	for button in buttons:
		_pop_in(button, delay, Vector2(0.85, 0.85), 0.35)
		delay += 0.07
	# "ARENA" keeps breathing once it has landed
	var arena: Control = titles[-1]
	if _title_pulse != null:
		_title_pulse.kill()
	_title_pulse = arena.create_tween()
	_title_pulse.tween_interval(delay + 0.5)
	_title_pulse.tween_callback(func() -> void:
		_title_pulse = arena.create_tween().set_loops()
		_title_pulse.tween_property(arena, "scale", Vector2.ONE * 1.05, 0.9) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_title_pulse.tween_property(arena, "scale", Vector2.ONE, 0.9) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))


func _pop_in(node: Control, delay: float, from: Vector2, duration: float) -> void:
	node.pivot_offset_ratio = Vector2(0.5, 0.5)
	node.scale = from
	node.modulate.a = 0.0
	var tween := node.create_tween().set_parallel()
	tween.tween_property(node, "modulate:a", 1.0, duration * 0.6).set_delay(delay)
	tween.tween_property(node, "scale", Vector2.ONE, duration).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _add_juice(button: Button) -> void:
	if button.has_meta(&"juice"):
		return
	button.set_meta(&"juice", true)
	button.pivot_offset_ratio = Vector2(0.5, 0.5)
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			_scale(button, 1.05, 0.12))
	button.mouse_exited.connect(_scale.bind(button, 1.0, 0.12))
	button.button_down.connect(_scale.bind(button, 0.94, 0.05))
	button.button_up.connect(func() -> void:
		_scale(button, 1.05 if button.is_hovered() else 1.0, 0.12))


func _scale(button: Button, target: float, duration: float) -> void:
	var previous: Tween = button.get_meta(&"juice_tween") if button.has_meta(&"juice_tween") else null
	if previous != null and previous.is_valid():
		previous.kill()
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * target, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	button.set_meta(&"juice_tween", tween)
