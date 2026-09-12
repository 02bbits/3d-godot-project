class_name Weapon


const BULLET_SCENE = preload("res://bullet.tscn")

var mag_size := 30
var reserve_max := 90
var shoot_interval := 0.2
var reload_time := 1.2


var ammo := mag_size
var reserve := reserve_max
var reloading := false
var cooldown := shoot_interval

var gun_anim: AnimationPlayer
var gun_barrel: Node3D
var camera: Camera3D


func setup(anim: AnimationPlayer, barrel: Node3D, cam: Camera3D) -> void:
	gun_anim = anim
	gun_barrel = barrel
	camera = cam


func shoot(parent: Node3D) -> bool:
	if gun_anim.is_playing() or reloading or ammo <= 0 or cooldown > 0.0:
		return false
	cooldown = shoot_interval
	ammo -= 1
	gun_anim.play("shoot")

	var muzzle_pos = gun_barrel.global_position + camera.global_transform.basis * Vector3(0, 0, -0.7)
	var forward = -camera.global_transform.basis.z

	var bullet = BULLET_SCENE.instantiate()
	parent.add_child(bullet)
	bullet.global_transform = camera.global_transform
	bullet.global_position = muzzle_pos

	MuzzleEffect.spawn(parent, muzzle_pos, forward)
	return true


func reload() -> void:
	if reloading or ammo >= mag_size or reserve <= 0:
		return
	reloading = true
	gun_anim.play("reload")
	await Engine.get_main_loop().create_timer(reload_time).timeout
	gun_anim.stop()
	var taken = min(mag_size - ammo, reserve)
	ammo += taken
	reserve -= taken
	reloading = false


func tick(delta: float) -> void:
	cooldown -= delta
