extends Node
class_name DiceManager

signal dice_stopped(results: Array)

var DiceScene = preload("res://scenes/dice.tscn")
var active_dice: Array = []
var dice_results: Array = []
var camera_markers: Array = []

func setup(markers: Array):
	camera_markers = markers

func roll_for_player(player_index: int):
	_clear_dice()
	dice_results.clear()
	active_dice.clear()
	
	var marker = camera_markers[player_index]
	var dir_to_center = (Vector3.ZERO - marker.global_position).normalized()
	
	for i in range(2):
		var die = DiceScene.instantiate()
		die.add_to_group("dados")
		
		add_child(die, true)
		
		var spawn_pos = marker.global_position + (dir_to_center * 0.6)
		spawn_pos.y = 0.8
		
		var lateral = marker.global_transform.basis.x * (0.15 if i == 0 else -0.15)
		die.global_position = spawn_pos + lateral
		
		die.linear_velocity = Vector3(0, -0.5, 0)
		die.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		
		active_dice.append(die)
		die.stopped.connect(_on_die_stopped)

func _on_die_stopped(value: int):
	dice_results.append(value)
	
	if dice_results.size() == 2:
		await get_tree().create_timer(1.0).timeout
		dice_stopped.emit(dice_results.duplicate())

func _clear_dice():
	for d in active_dice:
		if is_instance_valid(d):
			d.queue_free()
	active_dice.clear()
	get_tree().call_group("dados", "queue_free")

func clear_for_turn_end():
	_clear_dice()
