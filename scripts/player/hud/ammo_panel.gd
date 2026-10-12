extends Control

## Bottom-center ammo panel: magazine pips, reload state and the dash cooldown.
## Scaling rule from the mockup: never more than 24 pips; each pip stands for
## ceil(mag / 24) rounds, shown by a "×N" tag, and a half-height pip is a
## partly full group. Reserve ammo is unlimited, so it is not shown.

const S := preload("res://scripts/player/hud/hud_style.gd")
const K := S.K
const MAX_PIPS := 24
const LOW_FRACTION := 0.25
const PIP_AREA := 258.0
const PANEL_HEIGHT := 72.0
const CHIP_WIDTH := 52.0

var play_char: PlayerCharacter
var _t := 0.0
var _last_ammo := -1
var _flash := 0.0 # spent-pip flash, seconds left
var _flash_range := Vector2i.ZERO
var _was_ready := true
var _dash_pop := 0.0


func _ready() -> void:
	var hud := get_parent() as HUD
	if hud != null:
		play_char = hud.play_char
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if play_char == null or play_char.weapon == null or not is_visible_in_tree():
		return
	_t += delta
	var weapon = play_char.weapon
	var group := _group_size(weapon.mag_size())
	if _last_ammo >= 0 and weapon.ammo < _last_ammo and not weapon.reloading:
		# the pips that were just fired flash before going dark
		_flash = 0.18
		_flash_range = Vector2i(ceili(float(weapon.ammo) / group), ceili(float(_last_ammo) / group))
	_last_ammo = weapon.ammo
	_flash = maxf(_flash - delta, 0.0)
	var ready := dash_recovery() >= 1.0 and _has_dash_stamina()
	if ready and not _was_ready:
		_dash_pop = 1.0
	_was_ready = ready
	_dash_pop = maxf(_dash_pop - delta * 5.0, 0.0)
	queue_redraw()


## 1.0 = dash available; below that, how far the current cooldown has run
func dash_recovery() -> float:
	var p := play_char
	if p.nb_dashs_allowed > 0:
		if p.time_bef_can_dash_again > 0.0 and p.time_bef_can_dash_again_ref > 0.0:
			return 1.0 - p.time_bef_can_dash_again / p.time_bef_can_dash_again_ref
		return 1.0
	if p.time_bef_reload_dash_ref <= 0.0:
		return 1.0
	return clampf(1.0 - p.time_bef_reload_dash / p.time_bef_reload_dash_ref, 0.0, 1.0)


func _has_dash_stamina() -> bool:
	return play_char.stamina >= play_char.dash_stamina_cost - play_char.stamina_drop_forgive_range


static func _group_size(mag: int) -> int:
	return maxi(ceili(float(mag) / MAX_PIPS), 1)


func _draw() -> void:
	if play_char == null or play_char.weapon == null:
		return
	var weapon = play_char.weapon
	var mag: int = weapon.mag_size()
	var group := _group_size(mag)
	var chip := group > 1
	var width := 424.0 + (CHIP_WIDTH if chip else 0.0)
	# panel centered in this control (the tag widens it)
	var origin := Vector2((size.x / K - width) * 0.5, 0.0)
	S.card(self, Rect2(origin * K, Vector2(width, PANEL_HEIGHT) * K), 12.0 * K)

	var reloading: bool = weapon.reloading
	var progress: float = weapon.reload_progress() if reloading else 0.0
	_draw_slot(Rect2((origin + Vector2(19, 12)) * K, Vector2(47, 47) * K), reloading, progress)

	var area := Rect2((origin + Vector2(82, 25)) * K, Vector2(PIP_AREA, 22) * K)
	if weapon.ammo <= 0 and not reloading:
		var blink := 0.75 + 0.25 * sin(_t * 6.0)
		S.text(self, S.LILITA, int(24 * K), area.position.x, area.get_center().y,
				"RELOAD · R", Color(S.RED, blink), HORIZONTAL_ALIGNMENT_CENTER, area.size.x)
	else:
		# while reloading the pips refill with the progress
		var shown: float = weapon.ammo
		if reloading:
			shown = lerpf(weapon.ammo, mag, progress)
		var low: bool = not reloading and weapon.ammo <= mag * LOW_FRACTION
		_draw_pips(area, ceili(float(mag) / group), shown / group, S.RED if low else S.YELLOW)
	var dash_x := origin.x + width - 19.0 - 48.0
	if chip:
		var tag := "×%d" % group
		var chip_rect := Rect2(Vector2(dash_x - 12.0 - 44.0, 25.0) * K, Vector2(44, 22) * K)
		S.box(self, chip_rect, S.SLOT, 11.0 * K, 2.0 * K)
		S.text(self, S.rubik(700), int(14 * K), chip_rect.position.x, chip_rect.get_center().y,
				tag, S.CREAM, HORIZONTAL_ALIGNMENT_CENTER, chip_rect.size.x)
	_draw_dash(Rect2(Vector2(dash_x, 12.0) * K, Vector2(48, 48) * K))


func _draw_slot(rect: Rect2, reloading: bool, progress: float) -> void:
	var center := rect.get_center()
	if not reloading:
		S.box(self, rect, S.SLOT, 9.0 * K, 3.0 * K)
		S.box(self, Rect2(center - Vector2(5.5, 11) * K, Vector2(11, 22) * K), S.YELLOW, 3.0 * K)
		return
	# reload ring: blue arc fills with progress around a ↻ glyph
	var radius := rect.size.x * 0.5
	draw_circle(center, radius, S.INK)
	draw_circle(center, radius - 2.0 * K, S.SLOT)
	draw_arc(center, radius - 5.0 * K, 0.0, TAU, 48, S.EMPTY, 4.0 * K, true)
	draw_arc(center, radius - 5.0 * K, -PI * 0.5, -PI * 0.5 + TAU * progress, 48,
			S.BLUE, 4.0 * K, true)
	var glyph_r := 7.5 * K
	var spin := _t * 4.0
	draw_arc(center, glyph_r, spin, spin + PI * 1.5, 24, S.CREAM, 2.5 * K, true)
	var tip := center + Vector2.from_angle(spin + PI * 1.5) * glyph_r
	var along := Vector2.from_angle(spin + PI * 2.0)
	var across := Vector2.from_angle(spin + PI * 1.5)
	draw_colored_polygon(PackedVector2Array([tip + along * 4.0 * K,
			tip - across * 3.5 * K, tip + across * 3.5 * K]), S.CREAM)


func _draw_pips(area: Rect2, count: int, filled: float, color: Color) -> void:
	var step := area.size.x / MAX_PIPS if count >= MAX_PIPS else minf(area.size.x / count, 10.75 * 2.0 * K)
	var pip_width := 4.6 * K
	for i in count:
		var rect := Rect2(Vector2(area.position.x + i * step, area.position.y),
				Vector2(pip_width, area.size.y))
		var c := S.EMPTY
		if i < floori(filled):
			c = color
		elif i < filled:
			# partly full group: a half-height pip
			draw_rect(rect, S.EMPTY)
			rect = Rect2(rect.position + Vector2(0, rect.size.y * 0.5), rect.size * Vector2(1, 0.5))
			c = color
		elif _flash > 0.0 and i >= _flash_range.x and i < _flash_range.y:
			c = S.CREAM.lerp(S.EMPTY, 1.0 - _flash / 0.18)
		draw_rect(rect, c)


func _draw_dash(rect: Rect2) -> void:
	var recovery := dash_recovery()
	var ready := recovery >= 1.0 and _has_dash_stamina()
	var pop := 1.0 + 0.15 * _dash_pop
	rect = Rect2(rect.get_center() - rect.size * pop * 0.5, rect.size * pop)
	S.box(self, rect, S.INK, 11.0 * K)
	var inner := rect.grow(-3.0 * K)
	S.box(self, inner, S.SLOT if not ready else Color(S.BLUE, 0.12), 9.0 * K,
			3.0 * K if ready else 0.0, S.BLUE)
	if not ready and recovery > 0.0:
		# cooldown fill rises from the bottom
		var fill_h := inner.size.y * recovery
		S.box(self, Rect2(Vector2(inner.position.x, inner.end.y - fill_h),
				Vector2(inner.size.x, fill_h)), Color(S.BLUE, 0.45), 8.0 * K)
	var color := S.BLUE if ready else S.MUTED
	var c := inner.get_center()
	for offset in [-5.0, 5.0]:
		var x: float = c.x + offset * K - 2.0 * K
		draw_polyline(PackedVector2Array([Vector2(x - 4.0 * K, c.y - 8.0 * K),
				Vector2(x + 4.0 * K, c.y), Vector2(x - 4.0 * K, c.y + 8.0 * K)]),
				color, 3.5 * K, true)
