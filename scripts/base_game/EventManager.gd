extends Node
class_name EventManager
 
signal event_triggered(event_key: String, event_data: Dictionary)
signal extra_turn_requested(player_index: int) 

const ROUNDS_BETWEEN_EVENTS = 3
 
const EVENTS: Dictionary = {
	"lider_marcado": {
		"nombre": "Líder Marcado",
		"descripcion": "El jugador con más ruta total pierde su próximo turno",
		"condicion": "lider_existe",
		"efecto": "skip_turn"
	},
	"tregua": {
		"nombre": "Tregua",
		"descripcion": "No hay capturas este turno",
		"condicion": "siempre",
		"efecto": "no_capture"
	},
	"caos": {
		"nombre": "Caos",
		"descripcion": "Todas las fichas en juego retroceden 2 casillas",
		"condicion": "hay_fichas_en_juego",
		"efecto": "retroceder_todas"
	},
	"turno_extra": {
		"nombre": "Turno Extra",
		"descripcion": "El jugador activo tira de nuevo al terminar el turno",
		"condicion": "siempre",
		"efecto": "extra_turn"
	},
	"ruleta_carcel": {
		"nombre": "Ruleta de Cárcel",
		"descripcion": "Fichas en cárcel salen; si no tienes ninguna, entra una",
		"condicion": "siempre",
		"efecto": "ruleta_carcel"
	},
	"dados_inversos": {
		"nombre": "Dados Inversos",
		"descripcion": "Los dados se invierten: 6→1, 5→2, 4→3...",
		"condicion": "siempre",
		"efecto": "invertir_dados"
	},
	"handicap": {
		"nombre": "Handicap",
		"descripcion": "El jugador con menos ruta total obtiene ×2 en su tirada",
		"condicion": "hay_diferencia_ruta",
		"efecto": "double_roll"
	},
	"reversa": {
		"nombre": "Reversa",
		"descripcion": "El orden de juego se invierte por 3 turnos",
		"condicion": "siempre",
		"efecto": "invertir_orden"
	}
}

var players: Array = []
var turn_manager: TurnManager = null
var movement_manager: MovementManager = null
 
var rounds_since_last_event: int = -1
var current_event_key: String = ""
var current_event_data: Dictionary = {}
 
var tregua_active: bool = false
var extra_turn_players: Dictionary = {}
var invertir_dados_active: bool = false
var reversa_active: bool = false
var reversa_turns_remaining: int = 0
var skip_turn_player_id: int = -1   
var handicap_player_id: int = -1   
var processing_extra_turn: bool = false 
 
var event_label: Label = null
var event_counter_label: Label = null
 
func setup(p_players: Array, p_turn_manager: TurnManager, p_movement_manager: MovementManager, p_label: Label, pc_label: Label):
	players = p_players
	turn_manager = p_turn_manager
	movement_manager = p_movement_manager
	event_label = p_label
	event_counter_label = pc_label
	_clear_event_label()
	if event_counter_label:
		event_counter_label.text = "Próximo evento en: " + str(ROUNDS_BETWEEN_EVENTS) + " rondas"
 
func on_turn_started(player_index: int):
	if skip_turn_player_id == player_index:
		skip_turn_player_id = -1
		_show_event_label(players[player_index].display_name.to_upper() + " pierde este turno por Líder Marcado")
		await get_tree().create_timer(1.0).timeout
		turn_manager.end_turn()
		return
	
	if player_index == 0:
		rounds_since_last_event += 1
		if rounds_since_last_event >= ROUNDS_BETWEEN_EVENTS:
			rounds_since_last_event = 0
			await _trigger_random_event(player_index)
			return
	
	if event_counter_label:
		event_counter_label.text = "Próximo evento en: " + str(get_rounds_until_next_event()) + " rondas"
	
	
	if reversa_active:
		reversa_turns_remaining -= 1
		if reversa_turns_remaining <= 0:
			reversa_active = false
			_show_event_label("Reversa terminada — orden normal restaurado")
 
func on_turn_ended(player_index: int):
	if extra_turn_players.get(player_index, false):
		var all_jailed = players[player_index].pieces.all(func(p): return p.in_jail)
		if not all_jailed:
			extra_turn_players[player_index] = false
			_show_event_label("¡Turno Extra para " + players[player_index].display_name.to_upper() + "!")
			processing_extra_turn = true
			await get_tree().create_timer(1.0).timeout
			extra_turn_requested.emit(player_index)
			processing_extra_turn = false
			return

func is_tregua_active() -> bool:
	return tregua_active
 
func is_dados_inversos_active() -> bool:
	return invertir_dados_active
 
func is_reversa_active() -> bool:
	return reversa_active
 
func is_extra_turn_pending(player_index: int) -> bool:
	return extra_turn_players.get(player_index, false)

func consume_extra_turn(player_index: int):
	extra_turn_players[player_index] = false


 
func get_handicap_player_id() -> int:
	return handicap_player_id
 
func get_next_player_index(current: int) -> int:
	if reversa_active:
		return (current - 1 + players.size()) % players.size()
	return (current + 1) % players.size()
 
func invert_dice(dice_results: Array) -> Array:
	var inverted = []
	for d in dice_results:
		inverted.append(7 - d)
	return inverted
 
func _trigger_random_event(player_index: int):
	tregua_active = false
	invertir_dados_active = false
	handicap_player_id = -1
	extra_turn_players.clear()
	var elegibles: Array = []
 
	for key in EVENTS:
		var ev = EVENTS[key]
		if _check_condition(ev["condicion"], player_index):
			elegibles.append(key)
 
	if elegibles.is_empty():
		return
 
	var chosen_key: String = elegibles[randi() % elegibles.size()]
	current_event_key = chosen_key
	current_event_data = EVENTS[chosen_key]
 
	_show_event_label(current_event_data["nombre"] + " — " + current_event_data["descripcion"])
	await get_tree().create_timer(2.0).timeout
 
	await _apply_event(chosen_key, player_index)
	event_triggered.emit(chosen_key, current_event_data)
 
func _check_condition(condicion: String, _player_index: int) -> bool:
	match condicion:
		"siempre":
			return true
		"lider_existe":
			return _get_leader_player_id() != -1
		"hay_en_carcel":
			for p in players:
				for piece in p.pieces:
					if piece.in_jail:
						return true
			return false
		"hay_diferencia_ruta":
			var routes = _get_all_total_routes()
			return routes.max() - routes.min() > 10
		"hay_fichas_en_juego":
			for p in players:
				for piece in p.pieces:
					if not piece.in_jail and not piece.is_finished:
						return true
			return false
	return false
 
func _apply_event(key: String, player_index: int):
	match key:
		"lider_marcado":
			var leader_id = _get_leader_player_id()
			if leader_id != -1:
				skip_turn_player_id = leader_id
				_show_event_label(players[leader_id].display_name.to_upper() + " perderá su próximo turno")
 
		"tregua":
			tregua_active = true
 
		"caos":
			_show_event_label("¡Caos! Todas las fichas retroceden 2...")
			await get_tree().create_timer(0.5).timeout
			for p in players:
				for piece in p.pieces:
					if not piece.in_jail and not piece.is_finished:
						await piece._move_backward(2)
			# Reajustar stacking de todas las casillas afectadas
			var checked_positions = []
			for p in players:
				for piece in p.pieces:
					if not piece.in_jail and not piece.is_finished:
						if not piece.current_position in checked_positions:
							checked_positions.append(piece.current_position)
							movement_manager._check_stacking(piece.current_position)
 
		"turno_extra":
			for i in range(players.size()):
				extra_turn_players[i] = true
 
		"ruleta_carcel":
			await _apply_ruleta_carcel()
 
		"dados_inversos":
			invertir_dados_active = true
 
		"handicap":
			var routes = _get_all_total_routes()
			var min_route = routes.min()
			for i in range(players.size()):
				if _get_player_total_route(players[i]) == min_route:
					handicap_player_id = i
					_show_event_label(players[i].display_name.to_upper() + " tendrá ×2 en su tirada")
					break
 
		"reversa":
			reversa_active = true
			reversa_turns_remaining = ROUNDS_BETWEEN_EVENTS + players.size()
			_show_event_label("¡Orden invertido por " + str(ROUNDS_BETWEEN_EVENTS) + " rondas!")
 
func _apply_ruleta_carcel():
	for p in players:
		var jailed = []
		var active = []
		for piece in p.pieces:
			if piece.in_jail:
				jailed.append(piece)
			elif not piece.is_finished:
				active.append(piece)
 
		if jailed.size() > 0:
			var pieces_at_start = 0
			for piece in p.pieces:
				if not piece.in_jail and not piece.is_finished and piece.current_position == p.start_index:
					pieces_at_start += 1
			if pieces_at_start < 2:
				var chosen = jailed[randi() % jailed.size()]
				chosen._leave_jail()
				movement_manager._check_capture(chosen)
				movement_manager._check_stacking(chosen.current_position)
				movement_manager.reset_capture_flag()
		elif active.size() > 0:
			var chosen = active[randi() % active.size()]
			chosen._go_to_jail()
 
func _get_player_total_route(player: Player) -> int:
	var total = 0
	for piece in player.pieces:
		if not piece.is_finished:
			total += piece.route
	return total
 
func _get_all_total_routes() -> Array:
	var routes = []
	for p in players:
		routes.append(_get_player_total_route(p))
	return routes
 
func _get_leader_player_id() -> int:
	var routes = _get_all_total_routes()
	var max_route = routes.max()
	if max_route <= 0:
		return -1
	for i in range(players.size()):
		if routes[i] == max_route:
			return i
	return -1
 
func _show_event_label(text: String):
	if event_label:
		event_label.text = text
 
func _clear_event_label():
	if event_label:
		event_label.text = ""

func get_rounds_until_next_event() -> int:
	return ROUNDS_BETWEEN_EVENTS - rounds_since_last_event
