extends VBoxContainer

## Bottom-left vitals (scenes/player/hud/vitals.tscn): health (red, a tick
## every 10 HP, a pale ghost bar that holds lost health and drains after a
## short delay) and stamina (blue). Reads this HUD's player every frame.

const GHOST_DELAY := 0.4
const GHOST_DRAIN := 0.35
const HP_PER_SEGMENT := 10.0

@onready var icon: Control = %HealthIcon
@onready var health_bar: ProgressBar = %HealthBar
@onready var ghost_bar: ProgressBar = %GhostBar
@onready var ticks: HBoxContainer = %Ticks
@onready var stamina_bar: ProgressBar = %StaminaBar

var play_char: PlayerCharacter
var _health := 1.0 # shown fractions
var _ghost := 1.0
var _ghost_hold := 0.0
var _pulse := 0.0


func _ready() -> void:
	var hud := get_parent() as HUD
	if hud != null:
		play_char = hud.play_char


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
	health_bar.value = _health
	ghost_bar.value = _ghost
	var stamina := clampf(play_char.stamina / maxf(play_char.stamina_max, 1.0), 0.0, 1.0)
	stamina_bar.value = lerpf(stamina_bar.value, stamina, clampf(delta * 14.0, 0.0, 1.0))

	# the health icon throbs when health is low
	_pulse += delta
	var throb := 1.0
	if _health <= 0.25 and _health > 0.0:
		throb = 1.0 + 0.08 * maxf(sin(_pulse * 9.0), 0.0)
	icon.scale = Vector2.ONE * throb

	var segments := maxi(roundi(play_char.max_health / HP_PER_SEGMENT), 1)
	if ticks.get_child_count() != segments:
		NodeUtil.fit_children(ticks, segments)
		# a tick closes every segment but the last
		for i in segments:
			ticks.get_child(i).get_child(0).visible = i < segments - 1
