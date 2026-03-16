extends Node

var main_path = []
var piece

func _ready():
	
	for node in $Main_Path.get_children():
		main_path.append(node)
	
	piece = $"../Piece"
	piece.board = self
	piece.start_index = 0
	
	piece.move(35)
	
	print("squares ready: ", main_path.size())
