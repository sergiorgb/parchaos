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
const PORT = 9999
var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var controller: bool = false

var player_buttons: Array = ["HUMANO", "HUMANO", "HUMANO", "HUMANO"]
var difficulty_options: Array = [1, 1, 1, 1]

# INICIO MENU !
func _ready() -> void:
	yellow_option.visible = yellow_button.text == "IA"
	blue_option.visible = blue_button.text == "IA"
	red_option.visible = red_button.text == "IA"
	green_option.visible = red_button.text == "IA"

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

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
	var ia_counter : int = 0
	for i in range(4):
		if player_buttons[i].text == "IA":
			ia_counter += 1
		GameConfig.player_config[i]["is_ai"] = player_buttons[i].text == "IA"
		GameConfig.player_config[i]["difficulty"] = difficulty_options[i].selected
		if ia_counter == 4:
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
	add_child(player)

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
