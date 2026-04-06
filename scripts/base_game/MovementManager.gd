# MovementManager.gd - VERSIÓN FINAL CORREGIDA

class_name MovementManager
extends Node

signal piece_moved(piece: Piece)
signal capture_happened(captured_piece: Piece, bonus: int)
signal victory_achieved(player: Player)
signal movement_denied(message: String)

var board: Board
var players: Array = []
var captured_this_turn: bool = false

func setup(p_board: Board, p_players: Array):
	board = p_board
	players = p_players
	captured_this_turn = false

func can_move_piece(piece: Piece, steps: int, is_pair: bool = false) -> bool:
	if piece.is_finished or piece.in_jail:
		return false
	if piece.is_frozen:
		movement_denied.emit("¡Ficha congelada! No puede moverse.")
		return false
	
	var target_pos = (piece.route + steps + piece.start_index) % board.main_path.size()
	
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

	# Barrera enemiga — bloqueado
	if enemy_count >= 2:
		return false

	# No puedes caer donde hay enemigos si ya hay ficha propia (evita mezcla)
	if enemy_count >= 1 and own_count >= 1:
		return false

	# No puedes caer donde ya tienes 2 propias
	if own_count >= 2:
		return false
	
	# Verificar barreras en el camino
	var barrier_distance = _get_barrier_distance(piece, steps)
	if barrier_distance != -1 and barrier_distance <= steps:
		return false
	
	# Verificar home path
	if piece.in_home_path:
		var remaining = board.home_paths[piece.color].size() - piece.home_route - 1
		if steps > remaining:
			return false
		return true
	
	# Verificar entrada a home path
	var steps_to_entry = piece._steps_to_entry(piece.current_position)
	if steps > steps_to_entry:
		var overshoot = (steps - steps_to_entry) - board.home_paths[piece.color].size()
		if overshoot > 0:
			return false
	
	return true

# Función para obtener las fichas que forman una barrera en una casilla
func get_barrier_pieces_at(target_pos: int, player: Player) -> Array:
	var barrier_pieces = []
	for p in player.pieces:
		if not p.in_jail and not p.is_finished and p.current_position == target_pos:
			barrier_pieces.append(p)
	return barrier_pieces

func break_barrier(piece: Piece, steps: int):
	var current_pos = piece.current_position
	
	var success = await piece._move(steps)
	if not success:
		return
	
	_check_stacking(current_pos)
	_check_stacking(piece.current_position)
	
	if piece.current_position == piece.player.home_entry:
		piece.in_home_path = true
		piece.home_route = 0

func is_own_barrier_at_pos(piece: Piece, target_pos: int) -> bool:
	var count = 0
	
	for p in piece.player.pieces:
		if not p.in_jail and not p.is_finished and p.current_position == target_pos:
			count += 1
	
	return count >= 2

func _is_enemy_barrier_at_pos(piece: Piece, target_pos: int) -> bool:
	# Contar cuántas fichas enemigas están en target_pos
	for player in players:
		if player != piece.player:
			var count = 0
			for p in player.pieces:
				if not p.in_jail and not p.is_finished and p.current_position == target_pos:
					count += 1
			if count >= 2:
				return true
	return false

func _break_barrier_at(target_pos: int, player: Player):
	# Romper la barrera: mover una de las fichas 1 paso adelante
	for p in player.pieces:
		if not p.in_jail and not p.is_finished and p.current_position == target_pos:
			var next_pos = (target_pos + 1) % board.main_path.size()
			
			p.current_position = next_pos
			p.route += 1
			
			var next_cell = board.main_path[next_pos]
			await p._animate_hop_to(next_cell.global_position)
			
			_check_stacking(target_pos)
			_check_stacking(next_pos)
			
			break

func _get_barrier_distance(piece: Piece, steps: int) -> int:
	var current_pos = piece.current_position
	
	for i in range(1, steps + 1):
		var check_pos = (piece.route + steps + piece.start_index) % board.main_path.size()
		
		var pieces_on_cell = 0
		for player in players:
			for p in player.pieces:
				if not p.in_jail and not p.is_finished and p != piece:
					if p.current_position == check_pos:
						pieces_on_cell += 1
		
		if pieces_on_cell >= 2:
			return i
	
	return -1

func move_piece(piece: Piece, steps: int, is_pair: bool = false) -> bool:
	if not can_move_piece(piece, steps, is_pair):
		return false
	
	var target_pos = (piece.route + steps + piece.start_index) % board.main_path.size()
	var own_barrier = is_own_barrier_at_pos(piece, target_pos)  # ✅ Usar la función pública
	
	if own_barrier and is_pair:
		# No mover aún, primero hay que romper barrera
		return false  # Esto hará que GameManager entre en BREAK_BARRIER
	
	if not piece.in_home_path:
		_check_stacking(piece.current_position)
	
	if not await piece._move(steps):
		return false
	
	_check_capture(piece)
	await get_tree().process_frame
	_check_stacking(piece.current_position)
	
	return true

func _check_capture(piece: Piece):
	if piece.current_position in board.SAFE_SQUARES:
		return
	
	var enemies = board._get_enemies_at(piece.current_position, piece.player.player_id)
	
	for enemy in enemies:
		if enemy.current_position == enemy.player.start_index:
			continue
		if enemy.current_position == enemy.player.home_entry:
			continue
		_resolve_capture(enemy)

func _resolve_capture(enemy: Piece):
	if enemy.is_shielded:
		movement_denied.emit("¡Ataque bloqueado por Escudo!")
		return
	enemy.in_jail = true
	enemy.in_home_path = false
	enemy.home_route = 0
	enemy.route = 0
	enemy.lap_size = 0
	enemy.is_shielded = false
	enemy.shield_turns = 0
	enemy.is_frozen = false
	enemy.frozen_turns = 0
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

func needs_break_barrier(piece: Piece, steps: int, is_pair: bool) -> bool:
	if not is_pair:
		return false
	
	var target_pos = (piece.route + steps + piece.start_index) % board.main_path.size()
	return is_own_barrier_at_pos(piece, target_pos) 

func reset_capture_flag():
	captured_this_turn = false
