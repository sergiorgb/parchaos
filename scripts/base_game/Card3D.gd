class_name Card3D
extends Node3D

@export var card_type: int = -1 : set = set_card_type

const TEXTURES = {
	-1: "res://resources/cards/Respaldo.png",
	0:  "res://resources/cards/Turbo.png",
	1:  "res://resources/cards/Escudo.png",
	2:  "res://resources/cards/Fuga.png",
	3:  "res://resources/cards/Sabotaje.png",
	4:  "res://resources/cards/Hielo.png",
	5:  "res://resources/cards/Doble.png",
	6:  "res://resources/cards/Lagron.png"
}

var front_material: StandardMaterial3D
var back_material: StandardMaterial3D

signal clicked(card_3d)

func _ready():
	var front = $Front
	var back = $Back
	
	front_material = front.get_surface_override_material(0)
	back_material = back.get_surface_override_material(0)
	
	set_card_type(card_type)
	
	var area = $Area3D
	area.input_event.connect(_on_input_event)

func _on_input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)

func set_card_type(new_type: int):
	card_type = new_type
	if not front_material:
		return
	var texture_path = TEXTURES.get(new_type, TEXTURES[-1])
	front_material.albedo_texture = load(texture_path)

func highlight():
	if front_material:
		front_material.emission_enabled = true
		front_material.emission = Color(1.0, 0.9, 0.4)
		front_material.emission_energy_multiplier = 1.2

func remove_highlight():
	if front_material:
		front_material.emission_enabled = false
