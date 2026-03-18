extends Node3D

var piece_id: int = 0 
var route: int = 0
var start_index: int = 0
var current_position
var board = null
var in_jail = true
var color: String

func _ready():
	$Visual/yellow.visible = false
	$Visual/blue.visible = false
	$Visual/red.visible = false
	$Visual/green.visible = false
	get_node("Visual/" + color).visible = true

func move(steps):
	route += steps
	current_position = (route + start_index) % board.main_path.size()
	var square = board.main_path[current_position]
	print(square.global_position)
	global_position = square.global_position

func go_to_jail():
	in_jail = true
	var spot = board.jail[color][piece_id]
	global_position = spot.global_position

func leave_jail():
	in_jail = false
	route = 0
	move(0)
