extends PanelContainer

## Bottom-center ammo panel (scenes/player/hud/ammo_panel.tscn): magazine
## pips, reload ring and the dash cooldown. Scaling rule from the mockup:
## never more than 24 pips; each pip stands for ceil(mag / 24) rounds, shown
## by a "×N" chip, and a half-height pip is a partly full group. Reserve ammo
## is unlimited, so it is not shown.

const MAX_PIPS := 24
const LOW_FRACTION := 0.25
const FLASH_TIME := 0.18
const PIP_WIDTH := 4.0
const PIP_MAX_STEP := 17.0

@export var full_color := Color("#FFC933")
@export var low_color := Color("#FF6A5C")
@export var flash_color := Color("#F4EEE2")

@onready var bullet: Control = %Bullet
@onready var reload_ring: Control = %ReloadRing
@onready var ring_bar: TextureProgressBar = %RingBar
@onready var spinner: Control = %Spinner
@onready var pip_area: Control = %PipArea
@onready var pips: HBoxContainer = %Pips
@onready var reload_label: Label = %ReloadLabel
@onready var chip: Control = %Chip
@onready var chip_label: Label = %ChipLabel
@onready var dash: Control = %Dash
@onready var dash_ready: Control = %DashReady
@onready var dash_cooling: Control = %DashCooling
@onready var dash_bar: ProgressBar = %DashBar

var play_char: PlayerCharacter
var _t := 0.0
var _last_ammo := -1
var _flash := 0.0 # spent-pip flash, seconds left
var _flash_range := Vector2i.ZERO
var _was_ready := true


func _ready() -> void:
	var hud := get_parent() as HUD
	if hud != null:
		play_char = hud.play_char


func _process(delta: float) -> void:
	if play_char == null or play_char.weapon == null or not is_visible_in_tree():
		return
	_t += delta
	var weapon = play_char.weapon
	var mag: int = weapon.mag_size()
	var group := _group_size(mag)
	if _last_ammo >= 0 and weapon.ammo < _last_ammo and not weapon.reloading:
		# the pips that were just fired flash before going dark
		_flash = FLASH_TIME
		_flash_range = Vector2i(ceili(float(weapon.ammo) / group), ceili(float(_last_ammo) / group))
	_last_ammo = weapon.ammo
	_flash = maxf(_flash - delta, 0.0)

	# reload: the bullet slot turns into a progress ring
	var reloading: bool = weapon.reloading
	var progress: float = weapon.reload_progress() if reloading else 0.0
	bullet.visible = not reloading
	reload_ring.visible = reloading
	ring_bar.value = progress
	spinner.rotation = _t * 4.0

	chip.visible = group > 1
	chip_label.text = "×%d" % group
	var empty: bool = weapon.ammo <= 0 and not reloading
	reload_label.visible = empty
	reload_label.modulate.a = 0.75 + 0.25 * sin(_t * 6.0)
	pips.visible = not empty
	if not empty:
		# while reloading the pips refill with the progress
		var shown: float = lerpf(weapon.ammo, mag, progress) if reloading else float(weapon.ammo)
		var low: bool = not reloading and weapon.ammo <= mag * LOW_FRACTION
		_update_pips(ceili(float(mag) / group), shown / group, low_color if low else full_color)
	_update_dash()


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


static func _group_size(mag: int) -> int:
	return maxi(ceili(float(mag) / MAX_PIPS), 1)


func _update_pips(count: int, filled: float, color: Color) -> void:
	if pips.get_child_count() != count:
		NodeUtil.fit_children(pips, count)
		var step := pip_area.size.x / MAX_PIPS if count >= MAX_PIPS \
				else minf(pip_area.size.x / count, PIP_MAX_STEP)
		pips.add_theme_constant_override("separation", roundi(step - PIP_WIDTH))
	for i in count:
		var fill := pips.get_child(i).get_child(0) as ColorRect
		fill.visible = true
		fill.scale.y = 1.0
		if i < floori(filled):
			fill.color = color
		elif i < filled:
			# partly full group: a half-height pip
			fill.color = color
			fill.scale.y = 0.5
		elif _flash > 0.0 and i >= _flash_range.x and i < _flash_range.y:
			fill.color = Color(flash_color, _flash / FLASH_TIME)
		else:
			fill.visible = false


func _update_dash() -> void:
	var recovery := dash_recovery()
	var ready := recovery >= 1.0 \
			and play_char.stamina >= play_char.dash_stamina_cost - play_char.stamina_drop_forgive_range
	if ready and not _was_ready:
		# pop when the dash comes back
		dash.scale = Vector2.ONE * 1.15
		create_tween().tween_property(dash, "scale", Vector2.ONE, 0.2)
	_was_ready = ready
	dash_ready.visible = ready
	dash_cooling.visible = not ready
	dash_bar.value = recovery
