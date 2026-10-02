extends CanvasLayer

class_name HUD

#player character reference variable
@export var play_char : PlayerCharacter

#label references variables
@onready var speed_lines_container: ColorRect = %SpeedLinesContainer
@onready var health_bar: ProgressBar = $Healthbar
@onready var stamina_bar: ProgressBar = $Staminabar

func _ready() -> void:
	if play_char == null:
		assert(false, "Player character reference for the hud is mandatory")

func _process(_delta : float) -> void:
	# keep the bar range in sync when modifiers change max health
	if health_bar.max_value != play_char.max_health:
		health_bar.max_value = play_char.max_health
	if stamina_bar.max_value != play_char.stamina_max:
		stamina_bar.max_value = play_char.stamina_max
	
func display_speed_lines(value : bool) -> void:
	speed_lines_container.visible = value
	
func round_to_3_decimals(value: float) -> float:
	return round(value * 1000.0) / 1000.0
