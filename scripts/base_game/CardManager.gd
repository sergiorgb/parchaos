class_name CardManager
extends Node

enum CardType {
	TURBO,
	SHIELD,
	JAILBREAK,
	SABOTAGE,
	FREEZE,
	DOUBLE,
	THIEF
}

const CARD_INFO = {
	CardType.TURBO:     {"name": "Turbo",     "icon": "[T]", "desc": "Avanza 5 pasos extra",              "target": "own"},
	CardType.SHIELD:    {"name": "Escudo",    "icon": "[E]", "desc": "Protege de captura 2 turnos",       "target": "own"},
	CardType.JAILBREAK: {"name": "Fuga",      "icon": "[F]", "desc": "Libera ficha de la carcel",         "target": "own_jail"},
	CardType.SABOTAGE:  {"name": "Sabotaje",  "icon": "[S]", "desc": "Retrocede enemigo 4 pasos",         "target": "enemy"},
	CardType.FREEZE:    {"name": "Hielo",     "icon": "[H]", "desc": "Congela ficha enemiga 1 turno",     "target": "enemy"},
	CardType.DOUBLE:    {"name": "Doble",     "icon": "[D]", "desc": "Duplica siguiente lanzamiento",     "target": "none"},
	CardType.THIEF:     {"name": "Ladron",    "icon": "[L]", "desc": "Roba carta a otro jugador",         "target": "none"},
}	 

signal card_drawn(player_index: int, card_type: int)
signal card_used(player_index: int, card_type: int)

var deck: Array = []
var player_hands: Dictionary = {}
const MAX_HAND_SIZE = 3

func setup(player_count: int):
	for i in range(player_count):
		player_hands[i] = []
	_fill_deck()

func _fill_deck():
	deck.clear()
	for type in CardType.values():
		for i in range(4):
			deck.append(type)
	deck.shuffle()

func draw_card(player_index: int) -> int:
	if player_hands[player_index].size() >= MAX_HAND_SIZE:
		return -1
	if deck.is_empty():
		_fill_deck()
	var card = deck.pop_back()
	player_hands[player_index].append(card)
	card_drawn.emit(player_index, card)
	return card

func use_card(player_index: int, card_index: int) -> int:
	var hand = player_hands[player_index]
	if card_index < 0 or card_index >= hand.size():
		return -1
	var card = hand[card_index]
	hand.remove_at(card_index)
	card_used.emit(player_index, card)
	return card

func get_hand(player_index: int) -> Array:
	return player_hands.get(player_index, [])

func get_card_name(card_type: int) -> String:
	return CARD_INFO[card_type]["name"]

func get_card_icon(card_type: int) -> String:
	return CARD_INFO[card_type]["icon"]

func get_card_desc(card_type: int) -> String:
	return CARD_INFO[card_type]["desc"]

func get_card_target(card_type: int) -> String:
	return CARD_INFO[card_type]["target"]

func steal_random_card(from_player: int, to_player: int) -> int:
	var from_hand = player_hands.get(from_player, [])
	if from_hand.is_empty():
		return -1
	if player_hands[to_player].size() >= MAX_HAND_SIZE:
		return -1
	var idx = randi() % from_hand.size()
	var card = from_hand[idx]
	from_hand.remove_at(idx)
	player_hands[to_player].append(card)
	return card
