extends Node

# MENU VARIABLES 
@onready var main_menu: PanelContainer = $menu
@onready var host_menu: PanelContainer = $HostCustomer
@onready var yellow_button: Button = $HostCustomer/HBoxContainer/MarginContainer/PanelContainer/VBoxContainer/Yellow_Button
@onready var blue_button: Button = $HostCustomer/HBoxContainer/MarginContainer2/PanelContainer/VBoxContainer/Blue_Button
@onready var red_button: Button = $HostCustomer/HBoxContainer/MarginContainer3/PanelContainer/VBoxContainer/Red_Button
@onready var green_button: Button = $HostCustomer/HBoxContainer/MarginContainer4/PanelContainer/VBoxContainer/Green_Button
@onready var yellow_option: OptionButton = $HostCustomer/HBoxContainer/MarginContainer/PanelContainer/VBoxContainer/YellowOptionButton
@onready var blue_option: OptionButton = $HostCustomer/HBoxContainer/MarginContainer2/PanelContainer/VBoxContainer/BlueOptionButton
@onready var red_option: OptionButton = $HostCustomer/HBoxContainer/MarginContainer3/PanelContainer/VBoxContainer/RedOptionButton
@onready var green_option: OptionButton = $HostCustomer/HBoxContainer/MarginContainer4/PanelContainer/VBoxContainer/GreenOptionButton

@onready var address_entry: LineEdit = $menu/MarginContainer/VBoxContainer/HBoxContainer/ip_partida

const PlayerScene = preload("res://scenes/piecepvp.tscn")
var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
@export var enemy_spawns: PackedVector3Array = [
	Vector3(-10, 0.5, -10),
	Vector3(10, 0.5, 10),
	Vector3(0, 0.5, 15)
]

const PORT = 9999
var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()

var player_buttons: Array = ["HUMANO", "HUMANO", "HUMANO", "HUMANO"]
var difficulty_options: Array = [1, 1, 1, 1]
var ia_colors: Array = []
var human_colors: Array = []
var counter_ia: int = 0
var counter_human: int = 0

func _ready() -> void:
	yellow_option.visible = false
	blue_option.visible = false
	red_option.visible = false
	green_option.visible = false

func _on_yellow_button_pressed() -> void:
	if yellow_button.text == "HUMANO":
		player_buttons[0] = "IA"
		yellow_button.text = "IA"
		yellow_option.visible = true
	else:
		player_buttons[0] = "HUMANO"
		yellow_button.text = "HUMANO"
		yellow_option.visible = false

func _on_blue_button_pressed() -> void:
	if blue_button.text == "HUMANO":
		player_buttons[1] = "IA"
		blue_button.text = "IA"
		blue_option.visible = true
	else:
		player_buttons[1] = "HUMANO"
		blue_button.text = "HUMANO"
		blue_option.visible = false

func _on_red_button_pressed() -> void:
	if red_button.text == "HUMANO":
		player_buttons[2] = "IA"
		red_button.text = "IA"
		red_option.visible = true
	else:
		player_buttons[2] = "HUMANO"
		red_button.text = "HUMANO"
		red_option.visible = false

func _on_green_button_pressed() -> void:
	if green_button.text == "HUMANO":
		player_buttons[3] = "IA"
		green_button.text = "IA"
		green_option.visible = true
	else:
		player_buttons[3] = "HUMANO"
		green_button.text = "HUMANO"
		green_option.visible = false

func _on_host_button_pressed() -> void:
	main_menu.hide()
	host_menu.show()

func _on_back_button_pressed() -> void:
	main_menu.show()
	host_menu.hide()

func _on_yellow_option_button_item_selected(index: int) -> void:
	difficulty_options[0] = index

func _on_blue_option_button_item_selected(index: int) -> void:
	difficulty_options[1] = index

func _on_red_option_button_item_selected(index: int) -> void:
	difficulty_options[2] = index

func _on_green_option_button_item_selected(index: int) -> void:
	difficulty_options[3] = index

func _on_play_button_pressed() -> void:
	ia_colors.clear()
	human_colors.clear()
	counter_ia = 0
	counter_human = 0

	for i in range(4):
		GameConfig.player_config[i]["is_ai"] = player_buttons[i] == "IA"
		GameConfig.player_config[i]["difficulty"] = difficulty_options[i]
		if player_buttons[i] == "HUMANO":
			human_colors.append(i)
			counter_human += 1
		else:
			ia_colors.append(i)
			counter_ia += 1

	print("counter_human: ", counter_human, " human_colors: ", human_colors)

	if counter_human <= 1:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return

	# Ocultar UI
	_hide_ui()

	# Crear servidor
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(remove_player)

	# Agregar al host
	add_player(multiplayer.get_unique_id())
	upnp_setup()

	# Spawnear IAs si hay
	if counter_ia > 0:
		var ia_colors_snapshot = ia_colors.duplicate()
		spawn_enemies()
		sync_enemies.rpc(ia_colors_snapshot)

func _on_join_button_pressed() -> void:
	print("Join presionado, IP: ", address_entry.text)
	_hide_ui()
	enet_peer.create_client(address_entry.text, PORT)
	multiplayer.multiplayer_peer = enet_peer

func _hide_ui() -> void:
	if has_node("Pixelart"):
		$Pixelart.hide()
	if has_node("Colorcomplement"):
		$Colorcomplement.hide()
	if has_node("TextureRect"):
		$TextureRect.hide()
	main_menu.hide()
	host_menu.hide()

func _on_peer_connected(peer_id: int) -> void:
	print("Peer conectado: ", peer_id)
	add_player(peer_id)
	var total_conectados = multiplayer.get_peers().size() + 1
	print("Total: ", total_conectados, " necesarios: ", counter_human)
	if total_conectados >= counter_human:
		await get_tree().create_timer(0.6).timeout
		iniciar_cambio_escena_rpc.rpc()

func add_player(peer_id: int) -> void:
	var player: Node = PlayerScene.instantiate()
	player.name = str(peer_id)
	var assigned_color = human_colors.pop_front() if human_colors.size() > 0 else 0
	add_child(player)
	player.set_color.rpc(assigned_color)
	GameConfig.player_config[assigned_color]["peer_id"] = peer_id
	GameConfig.player_config[assigned_color]["is_ai"] = false
	print("HOST asignó color:", assigned_color)
	if peer_id != multiplayer.get_unique_id():
		await get_tree().create_timer(0.5).timeout
		GameConfig.set_my_color.rpc_id(peer_id, assigned_color)

func remove_player(peer_id: int) -> void:
	var player: Node = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()

func upnp_setup() -> void:
	var upnp: UPNP = UPNP.new()
	upnp.discover()
	upnp.add_port_mapping(PORT)
	var ip: String = upnp.query_external_address()
	if ip == "":
		print("Failed to establish upnp connection!")
	else:
		print("Success! Join Address: %s" % ip)

func spawn_enemies() -> void:
	for i in range(counter_ia):
		var assigned_color = ia_colors.pop_front()
		var enemy_instance = enemy_scene.instantiate()
		enemy_instance.name = "Enemy_" + str(i)
		enemy_instance.position = enemy_spawns[randi() % enemy_spawns.size()]
		add_child(enemy_instance)
		enemy_instance.set_color.rpc(assigned_color)

@rpc("authority", "call_local", "reliable")
func sync_enemies(colors: Array) -> void:
	if multiplayer.is_server():
		return
	for i in range(colors.size()):
		var enemy_instance = enemy_scene.instantiate()
		enemy_instance.name = "Enemy_" + str(i)
		enemy_instance.position = enemy_spawns[randi() % enemy_spawns.size()]
		add_child(enemy_instance)
		enemy_instance.set_color.rpc_id(multiplayer.get_unique_id(), colors[i])

@rpc("authority", "call_local", "reliable")
func iniciar_cambio_escena_rpc() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
