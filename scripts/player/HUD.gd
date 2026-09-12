

extends Control

# UI is authored in player.tscn; this script only binds to the nodes.

@onready var health_bar: ProgressBar = $Stats/Health
@onready var stamina_bar: ProgressBar = $Stats/Stamina
@onready var ammo_label: Label = $Stats/Ammo
@onready var death_overlay: Control = $DeathOverlay


func update(health: float, stamina: float, ammo: int, reserve: int) -> void:
	health_bar.value = health
	stamina_bar.value = stamina
	ammo_label.text = "AMMO  %02d / %d" % [ammo, reserve]


func show_death() -> void:
	death_overlay.visible = true
