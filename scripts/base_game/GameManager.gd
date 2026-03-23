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
		var player = Player.new()
		add_child(player)
		
		player.setup(data.id, data.color, data.start_index, data.home_entry)
		
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
		piece.clicked.connect(_on_piece_clicked)
		piece.finished.connect(_on_piece_finished_signal)
		player.add_child(piece)
		player.pieces.append(piece)
		piece._go_to_jail()

func _input(event):
	if event.is_action_pressed("ui_accept") and move_state == 0:
		_roll_dice()

func _roll_dice():
	current_roll = dice.roll()
	var player = players[current_turn]
	
	# --- LOS PRINTS QUE NECESITAMOS ---
	print("\n=== LANZAMIENTO JUGADOR: ", player.color.to_upper(), " ===")
	print("Dados: [", current_roll.dice1, "] y [", current_roll.dice2, "]")
	if current_roll.pair:
		print("¡ES UN PAR!")
	# ----------------------------------
	
	var can_play = player._can_move(current_roll)
	var can_exit = player._has_pieces_in_jail() and current_roll.pair

	if not can_play and not can_exit:
		print("Estado: Sin movimientos posibles. Saltando turno...")
		_end_turn()
		return
		
	if current_roll.pair and player._has_own_barrier():
		print("Estado: Barrera detectada. Debes abrirla.")
		move_state = 5
	else:
		move_state = 1
		print("Estado: Esperando primer movimiento (Dado 1: ", current_roll.dice1, ")")

	if not can_play and not can_exit:
		print("Sin movimientos posibles")
		_end_turn()
		return
		
	if current_roll.pair and player._has_own_barrier():
		print("Barrera detectada")
		move_state = 5
	else:
		move_state = 1

func _move_piece(piece_index: int, steps: int):
	var player = players[current_turn]
	var piece = player.pieces[piece_index]
	
	if piece.in_jail:
		if current_roll.pair and move_state == 1:
			print("Saliendo de la cárcel... Fin de movimiento.")
			piece._leave_jail()
			pulled_from_jail_this_turn = true
			_check_capture(piece)
			
			if captured_this_turn:
				move_state = 3 
			else:
				_end_turn()
			return 
		else:
			print("No puedes mover esta ficha (está en la cárcel)")
			return
		
	else:
		var barrier_dist = _get_barrier_distance(piece, steps)
		if barrier_dist != -1:
			print("Bloqueo por barrera")
			return
			
		var moved = piece._move(steps)
		if not moved:
			return

		_check_capture(piece)
		_check_victory(player)
		
		move_state += 1
		
		if move_state > 2:
			if captured_this_turn:
				move_state = 3 
			else:
				_end_turn()


func _move_piece_bonus(piece_index : int):
	var player = players[current_turn]
	var piece = player.pieces[piece_index]
	if not piece.in_jail:
		var moved = piece._move(bonus_steps)
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
	piece._go_to_jail()
	_end_turn()

func _break_barrier(piece_index):
	var player = players[current_turn]
	if not player._is_piece_in_barrier(piece_index):
		print("Esa ficha no está en barrera")
		return
	
	move_state = 1
	_move_piece(piece_index, current_roll.dice1)

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
	if piece.current_position in board.SAFE_SQUARES:
		return
	
	var enemies = board._get_enemies_at(piece.current_position, piece.player.player_id)
	
	for enemy in enemies:
		if piece.current_position == enemy.start_index or piece.current_position == piece.player.home_entry:
			continue
		_resolve_capture(enemy)

func _check_victory(player):
	var all_finished = player.pieces.all(func(p): return p.is_finished)
	if all_finished:
		print("jugador ", player.color, " ganó!")

func _resolve_capture(enemy):
	captured_this_turn = true
	enemy.in_jail = true
	enemy._go_to_jail()
	print("¡Ficha comida! Bonus de 20 pendiente...")
	bonus_steps = 20

func _on_piece_finished_signal():
	_check_victory(players[current_turn])
	bonus_steps = 24
	captured_this_turn = true  
	move_state = 3


func _on_piece_clicked(piece_ref: Piece): # Cambiado a Piece
	# 1. ¿Es el turno de este jugador?
	if piece_ref.player != players[current_turn]:
		print("No es tu turno")
		return
	
	# 2. ¿Se han lanzado los dados? (move_state debe ser > 0)
	if move_state == 0:
		print("Primero lanza los dados con Espacio")
		return

	print("Click en pieza: ", piece_ref.piece_id, " | Estado: ", move_state)
	match move_state:
		1, 2: 
			var steps = current_roll.dice1 if move_state == 1 else current_roll.dice2
			_move_piece(piece_ref.piece_id, steps)
		3: 
			_move_piece_bonus(piece_ref.piece_id)
		4: 
			_send_to_jail(piece_ref.piece_id)
		5: 
			_break_barrier(piece_ref.piece_id)
