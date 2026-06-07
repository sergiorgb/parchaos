extends Node

var my_color: int = -1:
	set(value):
		print("my_color cambia a: ", value)
		my_color = value
var player_config = [
	{"is_ai": false, "difficulty": 1, "peer_id": -1},
	{"is_ai": false, "difficulty": 1, "peer_id": -1},
	{"is_ai": false, "difficulty": 1, "peer_id": -1},
	{"is_ai": false, "difficulty": 1, "peer_id": -1},
]

func _ready():
	print("GameConfig ready, unique_id: ", multiplayer.get_unique_id())


@rpc("any_peer", "reliable")
func set_my_color(color: int) -> void:
	print("set_my_color recibido: ", color, " caller: ", get_stack())
	my_color = color
