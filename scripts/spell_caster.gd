extends Node3D
class_name SpellSystem

@export var wand_drawing: WandDrawing
@export var wand_tip: Node3D

@export_group("Hechizos")
@export var fireball_scene: PackedScene
@export var water_jet_scene: PackedScene

@export_group("Ajustes de hechizos")
@export var spell_time_window: float = 10.0

@export_group("Ajustes de disparo")
@export var forward_offset: float = 0.1
@export var cooldown_seconds: float = 0.4

var _cooldown_timer: float = 0.0

var _pending_shape: String = ""
var _shape_timestamp: float = -INF
var _shape_points: Array = []

var _pending_word: String = ""
var _word_timestamp: float = -INF

var _voice_source: Node


func _ready() -> void:
	if wand_drawing:
		wand_drawing.shape_recognized.connect(_on_shape_recognized)
		print("[SpellSystem] WandDrawing conectado")
	else:
		push_error("[SpellSystem] falta asignar wand_drawing")

	# Main es quien posee voice.gd
	_voice_source = get_tree().current_scene

	if _voice_source and _voice_source.has_signal("word_recognized"):
		_voice_source.word_recognized.connect(_on_word_recognized)
		print("[SpellSystem] Main/voice.gd conectado")
	else:
		push_error(
			"[SpellSystem] La escena principal no tiene la señal 'word_recognized'"
	)


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	var now := Time.get_ticks_msec() / 1000.0

	if _pending_shape != "":
		if now - _shape_timestamp > spell_time_window:
			_pending_shape = ""
			_shape_points.clear()

	if _pending_word != "":
		if now - _word_timestamp > spell_time_window:
			_pending_word = ""


func _on_shape_recognized(shape_name: String, points: Array) -> void:
	_pending_shape = shape_name.to_lower()
	_shape_timestamp = Time.get_ticks_msec() / 1000.0
	_shape_points = points.duplicate()

	print(
		"[SpellSystem] figura recibida: ",
		_pending_shape
	)

	_check_spell()


func _on_word_recognized(word: String) -> void:
	_pending_word = word.to_lower().strip_edges()
	_word_timestamp = Time.get_ticks_msec() / 1000.0

	print(
		"[SpellSystem] palabra recibida: ",
		_pending_word
	)

	_check_spell()


func _check_spell() -> void:
	if _cooldown_timer > 0.0:
		return

	print(
		"[SpellSystem] CHECK: ",
		_pending_shape,
		" + ",
		_pending_word
	)

	if _pending_shape == "" or _pending_word == "":
		return

	var now := Time.get_ticks_msec() / 1000.0

	if now - _shape_timestamp > spell_time_window:
		return

	if now - _word_timestamp > spell_time_window:
		return

	var spell_scene: PackedScene = null
	var spell_label := ""

	match _pending_shape:
		"circle":
			if _pending_word == "fuego" or _pending_word == "agua":
				spell_scene = fireball_scene
				spell_label = "fireball"

		"triangle":
			if _pending_word == "fuego" or _pending_word == "agua":
				spell_scene = water_jet_scene
				spell_label = "water_jet"

		"square":	
			if _pending_word == "fuego" or _pending_word == "agua":
				spell_scene = water_jet_scene
				spell_label = "water_jet"

	if spell_scene:
		print(
			"[SpellSystem] HECHIZO ACTIVADO: ",
			_pending_shape,
			" + ",
			_pending_word
		)

		_cast_projectile(spell_scene, spell_label)
		_clear_pending_spell()
	else:
		print(
			"[SpellSystem] combinación no válida: ",
			_pending_shape,
			" + ",
			_pending_word
		)


func _clear_pending_spell() -> void:
	_pending_shape = ""
	_pending_word = ""
	_shape_timestamp = -INF
	_word_timestamp = -INF
	_shape_points.clear()


func _cast_projectile(scene: PackedScene, label: String) -> void:
	if not scene:
		push_error(
			"SpellSystem: falta asignar la escena '%s' en el inspector"
			% label
		)
		return

	if not wand_tip:
		push_error(
			"SpellSystem: asigna wand_tip en el inspector"
		)
		return

	var projectile: Node3D = scene.instantiate()
	get_tree().current_scene.add_child(projectile)

	var forward: Vector3
	var origin: Vector3

	if (
		wand_drawing
		and wand_drawing.last_cast_direction.length() > 0.001
	):
		forward = wand_drawing.last_cast_direction
		origin = wand_drawing.last_cast_origin
	else:
		forward = -wand_tip.global_transform.basis.z
		origin = wand_tip.global_position

	print(
		"[SpellSystem] disparando ",
		label,
		": origin=",
		origin,
		" forward=",
		forward
	)

	projectile.global_position = origin + forward * forward_offset
	projectile.launch(forward)

	_cooldown_timer = cooldown_seconds
