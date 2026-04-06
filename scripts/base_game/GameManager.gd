extends Node

@onready var camera_markers = [
	$"../yellow", $"../blue", $"../red", $"../green"
]
@onready var status_label: Label = $"../UI/GameUI/StatusLabel" 

var Piece = preload("res://scenes/piece.tscn")
var card_scene = preload("res://scenes/card_3d.tscn")

var hand_display: HandDisplay
var turn_manager: TurnManager
var movement_manager: MovementManager
var dice_manager: DiceManager
var camera_controller: CameraController
var hover_manager: HoverManager
var card_manager: CardManager
var camera: Camera3D
var players = []
var board = null
var game_over: bool = false

var pending_card_screen_pos: Vector2 = Vector2.ZERO
var deck_pile_cards: Array = []
var discard_pile_top: Card3D = null
var pending_card_index: int = -1
var pending_card_type: int = -1
var roll_cooldown: bool = false
var jail_roll_attempts: int = 0
var is_ready: bool = false
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
	_setup_deck_display()
	
	for i in range(players.size()):
		card_manager.draw_card(i)
		card_manager.draw_card(i)
	
	turn_manager.start_turn(0)
	camera_controller.move_to_player(0, true)
	is_ready = true

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

func _setup_card_ui():
	hand_display = HandDisplay.new()
	hand_display.name = "HandDisplay"
	$"../UI/GameUI".add_child(hand_display)
	hand_display.setup()
	hand_display.card_clicked.connect(_on_hand_card_clicked)
	hand_display.hide_hand()
	
	hand_display.card_clicked.connect(_on_hand_card_clicked)
	hand_display.hide_hand()

func _on_hand_card_clicked(card_index: int, screen_position: Vector2):
	if turn_manager.current_state not in [TurnManager.State.IDLE, TurnManager.State.DRAW_PHASE]:
		return
	if turn_manager.card_used_this_turn:
		return
	
	pending_card_screen_pos = screen_position
	_select_card(card_index)

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

func _setup_deck_display():
	var deck_pos = Vector3(0.95, 0.03, -0.1)
	var discard_pos = Vector3(0.95, 0.03, 0.1)
	
	for i in range(35):
		var card = card_scene.instantiate()
		card.card_type = -1
		card.position = deck_pos + Vector3(0, i * 0.002, 0)
		get_parent().add_child(card)
		deck_pile_cards.append(card)
	
	discard_pile_top = card_scene.instantiate()
	discard_pile_top.card_type = -1
	discard_pile_top.position = discard_pos
	discard_pile_top.visible = false
	get_parent().add_child(discard_pile_top)

func _input(event):
	if game_over or not is_ready:
		return
	
	if event is InputEventKey and (not event.pressed or event.echo):
		return
	
	var key = event.keycode if event is InputEventKey else -1
	
	if turn_manager.current_state == TurnManager.State.DRAW_PHASE:
		if event.is_action_pressed("ui_accept"):
			turn_manager.current_state = TurnManager.State.IDLE
			_roll_dice()
			return
		elif key == KEY_R:
			_draw_card_phase()
			return
	
	if turn_manager.current_state == TurnManager.State.IDLE:
		if event.is_action_pressed("ui_accept") and not roll_cooldown:
			_roll_dice()
			return
	
	if turn_manager.current_state == TurnManager.State.CARD_TARGET:
		if key == KEY_ESCAPE:
			_cancel_card()
			return
	
func _draw_card_phase():
	var player_idx = turn_manager.current_player_index
	
	if card_manager.get_hand(player_idx).size() >= CardManager.MAX_HAND_SIZE:
		status_label.text = "Mano llena (máx 5 cartas)"
		await get_tree().create_timer(1.0).timeout
		turn_manager.current_state = TurnManager.State.IDLE
		status_label.text = "Mano llena — [Espacio] para lanzar dados"
		return
	
	if card_manager.deck.is_empty():
		discard_pile_top.visible = false
		await _animate_deck_refill()
		# re-mostrar tope del mazo
		if deck_pile_cards.size() > 0:
			deck_pile_cards[0].visible = true

	var card_type = card_manager.draw_card(player_idx)
	
	var animated_card = card_scene.instantiate()
	animated_card.card_type = -1
	get_parent().add_child(animated_card)
	
	var deck_world_pos = deck_pile_cards[card_manager.get_deck_size()].global_position \
		if card_manager.get_deck_size() < deck_pile_cards.size() \
		else Vector3(0.95, 0.03, -0.1)
	animated_card.global_position = deck_world_pos
	
	var hand_index = card_manager.get_hand(player_idx).size() - 1  # Última carta añadida
	var screen_pos = _get_hand_card_screen_position(hand_index)
	var target_world_pos = _screen_to_world_position(screen_pos)
	
	var tween = create_tween()
	tween.tween_property(animated_card, "global_position", target_world_pos, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(animated_card, "rotation:y", PI, 0.4)  # Gira mientras vuela
	
	await tween.finished
	
	animated_card.queue_free()
	_update_card_display()
	
	var card_name = card_manager.get_card_name(card_type)
	var card_icon = card_manager.get_card_icon(card_type)
	status_label.text = "Robaste: " + card_icon + " " + card_name
	await get_tree().create_timer(1.0).timeout
	status_label.text = "Carta robada — Turno terminado"
	await get_tree().create_timer(0.5).timeout
	turn_manager.end_turn()

func _get_hand_card_screen_position(card_index: int) -> Vector2:
	var vp = get_tree().root.get_viewport().get_visible_rect().size
	var hand = card_manager.get_hand(turn_manager.current_player_index)
	var count = hand.size()
	var total_width = count * (HandDisplay.CARD_SIZE.x + 10) - 10
	var start_x = vp.x / 2.0 - total_width / 2.0
	var card_x = start_x + card_index * (HandDisplay.CARD_SIZE.x + 10) + HandDisplay.CARD_SIZE.x / 2
	var card_y = vp.y - HandDisplay.CARD_SIZE.y / 1.75
	return Vector2(card_x, card_y)

func _screen_to_world_position(screen_pos: Vector2) -> Vector3:
	var camera = get_viewport().get_camera_3d()
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	
	var plane = Plane(Vector3.UP, 0.5)
	var intersection = plane.intersects_ray(ray_origin, ray_dir)
	
	if intersection:
		return intersection
	return Vector3.ZERO

func _roll_dice():
	roll_cooldown = true
	hand_display.hide_hand()
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
	
	if piece_ref.is_frozen:
		status_label.text = "¡Esa ficha está congelada!"
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
		status_label.text = "Necesitas un par para salir de la carcel"
		return
	
	if turn_manager.current_state not in [TurnManager.State.MOVE_DICE_1, TurnManager.State.MOVE_DICE_2]:
		status_label.text = "Accion no permitida ahora"
		return
	
	var pieces_at_start = 0
	for p in piece.player.pieces:
		if not p.in_jail and not p.is_finished and p.current_position == piece.start_index:
			pieces_at_start += 1
	
	if pieces_at_start >= 2:
		status_label.text = "No se puede salir: ya hay 2 fichas en la salida"
		return
	
	piece.jail_exited.connect(_on_jail_exited, CONNECT_ONE_SHOT)
	piece._leave_jail()

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
		turn_manager.current_roll["bonus"] = 10
		turn_manager.current_state = TurnManager.State.BONUS_MOVE
		turn_manager.bonus_came_from_dice = 0 
		turn_manager.bonus_move_available.emit(10)
		status_label.text = "¡Captura! Bonus de 10 pasos"
	else:
		status_label.text = "Ficha liberada! Turno terminado."
		await get_tree().create_timer(0.8).timeout
		turn_manager.end_turn()

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
		if not piece.in_jail and not piece.is_finished and not piece.is_frozen:
			if movement_manager.can_move_piece(piece, steps):
				return true
	
	return false

func _try_open_cards():
	var hand = card_manager.get_hand(turn_manager.current_player_index)
	if hand.is_empty():
		status_label.text = "No tienes cartas"
		return
	turn_manager.current_state = TurnManager.State.CARD_SELECT
	_show_card_selection()

func _show_card_selection():
	var hand = card_manager.get_hand(turn_manager.current_player_index)
	var text = "ELIGE CARTA: "
	for i in range(hand.size()):
		var info = CardManager.CARD_INFO[hand[i]]
		text += "[" + str(i + 1) + "] " + info["icon"] + " " + info["name"] + "  "
	text += "| [Esc] Cancelar"
	status_label.text = text

func _select_card(card_index: int):
	var hand = card_manager.get_hand(turn_manager.current_player_index)
	if card_index < 0 or card_index >= hand.size():
		status_label.text = "Carta inválida"
		return
	
	var card_type = card_manager.use_card(turn_manager.current_player_index, pending_card_index) 
	_update_discard_display(card_type)
	
	pending_card_index = card_index
	pending_card_type = hand[card_index]
	var target = card_manager.get_card_target(pending_card_type)
	
	match target:
		"none":
			_apply_no_target_card()
		"own":
			turn_manager.current_state = TurnManager.State.CARD_TARGET
			status_label.text = CardManager.CARD_INFO[pending_card_type]["icon"] + " Selecciona una de tus fichas activas"
			hand_display.hide_hand()  # ← agregá
		"own_jail":
			turn_manager.current_state = TurnManager.State.CARD_TARGET
			status_label.text = "FUGA: Selecciona una ficha tuya en la carcel"
			hand_display.hide_hand()  # ← agregá
		"enemy":
			turn_manager.current_state = TurnManager.State.CARD_TARGET
			status_label.text = CardManager.CARD_INFO[pending_card_type]["icon"] + " Selecciona una ficha enemiga"
			hand_display.hide_hand() 
		"enemy_any":
			turn_manager.current_state = TurnManager.State.CARD_TARGET
			status_label.text = "[L] Selecciona una ficha enemiga"
			hand_display.hide_hand()

func _apply_no_target_card():
	var player_idx = turn_manager.current_player_index
	var card_type = card_manager.use_card(player_idx, pending_card_index)
	
	_update_discard_display(card_type)
	
	if pending_card_type == CardManager.CardType.DOUBLE:
		turn_manager.double_next_roll = true
		status_label.text = "DOBLE: Tu proximo lanzamiento sera DOBLE!"
	
	pending_card_index = -1
	pending_card_type = -1
	turn_manager.current_state = TurnManager.State.IDLE
	turn_manager.card_used_this_turn = true
	_update_card_display()

func _update_discard_display(card_type: int):
	if discard_pile_top:
		discard_pile_top.card_type = card_type
		discard_pile_top.visible = true
	

func _animate_card_to_discard(card_type: int, from_screen_pos: Vector2):
	var animated_card = card_scene.instantiate()
	animated_card.card_type = card_type
	get_parent().add_child(animated_card)
	
	var start_world_pos = _screen_to_world_position(from_screen_pos)
	animated_card.global_position = start_world_pos
	
	var target_pos = discard_pile_top.global_position + Vector3(0, 0.002 * card_manager.discard.size(), 0)
	
	var tween = create_tween()
	tween.tween_property(animated_card, "global_position", target_pos, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(animated_card, "rotation:y", 0, 0.4)  # Enderezar
	
	await tween.finished
	
	animated_card.queue_free()
	_update_discard_display(card_type)

func _cancel_card():
	turn_manager.current_state = TurnManager.State.IDLE
	status_label.text = "Turno de " + players[turn_manager.current_player_index].display_name.to_upper() + " — [Espacio] lanzar"

func _handle_card_target(piece: Piece):
	var player = players[turn_manager.current_player_index]
	var target = card_manager.get_card_target(pending_card_type)
	
	match target:
		"own":
			if piece.player != player or piece.in_jail or piece.is_finished:
				status_label.text = "Selecciona una ficha tuya activa"
				hand_display.hide_hand()
				return
		"own_jail":
			if piece.player != player or not piece.in_jail:
				status_label.text = "Selecciona una ficha tuya en la cárcel"
				hand_display.hide_hand()
				return
		"enemy":
			if piece.player == player or piece.in_jail or piece.is_finished:
				status_label.text = "Selecciona una ficha enemiga activa"
				hand_display.hide_hand()
				return
		"enemy_any":
			if piece.player == player:
				status_label.text = "Selecciona una ficha enemiga"
				return
	
	var card_type = pending_card_type
	card_manager.use_card(turn_manager.current_player_index, pending_card_index)
	pending_card_index = -1
	pending_card_type = -1
	
	match card_type:
		CardManager.CardType.TURBO:
			if movement_manager.can_move_piece(piece, 5):
				status_label.text = "TURBO: +5 pasos!"
				await movement_manager.move_piece(piece, 5, false)
				var captured = movement_manager.captured_this_turn
				movement_manager.reset_capture_flag()
				movement_manager._check_stacking(piece.current_position)
			else:
				status_label.text = "TURBO: No puede moverse -- carta gastada"
		CardManager.CardType.SHIELD:
			piece.apply_shield(2)
			status_label.text = "ESCUDO: Activado por 2 turnos!"
		CardManager.CardType.JAILBREAK:
			var pieces_at_start = 0
			for p in piece.player.pieces:
				if not p.in_jail and not p.is_finished and p.current_position == piece.start_index:
					pieces_at_start += 1
			if pieces_at_start >= 2:
				status_label.text = "FUGA: No hay espacio -- carta gastada"
			else:
				status_label.text = "FUGA: Exitosa!"
				piece.jail_exited.connect(_on_jailbreak_card_exited, CONNECT_ONE_SHOT)  # ← callback propio
				piece._leave_jail()
		CardManager.CardType.SABOTAGE:
			status_label.text = "SABOTAJE: Retrocede 4 pasos"
			await piece._move_backward(4)
			movement_manager._check_stacking(piece.current_position)
		CardManager.CardType.FREEZE:
			piece.apply_freeze(1)
			status_label.text = "HIELO: Ficha congelada por 1 turno!"
		CardManager.CardType.THIEF:
			var stolen = card_manager.steal_random_card(piece.player.player_id, turn_manager.current_player_index)
			if stolen != -1:
				status_label.text = "LADRON: Robaste " + card_manager.get_card_name(stolen) + " a " + piece.player.display_name + "!"
			else:
				status_label.text = "LADRON: Ese jugador no tiene cartas..."
	
	turn_manager.current_state = TurnManager.State.IDLE
	turn_manager.card_used_this_turn = true 
	_update_card_display()
	await get_tree().create_timer(1.2).timeout
	status_label.text = "Turno de " + player.display_name.to_upper() + " — [Espacio] lanzar | [Q] cartas"
	hand_display.hide_hand()

func _on_jailbreak_card_exited(piece: Piece):
	movement_manager._check_capture(piece)
	movement_manager._check_stacking(piece.current_position)
	movement_manager.reset_capture_flag()

func _update_card_display():
	var hand = card_manager.get_hand(turn_manager.current_player_index)
	hand_display.show_hand(hand)
	if turn_manager.current_state in [TurnManager.State.IDLE, TurnManager.State.DRAW_PHASE] \
	   and not turn_manager.card_used_this_turn:
		hand_display.reveal_hand()
	else:
		hand_display.hide_hand()

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
	
	if turn_manager.current_state == TurnManager.State.DRAW_PHASE:
		status_label.text = "Turno de " + players[player_index].display_name.to_upper() + " — [R] Robar carta | [Espacio] Lanzar dados"
	else:
		status_label.text = "Turno de " + players[player_index].display_name.to_upper() + " — [Espacio] lanzar"
	
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

func _animate_deck_refill():
	# Animar las cartas del descarte volando de vuelta al mazo
	var discard_pos = Vector3(0.95, 0.03, 0.1)
	var deck_pos = Vector3(0.95, 0.03, -0.1)
	
	var temp_card = card_scene.instantiate()
	temp_card.card_type = -1  # respaldo
	get_parent().add_child(temp_card)
	temp_card.global_position = discard_pos + Vector3(0, 0.01, 0)
	
	var tween = create_tween()
	tween.tween_property(temp_card, "global_position", deck_pos + Vector3(0, 0.07, 0), 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(temp_card, "rotation:y", PI, 0.3)
	tween.tween_callback(temp_card.queue_free)
	
	await tween.finished
