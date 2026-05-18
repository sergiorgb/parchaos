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
var event_manager: EventManager
var camera: Camera3D
var ai_controllers: Array = []
var players = []
var board = null
var game_over: bool = false
var is_processing: bool = false
var pending_card_screen_pos: Vector2 = Vector2.ZERO
var deck_pile_cards: Array = []
var discard_pile_top: Card3D = null
var pending_card_index: int = -1
var pending_card_type: int = -1
var roll_cooldown: bool = false
var jail_roll_attempts: int = 0
var is_ready: bool = false
var pending_alliance_target_player: int = -1
var alliance_popup: PanelContainer = null
var wormhole_markers: Array = []  # [MeshInstance3D, MeshInstance3D]
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
	
	var event_label: Label = $"../UI/GameUI/EventLabel"
	var event_counter_label: Label = $"../UI/GameUI/EventCounterLabel"
	
	_setup_ui_styles(event_label, event_counter_label)
	
	event_manager = EventManager.new()
	add_child(event_manager)
	event_manager.setup(players, turn_manager, movement_manager, event_label, event_counter_label)
	event_manager.extra_turn_requested.connect(_on_extra_turn_requested)
	event_manager.wormhole_activated.connect(_on_wormhole_activated)
	event_manager.wormhole_deactivated.connect(_on_wormhole_deactivated)
	movement_manager.event_manager = event_manager
	movement_manager.mine_triggered.connect(_on_mine_triggered)
	movement_manager.alliance_expired.connect(_on_alliance_expired)
	
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
	movement_manager.setup(board, players, event_manager)
	movement_manager.capture_happened.connect(_on_capture_happened)
	movement_manager.victory_achieved.connect(_on_victory_achieved)
	
	turn_manager = TurnManager.new()
	add_child(turn_manager)
	turn_manager.setup(players)	
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.bonus_move_available.connect(_on_bonus_move)
	turn_manager.penalty_select_piece.connect(_on_penalty)
	turn_manager.break_barrier_requested.connect(_on_break_barrier_requested)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.turn_ended_ready_for_next.connect(_on_turn_ready_for_next)
	
	hover_manager = HoverManager.new()
	add_child(hover_manager)
	hover_manager.setup(board, turn_manager, movement_manager)
	
	card_manager = CardManager.new()
	add_child(card_manager)
	
	for i in range(4):
		var config = GameConfig.player_config[i]
		var ctrl = AIController.new()
		ctrl.setup(config["difficulty"] as AIController.Difficulty)
		add_child(ctrl)
		ai_controllers.append(ctrl)
	

func _setup_card_ui():
	hand_display = HandDisplay.new()
	hand_display.name = "HandDisplay"
	$"../UI/GameUI".add_child(hand_display)
	hand_display.setup()
	hand_display.card_clicked.connect(_on_hand_card_clicked)
	hand_display.hide_hand()

func _setup_ui_styles(event_label: Label, event_counter_label: Label):
	var ui = $"../UI/GameUI"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # Fix off-screen anchors
	
	# Main container for both panels, anchored to TOP RIGHT
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	main_vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	main_vbox.offset_top = 15
	main_vbox.offset_right = -15
	main_vbox.add_theme_constant_override("separation", 10)
	ui.add_child(main_vbox)
	
	# Status Label (Turn thing)
	var status_panel = PanelContainer.new()
	var status_style = StyleBoxFlat.new()
	status_style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	status_style.set_corner_radius_all(16)
	status_style.set_border_width_all(2)
	status_style.border_color = Color(0.9, 0.7, 0.2, 0.6)
	status_style.content_margin_left = 20
	status_style.content_margin_right = 20
	status_style.content_margin_top = 10
	status_style.content_margin_bottom = 10
	status_panel.add_theme_stylebox_override("panel", status_style)
	
	status_label.get_parent().remove_child(status_label)
	status_panel.add_child(status_label)
	main_vbox.add_child(status_panel)
	
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# Fix legibility: clear black modulate from scene
	status_label.modulate = Color(1, 1, 1, 1)
	status_label.self_modulate = Color(1, 1, 1, 1)
	
	var font_settings = LabelSettings.new()
	font_settings.font_size = 18
	font_settings.font_color = Color(0.95, 0.95, 0.95)
	status_label.label_settings = font_settings
	
	# Event Labels (Next Event & Current Event)
	var event_panel = PanelContainer.new()
	var event_style = StyleBoxFlat.new()
	event_style.bg_color = Color(0.12, 0.08, 0.18, 0.9)
	event_style.set_corner_radius_all(16)
	event_style.set_border_width_all(2)
	event_style.border_color = Color(0.6, 0.4, 0.9, 0.6)
	event_style.content_margin_left = 15
	event_style.content_margin_right = 15
	event_style.content_margin_top = 15
	event_style.content_margin_bottom = 15
	event_panel.add_theme_stylebox_override("panel", event_style)
	
	var event_vbox = VBoxContainer.new()
	event_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	event_vbox.add_theme_constant_override("separation", 8)
	event_panel.add_child(event_vbox)
	
	event_label.get_parent().remove_child(event_label)
	event_counter_label.get_parent().remove_child(event_counter_label)
	
	event_vbox.add_child(event_counter_label)
	event_vbox.add_child(event_label)
	main_vbox.add_child(event_panel)
	
	# Force both to be identically sized and aligned
	main_vbox.custom_minimum_size = Vector2(550, 0)
	status_panel.size_flags_horizontal = Control.SIZE_FILL
	event_panel.size_flags_horizontal = Control.SIZE_FILL
	
	event_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	var count_settings = LabelSettings.new()
	count_settings.font_size = 18
	count_settings.font_color = Color(0.6, 0.8, 1.0)
	event_counter_label.label_settings = count_settings
	
	var title_settings = LabelSettings.new()
	title_settings.font_size = 16
	title_settings.font_color = Color(0.9, 0.7, 1.0)
	event_label.label_settings = title_settings

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
		var config = GameConfig.player_config[data.id]
		player.setup(data.id, data.color, data.name, data.start_index, data.home_entry, config["is_ai"])
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
		if event.is_action_pressed("ui_accept") and not is_processing:
			turn_manager.current_state = TurnManager.State.IDLE
			_roll_dice()
			return
		elif key == KEY_R and not is_processing:
			_draw_card_phase()
			return

	if turn_manager.current_state == TurnManager.State.IDLE:
		if event.is_action_pressed("ui_accept") and not roll_cooldown and not is_processing:
			_roll_dice()
			return
	
	if turn_manager.current_state == TurnManager.State.CARD_TARGET:
		if key == KEY_ESCAPE:
			_cancel_card()
			return
			
	
func _draw_card_phase():
	if is_processing:
		return
	is_processing = true
	var player_idx = turn_manager.current_player_index
	
	if card_manager.get_hand(player_idx).size() >= CardManager.MAX_HAND_SIZE:
		status_label.text = "Mano llena (máx 5 cartas)"
		await get_tree().create_timer(1.0).timeout
		turn_manager.current_state = TurnManager.State.IDLE
		status_label.text = "Mano llena — [Espacio] para lanzar dados"
		is_processing = false
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
	is_processing = false

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
	if event_manager.get_handicap_player_id() == turn_manager.current_player_index:
		turn_manager.double_next_roll = true
	dice_manager.roll_for_player(turn_manager.current_player_index)

func _on_dice_stopped(results: Array):
	movement_manager.reset_capture_flag()
	var final_results = results
	if event_manager.is_dados_inversos_active():
		final_results = event_manager.invert_dice(results)
		status_label.text = "Dados Inversos: " + str(final_results[0]) + " - " + str(final_results[1])
		await get_tree().create_timer(1.0).timeout
	turn_manager.process_roll(final_results)
	var player = players[turn_manager.current_player_index]
	var all_in_jail = not player.pieces.any(func(p): return not p.in_jail and not p.is_finished)
	var is_pair = turn_manager.current_roll.get("pair", false)
	
	if all_in_jail and not is_pair:
		jail_roll_attempts += 1
		if jail_roll_attempts < MAX_JAIL_ROLLS:
			status_label.text = "No sacaste par! Intento " + str(jail_roll_attempts) + "/" + str(MAX_JAIL_ROLLS) + " -- Presiona espacio"
			turn_manager.current_state = TurnManager.State.IDLE
			_start_roll_cooldown()
			if players[turn_manager.current_player_index].is_ai:
				await get_tree().create_timer(1.0).timeout
				_do_ai_turn(turn_manager.current_player_index)
			return
		else:
			status_label.text = "3 intentos fallidos. Pasando turno..."
			await get_tree().create_timer(1.5).timeout
			turn_manager.end_turn()
			return
		
	
	
	if not _has_any_valid_move() and turn_manager.current_state != TurnManager.State.PENALTY_JAIL and turn_manager.current_state != TurnManager.State.BREAK_BARRIER_FIRST:
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
		
	if players[turn_manager.current_player_index].is_ai:
		await get_tree().create_timer(1.0).timeout
		_do_ai_pick_piece()
	
	_start_roll_cooldown()

func _do_ai_pick_piece():
	var player_index = turn_manager.current_player_index
	var context = {
		"player": players[player_index],
		"board": board,
		"movement_manager": movement_manager,
		"has_broken_barrier": turn_manager.has_broken_barrier_this_turn,
		"turn_manager": turn_manager,
		"card_manager": card_manager,
		"steps": turn_manager.get_current_steps(),
		"is_pair": turn_manager.current_roll.get("pair", false)
	}
	var piece = ai_controllers[turn_manager.current_player_index].decide_piece(context)
	if piece:
		await get_tree().create_timer(0.3).timeout
		_on_piece_clicked(piece)

func _on_piece_clicked(piece_ref: GamePiece):
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

func _handle_jail_exit(piece: GamePiece):
	var is_pair = turn_manager.current_roll.get("pair", false)
	
	if not is_pair:
		status_label.text = "Necesitas un par para salir de la carcel"
		return
	
	if turn_manager.has_broken_barrier_this_turn:
		status_label.text = "Ya rompiste barrera, no puedes sacar ficha"
		return
	
	if turn_manager.current_state not in [TurnManager.State.MOVE_DICE_1, TurnManager.State.MOVE_DICE_2]:
		status_label.text = "Accion no permitida ahora"
		if players[turn_manager.current_player_index].is_ai:
			await get_tree().create_timer(0.5).timeout
			_do_ai_pick_piece()
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

func _on_jail_exited(_piece: GamePiece):
	movement_manager._check_capture(_piece)
	movement_manager._check_stacking(_piece.current_position)
	var captured = movement_manager.captured_this_turn
	movement_manager.reset_capture_flag()
	
	if captured:
		turn_manager.current_roll["bonus"] = 10
		turn_manager.current_state = TurnManager.State.BONUS_MOVE
		turn_manager.bonus_came_from_dice = 2
		turn_manager.bonus_move_available.emit(10)
		status_label.text = "¡Captura! Bonus de 10 pasos"
		if players[turn_manager.current_player_index].is_ai:
			await get_tree().create_timer(0.75).timeout
			_do_ai_pick_piece()
	else:
		status_label.text = "Ficha liberada! Turno terminado."
		await get_tree().create_timer(0.8).timeout
		turn_manager.end_turn()

func _handle_break_barrier_first(piece: GamePiece):
	var barrier_pieces = movement_manager.get_barrier_pieces_at(piece.current_position, piece.player)
	
	if barrier_pieces.size() < 2:
		status_label.text = "Selecciona una ficha que forme parte de una barrera"
		return
	
	var steps = turn_manager.current_roll.get("dice1", 0)

# Verificar antes de mover
	if not movement_manager.can_move_piece(piece, steps, true):
		status_label.text = "¡Barrera bloqueada! Una ficha va a la cárcel como penalización"
		await get_tree().create_timer(1.0).timeout

	await movement_manager.break_barrier(piece, steps)
	
	var captured = movement_manager.captured_this_turn
	movement_manager.reset_capture_flag()
	
	turn_manager.has_broken_barrier_this_turn = true
	
	if captured:
		turn_manager.current_roll["bonus"] = 10
		turn_manager.current_state = TurnManager.State.BONUS_MOVE
		turn_manager.bonus_came_from_dice = 1
		turn_manager.bonus_move_available.emit(10)
		status_label.text = "¡Captura al romper barrera! Bonus de 10 pasos"
		if players[turn_manager.current_player_index].is_ai:
			await get_tree().create_timer(0.75).timeout
			_do_ai_pick_piece()
	else:
		turn_manager.current_state = TurnManager.State.MOVE_DICE_2
		status_label.text = "Barrera rota! Ahora mueve " + str(turn_manager.current_roll.get("dice2", 0)) + " pasos con otra ficha"
		if players[turn_manager.current_player_index].is_ai:
			await get_tree().create_timer(0.75).timeout
			_do_ai_pick_piece()

func _execute_move(piece: GamePiece, steps: int):
	var is_pair = turn_manager.current_roll.get("pair", false)
	var is_own_barrier = false
	
	if not piece.in_home_path:
		var steps_to_entry = piece._steps_to_entry(piece.current_position)
		if steps < steps_to_entry:
			var target_pos = (piece.current_position + steps) % board.main_path.size()
			is_own_barrier = movement_manager.is_own_barrier_at_pos(piece, target_pos)
	
	if is_own_barrier:
		if is_pair:
			turn_manager.pending_move_piece = Piece
			turn_manager.pending_move_steps = steps
			turn_manager.break_barrier_requested.emit()
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
	
	# Check mine and wormhole after move
	movement_manager.check_mine(piece)
	await event_manager.check_wormhole(piece)
	
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
			if players[turn_manager.current_player_index].is_ai:
				await get_tree().create_timer(1.0).timeout
				_do_ai_pick_piece()
		TurnManager.State.BONUS_MOVE:
			dice_manager.reset_dice_highlight(1)
			status_label.text = "¡Bonus! Mueve " + str(turn_manager.current_roll.get("bonus", 0)) + " pasos"
			status_label.visible = true
			if players[turn_manager.current_player_index].is_ai:
				await get_tree().create_timer(1.0).timeout
				_do_ai_pick_piece()
		TurnManager.State.IDLE:
			dice_manager.reset_dice_highlight(1)
			
	if turn_manager.current_state == TurnManager.State.BONUS_MOVE:
		if not _has_any_valid_move():
			status_label.text = "Sin movimientos posibles con bonus. Pasando turno..."
			await get_tree().create_timer(1.5).timeout
			turn_manager.end_turn()
			return
	
	_update_card_display()

func _has_any_valid_move() -> bool:
	var current_player = players[turn_manager.current_player_index]
	var steps = turn_manager.get_current_steps()
	var is_pair = turn_manager.current_roll.get("pair", false)
	
	for piece in current_player.pieces:
		if piece.is_finished:
			continue
		
		if piece.in_jail:
			if is_pair:
				# verificar que no haya ya 2 fichas propias en la salida
				var pieces_at_start = 0
				for p in current_player.pieces:
					if not p.in_jail and not p.is_finished and p.current_position == piece.start_index:
						pieces_at_start += 1
				if pieces_at_start < 2:
					return true
			continue
		
		if piece.is_frozen:
			continue
		
		if movement_manager.can_move_piece(piece, steps):
			return true
	
	return false

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
			var card_icon = CardManager.CARD_INFO[pending_card_type]["icon"]
			status_label.text = card_icon + " Selecciona una ficha enemiga"
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
	await _animate_card_to_discard(card_type, pending_card_screen_pos)

func _update_discard_display(_card_type: int):
	if discard_pile_top:
		discard_pile_top.visible = true

func _animate_card_to_discard(card_type: int, from_screen_pos: Vector2):
	var animated_card = card_scene.instantiate()
	animated_card.card_type = -1 
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

func _handle_card_target(piece: GamePiece):
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
				movement_manager._check_stacking(piece.current_position)
				movement_manager.check_mine(piece)
				await event_manager.check_wormhole(piece)
				if movement_manager.captured_this_turn:
					movement_manager.reset_capture_flag()
					turn_manager.current_roll["bonus"] = 10
					turn_manager.bonus_came_from_dice = 2
					turn_manager.current_state = TurnManager.State.BONUS_MOVE
					turn_manager.bonus_move_available.emit(10)
					return  # no continuar al final que resetea el estado
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
			movement_manager.check_mine(piece)
			await event_manager.check_wormhole(piece)
		CardManager.CardType.FREEZE:
			piece.apply_freeze(1)
			status_label.text = "HIELO: Ficha congelada por 1 turno!"
		CardManager.CardType.THIEF:
			var stolen = card_manager.steal_random_card(piece.player.player_id, turn_manager.current_player_index)
			if stolen != -1:
				status_label.text = "LADRON: Robaste " + card_manager.get_card_name(stolen) + " a " + piece.player.display_name + "!"
			else:
				status_label.text = "LADRON: Ese jugador no tiene cartas..."
		CardManager.CardType.MINE:
			movement_manager.place_mine(piece.current_position, player.player_id)
			status_label.text = "MINA: ¡Mina colocada en casilla " + str(piece.current_position) + "!"
		CardManager.CardType.GHOST:
			piece.apply_ghost(1)
			status_label.text = "FANTASMA: ¡Ficha intangible por 1 turno!"
		CardManager.CardType.ALLIANCE:
			pending_alliance_target_player = piece.player.player_id
			if piece.player.is_ai:
				var accepted = _ai_decide_alliance(piece.player.player_id, turn_manager.current_player_index)
				if accepted:
					movement_manager.add_alliance(turn_manager.current_player_index, piece.player.player_id, 5)
					status_label.text = "ALIANZA: ¡" + piece.player.display_name.to_upper() + " aceptó! Sin capturas mutuas por 5 turnos"
				else:
					status_label.text = "ALIANZA: " + piece.player.display_name.to_upper() + " rechazó la alianza"
				pending_alliance_target_player = -1
			else:
				# Human player — show UI popup
				_show_alliance_popup(turn_manager.current_player_index, piece.player.player_id)
				return  # Don't continue — popup handles state
	
	turn_manager.current_state = TurnManager.State.IDLE
	turn_manager.card_used_this_turn = true 
	await _animate_card_to_discard(card_type, pending_card_screen_pos)
	
	await get_tree().create_timer(1.2).timeout
	status_label.text = "Turno de " + player.display_name.to_upper() + " — [Espacio] lanzar | [Q] cartas"
	hand_display.hide_hand()

func _on_jailbreak_card_exited(piece: GamePiece):
	movement_manager._check_capture(piece)
	movement_manager._check_stacking(piece.current_position)
	movement_manager.reset_capture_flag()

func _update_card_display():
	if discard_pile_top:
		discard_pile_top.visible = true
	var hand = card_manager.get_hand(turn_manager.current_player_index)
	hand_display.show_hand(hand)
	if turn_manager.current_state in [TurnManager.State.IDLE, TurnManager.State.DRAW_PHASE] \
	   and not turn_manager.card_used_this_turn:
		hand_display.reveal_hand()
	else:
		hand_display.hide_hand()

func _execute_penalty(piece: GamePiece):
	piece._go_to_jail()
	turn_manager.end_turn()

func _on_capture_happened(_enemy: GamePiece, bonus: int):
	if event_manager.is_tregua_active():
		return
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
	if players[turn_manager.current_player_index].is_ai:
		await get_tree().create_timer(0.75).timeout
		_do_ai_break_barrier()

func _do_ai_break_barrier():
	var player = players[turn_manager.current_player_index]
	for piece in player.pieces:
		var barrier_pieces = movement_manager.get_barrier_pieces_at(piece.current_position, player)
		if barrier_pieces.size() >= 2:
			_handle_break_barrier_first(piece)
			return

func _on_penalty():
	status_label.text = "¡3 pares! Elige ficha para cárcel"

func _on_turn_started(player_index: int):
	is_processing = true
	var cam_tween = camera_controller.move_to_player(player_index)
	if cam_tween:
		await cam_tween.finished
	is_processing = false
	
	jail_roll_attempts = 0
	roll_cooldown = false
	await event_manager.on_turn_started(player_index)
	turn_manager.order_reversed = event_manager.is_reversa_active()
	if game_over:
		return
	
	if turn_manager.current_state == TurnManager.State.DRAW_PHASE:
		status_label.text = "Turno de " + players[player_index].display_name.to_upper() + " — [R] Robar carta | [Espacio] Lanzar dados"
	else:
		status_label.text = "Turno de " + players[player_index].display_name.to_upper() + " — [Espacio] lanzar"
	
	if players[player_index].is_ai:
		_do_ai_turn(player_index)
	_update_card_display()

func _on_turn_ended(_player_index: int):
	event_manager.on_turn_ended(_player_index)
	movement_manager.tick_alliances()
	if game_over:
		return
	dice_manager.clear_for_turn_end()

func _on_turn_ready_for_next(next_index: int):
	if game_over:
		return
	if event_manager.processing_extra_turn:
		return
	turn_manager.order_reversed = event_manager.is_reversa_active()
	var correct_next = event_manager.get_next_player_index(turn_manager.current_player_index)
	turn_manager.start_turn(correct_next)

func _on_extra_turn_requested(player_index: int):
	if game_over:
		return
	dice_manager.clear_for_turn_end()
	turn_manager.start_turn(player_index)

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

func _do_ai_turn(player_index: int):
	await get_tree().create_timer(1.25).timeout
	
	# Fase de cartas
	var context = {
		"player": players[player_index],
		"board": board,
		"movement_manager": movement_manager,
		"has_broken_barrier": turn_manager.has_broken_barrier_this_turn,
		"turn_manager": turn_manager,
		"card_manager": card_manager,
		"steps": 0,
		"is_pair": false
	}
	
	if ai_controllers[player_index].decide_should_draw(context) and turn_manager.current_state == TurnManager.State.DRAW_PHASE:
		await _draw_card_phase()
		return
	
	if ai_controllers[player_index].difficulty == AIController.Difficulty.NORMAL:
		var hand = card_manager.get_hand(player_index)
		var offensive = [CardManager.CardType.FREEZE, CardManager.CardType.SABOTAGE, CardManager.CardType.THIEF]
		for i in range(hand.size()):
			if hand[i] in offensive:
				card_manager.discard_card(player_index, i)
				break
	
	var card_index = ai_controllers[player_index].decide_card(context)
	if card_index != -1:
		pending_card_index = card_index
		pending_card_type = card_manager.get_hand(player_index)[card_index]
		_select_card(card_index)
		await get_tree().create_timer(0.8).timeout
		# si quedó en CARD_TARGET, la IA elige el target
		if turn_manager.current_state == TurnManager.State.CARD_TARGET:
			var target = _ai_pick_card_target(player_index, pending_card_type)
			if target:
				_on_piece_clicked(target)
			else:
				_cancel_card()
		await get_tree().create_timer(0.5).timeout
	
	# Lanzar dados
	turn_manager.current_state = TurnManager.State.IDLE
	_roll_dice()

func _ai_pick_card_target(player_index: int, card_type: int) -> GamePiece:
	var player = players[player_index]
	var main_path_size = board.main_path.size()
	match card_type:
		CardManager.CardType.JAILBREAK:
			for piece in player.pieces:
				if piece.in_jail:
					return piece
		CardManager.CardType.SHIELD:
			for piece in player.pieces:
				if not piece.in_jail and not piece.is_finished and not piece.is_shielded:
					return piece
		CardManager.CardType.TURBO:
			for piece in player.pieces:
				if not piece.in_jail and not piece.is_finished and not piece.is_frozen:
					if movement_manager.can_move_piece(piece, 5):
						return piece
		CardManager.CardType.FREEZE, CardManager.CardType.SABOTAGE:
			# primero busca el más adelantado con route >= 30
			var best: GamePiece = null
			var best_route = -1
			for enemy_player in players:
				if enemy_player == player:
					continue
				for enemy in enemy_player.pieces:
					if enemy.in_jail or enemy.is_finished:
						continue
					if enemy.route >= 30 and enemy.route > best_route:
						best_route = enemy.route
						best = enemy
			if best:
				return best
			# si no, el enemigo más cercano por detrás
			for piece in player.pieces:
				if piece.in_jail or piece.is_finished:
					continue
				for enemy_player in players:
					if enemy_player == player:
						continue
					for enemy in enemy_player.pieces:
						if enemy.in_jail or enemy.is_finished:
							continue
						var dist = (piece.current_position - enemy.current_position + main_path_size) % main_path_size
						if dist <= 6:
							return enemy
		CardManager.CardType.THIEF:
			# el enemigo con más cartas
			var best: GamePiece = null
			var best_cards = -1
			for enemy_player in players:
				if enemy_player == player:
					continue
				var hand_size = card_manager.get_hand(enemy_player.player_id).size()
				if hand_size > best_cards:
					best_cards = hand_size
					for enemy in enemy_player.pieces:
						if not enemy.in_jail and not enemy.is_finished:
							best = enemy
							break
			return best
		CardManager.CardType.MINE:
			# Place mine on own piece that enemies are approaching
			for piece in player.pieces:
				if piece.in_jail or piece.is_finished or piece.in_home_path:
					continue
				return piece
		CardManager.CardType.GHOST:
			# Ghost the most threatened piece
			for piece in player.pieces:
				if piece.in_jail or piece.is_finished or piece.is_ghost:
					continue
				for enemy_player in players:
					if enemy_player == player:
						continue
					for enemy in enemy_player.pieces:
						if enemy.in_jail or enemy.is_finished:
							continue
						var dist = (piece.current_position - enemy.current_position + main_path_size) % main_path_size
						if dist <= 6:
							return piece
			return null
		CardManager.CardType.ALLIANCE:
			# Propose alliance with the strongest enemy
			var best: GamePiece = null
			var best_route = -1
			for enemy_player in players:
				if enemy_player == player:
					continue
				var total_route = 0
				for ep in enemy_player.pieces:
					if not ep.is_finished:
						total_route += ep.route
				if total_route > best_route:
					best_route = total_route
					for ep in enemy_player.pieces:
						if not ep.in_jail and not ep.is_finished:
							best = ep
							break
			return best
	return null

# ── Alliance UI System ──────────────────────────────────────

func _show_alliance_popup(proposer_id: int, target_id: int):
	if alliance_popup:
		alliance_popup.queue_free()
	
	alliance_popup = PanelContainer.new()
	alliance_popup.name = "AlliancePopup"
	
	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.18, 0.95)
	style.border_color = Color(0.9, 0.7, 0.2, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	alliance_popup.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	alliance_popup.add_child(vbox)
	
	var title = Label.new()
	title.text = "⚔ PROPUESTA DE ALIANZA ⚔"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = players[proposer_id].display_name.to_upper() + " propone alianza a " + players[target_id].display_name.to_upper() + "\nSin capturas mutuas por 5 turnos"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(desc)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)
	
	var accept_btn = Button.new()
	accept_btn.text = "✓ Aceptar"
	accept_btn.custom_minimum_size = Vector2(120, 40)
	var accept_style = StyleBoxFlat.new()
	accept_style.bg_color = Color(0.1, 0.5, 0.2, 0.9)
	accept_style.set_corner_radius_all(8)
	accept_btn.add_theme_stylebox_override("normal", accept_style)
	accept_btn.add_theme_font_size_override("font_size", 16)
	hbox.add_child(accept_btn)
	
	var reject_btn = Button.new()
	reject_btn.text = "✗ Rechazar"
	reject_btn.custom_minimum_size = Vector2(120, 40)
	var reject_style = StyleBoxFlat.new()
	reject_style.bg_color = Color(0.5, 0.1, 0.1, 0.9)
	reject_style.set_corner_radius_all(8)
	reject_btn.add_theme_stylebox_override("normal", reject_style)
	reject_btn.add_theme_font_size_override("font_size", 16)
	hbox.add_child(reject_btn)
	
	accept_btn.pressed.connect(_on_alliance_accepted.bind(proposer_id, target_id))
	reject_btn.pressed.connect(_on_alliance_rejected.bind(target_id))
	
	$"../UI/GameUI".add_child(alliance_popup)
	
	# Center the popup
	alliance_popup.anchor_left = 0.5
	alliance_popup.anchor_right = 0.5
	alliance_popup.anchor_top = 0.4
	alliance_popup.anchor_bottom = 0.4
	alliance_popup.offset_left = -180
	alliance_popup.offset_right = 180
	alliance_popup.offset_top = -80
	alliance_popup.offset_bottom = 80

func _on_alliance_accepted(proposer_id: int, target_id: int):
	movement_manager.add_alliance(proposer_id, target_id, 5)
	status_label.text = "ALIANZA: ¡" + players[target_id].display_name.to_upper() + " aceptó! Sin capturas mutuas por 5 turnos"
	_cleanup_alliance_popup()

func _on_alliance_rejected(target_id: int):
	status_label.text = "ALIANZA: " + players[target_id].display_name.to_upper() + " rechazó la alianza"
	_cleanup_alliance_popup()

func _cleanup_alliance_popup():
	pending_alliance_target_player = -1
	if alliance_popup:
		alliance_popup.queue_free()
		alliance_popup = null
	turn_manager.current_state = TurnManager.State.IDLE
	turn_manager.card_used_this_turn = true
	await get_tree().create_timer(1.5).timeout
	var player = players[turn_manager.current_player_index]
	status_label.text = "Turno de " + player.display_name.to_upper() + " — [Espacio] lanzar"

func _ai_decide_alliance(target_id: int, proposer_id: int) -> bool:
	var ai = ai_controllers[target_id]
	match ai.difficulty:
		AIController.Difficulty.EASY:
			return true  # Always accept
		AIController.Difficulty.NORMAL:
			# Accept if they have >= 2 pieces in jail
			var jailed = 0
			for piece in players[target_id].pieces:
				if piece.in_jail:
					jailed += 1
			return jailed >= 2
		AIController.Difficulty.HARD:
			# Accept only if losing (lower total route than proposer)
			var target_route = 0
			for piece in players[target_id].pieces:
				if not piece.is_finished:
					target_route += piece.route
			var proposer_route = 0
			for piece in players[proposer_id].pieces:
				if not piece.is_finished:
					proposer_route += piece.route
			return target_route < proposer_route
	return false

# ── Mine / Wormhole Signal Handlers ─────────────────────────

func _on_mine_triggered(piece: GamePiece, _mine_owner_id: int):
	status_label.text = "¡BOOM! " + piece.player.display_name.to_upper() + " pisó una MINA!"

func _on_alliance_expired(player_a: int, player_b: int):
	status_label.text = "Alianza entre " + players[player_a].display_name.to_upper() + " y " + players[player_b].display_name.to_upper() + " ha expirado"

func _on_wormhole_activated(pos_a: int, pos_b: int):
	# Place glowing torus markers at portal positions
	for pos in [pos_a, pos_b]:
		var cell_node = board.main_path[pos]
		var marker = MeshInstance3D.new()
		var mesh = TorusMesh.new()
		mesh.inner_radius = 0.002
		mesh.outer_radius = 0.004
		marker.mesh = mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.8, 1.0, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.6, 1.0)
		mat.emission_energy_multiplier = 1.0
		marker.material_override = mat
		cell_node.add_child(marker)
		marker.position = Vector3(0, 0.005, 0)
		wormhole_markers.append(marker)

func _on_wormhole_deactivated():
	for marker in wormhole_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	wormhole_markers.clear()
