extends Node
class_name DiceManager

signal dice_stopped(results: Array)

var DiceScene = preload("res://scenes/dice.tscn")
var active_dice: Array = []
var dice_results: Array = []
var camera_markers: Array = []
var dice_nodes: Dictionary = {}

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
		die.stopped.connect(_on_die_stopped.bind(die))

func _on_die_stopped(value: int, die_node: RigidBody3D):
	var die_index = dice_results.size()
	dice_results.append(value)
	dice_nodes[die_index] = die_node  # ← referencia exacta al dado correcto
	
	if dice_results.size() == 2:
		await get_tree().create_timer(1.0).timeout
		dice_stopped.emit(dice_results.duplicate())

func get_dice_nodes() -> Dictionary:
	return dice_nodes

func highlight_active_dice(index: int):
	if not dice_nodes.has(index):
		return
	var die = dice_nodes[index]
	if not is_instance_valid(die):
		return
	
	var meshes = die.find_children("*", "MeshInstance3D", true, false)
	for mesh in meshes:
		var surface_count = mesh.mesh.get_surface_count()
		for i in range(surface_count):
			var mat = mesh.mesh.surface_get_material(i)
			if mat:
				var dup = mat.duplicate()
				dup.emission_enabled = true
				dup.emission = Color(1, 1, 1)
				dup.emission_energy_multiplier = 0.15
				mesh.set_surface_override_material(i, dup)

func reset_dice_highlight(index: int):
	if not dice_nodes.has(index):
		return
	var die = dice_nodes[index]
	if not is_instance_valid(die):
		return
	
	var meshes = die.find_children("*", "MeshInstance3D", true, false)
	for mesh in meshes:
		var surface_count = mesh.mesh.get_surface_count()
		for i in range(surface_count):
			var mat = mesh.mesh.surface_get_material(i)
			if mat:
				var dup = mat.duplicate()
				dup.emission_enabled = false
				mesh.set_surface_override_material(i, dup)

func _clear_dice():
	for d in active_dice:
		if is_instance_valid(d):
			d.queue_free()
	active_dice.clear()
	dice_nodes.clear()
	get_tree().call_group("dados", "queue_free")

func clear_for_turn_end():
	_clear_dice()
