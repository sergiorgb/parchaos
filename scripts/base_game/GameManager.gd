extends Node

@onready var camera_markers = [
	$"../yellow", $"../blue", $"../red", $"../green"
]
@onready var status_label: Label = $"../UI/GameUI/StatusLabel" 

var Piece = preload("res://scenes/piece.tscn")

var turn_manager: TurnManager
var movement_manager: MovementManager
var dice_manager: DiceManager
var camera_controller: CameraController
var hover_manager: HoverManager
var camera: Camera3D
var players = []
var board = null
var game_over: bool = false

const PLAYER_DATA = [
	{"id": 0, "color": "yellow", "name": "amarillo", "start_index": 0, "home_entry": 63},
	{"id": 1, "color": "blue", "name": "azul", "start_index": 17, "home_entry": 12},
	{"id": 2, "color": "red", "name": "rojo", "start_index": 34, "home_entry": 29},
	{"id": 3, "color": "green", "name": "verde", "start_index": 51, "home_entry": 46}
]

func _ready():
	await get_tree().process_frame
	board = $"../Board"
	board._fill_jail()
	board._fill_home_paths()
	
	camera = get_viewport().get_camera_3d() 
	if not camera:
		camera = Camera3D.new()
		add_child(camera)
	camera.make_current()
	
	_setup_managers()
	_setup_players()
	
	turn_manager.start_turn(0)
	camera_controller.move_to_player(0, true)

func _setup_managers():
	board.set_players(players)
	
	camera_controller = CameraController.new()
	add_child(camera_controller)
	camera_controller.setup(camera, camera_markers)
	
	dice_manager = DiceManager.new()
	add_child(dice_manager)
	dice_manager.setup(camera_markers)
	dice_manager.dice_stopped.connect(_on_dice_stopped)
	
	movement_manager = MovementManager.new()
	add_child(movement_manager)
	movement_manager.setup(board, players)
	movement_manager.capture_happened.connect(_on_capture_happened)
	movement_manager.victory_achieved.connect(_on_victory_achieved)
	
	turn_manager = TurnManager.new()
	add_child(turn_manager)
	turn_manager.setup(players)
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.bonus_move_available.connect(_on_bonus_move)
	turn_manager.penalty_select_piece.connect(_on_penalty)
	turn_manager.break_barrier_requested.connect(_on_break_barrier_requested)
	turn_manager.barrier_broken_continue.connect(_on_barrier_broken_continue)
	
	hover_manager = HoverManager.new()
	add_child(hover_manager)
	hover_manager.setup(board, turn_manager, movement_manager)

func _setup_players():
	for data in PLAYER_DATA:
		var player = Player.new()
		add_child(player)
		player.setup(data.id, data.color, data.name, data.start_index, data.home_entry)
		players.append(player)
		_spawn_pieces(player)

func _spawn_pieces(player):
	for i in range(4):
		var piece = Piece.instantiate()
		piece.player = player
		piece.piece_id = i
		piece.board = board
		piece.color = player.color
		piece.start_index = player.start_index
		piece.clicked.connect(_on_piece_clicked)
		piece.finished.connect(_on_piece_finished_signal)
		piece.hovered.connect(hover_manager.on_piece_hovered)
		piece.unhovered.connect(hover_manager.on_piece_unhovered)
		player.add_child(piece)
		player.pieces.append(piece)
		piece._go_to_jail()

func _input(event):
	if event.is_action_pressed("ui_accept") and turn_manager.current_state == TurnManager.State.IDLE:
		_roll_dice()

func _roll_dice():
	status_label.text = "Lanzando dados..."
	status_label.visible = true
	dice_manager.roll_for_player(turn_manager.current_player_index)

func _on_dice_stopped(results: Array):
	movement_manager.reset_capture_flag()
	var can_move = turn_manager.process_roll(results)
	
	if not can_move:
		status_label.text = "No puedes mover. Pasando turno..."
		await get_tree().create_timer(1.5).timeout
		turn_manager.end_turn()
		return
	
	var has_jail_exit = turn_manager.current_roll.get("pair", false) and players[turn_manager.current_player_index]._has_pieces_in_jail()

	if not _has_any_valid_move() and not has_jail_exit and turn_manager.current_state != TurnManager.State.PENALTY_JAIL and turn_manager.current_state != TurnManager.State.BREAK_BARRIER_FIRST:
		status_label.text = "Sin movimientos posibles. Pasando turno..."
		await get_tree().create_timer(1.5).timeout
		turn_manager.end_turn()
		return
	
	# Highlight DESPUÉS de procesar, solo si hay dados reales
	if dice_manager.dice_nodes.size() > 0:
		dice_manager.highlight_active_dice(0)
	
	match turn_manager.current_state:
		TurnManager.State.PENALTY_JAIL:
			status_label.text = "¡3 pares! Elige una ficha tuya para la cárcel"
		TurnManager.State.MOVE_DICE_1:
			status_label.text = "Dado 1: " + str(turn_manager.current_roll.dice1) + " | Dado 2: " + str(turn_manager.current_roll.dice2) + " | Mueve con dado 1"
		_:
			status_label.text = "¡Dados listos!"

func _on_piece_clicked(piece_ref: Piece):
	# Validaciones básicas
	if piece_ref.player != players[turn_manager.current_player_index]:
		status_label.text = "No es tu turno"
		return
	
	if not turn_manager.can_click_piece():
		status_label.text = "Espera los dados"
		return
	
	if piece_ref.in_jail:
		_handle_jail_exit(piece_ref)
		return
	
	if turn_manager.current_state == TurnManager.State.BREAK_BARRIER_FIRST:
		_handle_break_barrier_first(piece_ref)
		return
	
	if turn_manager.current_state in [TurnManager.State.MOVE_DICE_1, TurnManager.State.MOVE_DICE_2]:
		_execute_move(piece_ref, turn_manager.get_current_steps())
	elif turn_manager.current_state == TurnManager.State.BONUS_MOVE:
		_execute_move(piece_ref, turn_manager.current_roll.get("bonus", 0))
	elif turn_manager.current_state == TurnManager.State.PENALTY_JAIL:
		_execute_penalty(piece_ref)

func _handle_jail_exit(piece: Piece):
	var is_pair = turn_manager.current_roll.get("pair", false)
	
	if not is_pair:
		status_label.text = "Necesitas un par para salir de la cárcel"
		return
	
	if turn_manager.current_state != TurnManager.State.MOVE_DICE_1:
		status_label.text = "Solo puedes salir con el primer dado"
		return
	
	if turn_manager.has_exited_jail_this_turn:
		status_label.text = "Ya sacaste una ficha este turno"
		return
	
	# Verificar límite de 2 fichas en start_index
	var pieces_at_start = 0
	for p in piece.player.pieces:
		if not p.in_jail and not p.is_finished and p.current_position == piece.start_index:
			pieces_at_start += 1
	
	if pieces_at_start >= 2:
		status_label.text = "No se puede salir: ya hay 2 fichas en la salida"
		return
	
	turn_manager.has_exited_jail_this_turn = true
	piece.jail_exited.connect(_on_jail_exited, CONNECT_ONE_SHOT)
	piece._leave_jail()

func _handle_break_barrier_first(piece: Piece):
	# Verificar que la ficha forme parte de una barrera
	var barrier_pieces = movement_manager.get_barrier_pieces_at(piece.current_position, piece.player)
	
	if barrier_pieces.size() < 2:
		status_label.text = "Selecciona una ficha que forme parte de una barrera"
		return
	
	var steps = turn_manager.current_roll.get("dice1", 0)
	await movement_manager.break_barrier(piece, steps)
	
	turn_manager.has_broken_barrier_this_turn = true
	turn_manager.current_state = TurnManager.State.MOVE_DICE_2
	
	status_label.text = "Barrera rota! Ahora mueve " + str(turn_manager.current_roll.get("dice2", 0)) + " pasos con otra ficha"

func _on_jail_exited(_piece: Piece):
	turn_manager.on_jail_exit()
	movement_manager._check_capture(_piece)
	movement_manager._check_stacking(_piece.current_position)
	var captured = movement_manager.captured_this_turn
	movement_manager.reset_capture_flag()
	
	if captured:
		status_label.text = "¡Ficha liberada y captura!"
		turn_manager.current_roll["bonus"] = 10
		turn_manager.bonus_came_from_dice = 2  # jail exit = no queda dado pendiente
		turn_manager.current_state = TurnManager.State.BONUS_MOVE
		turn_manager.bonus_move_available.emit(10)
	else:
		status_label.text = "¡Ficha liberada! Fin del turno"
		await get_tree().create_timer(0.8).timeout
		turn_manager.end_turn()

func _execute_move(piece: Piece, steps: int):
	var is_pair = turn_manager.current_roll.get("pair", false)
	var target_pos = (piece.current_position + steps) % board.main_path.size()
	
	# Verificar barrera propia
	var is_own_barrier = movement_manager.is_own_barrier_at_pos(piece, target_pos)
	
	if is_own_barrier:
		if is_pair:
			turn_manager.pending_move_piece = piece
			turn_manager.pending_move_steps = steps
			turn_manager.request_break_barrier()
			return
		else:
			return
	
	
	if not await movement_manager.move_piece(piece, steps, is_pair):
		if not _has_any_valid_move():
			status_label.text = "Sin movimientos posibles. Pasando turno..."
			await get_tree().create_timer(1.5).timeout
			turn_manager.end_turn()
		return
	
	var captured = movement_manager.captured_this_turn 
	movement_manager.reset_capture_flag()
	movement_manager.check_victory(piece.player)
	turn_manager.on_piece_moved(true, captured)
	
	if turn_manager.current_state == TurnManager.State.MOVE_DICE_2:
		if not _has_any_valid_move():
			status_label.text = "Sin movimientos posibles con dado 2. Pasando turno..."
			await get_tree().create_timer(1.5).timeout
			turn_manager.end_turn()
			return
	
	match turn_manager.current_state:
		TurnManager.State.MOVE_DICE_2:
			dice_manager.reset_dice_highlight(0)
			dice_manager.highlight_active_dice(1)
			status_label.text = "Mueve con dado 2: " + str(turn_manager.current_roll.get("dice2", 0))
			status_label.visible = true
		TurnManager.State.BONUS_MOVE:
			dice_manager.reset_dice_highlight(1)
			status_label.text = "¡Bonus! Mueve " + str(turn_manager.current_roll.get("bonus", 0)) + " pasos"
			status_label.visible = true
		TurnManager.State.IDLE:
			dice_manager.reset_dice_highlight(1)

func _has_any_valid_move() -> bool:
	var current_player = players[turn_manager.current_player_index]
	var steps = turn_manager.get_current_steps()
	
	if steps == 0:
		return false
	
	for piece in current_player.pieces:
		if not piece.in_jail and not piece.is_finished:
			if movement_manager.can_move_piece(piece, steps):
				return true
	
	return false

func _execute_penalty(piece: Piece):
	piece._go_to_jail()
	turn_manager.end_turn()

func _on_capture_happened(_enemy: Piece, bonus: int):
	turn_manager.current_roll["bonus"] = bonus

func _on_piece_finished_signal(_piece_ref):
	if movement_manager.check_victory(_piece_ref.player):
		turn_manager.current_state = TurnManager.State.IDLE
		return
	turn_manager.current_roll["bonus"] = 10
	turn_manager.captured_this_turn = true

func _on_bonus_move(steps: int):
	status_label.text = "¡Bonus de " + str(steps) + "! Mueve una ficha"

func _on_break_barrier_requested():
	status_label.text = "Rompe la barrera: selecciona una ficha de la barrera para mover 1 paso"

func _on_barrier_broken_continue():
	status_label.text = "Barrera rota! Ahora mueve tu ficha " + str(turn_manager.pending_move_steps) + " pasos"

func _on_penalty():
	status_label.text = "¡3 pares! Elige ficha para cárcel"

func _on_turn_started(player_index: int):
	camera_controller.move_to_player(player_index, false)
	if game_over:
		return
	status_label.text = "Turno de " + players[player_index].display_name.to_upper() + " — Presiona espacio para lanzar"

func _on_turn_ended(_player_index: int):
	if game_over:
		return
	dice_manager.clear_for_turn_end()

func _on_victory_achieved(player: Player):
	game_over = true
	status_label.text = "¡" + player.display_name.to_upper() + " GANA!"
	status_label.visible = true
