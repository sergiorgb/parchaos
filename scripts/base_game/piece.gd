extends Node3D

class_name Piece

signal clicked(piece_ref)
signal finished(piece_ref)

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
		print("Pieza ", piece_id, " de color ", color, " DICE: Me han clicado!")
		clicked.emit(self)

func _on_mouse_enter():
	var tween = create_tween()
	tween.tween_property(self, "position:y", original_y + 0.02, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(1.1, 1.1, 1.1), 0.1)

func _on_mouse_exit():
	var tween = create_tween()
	tween.tween_property(self, "position:y", original_y, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), 0.1)

func _move(steps) -> bool:
	if in_home_path:
		var remaining = board.home_paths[color].size() - home_route - 1
		if steps > remaining and remaining != 0:
			print("te faltan exactamente ", remaining, " para llegar")
			return false
		home_route += steps
		var square = board.home_paths[color][home_route]
		await _animate_jump_to(square.global_position).finished
		if home_route == board.home_paths[color].size() - 1:
			_finish()
			return true
		return true
		
	
	var steps_to_entry = _steps_to_entry(current_position)
	route += steps
	current_position = (route + start_index) % board.main_path.size()
	if steps >= steps_to_entry:
		in_home_path = true
		home_route = steps - steps_to_entry
		var square = board.home_paths[color][home_route]
		await _animate_jump_to(square.global_position).finished

	else:
		var square = board.main_path[current_position]
		await _animate_jump_to(square.global_position).finished
	return true

func _steps_to_entry(old_pos: int):
	return (player.home_entry - old_pos + board.main_path.size()) % board.main_path.size()
	

func _animate_jump_to(target_pos: Vector3) -> Tween:
	var final_pos = target_pos
	final_pos.y = 0.015 
	
	var tween = create_tween().set_parallel(false)
	var mid_point = (global_position + final_pos) / 2
	mid_point.y += 0.06 
	
	tween.tween_property(self, "global_position", mid_point, 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "global_position", final_pos, 0.15).set_trans(Tween.TRANS_SINE)
	
	return tween

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
	_move(0)

func _input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self) 

func _mouse_enter():
	var gm = get_node_or_null("/root/Main/GameManager") # Ajusta la ruta a tu GameManager
	
	var tween = create_tween()
	tween.tween_property(self, "position:y", 0.3, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(1.1, 1.1, 1.1), 0.1)
	
	print("Ratón encima de ficha: ", piece_id, " de color: ", color)

func _mouse_exit():
	var tween = create_tween()
	tween.tween_property(self, "position:y", 0.0, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), 0.1)
	
func _shake_error():
	var tween = create_tween()
	var original_pos = position
	# Hace un zig-zag rápido a los lados
	tween.tween_property(self, "position:x", original_pos.x + 0.1, 0.05)
	tween.tween_property(self, "position:x", original_pos.x - 0.1, 0.05)
	tween.tween_property(self, "position:x", original_pos.x + 0.1, 0.05)
	tween.tween_property(self, "position:x", original_pos.x, 0.05)

func _adjust_visual_position(is_barrier: bool, piece_index_in_cell: int, cell_node: Node3D):
	var fixed_y = 0.015 
	
	var target_pos = cell_node.global_position
	target_pos.y = fixed_y

	if is_barrier:
		var current_idx = board.main_path.find(cell_node)
		var next_idx = (current_idx + 1) % board.main_path.size()
		var next_cell = board.main_path[next_idx]
		
		var forward_dir = (next_cell.global_position - cell_node.global_position).normalized()
		
		var side_dir = forward_dir.cross(Vector3.UP).normalized()
		
		var offset_distance = 0.025 
		var direction = 1 if piece_index_in_cell == 0 else -1
		
		target_pos += (side_dir * offset_distance * direction)

	var tween = create_tween()
	tween.tween_property(self, "global_position", target_pos, 0.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	print("Ajustando pieza ", name, " a posición: ", target_pos)
