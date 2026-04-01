class_name HoverManager
extends Node

var board: Node
var turn_manager: TurnManager
var movement_manager: MovementManager
var current_highlight: Node3D = null

func setup(p_board, p_turn, p_movement):
	board = p_board
	turn_manager = p_turn
	movement_manager = p_movement

func on_piece_hovered(piece: Piece):
	_clear_highlight()
	
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
	
	var target_pos = (piece.current_position + steps) % board.main_path.size()
	_show_ghost(piece, board.main_path[target_pos].global_position)

func on_piece_unhovered(_piece: Piece):
	print("unhovered - highlight existe: ", current_highlight != null)
	_clear_highlight()

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
			var mat = mesh.mesh.surface_get_material(i)  # ← del mesh, no del override
			if mat:
				var dup = mat.duplicate()
				dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				dup.albedo_color.a = 0.6
				mesh.set_surface_override_material(i, dup)
	
	get_tree().root.add_child(ghost)
	current_highlight = ghost  # ← asignar ANTES del await
	await get_tree().process_frame
	ghost.global_position = target_pos
	ghost.global_position.y = 0.02

func _clear_highlight():
	if current_highlight:
		current_highlight.queue_free()
		current_highlight = null
