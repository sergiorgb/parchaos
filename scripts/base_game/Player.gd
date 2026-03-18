extends Node

var player_id: int
var color: String
var start_index: int
var pieces = []

func setup (id: int, c: String, start: int):
	player_id = id
	color = c
	start_index = start
