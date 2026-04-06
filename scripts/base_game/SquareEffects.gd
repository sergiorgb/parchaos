class_name SquareEffects
extends Node

enum SquareType { NORMAL, CARD, SPEED_BOOST, TRAP }

signal effect_triggered(piece: Piece, effect_type: int, message: String)

const CARD_SQUARES = [4, 21, 38, 55]
const SPEED_BOOST_SQUARES = [10, 27, 44, 61]
const TRAP_SQUARES = [15, 32, 49, 2]

var board: Board
var card_manager: CardManager

func setup(p_board: Board, p_card_manager: CardManager):
	board = p_board
	card_manager = p_card_manager

func get_square_type(index: int) -> int:
	if index in CARD_SQUARES:
		return SquareType.CARD
	elif index in SPEED_BOOST_SQUARES:
		return SquareType.SPEED_BOOST
	elif index in TRAP_SQUARES:
		return SquareType.TRAP
	return SquareType.NORMAL

func apply_effect(piece: Piece) -> Dictionary:
	if piece.in_home_path or piece.in_jail:
		return {"type": SquareType.NORMAL, "extra_steps": 0, "message": ""}

	var sq_type = get_square_type(piece.current_position)
	var result = {"type": sq_type, "extra_steps": 0, "message": ""}

	match sq_type:
		SquareType.CARD:
			var card = card_manager.draw_card(piece.player.player_id)
			if card != -1:
				var icon = card_manager.get_card_icon(card)
				var cname = card_manager.get_card_name(card)
				result["message"] = "CARTA OBTENIDA: " + icon + " " + cname + "!"
			else:
				result["message"] = "Mano llena -- no puedes tomar mas cartas"
		SquareType.SPEED_BOOST:
			result["extra_steps"] = 3
			result["message"] = "VELOCIDAD: +3 pasos extra!"
		SquareType.TRAP:
			result["extra_steps"] = -3
			result["message"] = "TRAMPA: Retrocedes 3 pasos!"

	if sq_type != SquareType.NORMAL:
		effect_triggered.emit(piece, sq_type, result["message"])

	return result
