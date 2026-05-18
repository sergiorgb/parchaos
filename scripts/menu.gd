extends Control

const FONT_PATH = "res://resources/impact/impact.ttf"
const PLAYER_COLORS = [
	Color("#c4a832"),  # Amarillo
	Color("#2d6ea8"),  # Azul
	Color("#a83232"),  # Rojo
	Color("#2d8a3e")   # Verde
]
const PLAYER_NAMES = ["AMARILLO", "AZUL", "ROJO", "VERDE"]

var font: FontFile
var player_buttons: Array = []
var difficulty_options: Array = []

func _ready():
	font = load(FONT_PATH)
	_build_ui()

func _build_ui():
	# Fondo
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("060e1aff")
	add_child(bg)

	# Título
	var title = Label.new()
	title.text = "PARCHAOS"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.position.y = 40
	add_child(title)

	# Contenedor de jugadores
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_CENTER)
	hbox.position = Vector2(-420, -100)
	hbox.add_theme_constant_override("separation", 20)
	add_child(hbox)

	for i in range(4):
		hbox.add_child(_build_player_panel(i))

	# Botón jugar
	var play_btn = Button.new()
	play_btn.text = "¡JUGAR!"
	play_btn.anchor_left = 0.5
	play_btn.anchor_right = 0.5
	play_btn.anchor_top = 1.0
	play_btn.anchor_bottom = 1.0
	play_btn.offset_left = -100
	play_btn.offset_right = 100
	play_btn.offset_top = -80
	play_btn.offset_bottom = -20
	play_btn.add_theme_font_override("font", font)
	play_btn.add_theme_font_size_override("font_size", 28)
	play_btn.pressed.connect(_on_play_pressed)
	_style_button(play_btn, Color("8B1a2a"))
	add_child(play_btn)

func _build_player_panel(index: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 220)

	var style = StyleBoxFlat.new()
	style.bg_color = PLAYER_COLORS[index].darkened(0.4)
	style.border_color = PLAYER_COLORS[index]
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# Círculo de color
	var icon = Label.new()
	icon.text = "♙"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 64)
	icon.add_theme_color_override("font_color", PLAYER_COLORS[index])
	vbox.add_child(icon)

	# Nombre
	var label = Label.new()
	label.text = PLAYER_NAMES[index]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", PLAYER_COLORS[index])
	vbox.add_child(label)

	# Toggle Humano/IA
	var btn = Button.new()
	btn.text = "HUMANO"
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 16)
	_style_button(btn, Color("#333355"))
	btn.pressed.connect(_on_toggle_pressed.bind(index, btn))
	player_buttons.append(btn)
	vbox.add_child(btn)

	# Dificultad
	var opt = OptionButton.new()
	opt.add_item("Fácil", 0)
	opt.add_item("Normal", 1)
	opt.add_item("Difícil", 2)
	opt.selected = 1
	opt.visible = false
	opt.add_theme_font_override("font", font)
	opt.add_theme_font_size_override("font_size", 14)
	difficulty_options.append(opt)
	vbox.add_child(opt)

	return panel

func _style_button(btn: Button, color: Color):
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate()
	hover.bg_color = color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover)

func _on_toggle_pressed(index: int, btn: Button):
	var is_ai = btn.text == "HUMANO"
	btn.text = "IA" if is_ai else "HUMANO"
	_style_button(btn, Color("#8B1a2a") if is_ai else Color("#333355"))
	difficulty_options[index].visible = is_ai

func _on_play_pressed():
	for i in range(4):
		GameConfig.player_config[i]["is_ai"] = player_buttons[i].text == "IA"
		GameConfig.player_config[i]["difficulty"] = difficulty_options[i].selected

	get_tree().change_scene_to_file("res://scenes/main.tscn")
