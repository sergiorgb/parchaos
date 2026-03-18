extends Node

var Piece = preload("res://scenes/piece.tscn")

var players = []
var current_turn = 0
var board = null
var move_state = 0
var dice = null
var current_roll = null
var captured_this_turn = false

const PLAYER_DATA = [
	{"id": 0, "color": "yellow", "start_index": 0},
	{"id": 1, "color": "blue", "start_index": 17},
	{"id": 2, "color": "red", "start_index": 34},
	{"id": 3, "color": "green", "start_index": 51}
]

func _ready():
	dice = Node.new()
	dice.set_script(load("res://scripts/base_game/Dice.gd"))
	add_child(dice)
	board = $"../Board"
	board._fill_jail()
	_setup_players()

func _setup_players():
	for data in PLAYER_DATA:
		var player = Node.new()
		player.set_script(load("res://scripts/base_game/Player.gd"))
		player.setup(data.id, data.color, data.start_index)
		add_child(player)
		players.append(player)
		_spawn_pieces(player)

func _spawn_pieces(player):
	for i in range (4):
		var piece = Piece.instantiate()
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

func _roll_dice():
	current_roll = dice.roll()
	print("Dado 1: ", current_roll.dice1)
	print("Dado 2: ", current_roll.dice2)
	print("Total: ", current_roll.total)
	print("Par: ", current_roll.pair)
	
	var player = players[current_turn]
	var all_in_jail = player.pieces.all(func(p): return p.in_jail)
	
	if all_in_jail and not current_roll.pair:
		print("todas las fichas en la carcel")
		_end_turn()
		return
	elif all_in_jail and current_roll.pair:
		move_state = 1
		print("Par, saca una ficha")
	else:
		move_state = 1

func _move_piece(piece_index: int, steps: int):
	var player = players[current_turn]
	var piece = player.pieces[piece_index]
	if piece.in_jail:
		if current_roll.pair:
			piece.leave_jail()
			_check_capture(piece)
			_end_turn()
			return
		else:
			print("la pieza no se puede mover")
			return
		
	else:
		piece.move(steps)
		_check_capture(piece)
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
		piece.move(10)
		_check_capture(piece)
		_end_turn()
	else:
		print("esa ficha está en la carcel")

func _end_turn():
	if current_roll.pair and not _pulled_from_jail():
		print ("par, vuelve a lanzar")
		move_state = 0
		return
	
	move_state = 0
	current_turn = (current_turn + 1) % players.size()
	print("Turno del jugador: ", current_turn, " move_state: ", move_state)
	
func _pulled_from_jail() -> bool:
	var player = players[current_turn]
	for piece in player.pieces:
		if not piece.in_jail and piece.route == 0:
			return true
	return false

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
			var enemy_pos = enemy.current_position
			
			if current_pos == enemy_pos:
				_resolve_capture(enemy)

func _resolve_capture(enemy):
	captured_this_turn = true
	enemy.in_jail = true
	enemy.go_to_jail()
	print("ficha comida!")
	_give_bonus()

func _give_bonus():
	print("elige que ficha avanzar")
	move_state = 3
