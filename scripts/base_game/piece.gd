extends Node3D

class_name Piece

signal clicked(piece_ref)
signal finished(piece_ref)
signal jail_exited(piece: Piece)
signal hovered(piece_ref)
signal unhovered(piece_ref)

var mouse_inside = false
var original_y: float = 0.0
var player = null
var piece_id: int = 0 
var route: int = 0
var start_index: int = 0
var current_position = 0
var board = null
var in_jail = true
var color: String
var in_home_path = false
var home_route = 0
var is_finished = false

func _ready():
	$Visual/yellow.visible = false
	$Visual/blue.visible = false
	$Visual/red.visible = false
	$Visual/green.visible = false
	get_node("Visual/" + color).visible = true
	
	original_y = position.y
	var area = $Area3D
	# El hover (que ya te funciona)
	area.mouse_entered.connect(_on_mouse_enter)
	area.mouse_exited.connect(_on_mouse_exit)
	
	# EL CLIC (El que nos faltaba inicializar)
	if not area.input_event.is_connected(_on_area_3d_input_event):
		area.input_event.connect(_on_area_3d_input_event)

func _on_area_3d_input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)

func _on_mouse_enter():
	hovered.emit(self)
	var tween = create_tween()
	tween.tween_property(self, "position:y", original_y + 0.02, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(1.1, 1.1, 1.1), 0.1)

func _on_mouse_exit():
	unhovered.emit(self)
	var tween = create_tween()
	tween.tween_property(self, "position:y", original_y, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), 0.1)

func _move(steps) -> bool:
	if in_home_path:
		return await _move_in_home_path(steps)
	
	var steps_to_entry = _steps_to_entry(current_position)
	
	if steps >= steps_to_entry:
		var steps_on_board = steps_to_entry
		for i in range(steps_on_board):
			route += 1
			current_position = (route + start_index) % board.main_path.size()
			var square = board.main_path[current_position]
			await _animate_hop_to(square.global_position)
		
		var remaining_steps = steps - steps_to_entry
		
		if not in_home_path:
			in_home_path = true
			home_route = 0 
		
		for i in range(remaining_steps):
			home_route += 1
			if home_route >= board.home_paths[color].size():
				return false
			var square = board.home_paths[color][home_route]
			await _animate_hop_to(square.global_position)
		
		if home_route == board.home_paths[color].size() - 1:
			_finish()
		
		return true
	
	for i in range(steps):
		route += 1
		current_position = (route + start_index) % board.main_path.size()
		var square = board.main_path[current_position]
		await _animate_hop_to(square.global_position)
	
	return true

func _move_in_home_path(steps) -> bool:
	var max_home_index = board.home_paths[color].size() - 1
	var remaining = max_home_index - home_route
	
	if steps > remaining:
		return false
	
	for i in range(steps):
		home_route += 1
		var square = board.home_paths[color][home_route]
		await _animate_hop_to(square.global_position)
	
	if home_route == max_home_index:
		_finish()
	
	return true

func _animate_hop_to(target_pos: Vector3) -> void:
	var start_pos = global_position
	var final_pos = target_pos
	final_pos.y = 0.015
	
	# Punto medio elevado (el "hop")
	var mid_pos = (start_pos + final_pos) / 2
	mid_pos.y += 0.04  # Altura del salto
	
	var tween = create_tween().set_parallel(false)
	
	# Subir y avanzar
	tween.tween_property(self, "global_position", mid_pos, 0.08)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Bajar y llegar
	tween.tween_property(self, "global_position", final_pos, 0.08)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	await tween.finished

func _steps_to_entry(old_pos: int):
	return (player.home_entry - old_pos + board.main_path.size()) % board.main_path.size()


func _finish():
	is_finished = true
	finished.emit(self)

func _go_to_jail():
	in_jail = true
	var spot = board.jail[color][piece_id]
	global_position = spot.global_position

func _leave_jail():
	in_jail = false
	route = 0
	current_position = start_index 
	
	var start_square = board.main_path[start_index]
	await _animate_hop_to(start_square.global_position)
	jail_exited.emit(self)

func _adjust_visual_position(is_barrier: bool, piece_index_in_cell: int, cell_index: int, cell_node: Node3D):
	var fixed_y = 0.015 
	var target_pos = cell_node.global_position
	target_pos.y = fixed_y

	if is_barrier:
		var next_idx = (cell_index + 1) % board.main_path.size()
		var next_cell = board.main_path[next_idx]
		
		var forward_dir = (next_cell.global_position - cell_node.global_position).normalized()
		var side_dir = forward_dir.cross(Vector3.UP).normalized()
		
		var offset_distance = 0.04
		var direction = 1 if piece_index_in_cell == 0 else -1
		
		target_pos += (side_dir * offset_distance * direction)

	var tween = create_tween()
	tween.tween_property(self, "global_position", target_pos, 0.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
