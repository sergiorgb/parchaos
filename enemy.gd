extends CharacterBody3D

# --- Parámetros de Físicas ---
const JUMP_VELOCITY = 4.5
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- Parámetros de la IA (Salto) ---
var jump_timer: float = 0.0
@export var min_jump_interval: float = 1 
@export var max_jump_interval: float = 2.2 

@export var health: int = 5

# --- Parámetros de Disparo ---
@export var fire_rate: float = 3 # Tiempo entre cada disparo (en segundos)
var fire_timer: float = 0.0

var player: Node3D = null

## Colors
@onready var ficha_roja = $visual/ficharoja
@onready var ficha_verde = $visual/fichaverde
@onready var ficha_amarilla = $visual/fichaamarilla
@onready var ficha_azul = $visual/fichaazul
@export var color_id : int = 0

# --- Nodos ---
@onready var camera_3d: Camera3D = $Camera3D
@onready var raycast: RayCast3D = $Camera3D/RayCast3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var muzzle_flash: GPUParticles3D = $Camera3D/pistol/GPUParticles3D
@onready var gunshot_sound: AudioStreamPlayer3D = %GunshotSound

## The xyz position of the random spawns, you can add as many as you want!
@export var spawns: PackedVector3Array = ([
	Vector3(-18, 0.2, 0),
	Vector3(18, 0.2, 0),
	Vector3(-2.8, 0.2, -6),
	Vector3(-17,0,17),
	Vector3(17,0,17),
	Vector3(17,0,-17),
	Vector3(-17,0,-17)
])

func _ready():
	randomize() 
	reset_jump_timer()

func _physics_process(delta):
	# 1. Buscar al jugador
	if not player:
		player = get_tree().get_first_node_in_group("Player")
	
	# 2. Apuntar y evaluar disparo
	if player:
		aim_at_player()
		check_and_shoot(delta)

	# 3. Aplicar gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 4. Lógica del salto
	if is_on_floor():
		jump_timer -= delta
		if jump_timer <= 0.0:
			jump()

	# 5. Ejecutar movimiento
	move_and_slide()

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

# --- NUEVA LÓGICA DE DISPARO ---

func check_and_shoot(delta):
	# Reducimos el temporizador de disparo
	fire_timer -= delta
	
	# Forzamos al RayCast a actualizarse en este frame exacto para mayor precisión
	raycast.force_raycast_update()
	
	# Si el RayCast está chocando con algo...
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		
		# Verificamos si ese "algo" es nuestro jugador
		if collider == player:
			# Si es el jugador y ya pasó el tiempo de recarga, disparamos
			if fire_timer <= 0.0:
				shoot(collider)

func shoot(hit_player: Object):
	# Reiniciamos el temporizador para la cadencia de fuego
	fire_timer = fire_rate
	
	# 1. Efectos visuales y sonoros (Similares a los de tu jugador)
	if anim_player.has_animation("shoot"):
		anim_player.stop()
		anim_player.play("shoot")
	
	muzzle_flash.restart()
	muzzle_flash.emitting = true
	gunshot_sound.play()
	
	# 2. Aplicar daño usando la estructura de tu juego multijugador
	# Usamos el método recieve_damage que creaste en el script del jugador
	if hit_player.has_method("recieve_damage"):
		# Lo llamamos a través de RPC tal como lo haces en el _unhandled_input del jugador
		hit_player.recieve_damage.rpc_id(hit_player.get_multiplayer_authority())

@rpc("any_peer", "call_local")
func recieve_damage(damage:= 1) -> void:
	health -= damage
	if health <= 0:
		health = 5
		position = spawns[randi() % spawns.size()]
		
func actualizar_color(color_id):
	ficha_roja.visible = false
	ficha_verde.visible = false
	ficha_amarilla.visible = false
	ficha_azul.visible = false

	match color_id:
		0:
			ficha_amarilla.visible = true
		1:
			ficha_azul.visible = true
		2:
			ficha_roja.visible = true
		3:
			ficha_verde.visible = true
			
@rpc("any_peer", "call_local", "reliable")
func set_color(new_color:int):
	color_id = new_color
	actualizar_color(color_id)
