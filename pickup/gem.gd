extends PickupAbleBody3D

@export var delay_before_change: float = 3.0
@export var scene_to_load: String = "res://main.tscn"

@onready var light: OmniLight3D = $OmniLight3D
@onready var anim: AnimationPlayer = $AnimationPlayer   # opcional

var _time := 0.0
var _base_y := 0.0
var _picked := false
var _spin_speed := 0.8


func _ready() -> void:
	picked_up.connect(_on_picked_up)

	# Flotar sin gravedad
	freeze = true
	gravity_scale = 0.0
	_base_y = position.y


func _process(delta: float) -> void:
	_time += delta

	if _picked:
		# Efecto "portal": gira más rápido, escala pulsante, luz intensa
		rotate_y(delta * _spin_speed * 5.0)
		var s := 1.0 + sin(_time * 12.0) * 0.08
		scale = Vector3(s, s, s)
		if light:
			light.light_energy = 2.0 + sin(_time * 25.0) * 1.0
		return

	# Estado flotante normal
	rotate_y(delta * _spin_speed)
	position.y = _base_y + sin(_time * 1.5) * 0.1

	if light:
		# Brillo tintineante
		light.light_energy = 1.0 + sin(_time * 6.0) * 0.35


func _on_picked_up() -> void:
	if _picked:
		return
	_picked = true

	# Animación de portal (si tienes AnimationPlayer en la escena)
	if anim and anim.has_animation("portal"):
		anim.play("portal")

	# Si usas partículas, actívalas
	var particles := get_node_or_null("GPUParticles3D")
	if particles:
		particles.emitting = true

	# Espera y cambia de escena
	await get_tree().create_timer(delay_before_change).timeout
	get_tree().call_deferred("change_scene_to_file", scene_to_load)
