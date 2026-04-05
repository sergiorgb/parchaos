class_name HoverManager
extends Node

var board: Node
var turn_manager: TurnManager
var movement_manager: MovementManager
var current_highlight: Node3D = null
var highlight_owner: Piece = null

func setup(p_board, p_turn, p_movement):
	board = p_board
	turn_manager = p_turn
	movement_manager = p_movement

func on_piece_hovered(piece: Piece):
	_clear_highlight()
	highlight_owner = piece
	
	if not turn_manager.can_click_piece():
		return
	if piece.player != turn_manager.players[turn_manager.current_player_index]:
		return
	
	var steps = turn_manager.get_current_steps()
	if steps == 0:
		return
	
	if piece.in_jail:
		if turn_manager.current_roll.get("pair", false):
			_show_ghost(piece, board.main_path[piece.start_index].global_position)
		return
	
	if piece.in_home_path:
		var target = piece.home_route + steps
		if target < board.home_paths[piece.color].size():
			_show_ghost(piece, board.home_paths[piece.color][target].global_position)
		return
	
	# Verificar si debería entrar al home path
	var steps_to_entry = piece._steps_to_entry(piece.current_position)
	if steps >= steps_to_entry:
		var remaining = steps - steps_to_entry
		if remaining < board.home_paths[piece.color].size():
			_show_ghost(piece, board.home_paths[piece.color][remaining].global_position)
		return
	
	print("pos: ", piece.current_position, " | steps: ", steps, " | steps_to_entry: ", steps_to_entry, " | target: ", (piece.current_position + steps) % board.main_path.size())
	var target_pos = (piece.current_position + steps) % board.main_path.size()
	_show_ghost(piece, board.main_path[target_pos].global_position)

func on_piece_unhovered(piece: Piece):
	if piece == highlight_owner:
		await piece.get_tree().create_timer(0.05).timeout
		if piece == highlight_owner:  # verificar que sigue siendo el dueño
			_clear_highlight()
			highlight_owner = null

func _show_ghost(piece: Piece, target_pos: Vector3):
	var ghost = piece.duplicate()
	ghost.set_script(null)
	
	var area = ghost.get_node_or_null("Area3D")
	if area:
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)
	
	var visual = ghost.get_node("Visual/" + piece.color)
	var meshes = visual.find_children("*", "MeshInstance3D", true, false)
	
	for mesh in meshes:
		var surface_count = mesh.mesh.get_surface_count()
		for i in range(surface_count):
			var mat = mesh.mesh.surface_get_material(i)
			if mat:
				var dup = mat.duplicate()
				dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				dup.albedo_color.a = 0.6
				dup.render_priority = 1  # ← agregar esto
				dup.no_depth_test = true
				mesh.set_surface_override_material(i, dup)
	
	get_tree().root.add_child(ghost)
	current_highlight = ghost
	ghost.global_position = Vector3(target_pos.x, 0.025, target_pos.z)

func _clear_highlight():
	if current_highlight:
		current_highlight.queue_free()
		current_highlight = null
