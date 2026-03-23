extends Node

var main_path = []
var piece
var jail = {}
var home_paths = {}

const SAFE_SQUARES = [7, 12, 24, 29, 41, 46, 58, 63]

func _ready():
	for node in $Main_Path.get_children():
		main_path.append(node)
	_fill_jail()
	_fill_home_paths

func _fill_jail():
	jail["yellow"] = []
	jail["blue"] = []
	jail["red"] = []
	jail["green"] = []
	
	for node in $Jail.get_children():
		var n = node.name.to_lower()
		if n.begins_with("yellow"):
			jail["yellow"].append(node)
		elif n.begins_with("blue"):
			jail["blue"].append(node)
		elif n.begins_with("red"):
			jail["red"].append(node)
		elif n.begins_with("green"):
			jail["green"].append(node)

func _fill_home_paths():
	home_paths["yellow"] = []
	home_paths["blue"] = []
	home_paths["red"] = []
	home_paths["green"] = []
	
	for node in $Yellow_Path.get_children():
		home_paths["yellow"].append(node)
	for node in $Blue_Path.get_children():
		home_paths["blue"].append(node)
	for node in $Red_Path.get_children():
		home_paths["red"].append(node)
	for node in $Green_Path.get_children():
		home_paths["green"].append(node)
	print(home_paths)
