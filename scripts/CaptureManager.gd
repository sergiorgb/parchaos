extends Node

# --- Estado del duelo activo ---
var _attacker_peer: int = -1
var _defender_peer: int = -1
var _attacker_piece_id: int = -1
var _defender_piece_id: int = -1
var _attacker_player_id: int = -1
var _defender_player_id: int = -1
var _duel_active: bool = false
var duel_active: bool:
	get:
		return _duel_active
var _pre_duel_state: int = -1
var game_manager: Node = null
var _is_finishing: bool = false
var _capture_dice_index: int = -1

const SHOOTER_SCENE = preload("res://scenes/mapapvp.tscn")
var _shooter_instance: Node = null

func start_capture_duel(
	attacker_player_id: int,
	defender_player_id: int,
	attacker_piece,
	defender_piece,
	capture_dice_index: int = -1
) -> void:
	if _duel_active:
		print("⚠️ Duelo ya activo, ignorando nueva solicitud")
		return

	print("✅ Iniciando duelo - Attacker:", attacker_player_id, " Defender:", defender_player_id)

	_attacker_player_id = attacker_player_id
	_defender_player_id = defender_player_id
	_attacker_piece_id = attacker_piece.piece_id
	_defender_piece_id = defender_piece.piece_id
	
	var attacker_peer = GameConfig.player_config[attacker_player_id].get("peer_id", 1)
	var defender_peer = GameConfig.player_config[defender_player_id].get("peer_id", -1)
	
	_attacker_peer = attacker_peer
	_defender_peer = defender_peer
	_capture_dice_index = capture_dice_index
	_duel_active = true
	_is_finishing = false

	print("🔴 attacker_peer:", attacker_peer, " defender_peer:", defender_peer)

	if not multiplayer.is_server():
		return
	_pre_duel_state = game_manager.turn_manager.current_state
	_sync_duel_active.rpc(true)
	# 🔥 Pasar los valores como argumentos, no confiar en variables de instancia
	_launch_duel_rpc.rpc(attacker_peer, defender_peer)

@rpc("authority", "reliable")
func _sync_duel_active(active: bool) -> void:
	_duel_active = active
	print("📡 _sync_duel_active recibido en peer:", multiplayer.get_unique_id(), " active:", active)

func resolve_duel(loser_peer: int) -> void:
	if not multiplayer.is_server():
		return
	if not _duel_active:
		return
	_duel_active = false
	var attacker_won: bool = loser_peer == _defender_peer
	_finish_duel_rpc.rpc(attacker_won)

@rpc("authority", "call_local", "reliable")
func _launch_duel_rpc(attacker_peer: int, defender_peer: int) -> void:
	print("🔥 _launch_duel_rpc - attacker_peer:", attacker_peer, " defender_peer:", defender_peer)
	
	# Guardar los valores recibidos
	_attacker_peer = attacker_peer
	_defender_peer = defender_peer
	
	# Clientes: asegurar que duel_active esté true
	if not multiplayer.is_server():
		_duel_active = true
		print("📡 Cliente forzando _duel_active = true")
	
	if game_manager:
		game_manager.turn_manager.current_state = TurnManager.State.DUEL
		game_manager._broadcast_state()
		game_manager.duel_in_progress = true
		game_manager.get_parent().visible = false
		game_manager.dice_manager.clear_for_turn_end()
		game_manager.turn_manager.set_process(false)
		if game_manager.event_manager:
			game_manager.event_manager.set_process(false)
		for player in game_manager.players:
			for piece in player.pieces:
				piece.visible = false
		game_manager.set_process(false)
		game_manager.set_physics_process(false)
	_shooter_instance = SHOOTER_SCENE.instantiate()
	get_tree().root.add_child(_shooter_instance)
	await get_tree().process_frame
	_activate_duel_players_rpc.rpc(_attacker_peer, _defender_peer)

@rpc("authority", "call_local", "reliable")
func _finish_duel_rpc(attacker_won: bool) -> void:
	if _is_finishing:
		return
	_is_finishing = true
	
	_sync_duel_active.rpc(false)
	
	if _shooter_instance:
		_shooter_instance.queue_free()
		_shooter_instance = null

	if game_manager:
		game_manager.release_mouse_after_duel()
		game_manager.duel_in_progress = false
		game_manager.get_parent().visible = true
		game_manager.turn_manager.set_process(true)  # ← antes de _apply_result
		if game_manager.event_manager:
			game_manager.event_manager.set_process(true)
		for player in game_manager.players:
			for piece in player.pieces:
				piece.visible = true
		game_manager.set_process(true)
		game_manager.set_physics_process(true)
		var board_camera = game_manager.camera
		if board_camera:
			board_camera.make_current()

	_force_release_mouse.rpc()

	if _pre_duel_state != -1:
		game_manager.turn_manager.current_state = _pre_duel_state
		_pre_duel_state = -1

	if multiplayer.is_server():
		_apply_result(attacker_won)  # ← después de restaurar todo

	if game_manager and game_manager.turn_manager.current_state == TurnManager.State.DUEL:
		game_manager.turn_manager.current_state = _pre_duel_state if _pre_duel_state != -1 else TurnManager.State.IDLE
		game_manager._broadcast_state()
	
	_duel_active = false
	_attacker_peer = -1
	_defender_peer = -1
	_attacker_piece_id = -1
	_defender_piece_id = -1
	_attacker_player_id = -1
	_defender_player_id = -1
	_is_finishing = false

@rpc("authority", "call_local", "reliable")
func _force_release_mouse() -> void:
	# Liberar el mouse para que el jugador pueda interactuar con el tablero
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Si el jugador local tiene una cámara de espectador, asegurarse de que no capture el mouse
	var viewport = get_viewport()
	if viewport:
		viewport.gui_disable_input = false

@rpc("authority", "call_local", "reliable")
func _activate_duel_players_rpc(attacker_peer: int, defender_peer: int) -> void:
	print("🎯 _activate_duel_players_rpc - attacker:", attacker_peer, " defender:", defender_peer)
	_attacker_peer = attacker_peer
	_defender_peer = defender_peer
	
	if _shooter_instance == null:
		print("❌ ERROR: _shooter_instance es null")
		return
	
	var my_peer = multiplayer.get_unique_id()
	print("📡 my_peer:", my_peer)
	
	var ai_list = []  # ← Guardar IAs creadas
	
	if multiplayer.is_server():
		var PIECE_SCENE = preload("res://scenes/piecepvp.tscn")
		var ENEMY_SCENE = preload("res://scenes/enemy.tscn")
		
		# Primera pasada: crear todos los personajes
		for peer in [attacker_peer, defender_peer]:
			if peer == -1:
				# Es IA
				print("🤖 Creando IA para duelo")
				var enemy = ENEMY_SCENE.instantiate()
				enemy.name = "EnemyDuel"
				enemy.duel_mode = true
				_shooter_instance.add_child(enemy)
				
				# Asignar posición inicial aleatoria
				var spawn_positions = [
					Vector3(5, 0.2, 5), Vector3(-5, 0.2, 5),
					Vector3(5, 0.2, -5), Vector3(-5, 0.2, -5),
					Vector3(0, 0.2, 8), Vector3(0, 0.2, -8),
					Vector3(8, 0.2, 0), Vector3(-8, 0.2, 0)
				]
				enemy.global_position = spawn_positions[randi() % spawn_positions.size()]
				print("🦾 IA creada en posición:", enemy.global_position)
				
				# 🔥 Asignar color según player_id
				var player_id = _attacker_player_id if peer == attacker_peer else _defender_player_id
				if player_id != -1:
					enemy.set_color.rpc(player_id)
					print("🎨 IA asignó color:", player_id)
				
				ai_list.append(enemy)
				continue
			
			print("👤 Creando pieza para peer:", peer)
			var piece = PIECE_SCENE.instantiate()
			piece.name = str(peer)
			_shooter_instance.add_child(piece)
			piece.collision_layer = 1
			piece.collision_mask = 1
			piece.set_multiplayer_authority(peer)
			var player_id = _attacker_player_id if peer == attacker_peer else _defender_player_id
			piece.set_color.rpc(player_id)
		
		# 🔥 Segunda pasada: asignar targets entre IAs
		if ai_list.size() >= 2:
			ai_list[0].player = ai_list[1]
			ai_list[1].player = ai_list[0]
			print("🤝 IAs apuntándose entre sí")
		elif ai_list.size() == 1 and attacker_peer != -1:
			# Una IA vs humano
			var human_node = _shooter_instance.get_node_or_null(str(attacker_peer))
			if human_node:
				ai_list[0].player = human_node
				print("🤖 IA apunta a humano:", attacker_peer)
	
	# Todos los peers — activar modo correcto
	await get_tree().create_timer(0.3).timeout
	
	if my_peer == _attacker_peer or my_peer == _defender_peer:
		var my_piece = _shooter_instance.get_node_or_null(str(my_peer))
		if my_piece:
			print("✅ Activando modo duelo para mi pieza:", my_peer)
			my_piece.activate_duel_mode()
		else:
			print("❌ No encontré mi pieza:", my_peer)
	else:
		print("👀 Soy espectador, activando cámara de espectador")
		var spectator_cam = _shooter_instance.get_node_or_null("SpectatorCamera")
		if spectator_cam:
			spectator_cam.make_current()

func _apply_result(attacker_won: bool) -> void:
	if game_manager == null:
		return

	var players = game_manager.players
	if _attacker_player_id >= players.size() or _defender_player_id >= players.size():
		return

	var attacker_player = players[_attacker_player_id]
	var defender_player = players[_defender_player_id]
	var attacker_piece = _find_piece(attacker_player, _attacker_piece_id)
	var defender_piece = _find_piece(defender_player, _defender_piece_id)

	game_manager.movement_manager.bypass_duel = true

	if attacker_won:
		if defender_piece:
			defender_piece._go_to_jail()
			defender_piece.broadcast_state()
			
			if _capture_dice_index != 2 and not game_manager.movement_manager.captured_this_turn:
				game_manager.movement_manager.captured_this_turn = true
				game_manager.turn_manager.on_piece_moved(true, true)  # ← avanza a BONUS_MOVE
				game_manager.movement_manager.capture_happened.emit(defender_piece, 10)
			else:
				game_manager.turn_manager.on_piece_moved(true, false)
	else:
		# Atacante pierde: atacante a la cárcel y pierde el turno
		if attacker_piece:
			attacker_piece._go_to_jail()
			attacker_piece.broadcast_state()
			
			# El atacante pierde el resto del turno
			game_manager.turn_manager.end_turn()

	game_manager.movement_manager.bypass_duel = false
	game_manager._broadcast_state()

func _find_piece(player: Node, piece_id: int) -> Node:
	for piece in player.pieces:
		if piece.piece_id == piece_id:
			return piece
	return null

func is_duel_active() -> bool:
	return _duel_active
