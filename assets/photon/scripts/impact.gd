## One-shot impact sprite that frees itself after the animation finishes.
extends AnimatedSprite3D


func _on_animation_finished():
	queue_free()
