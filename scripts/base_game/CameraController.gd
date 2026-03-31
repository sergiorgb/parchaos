extends Node
class_name CameraController

@onready var camera: Camera3D
var camera_markers = []

func setup(cam: Camera3D, markers: Array):
	camera = cam
	camera_markers = markers

func move_to_player(player_index: int, instant: bool = false):
	var target = camera_markers[player_index]
	var center = Vector3.ZERO
	
	if instant:
		camera.global_position = target.global_position
		camera.look_at(center, Vector3.UP)
		return
	
	var tween = create_tween()
	tween.tween_property(camera, "global_position", target.global_position, 1.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	tween.parallel().tween_method(
		func(_v): camera.look_at(center, Vector3.UP),
		0.0, 1.0, 1.5
	)
