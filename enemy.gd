extends CharacterBody3D

# --- Pathfinding ---
@export var speed: float = 4.0
@export var waypoint_reach_dist: float = 0.3
@export var repath_interval: float = 0.2

var path: PackedVector3Array = []
var path_index: int = 0
var _repath_timer: float = 0.0

# --- Parámetros de Físicas ---
const JUMP_VELOCITY = 4.5
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- Parámetros de la IA (Salto) ---
var jump_timer: float = 0.0
@export var min_jump_interval: float = 1
@export var max_jump_interval: float = 2.2
var is_dead: bool = false
var health: int = 5

# --- Parámetros de Disparo ---
@export var fire_rate: float = 3
var fire_timer: float = 0.0
var duel_mode: bool = false
var player: Node3D = null
# AGREGAR junto a las otras vars:
var _sync_pos: Vector3 = Vector3.ZERO
var _sync_rot: Vector3 = Vector3.ZERO
var _interp_speed: float = 15.0
var _sync_timer: float = 0.0
var _sync_interval: float = 0.05  # 20 veces por segundo

## Colors
@onready var ficha_roja = $visual/ficharoja
@onready var ficha_verde = $visual/fichaverde
@onready var ficha_amarilla = $visual/fichaamarilla
@onready var ficha_azul = $visual/fichaazul
@export var color_id: int = 0

# --- Nodos ---
@onready var camera_3d: Camera3D = $Camera3D
@onready var raycast: RayCast3D = $Camera3D/RayCast3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var muzzle_flash: GPUParticles3D = $Camera3D/pistol/GPUParticles3D
@onready var gunshot_sound: AudioStreamPlayer3D = %GunshotSound

@export var spawns: PackedVector3Array = ([
	Vector3(-18, 0.2, 0),
	Vector3(18, 0.2, 0),
	Vector3(-2.8, 0.2, -6),
	Vector3(-17, 0, 17),
	Vector3(17, 0, 17),
	Vector3(17, 0, -17),
	Vector3(-17, 0, -17)
])

func _ready():
	randomize()
	reset_jump_timer()
	print("🦾 IA creada en posición:", global_position)
	if multiplayer.is_server():
		await get_tree().create_timer(0.3).timeout
		set_color.rpc(color_id)

func _physics_process(delta):
	if multiplayer.is_server():
		# Lógica solo en servidor
		if not player:
			player = get_tree().get_first_node_in_group("Player")
			if not player and duel_mode:
				for child in get_parent().get_children():
					if child != self and child.has_method("set_player_target"):
						player = child
						break

		if player:
			aim_at_player()
			check_and_shoot(delta)
			_follow_path(delta)
			_repath_timer -= delta
			if _repath_timer <= 0.0:
				_repath_timer = repath_interval
				path = PathFindingManager.find_path(global_position, player.global_position)
				path_index = 0

		if not is_on_floor():
			velocity.y -= gravity * delta
		if is_on_floor():
			jump_timer -= delta
			if jump_timer <= 0.0:
				jump()
		move_and_slide()

		# Mandar sync a clientes
		_sync_timer -= delta
		if _sync_timer <= 0.0:
			_sync_timer = _sync_interval
			_sync_state.rpc(global_position, global_rotation, health)
	else:
		# Cliente: interpolar hacia la posición autoritativa
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		global_position = global_position.lerp(_sync_pos, _interp_speed * delta)
		global_rotation = global_rotation.lerp(_sync_rot, _interp_speed * delta)

@rpc("authority", "unreliable")
func _sync_state(pos: Vector3, rot: Vector3, hp: int) -> void:
	_sync_pos = pos
	_sync_rot = rot
	if health != hp:
		health = hp

func _follow_path(_delta):
	if path_index >= path.size():
		return

	var target = path[path_index]
	var flat_target = Vector3(target.x, global_position.y, target.z)
	var direction = (flat_target - global_position).normalized()

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if global_position.distance_to(flat_target) < waypoint_reach_dist:
		path_index += 1

func jump():
	velocity.y = JUMP_VELOCITY
	reset_jump_timer()

func reset_jump_timer():
	jump_timer = randf_range(min_jump_interval, max_jump_interval)

func aim_at_player():
	var target_position = player.global_position
	target_position.y = global_position.y
	look_at(target_position, Vector3.UP)
	camera_3d.look_at(player.global_position, Vector3.UP)

func check_and_shoot(delta):
	fire_timer -= delta
	raycast.force_raycast_update()
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider == player:
			if fire_timer <= 0.0:
				shoot(collider)

func shoot(hit_player: Object):
	fire_timer = fire_rate
	_play_shoot_fx.rpc()
	if hit_player.has_method("recieve_damage"):
		if hit_player.get_multiplayer_authority() == multiplayer.get_unique_id():
			hit_player.recieve_damage()
		else:
			hit_player.recieve_damage.rpc_id(hit_player.get_multiplayer_authority())

@rpc("authority", "call_local", "reliable")
func _play_shoot_fx() -> void:
	if anim_player.has_animation("shoot"):
		anim_player.stop()
		anim_player.play("shoot")
	muzzle_flash.restart()
	muzzle_flash.emitting = true
	gunshot_sound.play()

# REEMPLAZAR recieve_damage:
func recieve_damage(damage: int = 1) -> void:
	if not multiplayer.is_server():
		return
	if is_dead or health <= 0:
		return
	health -= damage
	if health <= 0:
		is_dead = true
		if duel_mode:
			CaptureManager.resolve_duel(-1)
		else:
			health = 5
			is_dead = false
			var new_pos = spawns[randi() % spawns.size()]
			position = new_pos
			sync_position_enemy.rpc(new_pos)  # ya lo tenías

@rpc("authority", "call_local", "reliable")
func sync_position_enemy(new_pos: Vector3) -> void:
	position = new_pos

func actualizar_color(new_color_id: int) -> void:
	ficha_roja.visible = false
	ficha_verde.visible = false
	ficha_amarilla.visible = false
	ficha_azul.visible = false
	match new_color_id:
		0: ficha_amarilla.visible = true
		1: ficha_azul.visible = true
		2: ficha_roja.visible = true
		3: ficha_verde.visible = true

@rpc("any_peer", "call_local", "reliable")
func set_color(new_color: int) -> void:
	color_id = new_color
	actualizar_color(color_id)
	print("🎨 IA recibió color:", new_color)
