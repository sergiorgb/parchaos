extends Node3D

var posiciones = []

@onready var nodes = $nodes
@onready var boxes = $boxes
@onready var walls = $walls

func _ready() -> void:
	_vectors()

# Called every frame. 'delta' is the elapsed time since the previous frame. 
func _process(delta: float) -> void: pass

func _vectors() -> void:
	for node in walls.get_children():
		var lista = []
		for marker in node.get_children():
			lista.append(marker.global_position)
		posiciones.append(lista)
		
	print('[')
	for pos in posiciones:
		print(str(pos) + ',')
	print(']')
