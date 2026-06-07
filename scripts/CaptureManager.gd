extends Node

# CaptureManager.gd
# Autoload singleton. Coordina el flujo: captura en tablero → duelo shooter → resultado.
#
# Para registrarlo: Project > Project Settings > Autoload
# Nombre: CaptureManager
# Ruta: res://scripts/CaptureManager.gd

# --- Estado del duelo activo ---
var _duel_active: bool = false
var _attacker_peer: int = -1   # peer_id del jugador atacante
var _defender_peer: int = -1   # peer_id del jugador defensor
var _attacker_piece_id: int = -1  # índice de la ficha atacante
var _defender_piece_id: int = -1  # índice de la ficha capturada
var _attacker_player_id: int = -1 # índice del jugador atacante (0-3)
var _defender_player_id: int = -1 # índice del jugador defensor (0-3)

# Referencia al GameManager del tablero (se asigna en _ready del GameManager)
var game_manager: Node = null

# Escena del mapa PvP
const SHOOTER_SCENE = preload("res://scenes/mapapvp.tscn")
var _shooter_instance: Node = null

# --- API pública ---

# Llamado desde MovementManager cuando detecta una captura entre dos humanos.
# attacker_player_id / defender_player_id: índices 0-3 del array players[]
# attacker_piece / defender_piece: referencias a GamePiece
func start_capture_duel(
	attacker_player_id: int,
	defender_player_id: int,
	attacker_piece,
	defender_piece
) -> void:
	if _duel_active:
		return  # ya hay un duelo en curso, ignorar

	_attacker_player_id = attacker_player_id
	_defender_player_id = defender_player_id
	_attacker_piece_id = attacker_piece.piece_id
	_defender_piece_id = defender_piece.piece_id

	# Obtener peer_ids desde GameConfig
	_attacker_peer = GameConfig.player_config[attacker_player_id].get("peer_id", 1)
	_defender_peer = GameConfig.player_config[defender_player_id].get("peer_id", -1)

	_duel_active = true

	# Solo el servidor orquesta
	if not multiplayer.is_server():
		return

	_launch_duel_rpc.rpc()

# Llamado desde piecepvp.gd cuando un jugador muere en modo duelo.
# loser_peer: peer_id del que murió.
func resolve_duel(loser_peer: int) -> void:
	if not multiplayer.is_server():
		return
	if not _duel_active:
		return

	var attacker_won: bool = loser_peer == _defender_peer
	_finish_duel_rpc.rpc(attacker_won)

# --- RPCs ---
@rpc("authority", "call_local", "reliable")
func _launch_duel_rpc() -> void:
	if game_manager:
		game_manager.get_parent().visible = false
		game_manager.set_process(false)
		game_manager.set_physics_process(false)
	_shooter_instance = SHOOTER_SCENE.instantiate()
	get_tree().root.add_child(_shooter_instance)
	await get_tree().process_frame  # esperar que el nodo esté listo
	_activate_duel_players_rpc.rpc()  # ← agregar

@rpc("authority", "call_local", "reliable")
func _finish_duel_rpc(attacker_won: bool) -> void:
	# Destruir el shooter
	if _shooter_instance:
		_shooter_instance.queue_free()
		_shooter_instance = null

	# Mostrar y reanudar el tablero
	if game_manager:
		game_manager.get_parent().visible = true
		game_manager.set_process(true)
		game_manager.set_physics_process(true)

	if multiplayer.is_server():
		_apply_result(attacker_won)

	_duel_active = false
	_attacker_peer = -1
	_defender_peer = -1
	_attacker_piece_id = -1
	_defender_piece_id = -1
	_attacker_player_id = -1
	_defender_player_id = -1

@rpc("authority", "call_local", "reliable")
func _activate_duel_players_rpc() -> void:
	if _shooter_instance == null:
		return
	# Buscar los nodos de los jugadores en la escena del shooter
	var attacker_node = _shooter_instance.get_node_or_null(str(_attacker_peer))
	var defender_node = _shooter_instance.get_node_or_null(str(_defender_peer))
	if attacker_node and attacker_node.has_method("activate_duel_mode"):
		attacker_node.activate_duel_mode()
	if defender_node and defender_node.has_method("activate_duel_mode"):
		defender_node.activate_duel_mode()

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

	if attacker_won:
		if defender_piece:
			game_manager.movement_manager.bypass_duel = true
			game_manager.movement_manager._resolve_capture(defender_piece)
	else:
		if attacker_piece:
			game_manager.movement_manager.bypass_duel = true
			game_manager.movement_manager._resolve_capture(attacker_piece)
		game_manager.movement_manager.captured_this_turn = false

	game_manager.turn_manager.on_piece_moved(true, attacker_won)

func _find_piece(player: Node, piece_id: int) -> Node:
	for piece in player.pieces:
		if piece.piece_id == piece_id:
			return piece
	return null
