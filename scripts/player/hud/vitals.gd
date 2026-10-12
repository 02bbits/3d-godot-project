extends Control

## Bottom-left vitals: health (red, 10 HP segments, a pale ghost bar that
## holds lost health and drains after a short delay) and stamina (blue).
## Reads this HUD's own player every frame and draws itself.

const S := preload("res://scripts/player/hud/hud_style.gd")
const K := S.K
const GHOST_DELAY := 0.4
const GHOST_DRAIN := 0.35
const HP_PER_SEGMENT := 10.0

var play_char: PlayerCharacter
var _health := 1.0 # shown fractions
var _ghost := 1.0
var _stamina := 1.0
var _ghost_hold := 0.0
var _pulse := 0.0


func _ready() -> void:
	var hud := get_parent() as HUD
	if hud != null:
		play_char = hud.play_char
	custom_minimum_size = Vector2(327, 67) * K
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if play_char == null or not is_visible_in_tree():
		return
	var health := clampf(play_char.health / maxf(play_char.max_health, 1.0), 0.0, 1.0)
	if health < _health:
		# damage: the ghost keeps the old value, then drains after the delay
		_ghost = maxf(_ghost, _health)
		_ghost_hold = GHOST_DELAY
	elif health > _ghost:
		_ghost = health
	_health = health
	if _ghost_hold > 0.0:
		_ghost_hold -= delta
	else:
		_ghost = move_toward(_ghost, _health, delta / GHOST_DRAIN)
	var stamina := clampf(play_char.stamina / maxf(play_char.stamina_max, 1.0), 0.0, 1.0)
	_stamina = lerpf(_stamina, stamina, clampf(delta * 14.0, 0.0, 1.0))
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	if play_char == null:
		return
	# health icon: red tile with an ink plus; it throbs when health is low
	var throb := 1.0
	if _health <= 0.25 and _health > 0.0:
		throb = 1.0 + 0.08 * maxf(sin(_pulse * 9.0), 0.0)
	var icon := Rect2(Vector2(0, 0), Vector2(35, 35) * K)
	icon = Rect2(icon.get_center() - icon.size * throb * 0.5, icon.size * throb)
	S.box(self, icon, S.RED, 8.0 * K, 3.0 * K)
	var c := icon.get_center()
	var arm := 9.0 * K * throb
	var thick := 4.5 * K * throb
	draw_rect(Rect2(c - Vector2(arm, thick * 0.5), Vector2(arm * 2.0, thick)), S.INK)
	draw_rect(Rect2(c - Vector2(thick * 0.5, arm), Vector2(thick, arm * 2.0)), S.INK)

	var bar := Rect2(Vector2(48, 2) * K, Vector2(279, 31) * K)
	_draw_bar(bar, _health, _ghost, S.RED, play_char.max_health / HP_PER_SEGMENT)

	_draw_bolt(Vector2(17, 57) * K, 9.0 * K)
	var stamina_bar := Rect2(Vector2(48, 49) * K, Vector2(279, 18) * K)
	_draw_bar(stamina_bar, _stamina, 0.0, S.BLUE, 0)


func _draw_bar(rect: Rect2, fill: float, ghost: float, color: Color, segments: float) -> void:
	S.box(self, rect, S.SLOT, 6.0 * K, 3.0 * K)
	var inner := rect.grow(-3.0 * K)
	if ghost > fill:
		S.box(self, Rect2(inner.position, Vector2(inner.size.x * ghost, inner.size.y)),
				S.GHOST, 4.0 * K)
	if fill > 0.0:
		var width := maxf(inner.size.x * fill, 4.0 * K)
		S.box(self, Rect2(inner.position, Vector2(width, inner.size.y)), color, 4.0 * K)
	# segment ticks over the fill, one every HP_PER_SEGMENT
	if segments > 1.0:
		var step := inner.size.x / segments
		var x := inner.position.x + step
		while x < inner.end.x - 1.0:
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y),
					Color(S.INK, 0.45), 2.0 * K)
			x += step


func _draw_bolt(center: Vector2, size: float) -> void:
	var points := PackedVector2Array([
		Vector2(0.15, -1.0), Vector2(-0.6, 0.15), Vector2(-0.05, 0.15),
		Vector2(-0.2, 1.0), Vector2(0.6, -0.2), Vector2(0.05, -0.2)])
	for i in points.size():
		points[i] = center + points[i] * size
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, S.INK, 3.0 * K, true)
	draw_colored_polygon(points, S.BLUE)
