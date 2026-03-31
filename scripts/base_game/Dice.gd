extends RigidBody3D

signal stopped(value)

var is_stopped = false

func _physics_process(_delta):
	if linear_velocity.length() > 1.0 and is_stopped:
		is_stopped = false
	# Si la velocidad es casi cero y no hemos avisado aún...
	if linear_velocity.length() < 0.1 and angular_velocity.length() < 0.1 and not is_stopped:
		is_stopped = true
		emit_signal("stopped", _get_upward_face())

func _get_upward_face() -> int:
	var b = global_transform.basis
	 
	var directions = {
		"4": b.y,          # Arriba (Y+)
		"3": -b.y,         # Abajo (Y-)
		"6": b.x,          # Derecha (X+)
		"1": -b.x,         # Izquierda (X-)
		"5": b.z,          # Frente (Z+)
		"2": -b.z          # Atrás (Z-)
	}
	
	var max_dot = -1.0
	var best_face = 0
	
	for face_value in directions:
		var dot = directions[face_value].dot(Vector3.UP)
		if dot > max_dot:
			max_dot = dot
			best_face = int(face_value)
	
	return best_face
