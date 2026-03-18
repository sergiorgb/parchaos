extends Node

var Piece = preload("res://scenes/piece.tscn")

var move_state = 0
var dice = null
var current_roll = null
var players = []
var current_turn = 0
var board = null

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
		roll_dice()
		move_state = 1
	
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

func roll_dice():
	current_roll = dice.roll()
	print("Dado 1: ", current_roll.dice1)
	print("Dado 2: ", current_roll.dice2)
	print("Total: ", current_roll.total)
	print("Par: ", current_roll.pair)
	
func _move_piece(piece_index: int, steps: int):
	var player = players[current_turn]
	var piece = player.pieces[piece_index]
	if piece.in_jail:
		if current_roll.pair:
			piece.leave_jail
		else:
			print("la pieza no se puede mover")
			return
		
	else:
		piece.move(steps)
	move_state += 1
	if move_state > 2:
		move_state = 0
		current_turn = (current_turn + 1) % players.size()
		 
