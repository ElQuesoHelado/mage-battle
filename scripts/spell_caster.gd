extends Node3D
class_name SpellSystem

@export var wand_drawing: WandDrawing
@export var wand_tip: Node3D

@export_group("Hechizos")
@export var fireball_scene: PackedScene
@export var water_jet_scene: PackedScene
@export var bolt_scene: PackedScene
@export var rock_scene: PackedScene

@export_group("Ajustes")
@export var shape_window_seconds: float = 5.0
@export var cooldown_seconds: float = 0.4

@export_group("Mono")
@export var mono_mesh: Mesh = preload("res://assets/Orangutan.obj")

@export_group("HUD VR")
@export var hud_distance: float = 1.2
@export var hud_font_size: int = 96
@export var debug_font_size: int = 32

const SPELL_TABLE := {
	"fuego": "circle",
	"agua":  "triangle",
	"rayo": "bolt",
	"roca": "lt",
}

const SHAPE_LABEL := {
	"circle":    "FUEGO",
	"triangle": "AGUA",
	"bolt":   "RAYO",
	"lt": "ROCA",
}

var _pending_shape: String = ""
var _shape_timestamp: float = -INF
var _cooldown_timer: float = 0.0
var _last_word: String = ""
var _signal_hits: int = 0

var _cast_feedback: String = ""
var _cast_feedback_timestamp: float = -INF

var _voice_source: Node
var _hud: Label3D
var _debug_hud: Label3D
var _hud_anchor: Node3D


func _ready() -> void:
	_setup_hud()

	# Si no está asignado en el inspector, lo buscamos en la escena.
	if not wand_drawing:
		wand_drawing = _find_wand_drawing()
		if wand_drawing:
			print("[SpellSystem] WandDrawing encontrado por búsqueda: ", wand_drawing.name)

	if wand_drawing:
		var ok := wand_drawing.shape_recognized.connect(_on_shape_recognized)
		if ok == OK:
			print("[SpellSystem] conexión OK con shape_recognized")
		else:
			push_error("[SpellSystem] fallo al conectar: código %d" % ok)
	else:
		push_error("[SpellSystem] NO encontré ningún WandDrawing en la escena")

	_voice_source = get_tree().current_scene
	if _voice_source and _voice_source.has_signal("word_recognized"):
		_voice_source.word_recognized.connect(_on_word_recognized)
		print("[SpellSystem] conexión OK con word_recognized")
	else:
		push_error("[SpellSystem] escena principal sin 'word_recognized'")

	print("[SpellSystem] listo")


func _find_wand_drawing() -> WandDrawing:
	var root := get_tree().current_scene
	if not root:
		return null
	return _find_recursive(root) as WandDrawing


func _find_recursive(n: Node) -> Node:
	if n is WandDrawing:
		return n
	for c in n.get_children():
		var r := _find_recursive(c)
		if r:
			return r
	return null


func _on_shape_recognized(shape_name: String, _points: Array) -> void:
	_signal_hits += 1
	var s := shape_name.to_lower()
	print("[SpellSystem] FIGURA: '", s, "' (hit #", _signal_hits, ")")

	if s == "" or s == "unknown":
		return

	_pending_shape = s
	_shape_timestamp = Time.get_ticks_msec() / 1000.0


func _on_word_recognized(word: String) -> void:
	var w := word.to_lower().strip_edges()
	_last_word = w
	print("[SpellSystem] VOZ: '", w, "'")

	if w == "mono":
		_spawn_mono()
		return

	if not SPELL_TABLE.has(w):
		print("[SpellSystem] palabra no es hechizo")
		return

	if _pending_shape == "":
		print("[SpellSystem] no hay figura armada")
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _shape_timestamp > shape_window_seconds:
		print("[SpellSystem] figura expirada")
		_clear_pending_shape()
		return

	var expected: String = SPELL_TABLE[w]
	if _pending_shape != expected:
		print("[SpellSystem] figura incorrecta: '", _pending_shape,
			"' vs esperada '", expected, "'")
		return

	if _cooldown_timer > 0.0:
		print("[SpellSystem] en cooldown")
		return

	print("[SpellSystem] *** HECHIZO: '", w, "' + '", _pending_shape, "' ***")
	_cast_spell(w)
	_clear_pending_shape()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and _hud_anchor:
		_hud_anchor.global_transform = cam.global_transform

	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if _pending_shape != "":
		var now := Time.get_ticks_msec() / 1000.0
		var remaining := shape_window_seconds - (now - _shape_timestamp)
		if remaining <= 0.0:
			_clear_pending_shape()
		else:
			var label_text: String = SHAPE_LABEL.get(_pending_shape, _pending_shape.to_upper())
			_hud.text = "%s\n%.1fs · di la palabra" % [label_text, remaining]
	else:
		_hud.text = ""

	_update_debug_hud()


func _update_debug_hud() -> void:
	if not _debug_hud:
		return
	var lines: Array[String] = []
	lines.append("shape: '%s'" % _pending_shape)
	lines.append("word:  '%s'" % _last_word)
	lines.append("hits:  %d" % _signal_hits)
	if _pending_shape != "":
		var now := Time.get_ticks_msec() / 1000.0
		var rem := shape_window_seconds - (now - _shape_timestamp)
		lines.append("timer: %.1fs" % rem)
	if not wand_drawing:
		lines.append("wand: NULL")
	if _cast_feedback != "":
		var elapsed := Time.get_ticks_msec() / 1000.0 - _cast_feedback_timestamp
		if elapsed > 3.0:
			_cast_feedback = ""
		else:
			lines.append("cast: %s" % _cast_feedback)
	_debug_hud.text = "\n".join(lines)


func _setup_hud() -> void:
	_hud_anchor = Node3D.new()
	_hud_anchor.name = "HUDAnchor"
	add_child(_hud_anchor)

	_hud = Label3D.new()
	_hud.font_size = hud_font_size
	_hud.outline_size = 32
	_hud.modulate = Color(1, 1, 1)
	_hud.outline_modulate = Color(0, 0, 0)
	_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hud.no_depth_test = true
	_hud.fixed_size = true
	_hud.pixel_size = 0.001
	_hud.position = Vector3(0, 0.25, -hud_distance)
	_hud.text = ""
	_hud_anchor.add_child(_hud)

	_debug_hud = Label3D.new()
	_debug_hud.font_size = debug_font_size
	_debug_hud.outline_size = 8
	_debug_hud.modulate = Color(0.6, 1, 0.6)
	_debug_hud.outline_modulate = Color(0, 0, 0)
	_debug_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_hud.no_depth_test = true
	_debug_hud.fixed_size = true
	_debug_hud.pixel_size = 0.001
	_debug_hud.position = Vector3(0, -0.15, -hud_distance)
	_debug_hud.text = ""
	_hud_anchor.add_child(_debug_hud)


func _clear_pending_shape() -> void:
	_pending_shape = ""
	_shape_timestamp = -INF
	if _hud:
		_hud.text = ""


func _cast_spell(word: String) -> void:
	match word:
		"fuego":
			if not fireball_scene:
				_feedback("FALTA fireball_scene en el inspector")
				return
			_cast_projectile(fireball_scene, "fireball")
		"agua":
			if not water_jet_scene:
				_feedback("FALTA water_jet_scene en el inspector")
				return
			_cast_projectile(water_jet_scene, "water_jet")
		"rayo":
			if not bolt_scene:
				_feedback("FALTA bolt_scene en el inspector")
				return
			_cast_projectile(bolt_scene, "bolt")
		"roca":
			if not rock_scene:
				_feedback("FALTA rock_scene en el inspector")
				return
			_cast_projectile(rock_scene, "roca")
			
func _cast_projectile(scene: PackedScene, label: String) -> void:
	if not wand_tip:
		_feedback("FALTA wand_tip en el inspector")
		return

	var projectile: Node3D = scene.instantiate()
	get_tree().current_scene.add_child(projectile)

	var forward: Vector3
	var origin: Vector3
	if wand_drawing and wand_drawing.last_cast_direction.length() > 0.001:
		forward = wand_drawing.last_cast_direction
		origin = wand_drawing.last_cast_origin
	else:
		forward = -wand_tip.global_transform.basis.z
		origin = wand_tip.global_position

	projectile.global_position = origin + forward * 0.1

	if not projectile.has_method("launch"):
		_feedback("La escena '%s' no tiene launch()" % label)
		return

	projectile.launch(forward)
	_cooldown_timer = cooldown_seconds
	_feedback("CAST: %s OK" % label)


func _spawn_mono() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var from := camera.global_transform.origin
	var forward := -camera.global_transform.basis.z
	var to := from + forward * 100.0
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return
	_create_mono_at(result.position)


func _create_mono_at(pos: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mono_mesh
	var body := StaticBody3D.new()
	body.global_transform.origin = pos
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = mono_mesh.create_trimesh_shape()
	body.add_child(mesh_instance)
	body.add_child(collision_shape)
	get_tree().current_scene.add_child(body)
	var camera := get_viewport().get_camera_3d()
	if camera:
		body.look_at(camera.global_transform.origin, Vector3.UP)
	print("[SpellSystem] MONO en ", pos)
	
	
func _feedback(msg: String) -> void:
	_cast_feedback = msg
	_cast_feedback_timestamp = Time.get_ticks_msec() / 1000.0
	print("[SpellSystem] FEEDBACK: ", msg)
