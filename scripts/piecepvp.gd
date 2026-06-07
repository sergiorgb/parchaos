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
		if raycast.is_colliding() and str(raycast.get_collider()).contains("CharacterBody3D"):
			var hit_player: Object = raycast.get_collider()
			hit_player.recieve_damage.rpc_id(hit_player.get_multiplayer_authority())

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

@rpc("any_peer", "call_local")
func recieve_damage(damage: int = 1) -> void:
	if not is_multiplayer_authority(): return
	health -= damage
	if health <= 0:
		if duel_mode:
			# En modo duelo: notificar al servidor que este peer perdió
			_notify_duel_lost.rpc_id(1)
		else:
			health = 5
			position = spawns[randi() % spawns.size()]

@rpc("any_peer", "reliable")
func _notify_duel_lost() -> void:
	if not multiplayer.is_server(): return  # ← correcto
	var loser_peer = multiplayer.get_remote_sender_id()
	CaptureManager.resolve_duel(loser_peer)


func activate_duel_mode() -> void:
	duel_mode = true
	health = 5
	position = spawns[randi() % spawns.size()]

func deactivate_duel_mode() -> void:
	duel_mode = false
	health = 5

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "shoot":
		anim_player.play("idle")

func actualizar_color(color_id: int) -> void:
	ficha_roja.visible = false
	ficha_verde.visible = false
	ficha_amarilla.visible = false
	ficha_azul.visible = false
	match color_id:
		0: ficha_amarilla.visible = true
		1: ficha_azul.visible = true
		2: ficha_roja.visible = true
		3: ficha_verde.visible = true

@rpc("any_peer", "call_local", "reliable")
func set_color(new_color: int) -> void:
	color_id = new_color
	actualizar_color(color_id)
