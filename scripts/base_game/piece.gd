extends Node3D

class_name Piece

signal clicked(piece_ref)
signal finished(piece_ref)
signal jail_exited(piece: Piece)
signal hovered(piece_ref)
signal unhovered(piece_ref)
signal status_message_requested(message: String)

var lap_size: int = 0
var has_completed_lap: bool = false
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
var is_shielded: bool = false
var shield_turns: int = 0
var is_frozen: bool = false
var frozen_turns: int = 0

func _ready():
	$Visual/yellow.visible = false
	$Visual/blue.visible = false
	$Visual/red.visible = false
	$Visual/green.visible = false
	get_node("Visual/" + color).visible = true
	
	original_y = position.y
	var area = $Area3D
	area.mouse_entered.connect(_on_mouse_enter)
	area.mouse_exited.connect(_on_mouse_exit)
	
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
	
	if is_frozen:
		status_message_requested.emit("¡Ficha congelada! No puede moverse.")
		return false
	
	if in_home_path:
		return await _move_in_home_path(steps)
	
	if has_completed_lap and current_position == player.home_entry:
		in_home_path = true
		home_route = 0
		return await _move_in_home_path(steps)
	
	var steps_to_entry = _steps_to_entry(current_position)
	
	if steps == steps_to_entry:
		for i in range(steps):
			route += 1
			current_position = (route + start_index) % board.main_path.size()
			var square = board.main_path[current_position]
			await _animate_hop_to(square.global_position)
			
			if not has_completed_lap and route == lap_size:
				has_completed_lap = true
		
		if _can_enter_home_path():
			in_home_path = true
			home_route = 0
			var square = board.home_paths[color][home_route]
			await _animate_hop_to(square.global_position)
		
		return true
	
	elif steps > steps_to_entry:
		for i in range(steps_to_entry):
			route += 1
			current_position = (route + start_index) % board.main_path.size()
			var square = board.main_path[current_position]
			await _animate_hop_to(square.global_position)
			
			if not has_completed_lap and route == lap_size:
				has_completed_lap = true
		
		if _can_enter_home_path():
			in_home_path = true
			home_route = 0
			
			var remaining = steps - steps_to_entry
			var max_home_index = board.home_paths[color].size() - 1
			
			for i in range(remaining):
				home_route += 1
				if home_route >= board.home_paths[color].size():
					return false
				var square = board.home_paths[color][home_route]
				await _animate_hop_to(square.global_position)
			
			if home_route == max_home_index:
				_finish()
		else:
			var remaining = steps - steps_to_entry
			status_message_requested.emit("¡Debes completar el circuito primero!")
			
			for i in range(remaining):
				route += 1
				if route >= board.main_path.size():
					route -= board.main_path.size()
					if not has_completed_lap:
						has_completed_lap = true
				
				current_position = (route + start_index) % board.main_path.size()
				var square = board.main_path[current_position]
				await _animate_hop_to(square.global_position)
		
		return true
	
	for i in range(steps):
		route += 1
		current_position = (route + start_index) % board.main_path.size()
		var square = board.main_path[current_position]
		await _animate_hop_to(square.global_position)
		
		if not has_completed_lap and route == lap_size:
			has_completed_lap = true
	
	return true

func _can_enter_home_path() -> bool:
	return has_completed_lap and current_position == player.home_entry

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
	var current_pos = global_position
	
	var final_pos = target_pos
	final_pos.y = 0.015
	
	var mid_pos = (current_pos + final_pos) / 2
	mid_pos.y += 0.04
	
	if has_meta("current_tween"):
		var old_tween = get_meta("current_tween")
		if is_instance_valid(old_tween):
			old_tween.kill()
	
	var tween = create_tween().set_parallel(false)
	set_meta("current_tween", tween)
	
	tween.tween_property(self, "global_position", mid_pos, 0.08)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", final_pos, 0.08)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	await tween.finished
	remove_meta("current_tween")

func _steps_to_entry(old_pos: int):
	return (player.home_entry - old_pos + board.main_path.size()) % board.main_path.size()

func _finish():
	is_finished = true
	finished.emit(self)

func tick_status_effects() -> void:
	if is_shielded:
		shield_turns -= 1
		if shield_turns <= 0: 
			is_shielded = false
	
	if is_frozen:
		frozen_turns -= 1
		if frozen_turns <= 0: 
			is_frozen = false
	
	update_visual_effect()

func apply_shield(turns: int) -> void:
	is_shielded = true
	shield_turns = turns
	update_visual_effect()

func apply_freeze(turns: int) -> void:
	is_frozen = true
	frozen_turns = turns
	update_visual_effect()

func update_visual_effect() -> void:
	for child in get_children():
		if child.name == "StatusEffect":
			child.free()
	
	if not is_frozen and not is_shielded:
		return
	
	var effect = MeshInstance3D.new()
	effect.name = "StatusEffect"
	
	var mesh: Mesh
	if is_frozen:
		mesh = BoxMesh.new()
		mesh.size = Vector3(0.10, 0.18, 0.10)

	else:
		mesh = CapsuleMesh.new()
		mesh.radius = 0.25
		mesh.height = 0.15
	
	
	effect.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 1 
	
	if is_frozen:
		mat.albedo_color = Color(0.4, 0.7, 1.0, 0.6)
		mat.emission = Color(0.2, 0.5, 1.0)
	else:
		mat.albedo_color = Color(1.0, 0.902, 0.302, 0.451)
		mat.emission = Color(1.0, 0.8, 0.2)
	
	mat.emission_energy_multiplier = 1.0
	effect.material_override = mat
	
	add_child(effect)
	effect.position = Vector3(0, 0.05, 0)

func _go_to_jail():
	in_jail = true
	is_shielded = false
	is_frozen = false
	shield_turns = 0
	frozen_turns = 0
	has_completed_lap = false
	update_visual_effect()
	var spot = board.jail[color][piece_id]
	global_position = spot.global_position

func _leave_jail():
	in_jail = false
	route = 0
	current_position = start_index 
	lap_size = (player.home_entry - start_index + board.main_path.size()) % board.main_path.size()
	var start_square = board.main_path[start_index]
	await _animate_hop_to(start_square.global_position)
	jail_exited.emit(self)

func _move_backward(steps: int):
	if in_home_path:
		for i in range(steps):
			home_route -= 1
			
			if home_route < 0:
				in_home_path = false
				route = (player.home_entry - start_index - 1 + board.main_path.size()) % board.main_path.size()
				current_position = (route + start_index) % board.main_path.size()
				
				if has_completed_lap:
					has_completed_lap = false
				
				var remaining = steps - i - 1
				
				for j in range(remaining):
					route -= 1
					if route < 0:
						route += board.main_path.size()
						if has_completed_lap:
							has_completed_lap = false
					
					current_position = (route + start_index) % board.main_path.size()
					var square = board.main_path[current_position]
					await _animate_hop_to(square.global_position)
				
				return 
			
			var square = board.home_paths[color][home_route]
			await _animate_hop_to(square.global_position)
		
		return
	
	for i in range(steps):
		route -= 1
		if route < 0:
			route += board.main_path.size()
			if has_completed_lap:
				has_completed_lap = false
		
		current_position = (route + start_index) % board.main_path.size()
		var square = board.main_path[current_position]
		await _animate_hop_to(square.global_position)

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
