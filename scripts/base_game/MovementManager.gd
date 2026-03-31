# MovementManager.gd - VERSIÓN FINAL CORREGIDA

class_name MovementManager
extends Node

signal piece_moved(piece: Piece)
signal capture_happened(captured_piece: Piece, bonus: int)
signal victory_achieved(player: Player)

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
	
	var target_pos = (piece.current_position + steps) % board.main_path.size()
	
	# Validar límite de 2 fichas por casilla
	var pieces_on_target = 0
	for player in players:
		for p in player.pieces:
			if not p.in_jail and not p.is_finished and p != piece and p.current_position == target_pos:
				pieces_on_target += 1
	
	if pieces_on_target >= 2:
		print("No se puede mover: ya hay 2 fichas en destino")
		return false
	
	# Verificar barreras en el camino
	var barrier_distance = _get_barrier_distance(piece, steps)
	if barrier_distance != -1 and barrier_distance <= steps:
		print("Movimiento bloqueado por barrera")
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
	var next_pos = (current_pos + steps) % board.main_path.size()
	
	print("Rompiendo barrera: moviendo ficha ", piece.piece_id, " de ", piece.color, " desde ", current_pos, " a ", next_pos, " (", steps, " pasos)")
	
	# ✅ Mover la ficha usando _move (ya maneja route y animación)
	var success = await piece._move(steps)
	if not success:
		print("Error al mover la ficha")
		return
	
	# Reajustar stacking en ambas posiciones
	_check_stacking(current_pos)
	_check_stacking(piece.current_position)
	
	# Verificar si la ficha entró a home path
	if piece.current_position == piece.player.home_entry:
		piece.in_home_path = true
		piece.home_route = 0

func is_own_barrier_at_pos(piece: Piece, target_pos: int) -> bool:
	var count = 0
	print("🔍 is_own_barrier_at_pos - target_pos: ", target_pos)
	
	for p in piece.player.pieces:
		print("   Revisando ficha ", p.piece_id, " pos: ", p.current_position, " | in_jail: ", p.in_jail, " | finished: ", p.is_finished)
		if not p.in_jail and not p.is_finished and p.current_position == target_pos:
			count += 1
			print("      -> Coincide! Count: ", count)
	
	print("   Total fichas propias en destino: ", count)
	return count >= 2

# Mantener la versión interna si quieres, pero actualizar referencias
func _is_own_barrier_at_pos(piece: Piece, target_pos: int) -> bool:
	return is_own_barrier_at_pos(piece, target_pos)

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
	# En Parqués real, el jugador elige qué ficha mover
	# Por ahora, tomamos la primera ficha de la barrera y la movemos 1 paso
	
	for p in player.pieces:
		if not p.in_jail and not p.is_finished and p.current_position == target_pos:
			# Mover la ficha 1 paso adelante
			print("Rompiendo barrera: moviendo ficha ", p.piece_id, " de ", player.color, " desde ", target_pos)
			
			# Calcular siguiente posición
			var next_pos = (target_pos + 1) % board.main_path.size()
			
			# Actualizar posición de la ficha
			p.current_position = next_pos
			p.route += 1
			
			# Animar movimiento
			var next_cell = board.main_path[next_pos]
			await p._animate_hop_to(next_cell.global_position)
			
			# Reajustar stacking en ambas posiciones
			_check_stacking(target_pos)
			_check_stacking(next_pos)
			
			break  # Solo rompemos una ficha por ahora

func _get_barrier_distance(piece: Piece, steps: int) -> int:
	var current_pos = piece.current_position
	
	for i in range(1, steps + 1):
		var check_pos = (current_pos + i) % board.main_path.size()
		
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
	
	# Verificar si el destino es barrera propia y hay par
	var target_pos = (piece.current_position + steps) % board.main_path.size()
	var is_own_barrier = _is_own_barrier_at_pos(piece, target_pos)
	
	if is_own_barrier and is_pair:
		# No mover aún, primero hay que romper barrera
		print("🔨 Se necesita romper barrera antes de mover")
		return false  # Esto hará que GameManager entre en BREAK_BARRIER
	
	if not await piece._move(steps):
		return false
	
	_check_stacking(piece.current_position)
	_check_capture(piece)
	
	return true

func _check_capture(piece: Piece):
	# Casillas seguras no permiten captura
	if piece.current_position in board.SAFE_SQUARES:
		return
	
	var enemies = board._get_enemies_at(piece.current_position, piece.player.player_id)
	
	for enemy in enemies:
		# No se puede capturar en casilla de inicio propia
		if piece.current_position == piece.start_index:
			continue
		# No se puede capturar en la entrada al home path
		if piece.current_position == piece.player.home_entry:
			continue
		
		_resolve_capture(enemy)

func _resolve_capture(enemy: Piece):
	enemy.in_jail = true
	enemy._go_to_jail()
	captured_this_turn = true
	capture_happened.emit(enemy, 10)

func _check_stacking(cell_index: int):
	var pieces_in_cell = []
	
	for player in players:
		for p in player.pieces:
			if p.current_position == cell_index and not p.in_jail and not p.is_finished:
				pieces_in_cell.append(p)
	
	# ✅ Si hay más de 2 fichas, es un error de reglas
	if pieces_in_cell.size() > 2:
		print("⚠️ ERROR: ", pieces_in_cell.size(), " fichas en la misma casilla! Ajustando a 2 máximo")
		# Por ahora, solo mostramos el error, pero idealmente deberíamos evitar que esto pase
	
	var cell_node = board.main_path[cell_index]
	
	# ✅ Limitar a máximo 2 fichas visualmente
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
	
	var target_pos = (piece.current_position + steps) % board.main_path.size()
	return _is_own_barrier_at_pos(piece, target_pos)

func reset_capture_flag():
	captured_this_turn = false
