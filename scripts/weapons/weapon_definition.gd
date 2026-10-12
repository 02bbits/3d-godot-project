class_name WeaponDefinition
extends Resource

## All per-weapon configuration lives here: stats, visuals, transforms and
## audio. A new weapon is one .tres (plus its model scenes) — no shared script
## or player scene edits required.

@export var display_name: String = "Weapon"

@export_group("Stats")
@export var damage: int = 30
@export var mag_size: int = 5
@export var fire_interval: float = 0.3
@export var reload_time: float = 2.0
@export var range: float = 60.0

@export_group("Camera recoil")
## view kick per shot, upward; 0 = no camera recoil
@export_range(0.0, 10.0, 0.05) var recoil_pitch_degrees: float = 0.0
## random sideways kick per shot, up to this many degrees either way
@export_range(0.0, 5.0, 0.05) var recoil_yaw_degrees: float = 0.0
## how fast the view settles back after a kick (higher = snappier)
@export_range(1.0, 30.0, 0.5) var recoil_recovery: float = 10.0

@export_group("Visuals")
@export var viewmodel_scene: PackedScene
@export var viewmodel_transform: Transform3D = Transform3D.IDENTITY
@export var world_model_scene: PackedScene
@export var world_model_transform: Transform3D = Transform3D.IDENTITY
@export var muzzle_transform: Transform3D = Transform3D.IDENTITY

@export_group("Audio")
@export var shoot_sounds: Array[AudioStream] = []
@export var reload_sounds: Array[AudioStream] = []
