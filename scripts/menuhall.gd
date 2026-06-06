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

# MULTIPLAYER VARIBALES
@onready var address_entry: LineEdit = $menu/MarginContainer/VBoxContainer/HBoxContainer/ip_partida

const Player = preload("res://scenes/piecepvp.tscn")
var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
@export var enemy_spawns: PackedVector3Array = [
	Vector3(-10, 0.5, -10),
	Vector3(10, 0.5, 10),
	Vector3(0, 0.5, 15)
]

const PORT = 9999
var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var controller: bool = false

var player_buttons: Array = ["HUMANO", "HUMANO", "HUMANO", "HUMANO"]
var difficulty_options: Array = [1, 1, 1, 1]
var ia_colors : Array = []
var human_colors : Array = []
var counter_ia : int = 0
var counter_human : int = 0

# INICIO MENU !
func _ready() -> void:
	yellow_option.visible = yellow_button.text == "IA"
	blue_option.visible = blue_button.text == "IA"
	red_option.visible = red_button.text == "IA"
	green_option.visible = red_button.text == "IA"

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	verificar_inicio_partida()
	
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

# FIN MENU !

func _on_play_button_pressed() -> void:
	for i in range(4):
		GameConfig.player_config[i]["is_ai"] = player_buttons[i] == "IA"
		GameConfig.player_config[i]["difficulty"] = difficulty_options[i]
		if player_buttons[i] == "HUMANO":
			human_colors.append(i)
			counter_human += 1
		else:
			ia_colors.append(i)
			counter_ia += 1
	print(ia_colors)
	print(human_colors)
	if player_buttons == ["IA", "IA", "IA", "IA"] or player_buttons == ["HUMAN", "IA", "IA", "IA"]:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		# HIDE 2D
		$Pixelart.hide()
		$Colorcomplement.hide()
		main_menu.hide()
		$TextureRect.hide()
		$HostCustomer.hide()
			
		enet_peer.create_server(PORT)
		multiplayer.multiplayer_peer = enet_peer
		multiplayer.peer_connected.connect(add_player)
		multiplayer.peer_disconnected.connect(remove_player)

		add_player(multiplayer.get_unique_id())
		upnp_setup()
		spawn_enemies()
		
		print(counter_ia)
	
func _on_join_button_pressed() -> void:
	# HIDE 2D
	$Pixelart.hide()
	$Colorcomplement.hide()
	main_menu.hide()
	$TextureRect.hide()
	$HostCustomer.hide()
	
	# JOIN
	enet_peer.create_client(address_entry.text, PORT)
	multiplayer.multiplayer_peer = enet_peer

func add_player(peer_id: int) -> void:
	var player: Node = Player.instantiate()
	player.name = str(peer_id)
	var assigned_color = human_colors.pop_front()
	add_child(player)
	player.set_color.rpc(assigned_color)
	print("HOST asignó color:", player.color_id)

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
		print("Success! Join Address: %s" % upnp.query_external_address())

func spawn_enemies() -> void:
	for i in range(counter_ia):
		var iassigned_color = ia_colors.pop_front()
		# A. Creamos la instancia en memoria
		var enemy_instance = enemy_scene.instantiate()
		# B. Le damos un nombre único (crucial para la sincronización multijugador)
		enemy_instance.name = "Enemy_" + str(i)
		# C. Le asignamos una posición de aparición aleatoria
		var random_index = randi() % enemy_spawns.size()
		enemy_instance.position = enemy_spawns[random_index]
		# D. Lo añadimos físicamente al árbol de la escena principal
		add_child(enemy_instance)
		enemy_instance.set_color.rpc(iassigned_color)

# Supongamos que aquí es donde sumas a los jugadores que están listos

func verificar_inicio_partida() -> void:
	# REGLA DE ORO: Solo el servidor/host controla el flujo de las escenas
	if not is_multiplayer_authority(): 
		return
	
	# Godot cuenta los clientes conectados con get_peers(). 
	# Le sumamos 1 para incluir también al Host (servidor).
	var total_conectados = multiplayer.get_peers().size() + 1
	
	# Comparamos tu contador con el total real de personas en la sala
	if counter_human == total_conectados:
		# Ordenamos a todos los peers (clientes y a nosotros mismos) cambiar de escena
		iniciar_cambio_escena_rpc.rpc()

# Este RPC le da la orden directa al motor de cada jugador
@rpc("authority", "call_local", "reliable")
func iniciar_cambio_escena_rpc() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
