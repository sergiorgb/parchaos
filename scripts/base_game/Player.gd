extends Node
class_name Player

var player_id: int
var color: String
var start_index: int
var home_entry: int
var pieces = []

func setup(id: int, p_color: String, s_index: int, h_entry: int):
	self.player_id = id
	self.color = p_color
	self.start_index = s_index
	self.home_entry = h_entry

func _has_pieces_in_jail() -> bool:
	for piece in pieces:
		if piece.in_jail:
			return true
	return false

func _can_move(roll) -> bool:
	# Si hay piezas fuera que no han terminado, puede mover
	for piece in pieces:
		if not piece.in_jail and not piece.is_finished:
			return true
	return false

func _is_valid_piece(index: int) -> bool:
	return index >= 0 and index < pieces.size() and not pieces[index].is_finished

func _has_own_barrier() -> bool:
	for piece in pieces:
		if piece.in_jail or piece.is_finished:
			continue
		var count = pieces.filter(func(p):
			return not p.in_jail and not p.is_finished and p.current_position == piece.current_position)
		if count.size() >= 2: # Cambiado a >= por seguridad
			return true
	return false

func _is_piece_in_barrier(piece_index: int) -> bool:
	var piece = pieces[piece_index]
	var count = pieces.filter(func(p):
		return not p.in_jail and not p.is_finished and p.current_position == piece.current_position)
	return count.size() >= 2
