extends Node


@onready var camera_markers = [
	$"../yellow", $"../blue", $"../red", $"../green"
]

var Piece = preload("res://scenes/piece.tscn")
var DiceScene = preload("res://scenes/dice.tscn")

var camera : Camera3D
var active_dice = []
var players = []
var current_turn = 0
var board = null
var move_state = 0
var dice = null
var dice_results = []
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
	board = $"../Board"
	board._fill_jail()
	board._fill_home_paths()
	
	# Configuración de cámara única
	camera = get_viewport().get_camera_3d() 
	if not camera:
		camera = Camera3D.new()
		add_child(camera)
	camera.make_current()
	
	_setup_players()
	_update_camera(true) # Empezar en la posición del primer jugador


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
	get_tree().call_group("dados", "queue_free")
	dice_results.clear()
	active_dice.clear()
	move_state = -1 
	
	var marker = camera_markers[current_turn]
	
	var dir_al_centro = (Vector3.ZERO - marker.global_position).normalized()
	
	for i in range(2):
		var die = DiceScene.instantiate()
		die.add_to_group("dados")
		add_child(die)
		
		var spawn_pos = marker.global_position + (dir_al_centro * 0.6)
		spawn_pos.y = 0.8
		
		var lateral = marker.global_transform.basis.x * (0.15 if i == 0 else -0.15)
		die.global_position = spawn_pos + lateral
		
		die.linear_velocity = Vector3(0, -0.5, 0) 
		die.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		
		active_dice.append(die)
		die.stopped.connect(_on_die_stopped)
		

func _on_die_stopped(value):
	dice_results.append(value)
	
	if dice_results.size() == 2:
		await get_tree().create_timer(1.0).timeout
		
		_process_physics_results()

func _process_physics_results():
	var d1 = dice_results[0]
	var d2 = dice_results[1]
	current_roll = {"dice1": d1, "dice2": d2, "pair": d1 == d2}
	
	print("Resultado Físico: ", d1, " y ", d2)
	
	var player = players[current_turn]
	if not player._can_move(current_roll) and not (player._has_pieces_in_jail() and current_roll.pair):
		_end_turn()
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

func _check_stacking(cell_index: int):
	var pieces_in_cell = []
	for player in players:
		for p in player.pieces: 
			if p.current_position == cell_index and not p.in_jail:
				pieces_in_cell.append(p)
	
	if pieces_in_cell.size() == 2:
		pieces_in_cell[0]._adjust_visual_position(true, 0)
		pieces_in_cell[1]._adjust_visual_position(true, 1)
	elif pieces_in_cell.size() == 1:
		pieces_in_cell[0]._adjust_visual_position(false, 0) # Vuelve al centro

func _end_turn():
	for d in active_dice:
		if is_instance_valid(d):
			d.queue_free()
	active_dice.clear()
	
	get_tree().call_group("dice", "queue_free")
	
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
	_update_camera()
	print("Cámara moviéndose al jugador: ", current_turn)

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

func _on_piece_finished_signal(piece_ref):
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

func _update_camera(instant: bool = false):
	var target_marker = camera_markers[current_turn]
	var center_of_board = Vector3(0, 0, 0) # El centro de tu tablero

	if instant:
		camera.global_position = target_marker.global_position
		camera.look_at(center_of_board, Vector3.UP)
		return

	var tween = create_tween()
	
	# 1. Animamos la POSICIÓN hacia el marcador
	tween.tween_property(camera, "global_position", target_marker.global_position, 1.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# 2. En cada frame del movimiento, obligamos a la cámara a mirar al centro
	# Esto corrige automáticamente que se ponga boca abajo o de espaldas
	tween.parallel().tween_method(
		func(_v): camera.look_at(center_of_board, Vector3.UP),
		0.0, 1.0, 1.5
	)
