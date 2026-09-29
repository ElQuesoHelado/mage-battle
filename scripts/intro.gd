extends Node3D

@onready var wizard: Node3D = $mageIntro
@onready var gem: RigidBody3D = $Table/Gem
@onready var texto_mago: Label3D = $mageIntro/TextoSobreMago

#const TEXTO := "tu magia esta en tu voz, proteje al libro con ella"
const TEXTO := ""

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

	# Texto sobre el mago: definir y mostrar desde el inicio
	if texto_mago:
		texto_mago.text = TEXTO
		texto_mago.visible = false     # <- si lo quieres oculto hasta el cast, pon false


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

	# Aseguramos que el texto esté visible cuando el mago castea
	if texto_mago:
		texto_mago.visible = true

	# Pequeño "pop" de aparición
	gem.scale = Vector3.ZERO
	var tween := create_tween()
	tween.tween_property(gem, "scale", Vector3.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
