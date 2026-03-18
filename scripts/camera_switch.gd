extends Node3D

@onready var cameras = [$Camera3D, $Camera3D2, $Camera3D3, $Camera3D4, $Camera3D5 ]
var index = 0

func _input(event):
	if event.is_action_pressed("switch_camera"):
		# Increase index, but reset to 0 if it goes past the last camera
		index = (index + 1) % cameras.size()
		cameras[index].make_current()
