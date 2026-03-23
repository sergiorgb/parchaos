extends Node

var player_id: int
var color: String
var start_index: int
var home_entry: int
var pieces = []

func setup (id: int, c: String, start: int, home:int):
	player_id = id
	color = c
	start_index = start
	home_entry = home
