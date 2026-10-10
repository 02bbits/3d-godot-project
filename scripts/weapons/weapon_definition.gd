class_name WeaponDefinition
extends Resource

## All per-weapon configuration lives here: stats, visuals, transforms and
## audio. A new weapon is one .tres (plus its model scenes) — no shared script
## or player scene edits required.

@export var display_name: String = "Weapon"

@export_group("Stats")
@export var damage: int = 30
@export var mag_size: int = 24
@export var reserve_max: int = 999
@export var fire_interval: float = 0.15
@export var reload_time: float = 1.2
@export var range: float = 60.0

@export_group("Visuals")
@export var viewmodel_scene: PackedScene
@export var viewmodel_transform: Transform3D = Transform3D.IDENTITY
@export var world_model_scene: PackedScene
@export var world_model_transform: Transform3D = Transform3D.IDENTITY
@export var muzzle_transform: Transform3D = Transform3D.IDENTITY

@export_group("Audio")
@export var shoot_sounds: Array[AudioStream] = []
@export var reload_sounds: Array[AudioStream] = []
