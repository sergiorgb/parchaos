extends Node
class_name Player

var display_name: String
var player_id: int
var color: String
var start_index: int
var home_entry: int
var is_ai: bool
var pieces = []

func setup(id: int, p_color: String, p_name:String, s_index: int, h_entry: int, isAI: bool):
	self.display_name = p_name
	self.player_id = id
	self.color = p_color
	self.start_index = s_index
	self.home_entry = h_entry
	self.is_ai = isAI

func _has_pieces_in_jail() -> bool:
	for piece in pieces:
		if piece.in_jail:
			return true
	return false

func _has_own_barrier() -> bool:
	for piece in pieces:
		if piece.in_jail or piece.is_finished:
			continue
		var count = 0
		for p in pieces:
			if not p.in_jail and not p.is_finished and p.current_position == piece.current_position:
				count += 1
		if count >= 2:
			return true
	return false
