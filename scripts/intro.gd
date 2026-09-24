extends Node3D

@onready var wizard: Node3D = $mageIntro
@onready var gem: RigidBody3D = $Table/Gem

var _time := 0.0
var _gem_base_y := 0.0
var _gem_active := false


func _ready() -> void:
	print("Hijos del root: ", get_children().map(func(n): return n.name))
	print("¿Existe Gem? ", has_node("Gem"))
	print("Ruta: ", get_path())
	# La gema empieza oculta
	gem.visible = false
	gem.freeze = true
	gem.gravity_scale = 0.0
	_gem_base_y = gem.global_position.y

	# Escucha al mago
	wizard.cast_started.connect(_show_gem)


func _process(delta: float) -> void:
	if not _gem_active:
		return

	_time += delta
	gem.global_position.y = _gem_base_y + sin(_time * 1.5) * 0.08
	gem.rotate_y(delta * 0.4)


func _show_gem() -> void:
	gem.visible = true
	_gem_active = true

	# Pequeño "pop" de aparición
	gem.scale = Vector3.ZERO
	var tween := create_tween()
	tween.tween_property(gem, "scale", Vector3.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
