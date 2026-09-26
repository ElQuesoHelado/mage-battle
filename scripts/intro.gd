extends Node3D

@onready var wizard: Node3D = $mageIntro
@onready var gem: RigidBody3D = $Table/Gem

## Si el jugador no recoge la gema en este tiempo, la escena avanza
## sola. Evita que la intro se convierta en un callejón sin salida.
@export var auto_advance_seconds: float = 20.0
@export var next_scene: String = "res://main.tscn"

var _time := 0.0
var _gem_base_y := 0.0
var _gem_active := false


func _ready() -> void:
	if not wizard:
		push_error("[Intro] falta el nodo 'mageIntro'")
	elif not wizard.has_signal("cast_started"):
		push_error("[Intro] 'mageIntro' no expone la señal 'cast_started'")
	else:
		wizard.cast_started.connect(_show_gem)

	if gem == null:
		push_error("[Intro] falta el nodo 'Table/Gem'")
		return

	# La gema empieza oculta
	gem.visible = false
	gem.freeze = true
	gem.gravity_scale = 0.0
	_gem_base_y = gem.global_position.y

	if auto_advance_seconds > 0.0:
		_auto_advance()


func _process(delta: float) -> void:
	if not _gem_active or gem == null:
		return

	_time += delta
	gem.global_position.y = _gem_base_y + sin(_time * 1.5) * 0.08
	gem.rotate_y(delta * 0.4)


func _show_gem() -> void:
	if gem == null or _gem_active:
		return
	_gem_active = true
	gem.visible = true

	# Pequeño "pop" de aparición
	gem.scale = Vector3.ZERO
	var tween := create_tween()
	tween.tween_property(gem, "scale", Vector3.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _auto_advance() -> void:
	await get_tree().create_timer(auto_advance_seconds).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file(next_scene)
