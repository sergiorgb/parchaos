extends CharacterBody3D

@onready var camera: Camera3D = $Camera3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var muzzle_flash: GPUParticles3D = $Camera3D/pistol/GPUParticles3D
@onready var raycast: RayCast3D = $Camera3D/RayCast3D
@onready var gunshot_sound: AudioStreamPlayer3D = %GunshotSound

## Colors
@onready var ficha_roja = $visual/ficharoja
@onready var ficha_verde = $visual/fichaverde
@onready var ficha_amarilla = $visual/fichaamarilla
@onready var ficha_azul = $visual/fichaazul
@export var color_id: int = 0
var is_dead: bool = false
@export var health: int = 5
@export var spawns: PackedVector3Array = ([
	Vector3(-18, 0.2, 0),
	Vector3(18, 0.2, 0),
	Vector3(-2.8, 0.2, -6),
	Vector3(-17, 0, 17),
	Vector3(17, 0, 17),
	Vector3(17, 0, -17),
	Vector3(-17, 0, -17)
])

var sensitivity: float = .005
var controller_sensitivity: float = .010
var axis_vector: Vector2
var mouse_captured: bool = true

# Modo duelo: si es true, la muerte termina el duelo en vez de respawnear
var duel_mode: bool = false

const SPEED = 5.5
const JUMP_VELOCITY = 8

func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	add_to_group("Player")
	actualizar_color(color_id)
	if not is_multiplayer_authority(): return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true
	position = spawns[randi() % spawns.size()]

func _process(_delta: float) -> void:
	rotate_y(-axis_vector.x * controller_sensitivity)
	camera.rotate_x(-axis_vector.y * controller_sensitivity)
	camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return

	axis_vector = Input.get_vector("look_left", "look_right", "look_up", "look_down")

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
	camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)

	if Input.is_action_just_pressed("shoot") \
			and anim_player.current_animation != "shoot":
		play_shoot_effects.rpc()
		gunshot_sound.play()
		if raycast.is_colliding() and raycast.get_collider() is CharacterBody3D:
			var hit_player: Object = raycast.get_collider()
			if multiplayer.is_server():
				var authority = hit_player.get_multiplayer_authority()
				if authority == multiplayer.get_unique_id():
					hit_player.recieve_damage()
				else:
					hit_player.recieve_damage.rpc_id(authority)
			else:
				request_damage.rpc_id(1, hit_player.get_path())

	if Input.is_action_just_pressed("respawn") and not duel_mode:
		recieve_damage(5)

	if Input.is_action_just_pressed("capture"):
		if mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			mouse_captured = false
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			mouse_captured = true

func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null:
		if not is_multiplayer_authority(): return

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	if anim_player.current_animation == "shoot":
		pass
	elif input_dir != Vector2.ZERO and is_on_floor():
		anim_player.play("move")
	else:
		anim_player.play("idle")

	move_and_slide()

@rpc("call_local")
func play_shoot_effects() -> void:
	anim_player.stop()
	anim_player.play("shoot")
	muzzle_flash.restart()
	muzzle_flash.emitting = true

@rpc("any_peer", "reliable")
func recieve_damage(damage: int = 1) -> void:
	if not is_multiplayer_authority(): 
		return
	
	if is_dead or health <= 0:
		print("recieve_damage ignorado - ya muerto")
		return
	
	# 🔥 Verificación más robusta para duelo
	if duel_mode:
		# Intentar obtener estado del duelo, si falla asumir que sigue activo
		var duel_active_state = CaptureManager.is_duel_active()
		
		print("🔍 duel_mode:", duel_mode, " duel_active_state:", duel_active_state)
		
		if not duel_active_state:
			print("Duelo terminado, ignorando daño")
			return
		
	health -= damage
	print("recieve_damage, health:", health, " peer:", multiplayer.get_unique_id())
	
	if health <= 0:
		is_dead = true
		if duel_mode:
			if multiplayer.is_server():
				# 👇 ESTE ES EL CAMBIO RELEVANTE
				CaptureManager.resolve_duel(multiplayer.get_unique_id())
			else:
				_notify_duel_lost.rpc_id(1)
		else:
			health = 5
			is_dead = false
			position = spawns[randi() % spawns.size()]

@rpc("any_peer", "reliable")
func _notify_duel_lost() -> void:
	if not multiplayer.is_server(): 
		return
	
	# Usar la función en lugar de la propiedad directamente
	if not CaptureManager.is_duel_active():
		print("Duelo ya terminado, ignorando notificación")
		return
		
	var loser_peer = multiplayer.get_remote_sender_id()
	if loser_peer == 0:
		loser_peer = multiplayer.get_unique_id()
	print("💀 Resolviendo duelo, perdedor peer:", loser_peer)
	CaptureManager.resolve_duel(loser_peer)

func activate_duel_mode() -> void:
	print("🎮 activate_duel_mode llamado - peer:", multiplayer.get_unique_id())
	duel_mode = true
	health = 5
	is_dead = false
	position = spawns[randi() % spawns.size()]
	if is_multiplayer_authority():
		$Camera3D.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("✅ duel_mode =", duel_mode, " health =", health)

func deactivate_duel_mode() -> void:
	duel_mode = false
	health = 5
	is_dead = false
	
	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "shoot":
		anim_player.play("idle")

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

@rpc("any_peer", "reliable")
func request_damage(target_path: NodePath) -> void:
	print("request_damage recibido, path:", target_path)
	if not multiplayer.is_server():
		return
	var target = get_tree().root.get_node_or_null(target_path)
	print("target encontrado:", target)
	if target and target.has_method("recieve_damage"):
		var authority = target.get_multiplayer_authority()
		print("authority:", authority, " my_peer:", multiplayer.get_unique_id())
		if authority == multiplayer.get_unique_id():
			target.recieve_damage()
		else:
			target.recieve_damage.rpc_id(authority)
