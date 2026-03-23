extends Node

var Piece = preload("res://scenes/piece.tscn")

var players = []
var current_turn = 0
var board = null
var move_state = 0
var dice = null
var current_roll = null
var captured_this_turn = false
var captured_on_first_dice = false
var pulled_from_jail_this_turn = false
var bonus_steps = 0
var consecutive_pairs = 0

const PLAYER_DATA = [
	{"id": 0, "color": "yellow", "start_index": 0, "home_entry": 63},
	{"id": 1, "color": "blue", "start_index": 17, "home_entry": 12},
	{"id": 2, "color": "red", "start_index": 34, "home_entry": 29},
	{"id": 3, "color": "green", "start_index": 51, "home_entry": 46}
]

func _ready():
	dice = Node.new()
	dice.set_script(load("res://scripts/base_game/Dice.gd"))
	add_child(dice)
	board = $"../Board"
	board._fill_jail()
	board._fill_home_paths()
	_setup_players()

func _setup_players():
	for data in PLAYER_DATA:
		var player = Node.new()
		player.set_script(load("res://scripts/base_game/Player.gd"))
		player.setup(data.id, data.color, data.start_index, data.home_entry)
		add_child(player)
		players.append(player)
		_spawn_pieces(player)

func _spawn_pieces(player):
	for i in range (4):
		var piece = Piece.instantiate()
		piece.player = player
		piece.piece_id = i
		piece.board = board
		piece.color = player.color
		piece.start_index = player.start_index
		player.add_child(piece)
		player.pieces.append(piece)
		piece.go_to_jail()

func _input(event):
	if event.is_action_pressed("ui_accept") and move_state == 0:
		print("lanzando dados")
		_roll_dice()
	
	elif move_state == 1 or move_state == 2:
		var steps: int
		if move_state == 1:
			steps = current_roll.dice1 
		else:
			steps = current_roll.dice2
			
		if event.is_action_pressed("piece_1"):
			_move_piece(0, steps)
		elif event.is_action_pressed("piece_2"):
			_move_piece(1, steps)
		elif event.is_action_pressed("piece_3"):
			_move_piece(2, steps)
		elif event.is_action_pressed("piece_4"):
			_move_piece(3, steps)
	
	elif move_state == 3:
		if event.is_action_pressed("piece_1"):
			_move_piece_bonus(0)
		elif event.is_action_pressed("piece_2"):
			_move_piece_bonus(1)
		elif event.is_action_pressed("piece_3"):
			_move_piece_bonus(2)
		elif event.is_action_pressed("piece_4"):
			_move_piece_bonus(3)
	
	elif move_state == 4:
		if event.is_action_pressed("piece_1"):
			_send_to_jail(0)
		elif event.is_action_pressed("piece_2"):
			_send_to_jail(1)
		elif event.is_action_pressed("piece_3"):
			_send_to_jail(2)
		elif event.is_action_pressed("piece_4"):
			_send_to_jail(3)
	
	elif move_state == 5:
		if event.is_action_pressed("piece_1"):
			_send_to_jail(0)
		elif event.is_action_pressed("piece_2"):
			_send_to_jail(1)
		elif event.is_action_pressed("piece_3"):
			_send_to_jail(2)
		elif event.is_action_pressed("piece_4"):
			_send_to_jail(3)

func _roll_dice():
	current_roll = dice.roll()
	print("Dado 1: ", current_roll.dice1)
	print("Dado 2: ", current_roll.dice2)
	print("Total: ", current_roll.total)
	print("Par: ", current_roll.pair)
	
	var player = players[current_turn]
	var can_play = player.pieces.any(func(piece):
		if piece.is_finished or piece.in_jail:
			return false
		if piece.in_home_path:
			var remaining = piece.board.home_paths[piece.color].size() - 1 - piece.home_route
			return remaining >= current_roll.dice1 or remaining >= current_roll.dice2
		return true)
	var can_exit = player.pieces.any(func(p): return p.in_jail) and current_roll.pair

	
	if not can_play and not can_exit:
		print("todas las fichas en la carcel")
		_end_turn()
		return
	elif current_roll.pair and _has_own_barrier():
		print("tienes una barrera, debes romperla")
		move_state = 5
	elif can_exit:
		move_state = 1
		print("Par, saca una ficha")
	else:
		move_state = 1

func _move_piece(piece_index: int, steps: int):
	var player = players[current_turn]
	var piece = player.pieces[piece_index]
	if piece.in_jail:
		if current_roll.pair and move_state == 1:
			piece.leave_jail()
			pulled_from_jail_this_turn = true
			_check_capture(piece)
			if captured_this_turn:
				captured_this_turn = false
				move_state = 3
				return
			_end_turn()
			return
		else:
			print("la pieza no se puede mover")
			return
		
	else:
		var barrier_dist = _get_barrier_distance(piece, steps)
		if barrier_dist != -1:
			print("hay una barrera a ", barrier_dist, " casillas")
			return
		var moved = piece.move(steps)
		if not moved:
			var playable_count = player.pieces.count(func(p): return not p.in_jail and not p.is_finished)
			if playable_count == 1:
				move_state += 1
				return
		_check_capture(piece)
		_check_victory(player)
	move_state += 1
	if move_state > 2:
		if captured_this_turn:
			move_state = 3
			captured_this_turn = false
		else:
			_end_turn()
		
func _move_piece_bonus(piece_index : int):
	var player = players[current_turn]
	var piece = player.pieces[piece_index]
	if not piece.in_jail:
		var moved = piece.move(bonus_steps)
		if not moved:
			return
		_check_capture(piece)
		if captured_on_first_dice:
			move_state = 2
			bonus_steps = 0
			return
		bonus_steps = 0
		_end_turn()
	else:
		print("esa ficha está en la carcel")

func _send_to_jail(piece_index):
	var piece = players[current_turn].pieces[piece_index]
	piece.go_to_jail()
	_end_turn()

func _break_barrier(piece_index):
	var player = players[current_turn]
	var piece = player.pieces[piece_index]
	var count = player.pieces.filter(func(p):
		return not p.in_jail and not p.is_finished and p.current_position == piece.current_position)
	if count.size() < 2:
		print("esa ficha no está en barrera")
		return
	move_state = 1
	_move_piece(piece_index, current_roll.dice1)

func _has_own_barrier()-> bool:
	var player = players[current_turn]
	for piece in player.pieces:
		if piece.in_jail or piece.is_finished:
			continue
		var count = player.pieces.filter(func(p):
			return not p.in_jail and not p.is_finished and p.current_position == piece.current_position)
		if count == 2:
			return true
	return false

func _get_barrier_distance(piece, steps):
	for i in range(1, steps + 1):
		var pos = (piece.current_position + i) % board.main_path.size()
		for player in players:
			var count = player.pieces.filter(func(p):
				return not p.in_jail and not p.is_finished and p.current_position == pos)
			if count.size() == 2:
				return i
	return -1

func _end_turn():
	if current_roll.pair and not pulled_from_jail_this_turn:
		consecutive_pairs += 1
		if consecutive_pairs >= 3:
			consecutive_pairs = 0
			print("3 pares seguidos, elige una ficha para enviarla a la carcel")
			move_state = 4
			return
		print ("par, vuelve a lanzar")
		move_state = 0
		return
	
	pulled_from_jail_this_turn = false
	move_state = 0
	consecutive_pairs = 0
	current_turn = (current_turn + 1) % players.size()
	print("Turno del jugador: ", current_turn, " move_state: ", move_state)
	

func _check_capture(piece):
	var current_pos = piece.current_position
	
	if current_pos in board.SAFE_SQUARES:
		return
	
	for player in players:
		if player == players[current_turn]:
			continue
		for enemy in player.pieces:
			if enemy.in_jail or current_pos == enemy.start_index:
				continue
			elif enemy.in_home_path:
				continue
			var enemy_pos = enemy.current_position
			
			if current_pos == enemy_pos:
				_resolve_capture(enemy)

func _check_victory(player):
	var all_finished = player.pieces.all(func(p): return p.is_finished)
	if all_finished:
		print("jugador ", player.color, " ganó!")

func _resolve_capture(enemy):
	if move_state == 1:
		captured_on_first_dice = true
	captured_this_turn = true
	enemy.in_jail = true
	enemy.go_to_jail()
	print("ficha comida!")
	bonus_steps = 10
	move_state = 3

func _on_piece_finished():
	_check_victory(players[current_turn])
	bonus_steps = 24
	captured_this_turn = true  
	move_state = 3
