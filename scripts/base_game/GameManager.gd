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
var card_manager: CardManager
var square_effects: SquareEffects
var camera: Camera3D
var players = []
var board = null
var game_over: bool = false


var card_label: Label
var pending_card_index: int = -1
var pending_card_type: int = -1
var roll_cooldown: bool = false
var jail_roll_attempts: int = 0
const MAX_JAIL_ROLLS = 3
const ROLL_COOLDOWN_TIME = 1.5

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
	board.set_players(players)
	card_manager.setup(players.size())
	
	_setup_card_ui()
	_mark_special_squares()
	
	turn_manager.start_turn(0)
	camera_controller.move_to_player(0, true)

func _setup_managers():
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
	
	card_manager = CardManager.new()
	add_child(card_manager)
	
	square_effects = SquareEffects.new()
	add_child(square_effects)
	square_effects.setup(board, card_manager)

func _setup_card_ui():
	card_label = Label.new()
	card_label.name = "CardLabel"
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.anchors_preset = Control.PRESET_BOTTOM_WIDE
	card_label.offset_top = -60
	card_label.offset_bottom = -10
	card_label.add_theme_font_size_override("font_size", 18)
	$"../UI/GameUI".add_child(card_label)

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
	if game_over:
		return
	
	if event.is_action_pressed("ui_accept") and turn_manager.current_state == TurnManager.State.IDLE and not roll_cooldown:
		_roll_dice()
		return
	
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	
	var key = event.physical_keycode
	
	match turn_manager.current_state:
		TurnManager.State.IDLE:
			if key == KEY_Q:
				_try_open_cards()
		TurnManager.State.CARD_SELECT:
			if key == KEY_ESCAPE or key == KEY_Q:
				_cancel_card()
			elif key == KEY_1:
				_select_card(0)
			elif key == KEY_2:
				_select_card(1)
			elif key == KEY_3:
				_select_card(2)
		TurnManager.State.CARD_TARGET:
			if key == KEY_ESCAPE:
				_cancel_card()



func _roll_dice():
	roll_cooldown = true
	status_label.text = "Lanzando dados..."
	status_label.visible = true
	dice_manager.roll_for_player(turn_manager.current_player_index)

func _on_dice_stopped(results: Array):
	movement_manager.reset_capture_flag()
	var can_move = turn_manager.process_roll(results)
	var player = players[turn_manager.current_player_index]
	var all_in_jail = not player.pieces.any(func(p): return not p.in_jail and not p.is_finished)
	var is_pair = turn_manager.current_roll.get("pair", false)
	
	if all_in_jail and not is_pair:
		jail_roll_attempts += 1
		if jail_roll_attempts < MAX_JAIL_ROLLS:
			status_label.text = "No sacaste par! Intento " + str(jail_roll_attempts) + "/" + str(MAX_JAIL_ROLLS) + " -- Presiona espacio"
			turn_manager.current_state = TurnManager.State.IDLE
			_start_roll_cooldown()
			return
		else:
			status_label.text = "3 intentos fallidos. Pasando turno..."
			await get_tree().create_timer(1.5).timeout
			turn_manager.end_turn()
			return
	
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
	
	if dice_manager.dice_nodes.size() > 0:
		dice_manager.highlight_active_dice(0)
	
	match turn_manager.current_state:
		TurnManager.State.PENALTY_JAIL:
			status_label.text = "¡3 pares! Elige una ficha tuya para la cárcel"
		TurnManager.State.MOVE_DICE_1:
			status_label.text = "Dado 1: " + str(turn_manager.current_roll.dice1) + " | Dado 2: " + str(turn_manager.current_roll.dice2) + " | Mueve con dado 1"
		_:
			status_label.text = "Dados listos!"
	
	_start_roll_cooldown()



func _on_piece_clicked(piece_ref: Piece):

	if turn_manager.current_state == TurnManager.State.CARD_TARGET:
		_handle_card_target(piece_ref)
		return
	

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
	var d1 = turn_manager.current_roll.get("dice1", 0)
	var is_pair = turn_manager.current_roll.get("pair", false)
	
	if not is_pair:
		status_label.text = "Necesitas un par para salir de la carcel"
		return
	
	if turn_manager.current_state not in [TurnManager.State.MOVE_DICE_1, TurnManager.State.MOVE_DICE_2]:
		status_label.text = "Accion no permitida ahora"
		return
	
	var is_super_pair = d1 == 1 or d1 == 6
	var max_pieces_to_take = 2 if is_super_pair else 1
	var pieces_taken = 0
	
	var pieces_at_start = 0
	for p in piece.player.pieces:
		if not p.in_jail and not p.is_finished and p.current_position == piece.start_index:
			pieces_at_start += 1
	
	if pieces_at_start >= 2:
		status_label.text = "No se puede salir: ya hay 2 fichas en la salida"
		return
	
	piece.jail_exited.connect(_on_jail_exited, CONNECT_ONE_SHOT)
	piece._leave_jail()
	pieces_taken += 1
	pieces_at_start += 1
	
	if max_pieces_to_take > 1 and pieces_at_start < 2:
		for other_piece in piece.player.pieces:
			if other_piece != piece and other_piece.in_jail:
				other_piece.jail_exited.connect(_on_secondary_jail_exited, CONNECT_ONE_SHOT)
				other_piece._leave_jail()
				break

func _on_secondary_jail_exited(_piece: Piece):
	movement_manager._check_capture(_piece)
	movement_manager._check_stacking(_piece.current_position)
	movement_manager.reset_capture_flag()

func _on_jail_exited(_piece: Piece):
	movement_manager._check_capture(_piece)
	movement_manager._check_stacking(_piece.current_position)
	var captured = movement_manager.captured_this_turn
	movement_manager.reset_capture_flag()
	
	if captured:
		_draw_card_for_player(turn_manager.current_player_index)
	
	turn_manager.on_piece_moved(true, captured)
	
	if turn_manager.current_state == TurnManager.State.MOVE_DICE_2:
		if not _has_any_valid_move():
			status_label.text = "Sin movimientos posibles con dado 2. Pasando turno..."
			await get_tree().create_timer(1.5).timeout
			turn_manager.end_turn()
			return
		status_label.text = "Fichas liberadas! Dado 1: " + str(turn_manager.current_roll.get("dice1", 0)) + " | Dado 2: " + str(turn_manager.current_roll.get("dice2", 0)) + " | Mueve con dado 2"
	elif turn_manager.current_state == TurnManager.State.IDLE:
		pass
	elif turn_manager.current_state == TurnManager.State.BONUS_MOVE:
		status_label.text = "Fichas liberadas y captura! Bonus!"



func _handle_break_barrier_first(piece: Piece):
	var barrier_pieces = movement_manager.get_barrier_pieces_at(piece.current_position, piece.player)
	
	if barrier_pieces.size() < 2:
		status_label.text = "Selecciona una ficha que forme parte de una barrera"
		return
	
	var steps = turn_manager.current_roll.get("dice1", 0)
	await movement_manager.break_barrier(piece, steps)
	
	turn_manager.has_broken_barrier_this_turn = true
	turn_manager.current_state = TurnManager.State.MOVE_DICE_2
	
	status_label.text = "Barrera rota! Ahora mueve " + str(turn_manager.current_roll.get("dice2", 0)) + " pasos con otra ficha"



func _execute_move(piece: Piece, steps: int):
	var is_pair = turn_manager.current_roll.get("pair", false)
	

	var is_own_barrier = false
	if not piece.in_home_path:
		var steps_to_entry = piece._steps_to_entry(piece.current_position)
		if steps < steps_to_entry:
			var target_pos = (piece.current_position + steps) % board.main_path.size()
			is_own_barrier = movement_manager.is_own_barrier_at_pos(piece, target_pos)
	
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
	
	if captured:
		_draw_card_for_player(turn_manager.current_player_index)
	
	await _apply_square_effects(piece)
	
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
	
	_update_card_display()

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



func _apply_square_effects(piece: Piece):
	var result = square_effects.apply_effect(piece)
	if result.message == "":
		return
	
	status_label.text = result.message
	await get_tree().create_timer(1.5).timeout
	
	match result.type:
		SquareEffects.SquareType.SPEED_BOOST:
			if movement_manager.can_move_piece(piece, 3):
				await movement_manager.move_piece(piece, 3, false)
				movement_manager._check_stacking(piece.current_position)
		SquareEffects.SquareType.TRAP:
			await piece._move_backward(3)
			movement_manager._check_stacking(piece.current_position)
	
	_update_card_display()



func _try_open_cards():
	var hand = card_manager.get_hand(turn_manager.current_player_index)
	if hand.is_empty():
		status_label.text = "No tienes cartas — [Espacio] para lanzar"
		return
	turn_manager.current_state = TurnManager.State.CARD_SELECT
	_show_card_selection()

func _show_card_selection():
	var hand = card_manager.get_hand(turn_manager.current_player_index)
	var text = "ELIGE CARTA:  "
	for i in range(hand.size()):
		var info = CardManager.CARD_INFO[hand[i]]
		text += "[" + str(i + 1) + "] " + info["icon"] + " " + info["name"] + "  "
	text += " | [Esc] Cancelar"
	status_label.text = text

func _select_card(card_index: int):
	var hand = card_manager.get_hand(turn_manager.current_player_index)
	if card_index < 0 or card_index >= hand.size():
		status_label.text = "Carta inválida"
		return
	
	pending_card_index = card_index
	pending_card_type = hand[card_index]
	var target = card_manager.get_card_target(pending_card_type)
	
	match target:
		"none":
			_apply_no_target_card()
		"own":
			turn_manager.current_state = TurnManager.State.CARD_TARGET
			status_label.text = CardManager.CARD_INFO[pending_card_type]["icon"] + " Selecciona una de tus fichas activas"
		"own_jail":
			turn_manager.current_state = TurnManager.State.CARD_TARGET
			status_label.text = "FUGA: Selecciona una ficha tuya en la carcel"
		"enemy":
			turn_manager.current_state = TurnManager.State.CARD_TARGET
			status_label.text = CardManager.CARD_INFO[pending_card_type]["icon"] + " Selecciona una ficha enemiga"

func _cancel_card():
	pending_card_index = -1
	pending_card_type = -1
	turn_manager.current_state = TurnManager.State.IDLE
	status_label.text = "Turno de " + players[turn_manager.current_player_index].display_name.to_upper() + " — [Espacio] lanzar | [Q] cartas"
	_update_card_display()

func _apply_no_target_card():
	var player_idx = turn_manager.current_player_index
	card_manager.use_card(player_idx, pending_card_index)
	
	match pending_card_type:
		CardManager.CardType.DOUBLE:
			turn_manager.double_next_roll = true
			status_label.text = "DOBLE: Tu proximo lanzamiento sera DOBLE!"
		CardManager.CardType.THIEF:
			var stolen = false
			for i in range(players.size()):
				if i != player_idx and card_manager.get_hand(i).size() > 0:
					var card = card_manager.steal_random_card(i, player_idx)
					if card != -1:
						status_label.text = "LADRON: Robaste " + card_manager.get_card_name(card) + " de " + players[i].display_name + "!"
						stolen = true
						break
			if not stolen:
				status_label.text = "LADRON: Nadie tiene cartas para robar..."
	
	pending_card_index = -1
	pending_card_type = -1
	turn_manager.current_state = TurnManager.State.IDLE
	_update_card_display()
	await get_tree().create_timer(1.5).timeout
	status_label.text = "Turno de " + players[player_idx].display_name.to_upper() + " — [Espacio] lanzar | [Q] cartas"

func _handle_card_target(piece: Piece):
	var player = players[turn_manager.current_player_index]
	var target = card_manager.get_card_target(pending_card_type)
	

	match target:
		"own":
			if piece.player != player or piece.in_jail or piece.is_finished:
				status_label.text = "Selecciona una ficha tuya activa"
				return
		"own_jail":
			if piece.player != player or not piece.in_jail:
				status_label.text = "Selecciona una ficha tuya en la cárcel"
				return
		"enemy":
			if piece.player == player or piece.in_jail or piece.is_finished:
				status_label.text = "Selecciona una ficha enemiga activa"
				return
	

	var card_type = pending_card_type
	card_manager.use_card(turn_manager.current_player_index, pending_card_index)
	pending_card_index = -1
	pending_card_type = -1
	
	match card_type:
		CardManager.CardType.TURBO:
			if not movement_manager.can_move_piece(piece, 5):
				status_label.text = "TURBO: No puede moverse 5 pasos -- carta gastada"
			else:
				status_label.text = "TURBO: +5 pasos!"
				await movement_manager.move_piece(piece, 5, false)
				var captured = movement_manager.captured_this_turn
				movement_manager.reset_capture_flag()
				if captured:
					_draw_card_for_player(turn_manager.current_player_index)
				await _apply_square_effects(piece)
		
		CardManager.CardType.SHIELD:
			piece._apply_shield(2)
			status_label.text = "ESCUDO: Activado por 2 turnos!"
		
		CardManager.CardType.JAILBREAK:

			var pieces_at_start = 0
			for p in piece.player.pieces:
				if not p.in_jail and not p.is_finished and p.current_position == piece.start_index:
					pieces_at_start += 1
			if pieces_at_start >= 2:
				status_label.text = "FUGA: No hay espacio en la salida -- carta gastada"
			else:
				status_label.text = "FUGA: Exitosa!"
				piece.jail_exited.connect(_on_jail_exited_card, CONNECT_ONE_SHOT)
				piece._leave_jail()
		
		CardManager.CardType.SABOTAGE:
			status_label.text = "SABOTAJE: Retrocede 4 pasos"
			await piece._move_backward(4)
			movement_manager._check_stacking(piece.current_position)
		
		CardManager.CardType.FREEZE:
			piece._apply_freeze(1)
			status_label.text = "HIELO: Ficha congelada por 1 turno!"
	
	turn_manager.current_state = TurnManager.State.IDLE
	_update_card_display()
	await get_tree().create_timer(1.2).timeout
	status_label.text = "Turno de " + player.display_name.to_upper() + " — [Espacio] lanzar | [Q] cartas"

func _on_jail_exited_card(_piece: Piece):
	movement_manager._check_capture(_piece)
	movement_manager._check_stacking(_piece.current_position)
	movement_manager.reset_capture_flag()

func _draw_card_for_player(player_index: int):
	var card = card_manager.draw_card(player_index)
	if card != -1:
		card_label.text += "  |  +" + card_manager.get_card_icon(card) + " " + card_manager.get_card_name(card)

func _update_card_display():
	var hand = card_manager.get_hand(turn_manager.current_player_index)
	if hand.is_empty():
		card_label.text = "[Q] Cartas: ninguna"
		return
	var text = "[Q] Cartas: "
	for i in range(hand.size()):
		var info = CardManager.CARD_INFO[hand[i]]
		text += info["icon"] + info["name"]
		if i < hand.size() - 1:
			text += " | "
	card_label.text = text



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
	turn_manager.bonus_came_from_dice = 2
	turn_manager.current_state = TurnManager.State.BONUS_MOVE
	turn_manager.bonus_move_available.emit(10)

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
	jail_roll_attempts = 0
	roll_cooldown = false
	if game_over:
		return
	status_label.text = "Turno de " + players[player_index].display_name.to_upper() + " — [Espacio] lanzar | [Q] cartas"
	_update_card_display()

func _on_turn_ended(_player_index: int):
	if game_over:
		return
	dice_manager.clear_for_turn_end()

func _on_victory_achieved(player: Player):
	game_over = true
	status_label.text = "¡" + player.display_name.to_upper() + " GANA!"
	status_label.visible = true

func _start_roll_cooldown():
	roll_cooldown = true
	await get_tree().create_timer(ROLL_COOLDOWN_TIME).timeout
	roll_cooldown = false

func _mark_special_squares():
	for idx in SquareEffects.CARD_SQUARES:
		_place_marker(idx, Color(0.2, 0.6, 1.0))
	for idx in SquareEffects.SPEED_BOOST_SQUARES:
		_place_marker(idx, Color(1.0, 0.8, 0.0))
	for idx in SquareEffects.TRAP_SQUARES:
		_place_marker(idx, Color(1.0, 0.2, 0.2))

func _place_marker(square_index: int, color: Color):
	var mesh_instance = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.03
	cylinder.bottom_radius = 0.03
	cylinder.height = 0.002
	mesh_instance.mesh = cylinder
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	mesh_instance.material_override = mat
	
	var pos = board.main_path[square_index].global_position
	mesh_instance.global_position = Vector3(pos.x, 0.012, pos.z)
	add_child(mesh_instance)
