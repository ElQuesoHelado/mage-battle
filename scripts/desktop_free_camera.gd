extends Camera3D

@export var move_speed: float = 20.0
@export var fast_multiplier: float = 2.5
@export var mouse_sensitivity: float = 0.003

var _rot_x: float = 0.0
var _rot_y: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	make_current()
	current = true
	_rot_x = rotation.x
	_rot_y = rotation.y
	print("[DesktopCamera] Modo espectador listo. Mantén CLIC DERECHO y usa WASD para volar.")


func _sync_rotation() -> void:
	_rot_x = rotation.x
	_rot_y = rotation.y


func _input(event: InputEvent) -> void:
	# Clic derecho sostenido (estilo editor de Godot) o clic izquierdo para capturar
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Escape libera el ratón
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Rotar la vista
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_rot_y -= event.relative.x * mouse_sensitivity
			_rot_x = clampf(_rot_x - event.relative.y * mouse_sensitivity, -1.45, 1.45)
			transform.basis = Basis()
			rotate_y(_rot_y)
			rotate_object_local(Vector3.RIGHT, _rot_x)


func _process(delta: float) -> void:
	if not is_current():
		make_current()

	var input_dir := Vector3.ZERO

	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input_dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input_dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_E):
		input_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_Q):
		input_dir.y -= 1.0

	if input_dir != Vector3.ZERO:
		var spd := move_speed
		if Input.is_physical_key_pressed(KEY_SHIFT):
			spd *= fast_multiplier

		var forward := -global_transform.basis.z
		var right := global_transform.basis.x
		var up := Vector3.UP

		var motion := (forward * (-input_dir.z) + right * input_dir.x + up * input_dir.y).normalized()
		global_position += motion * spd * delta
