class_name MovementManager
extends Node

signal capture_happened(captured_piece: GamePiece, bonus: int)
signal victory_achieved(player: Player)
signal movement_denied(message: String)
signal mine_triggered(piece: GamePiece, mine_owner_id: int)
signal alliance_expired(player_a: int, player_b: int)

var board: GameBoard
var players: Array = []
var captured_this_turn: bool = false
var bypass_duel: bool = false
var event_manager = null

var mines: Dictionary = {}
var mine_markers: Dictionary = {}
var alliances: Array = []

func setup(p_board: GameBoard, p_players: Array, p_event_manager = null):
	board = p_board
	players = p_players
	captured_this_turn = false
	event_manager = p_event_manager

func can_move_piece(piece: GamePiece, steps: int, is_pair: bool = false) -> bool:
	if piece.is_finished or piece.in_jail:
		return false
	if piece.is_frozen:
		movement_denied.emit("¡Ficha congelada! No puede moverse.")
		return false

	if piece.in_home_path:
		var remaining = board.home_paths[piece.color].size() - piece.home_route - 1
		if steps > remaining:
			return false
		return true

	var target_pos = (piece.route + steps + piece.start_index) % board.main_path.size()

	if not piece.is_ghost:
		var own_count = 0
		var enemy_count = 0

		for player in players:
			for p in player.pieces:
				if p.in_jail or p.is_finished or p == piece:
					continue
				if p.current_position == target_pos:
					if player == piece.player:
						own_count += 1
					else:
						enemy_count += 1

		if enemy_count >= 2:
			return false
		if enemy_count >= 1 and own_count >= 1:
			return false
		if own_count >= 2:
			return false

	if _has_barrier_in_path(piece, steps):
		return false

	var steps_to_entry = piece._steps_to_entry(piece.current_position)
	if steps > steps_to_entry:
		var overshoot = (steps - steps_to_entry) - board.home_paths[piece.color].size()
		if overshoot > 0:
			return false

	return true

func get_barrier_pieces_at(target_pos: int, player: Player) -> Array:
	var barrier_pieces = []
	for p in player.pieces:
		if not p.in_jail and not p.is_finished and p.current_position == target_pos:
			barrier_pieces.append(p)
	return barrier_pieces

func break_barrier(piece: GamePiece, steps: int):
	var current_pos = piece.current_position

	if not can_move_piece(piece, steps, true):
		var barrier = get_barrier_pieces_at(current_pos, piece.player)
		if barrier.size() > 0:
			var penalized = barrier[randi() % barrier.size()]
			penalized._go_to_jail()
			_check_stacking(current_pos)
		return

	var success = await piece._move(steps)
	if not success:
		return

	_check_stacking(current_pos)
	_check_capture(piece)
	check_mine(piece)
	if event_manager:
		await event_manager.check_wormhole(piece)
	_check_stacking(piece.current_position)

	if piece.current_position == piece.player.home_entry:
		piece.in_home_path = true
		piece.home_route = 0
		piece.broadcast_state()

func is_own_barrier_at_pos(piece: GamePiece, target_pos: int) -> bool:
	var count = 0
	for p in piece.player.pieces:
		if not p.in_jail and not p.is_finished and p.current_position == target_pos:
			count += 1
	return count >= 2

func _has_barrier_in_path(piece: GamePiece, steps: int) -> bool:
	if piece.is_ghost:
		return false

	for i in range(1, steps + 1):
		var check_pos = (piece.route + i + piece.start_index) % board.main_path.size()

		var own_count = 0
		var enemy_count = 0

		for player in players:
			for p in player.pieces:
				if p.in_jail or p.is_finished or p == piece:
					continue
				if p.current_position == check_pos:
					if player == piece.player:
						own_count += 1
					else:
						enemy_count += 1

		if enemy_count >= 2:
			return true
		if own_count >= 2:
			return true

	return false

func move_piece(piece: GamePiece, steps: int, is_pair: bool = false, active_dice_index: int = -1) -> bool:
	if not can_move_piece(piece, steps, is_pair):
		return false

	var target_pos = (piece.route + steps + piece.start_index) % board.main_path.size()
	var own_barrier = is_own_barrier_at_pos(piece, target_pos)

	if own_barrier and is_pair:
		return false

	if not piece.in_home_path:
		_check_stacking(piece.current_position)

	if not await piece._move(steps):
		return false

	_check_capture(piece, active_dice_index)
	await get_tree().process_frame
	_check_stacking(piece.current_position)

	return true

func _check_capture(piece: GamePiece, active_dice_index: int = -1):
	if event_manager and event_manager.is_tregua_active():
		return
	if piece.current_position in board.SAFE_SQUARES:
		return

	var enemies = board._get_enemies_at(piece.current_position, piece.player.player_id)

	for enemy in enemies:
		if enemy.current_position == enemy.player.start_index:
			continue
		if enemy.current_position == enemy.player.home_entry:
			continue
		_resolve_capture(enemy, piece, active_dice_index)

func _resolve_capture(enemy: GamePiece, catcher: GamePiece = null, active_dice_index: int = -1) -> void:
	if enemy.is_shielded:
		movement_denied.emit("¡Ataque bloqueado por Escudo!")
		return
	if enemy.is_ghost:
		movement_denied.emit("¡Ficha fantasma — intangible!")
		return
	if catcher and are_allied(catcher.player.player_id, enemy.player.player_id):
		movement_denied.emit("¡Alianza activa — no se puede capturar!")
		return

	if bypass_duel:
		bypass_duel = false
		_execute_capture(enemy)
		return

	var attacker_piece: GamePiece = catcher
	var attacker_player_id: int = catcher.player.player_id if catcher else -1

	if not attacker_piece:
		for player in players:
			for p in player.pieces:
				if p.current_position == enemy.current_position and p != enemy:
					attacker_piece = p
					attacker_player_id = player.player_id
					break
			if attacker_piece:
				break

	if attacker_piece:
		CaptureManager.start_capture_duel(
			attacker_player_id,
			enemy.player.player_id,
			attacker_piece,
			enemy,
			active_dice_index
		)
		return

	_execute_capture(enemy)

func _execute_capture(enemy: GamePiece) -> void:
	enemy.in_jail = true
	enemy.in_home_path = false
	enemy.home_route = 0
	enemy.route = 0
	enemy.lap_size = 0
	enemy.is_shielded = false
	enemy.shield_turns = 0
	enemy.is_frozen = false
	enemy.frozen_turns = 0
	enemy.is_ghost = false
	enemy.ghost_turns = 0
	enemy._go_to_jail()
	captured_this_turn = true
	capture_happened.emit(enemy, 10)

func _check_stacking(cell_index: int):
	var pieces_in_cell = []

	for player in players:
		for p in player.pieces:
			if p.current_position == cell_index and not p.in_jail and not p.is_finished and not p.in_home_path:
				pieces_in_cell.append(p)

	var cell_node = board.main_path[cell_index]
	var visible_count = min(2, pieces_in_cell.size())

	if visible_count >= 2:
		for i in range(visible_count):
			pieces_in_cell[i]._adjust_visual_position(true, i, cell_index, cell_node)
	else:
		for p in pieces_in_cell:
			p._adjust_visual_position(false, 0, cell_index, cell_node)

func check_victory(player: Player) -> bool:
	var all_finished = true
	for p in player.pieces:
		if not p.is_finished:
			all_finished = false
			break

	if all_finished:
		victory_achieved.emit(player)
		return true
	return false

func reset_capture_flag():
	captured_this_turn = false

func place_mine(position: int, owner_id: int):
	mines[position] = owner_id

	var cell_marker = board.main_path[position]
	var world_pos = cell_marker.global_position

	var marker = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.025
	mesh.bottom_radius = 0.025
	mesh.height = 0.02
	marker.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.1, 0.1, 1)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.05, 0.05)
	mat.emission_energy_multiplier = 0.5
	marker.material_override = mat

	get_tree().current_scene.add_child(marker)
	marker.global_position = world_pos + Vector3(0, 0.001, 0)
	mine_markers[position] = marker

func check_mine(piece: GamePiece):
	if piece.in_home_path or piece.in_jail or piece.is_finished:
		return
	var pos = piece.current_position
	if pos in mines:
		if mines[pos] != piece.player.player_id:
			var owner_id = mines[pos]
			_remove_mine(pos)
			mine_triggered.emit(piece, owner_id)
			_resolve_capture(piece)

func _remove_mine(position: int):
	mines.erase(position)
	if position in mine_markers:
		if is_instance_valid(mine_markers[position]):
			mine_markers[position].queue_free()
		mine_markers.erase(position)

func add_alliance(player_a: int, player_b: int, turns: int):
	alliances.append({"players": [player_a, player_b], "turns_remaining": turns})

func are_allied(player_a: int, player_b: int) -> bool:
	for alliance in alliances:
		var p = alliance["players"]
		if (p[0] == player_a and p[1] == player_b) or (p[0] == player_b and p[1] == player_a):
			return true
	return false

func tick_alliances():
	var expired = []
	for i in range(alliances.size()):
		alliances[i]["turns_remaining"] -= 1
		if alliances[i]["turns_remaining"] <= 0:
			expired.append(i)
	for i in range(expired.size() - 1, -1, -1):
		var idx = expired[i]
		var a = alliances[idx]
		alliance_expired.emit(a["players"][0], a["players"][1])
		alliances.remove_at(idx)
