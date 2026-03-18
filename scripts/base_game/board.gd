extends Node

var main_path = []
var piece
var jail = {}

const SAFE_SQUARES = [7, 12, 24, 29, 41, 46, 58, 63]

func _ready():
	for node in $Main_Path.get_children():
		main_path.append(node)
	_fill_jail()

func _fill_jail():
	jail["yellow"] = []
	jail["blue"] = []
	jail["red"] = []
	jail["green"] = []
	
	for node in $Home.get_children():
		var n = node.name.to_lower()
		if n.begins_with("yellow"):
			jail["yellow"].append(node)
		elif n.begins_with("blue"):
			jail["blue"].append(node)
		elif n.begins_with("red"):
			jail["red"].append(node)
		elif n.begins_with("green"):
			jail["green"].append(node)
