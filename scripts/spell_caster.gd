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
## Techo de monos vivos: evita que alguien invoque 500 y revente la
## memoria del Quest.
@export var mono_max_count: int = 12

@export_group("HUD VR")
@export var hud_distance: float = 1.2
@export var hud_font_size: int = 96
@export var debug_font_size: int = 32
## Volcado de estado interno (shape/word/hits) bajo el texto principal.
@export var show_debug_hud: bool = false
## Avisos breves al jugador ("decí la palabra", "esa figura es de...").
@export var feedback_seconds: float = 3.0

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

var _feedback: String = ""
var _feedback_timestamp: float = -INF

var _voice_source: Node
var _hud: Label3D
var _debug_hud: Label3D
var _hud_anchor: Node3D

# Cachés: reasignar el texto de un Label3D regenera su malla, así que
# solo se toca cuando el string cambia de verdad.
var _hud_cache: String = ""
var _debug_cache: String = ""
var _debug_timer: float = 0.0

# El "mono" reutiliza la misma malla y el mismo shape: crear un
# trimesh nuevo por cada invocación era el grueso del coste.
var _mono_shape: ConcavePolygonShape3D
var _mono_bodies: Array[Node] = []


func _ready() -> void:
	_setup_hud()

	# Si no está asignado en el inspector, lo buscamos en la escena.
	if not wand_drawing:
		wand_drawing = _find_wand_drawing()

	if wand_drawing:
		var err := wand_drawing.shape_recognized.connect(_on_shape_recognized)
		if err != OK:
			push_error("[SpellSystem] no se pudo conectar shape_recognized (%d)" % err)
	else:
		push_error("[SpellSystem] NO encontré ningún WandDrawing en la escena")

	_voice_source = get_tree().current_scene
	if _voice_source and _voice_source.has_signal("word_recognized"):
		_voice_source.word_recognized.connect(_on_word_recognized)
	else:
		push_error("[SpellSystem] escena principal sin 'word_recognized'")


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

	if s == "" or s == "unknown":
		_set_feedback("No reconocí esa figura")
		return

	# "star" y "heart" las reconoce el reconocedor pero no son hechizo.
	if not SHAPE_LABEL.has(s):
		_set_feedback("%s no es un hechizo" % s.to_upper())
		return

	_pending_shape = s
	_shape_timestamp = Time.get_ticks_msec() / 1000.0
	_set_feedback("Decí: %s" % SHAPE_LABEL[s])


func _on_word_recognized(word: String) -> void:
	var w := word.to_lower().strip_edges()
	_last_word = w

	if w == "mono":
		_spawn_mono()
		return

	if not SPELL_TABLE.has(w):
		return

	if _pending_shape == "":
		_set_feedback("Primero dibujá una figura")
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _shape_timestamp > shape_window_seconds:
		_clear_pending_shape()
		_set_feedback("Se pasó el tiempo, dibujá de nuevo")
		return

	var expected: String = SPELL_TABLE[w]
	if _pending_shape != expected:
		_set_feedback("Esa figura no es de %s" % w.to_upper())
		return

	if _cooldown_timer > 0.0:
		return

	_cast_spell(w)
	_clear_pending_shape()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and _hud_anchor:
		_hud_anchor.global_transform = cam.global_transform

	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	var now := Time.get_ticks_msec() / 1000.0
	var lines: Array[String] = []

	if _pending_shape != "":
		var remaining := shape_window_seconds - (now - _shape_timestamp)
		if remaining <= 0.0:
			_clear_pending_shape()
		else:
			lines.append(SHAPE_LABEL.get(_pending_shape, _pending_shape.to_upper()))
			lines.append("%.1fs · decí la palabra" % remaining)

	if _feedback != "":
		if now - _feedback_timestamp > feedback_seconds:
			_feedback = ""
		else:
			lines.append(_feedback)

	_set_hud("\n".join(lines))
	_update_debug_hud(now)


func _set_hud(text: String) -> void:
	if text == _hud_cache:
		return
	_hud_cache = text
	_hud.text = text


func _update_debug_hud(now: float) -> void:
	if not _debug_hud:
		return
	_debug_hud.visible = show_debug_hud
	if not show_debug_hud:
		return

	# Volcado a ~4 Hz: es información de depuración, no HUD.
	_debug_timer -= get_process_delta_time()
	if _debug_timer > 0.0:
		return
	_debug_timer = 0.25

	var lines: Array[String] = []
	lines.append("shape: '%s'" % _pending_shape)
	lines.append("word:  '%s'" % _last_word)
	lines.append("hits:  %d" % _signal_hits)
	if _pending_shape != "":
		lines.append("timer: %.1fs"
			% (shape_window_seconds - (now - _shape_timestamp)))
	if not wand_drawing:
		lines.append("wand: NULL")

	var text := "\n".join(lines)
	if text == _debug_cache:
		return
	_debug_cache = text
	_debug_hud.text = text


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
	# Apagado salvo que show_debug_hud se active a mano.
	_debug_hud.visible = false
	_hud_anchor.add_child(_debug_hud)


func _clear_pending_shape() -> void:
	_pending_shape = ""
	_shape_timestamp = -INF


func _cast_spell(word: String) -> void:
	match word:
		"fuego":
			_cast_projectile(fireball_scene, "FUEGO")
		"agua":
			_cast_projectile(water_jet_scene, "AGUA")
		"rayo":
			_cast_projectile(bolt_scene, "RAYO")
		"roca":
			_cast_projectile(rock_scene, "ROCA")


func _cast_projectile(scene: PackedScene, label: String) -> void:
	if not wand_tip:
		_set_feedback("Falta wand_tip en el inspector")
		return
	if not scene:
		_set_feedback("Falta la escena de %s" % label)
		return

	var projectile := scene.instantiate() as Node3D
	if projectile == null or not projectile.has_method("launch"):
		_set_feedback("La escena de %s no tiene launch()" % label)
		return

	var forward: Vector3
	var origin: Vector3
	if wand_drawing and wand_drawing.last_cast_direction.length() > 0.001:
		forward = wand_drawing.last_cast_direction
		origin = wand_drawing.last_cast_origin
	else:
		forward = -wand_tip.global_transform.basis.z
		origin = wand_tip.global_position

	get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin + forward * 0.1
	projectile.launch(forward)

	_cooldown_timer = cooldown_seconds
	_set_feedback("¡%s!" % label)


# -----------------------------------------------------------------
# Mono
# -----------------------------------------------------------------

func _spawn_mono() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var from := camera.global_transform.origin
	var to := from + (-camera.global_transform.basis.z) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		_set_feedback("No veo dónde ponerlo")
		return

	_create_mono_at(result.position, camera.global_transform.origin)
	_set_feedback("¡Mono invocado!")


func _create_mono_at(pos: Vector3, look_from: Vector3) -> void:
	if not mono_mesh:
		return

	# El shape se crea una sola vez y se comparte entre todos los monos.
	if _mono_shape == null:
		_mono_shape = mono_mesh.create_trimesh_shape()
	_prune_monos()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mono_mesh
	mesh_instance.material_override = _mono_material()

	var body := StaticBody3D.new()
	body.add_child(mesh_instance)

	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = _mono_shape
	body.add_child(collision_shape)

	get_tree().current_scene.add_child(body)
	# Se posiciona ya dentro del árbol: si se fijara global_position
	# antes, en un nodo sin padre se interpretaría como local.
	body.global_position = pos
	if pos.distance_to(look_from) > 0.01:
		body.look_at(look_from, Vector3.UP)

	_mono_bodies.append(body)


func _mono_material() -> StandardMaterial3D:
	# El .obj viene sin .mtl, así que la superficie sale sin material.
	# Se asigna uno aquí para que no se vea negro puro.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.30, 0.20)
	mat.roughness = 0.9
	return mat


func _prune_monos() -> void:
	var dead: Array[Node] = []
	for m in _mono_bodies:
		if not is_instance_valid(m):
			dead.append(m)
	for m in dead:
		_mono_bodies.erase(m)

	while _mono_bodies.size() >= mono_max_count:
		# pop_front() devuelve Variant en un Array tipado, así que el tipo
		# se declara explícito (si no, el aviso de inferencia es error).
		var oldest: Node = _mono_bodies.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _set_feedback(msg: String) -> void:
	_feedback = msg
	_feedback_timestamp = Time.get_ticks_msec() / 1000.0
