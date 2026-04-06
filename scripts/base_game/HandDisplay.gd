class_name HandDisplay
extends Control

var card_scene = preload("res://scenes/card_3d.tscn")
const CARD_TEXTURES = {
	-1: preload("res://resources/cards/Respaldo.png"),
	0:  preload("res://resources/cards/Turbo.png"),
	1:  preload("res://resources/cards/Escudo.png"),
	2:  preload("res://resources/cards/Fuga.png"),
	3:  preload("res://resources/cards/Sabotaje.png"),
	4:  preload("res://resources/cards/Hielo.png"),
	5:  preload("res://resources/cards/Doble.png"),
	6:  preload("res://resources/cards/Ladron.png")
}

const CARD_SIZE = Vector2(180, 260)
const MAX_CARDS = 5
const FAN_SPREAD = 20.0
const FAN_Y_OFFSET = 0.8

# ✅ SEÑAL MODIFICADA: ahora incluye posición en pantalla
signal card_clicked(card_index: int, screen_position: Vector2)

var card_nodes: Array = []

func setup():
	position = Vector2.ZERO 
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_right = 0
	offset_top = 0
	offset_bottom = 0

func show_hand(hand: Array):
	_clear_cards()
	var count = hand.size()
	if count == 0:
		return
	
	var vp = get_tree().root.get_viewport().get_visible_rect().size
	var total_width = count * (CARD_SIZE.x + 10) - 10
	var start_x = vp.x / 2.0 - total_width / 2.0 - global_position.x
	var base_y = vp.y - CARD_SIZE.y / 1.75 - global_position.y
	
	for i in range(count):
		var card = TextureRect.new()
		card.texture = CARD_TEXTURES.get(hand[i], CARD_TEXTURES[-1])
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_SCALE
		card.z_index = i
		card.position = Vector2(start_x + i * (CARD_SIZE.x + 10), base_y)
		
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		
		# ✅ GUARDAR POSICIÓN PARA LA SEÑAL
		var idx = i
		var card_screen_pos = card.position + CARD_SIZE / 2 + global_position
		
		card.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				# ✅ EMITIR ÍNDICE Y POSICIÓN CENTRAL DE LA CARTA
				card_clicked.emit(idx, card_screen_pos)
		)
		
		# Hover efecto
		card.mouse_entered.connect(func():
			var tween = create_tween()
			tween.tween_property(card, "position:y", card.position.y - 15, 0.1)
		)
		card.mouse_exited.connect(func():
			var tween = create_tween()
			tween.tween_property(card, "position:y", card.position.y + 15, 0.1)
		)
		
		add_child(card)
		card.size = CARD_SIZE
		card_nodes.append(card)

func hide_hand():
	visible = false

func reveal_hand():
	visible = true

func _clear_cards():
	for c in card_nodes:
		c.queue_free()
	card_nodes.clear()
