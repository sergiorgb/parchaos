extends Node3D

var player = null
var piece_id: int = 0 
var route: int = 0
var start_index: int = 0
var current_position = 0
var board = null
var in_jail = true
var color: String
var in_home_path = false
var home_route = 0
var is_finished = false

func _ready():
	$Visual/yellow.visible = false
	$Visual/blue.visible = false
	$Visual/red.visible = false
	$Visual/green.visible = false
	get_node("Visual/" + color).visible = true

func move(steps) -> bool:
	if in_home_path:
		var remaining = board.home_paths[color].size() - home_route - 1
		if steps > remaining and remaining != 0:
			print("te faltan exactamente ", remaining, " para llegar")
			return false
		home_route += steps
		var square = board.home_paths[color][home_route]
		global_position = square.global_position
		if home_route == board.home_paths[color].size() - 1:
			_finish()
			return true
		return true
		
	
	var steps_to_entry = _steps_to_entry(current_position)
	route += steps
	current_position = (route + start_index) % board.main_path.size()
	if steps >= steps_to_entry:
		in_home_path = true
		home_route = steps - steps_to_entry
		var square = board.home_paths[color][home_route]
		global_position = square.global_position
	else:
		var square = board.main_path[current_position]
		global_position = square.global_position
	return true

func _steps_to_entry(old_pos: int):
	return (player.home_entry - old_pos + board.main_path.size()) % board.main_path.size()
	

func _finish():
	is_finished = true
	board.get_parent().get_node("GameManager")._on_piece_finished()

func go_to_jail():
	in_jail = true
	var spot = board.jail[color][piece_id]
	global_position = spot.global_position

func leave_jail():
	in_jail = false
	route = 0
	move(0)
