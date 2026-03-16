extends Node3D

var route = 0
var start_index = 0
var board = null

var color: String = "amarilla"

func _ready():
	$Visual/fichaamarilla.visible = false
	$Visual/ficharoja.visible = false
	$Visual/fichaverde.visible = false
	$Visual/fichaazul.visible = false
	get_node("Visual/ficha" + color).visible = true

func move(steps):
	route += steps
	var path_index = (route + start_index) % board.main_path.size()
	var square = board.main_path[path_index]
	print(square.global_position)
	global_position = square.global_position
