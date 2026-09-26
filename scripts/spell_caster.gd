extends Node3D
class_name SpellSystem

## Director de la batalla. Se ocupa de tres cosas:
##   1. saber si el jugador está en un altar,
##   2. lanzar el hechizo que el jugador dice por la voz,
##   3. llevar la cuenta de bajas e invocar al jefe gigante.

# -----------------------------------------------------------------
# Datos de los elementos
# -----------------------------------------------------------------

## Ciclo de debilidades: cada elemento es débil al que le sigue.
## fuego → agua → rayo → tierra → fuego
const WEAK_CYCLE := {
	"fuego":  "agua",
	"agua":   "rayo",
	"rayo":   "tierra",
	"tierra": "fuego",
}

const LABEL := {
	"fuego": "FUEGO",
	"agua": "AGUA",
	"rayo": "RAYO",
	"tierra": "TIERRA",
}

const COLOR := {
	"fuego":  Color(1.00, 0.35, 0.08),
	"agua":   Color(0.15, 0.55, 1.00),
	"rayo":   Color(1.00, 0.90, 0.25),
	"tierra": Color(0.60, 0.38, 0.16),
}

## Texto corto que resume la regla, para el HUD.
const RULE_TEXT := "FUEGO→AGUA · AGUA→RAYO · RAYO→TIERRA · TIERRA→FUEGO"
const ENERGY_TEXT := "Dibuja círculos para encender el ALTAR MAYOR"


static func label_of(element: String) -> String:
	return LABEL.get(element, element.to_upper())


static func color_of(element: String) -> Color:
	return COLOR.get(element, Color.WHITE)


## Elemento al que es vulnerable "element". Cadena vacía si no aplica.
static func weakness_of(element: String) -> String:
	return WEAK_CYCLE.get(element, "")


## Texto de una weakness, listo para el HUD.
static func weakness_text(weak: String) -> String:
	if weak.is_empty():
		return "cualquiera"
	return label_of(weak)


# -----------------------------------------------------------------
# Exportaciones
# -----------------------------------------------------------------

@export_group("Hechizos")
@export var fireball_scene: PackedScene
@export var water_jet_scene: PackedScene
@export var bolt_scene: PackedScene
@export var rock_scene: PackedScene

@export_group("Altares")
## Altar Mayor: el único que habilita el lanzamiento. Su energía la
## recarga el jugador dibujando círculos.
@export var major_altar: AltarMayor
@export var cast_cost: float = 10.0
## En false se puede hechizar sin energía. Sólo para depurar.
@export var require_energy: bool = true

@export_group("Jefe gigante")
@export var giant_scene: PackedScene
@export var giant_max_health: int = 14
@export var giant_scale: float = 2.6
## Distancia a la que aparece el jefe, por delante del jugador.
@export var giant_spawn_distance: float = 4.5
@export var giant_cleanup_delay: float = 2.0

@export_group("Ajustes")
@export var cooldown_seconds: float = 0.35
## Cuánto se adelanta el hechizo respecto a la cámara, para que salga
## de la mano y no de la cara.
@export var cast_offset: float = 0.45
## Tope de hechizos vivos a la vez. Cada uno arrastra 2-3 sistemas de
## partículas, que es lo caro de verdad en un Quest 2. Con 4 hay
## bastante visualmente sin hundir el frame rate.
@export var max_projectiles: int = 4

@export_group("Mono")
@export var mono_mesh: Mesh = preload("res://assets/Orangutan.obj")
@export var mono_max_count: int = 12

@export_group("HUD VR")
@export var hud_distance: float = 1.2
@export var hud_font_size: int = 64
@export var show_debug_hud: bool = false
@export var feedback_seconds: float = 3.5

# -----------------------------------------------------------------
# Estado
# -----------------------------------------------------------------

var _altars: Array[Node] = []
var _cooldown: float = 0.0
var _giant_spawned: bool = false
var _finished: bool = false

var _feedback: String = ""
var _feedback_timestamp: float = -INF

var _voice_source: Node
var _hud: Label3D
var _hud_anchor: Node3D
var _hud_cache: String = ""
## El texto del HUD sólo se reconstruye cuando algo lo invalida.
## Antes se armaba la cadena y el Array cada frame.
var _hud_dirty: bool = true
## Último porcentaje pintado en la barra, para no reescribirla cada
## frame mientras la energía se drena.
var _hud_pct: int = -1

var _mono_shape: ConcavePolygonShape3D
var _mono_bodies: Array[Node] = []


# -----------------------------------------------------------------
# Arranque
# -----------------------------------------------------------------

func _ready() -> void:
	# El grupo es la vía por la que los magos encuentran al director
	# sin depender de la posición en el árbol: register_mage_kill() ya
	# no está en la raíz de la escena, sino aquí.
	add_to_group("spell_system")
	_setup_hud()
	_connect_voice()
	# Diferido a propósito: el Altar Mayor y la varita son hermanos y su
	# _ready() corre después del nuestro, así que en este punto todavía
	# no se han registrado en sus grupos y el NodePath exportado puede
	# no haber resuelto. Un frame más tarde todo está en su sitio y el
	# orden en el archivo deja de importar.
	_connect_altar.call_deferred()


func _connect_altar() -> void:
	if major_altar == null or not is_instance_valid(major_altar):
		# Si no se asignó a mano, se busca por tipo en la escena.
		var found := get_tree().get_first_node_in_group("altar_mayor")
		if found is AltarMayor:
			major_altar = found
	if major_altar == null or not is_instance_valid(major_altar):
		push_error("[SpellSystem] falta el AltarMayor: no se podrá lanzar")
		return

	if not major_altar.energy_gained.is_connected(_on_energy_gained):
		major_altar.energy_gained.connect(_on_energy_gained)

	# El círculo se dibuja con la varita, que cuelga del mando derecho.
	var wand := get_tree().get_first_node_in_group("wand_drawing")
	if wand != null and wand.has_signal("circle_drawn"):
		if not wand.circle_drawn.is_connected(_on_circle_drawn):
			wand.circle_drawn.connect(_on_circle_drawn)
	else:
		push_warning("[SpellSystem] no se encontró WandDrawing: el círculo no recargará")


func _connect_voice() -> void:
	_voice_source = get_tree().current_scene
	if _voice_source != null and _voice_source.has_signal("word_recognized"):
		_voice_source.word_recognized.connect(_on_word_recognized)
	else:
		push_error("[SpellSystem] la escena principal no expone 'word_recognized'")


# -----------------------------------------------------------------
# Bucle
# -----------------------------------------------------------------

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and _hud_anchor != null:
		_hud_anchor.global_transform = cam.global_transform

	if _cooldown > 0.0:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_hud_dirty = true

	# El aviso del jugador caduca solo.
	if _feedback != "" \
			and Time.get_ticks_msec() / 1000.0 - _feedback_timestamp > feedback_seconds:
		_feedback = ""
		_hud_dirty = true

	# La barra de energía se repinta sólo cuando cambia el porcentaje
	# entero. Con el drenaje continuo cambia en cada frame, y rehacer
	# el texto del HUD 90 veces por segundo no es gratis.
	if major_altar != null and is_instance_valid(major_altar):
		var pct := int(round(major_altar.get_fill() * 100.0))
		if pct != _hud_pct:
			_hud_pct = pct
			_hud_dirty = true

	if _hud_dirty:
		_hud_dirty = false
		_set_hud(_build_hud_text())


# -----------------------------------------------------------------
# Círculo → energía
# -----------------------------------------------------------------

func _on_circle_drawn() -> void:
	if major_altar == null or not is_instance_valid(major_altar):
		return
	major_altar.add_circle()


func _on_energy_gained(amount: float) -> void:
	_set_feedback("+%.0f de energía" % amount)


# -----------------------------------------------------------------
# Voz → hechizo
# -----------------------------------------------------------------

func _on_word_recognized(word: String) -> void:
	var w := word.to_lower().strip_edges()

	if w == "mono":
		_spawn_mono()
		return

	if not LABEL.has(w):
		return

	if _finished:
		return

	if require_energy:
		if major_altar == null or not is_instance_valid(major_altar):
			_set_feedback("No hay Altar Mayor")
			return
		if not major_altar.is_online():
			_set_feedback("Sin energía: dibuja un círculo en el aire")
			return
		if major_altar.energia < cast_cost:
			_set_feedback("Energía insuficiente (%d)" % int(major_altar.energia))
			return

	if _cooldown > 0.0:
		return

	# Tope de proyectiles: preferimos un aviso a hundir el frame rate.
	if get_tree().get_nodes_in_group("projectiles").size() >= max_projectiles:
		_set_feedback("Demasiados hechizos en vuelo")
		return

	_cast(w)


func _cast(element: String) -> void:
	var scene := _scene_for(element)
	if scene == null:
		_set_feedback("Falta la escena de %s" % label_of(element))
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_set_feedback("No hay camara")
		return

	var projectile := scene.instantiate() as Node3D
	if projectile == null or not projectile.has_method("launch"):
		_set_feedback("La escena de %s no tiene launch()" % label_of(element))
		return

	# El hechizo sale disparado en la dirección en la que está
	# mirando la cámara en ese instante.
	var forward: Vector3 = -cam.global_transform.basis.z
	var origin: Vector3 = cam.global_position + forward * cast_offset

	get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin
	projectile.launch(forward)

	# Se cobra la energía sólo cuando el hechizo sale de verdad.
	if major_altar != null and is_instance_valid(major_altar):
		major_altar.spend(cast_cost)

	_cooldown = cooldown_seconds
	_set_feedback("¡%s!" % label_of(element))


func _scene_for(element: String) -> PackedScene:
	match element:
		"fuego":
			return fireball_scene
		"agua":
			return water_jet_scene
		"rayo":
			return bolt_scene
		"tierra":
			return rock_scene
	return null


# -----------------------------------------------------------------
# Jefes y fin de partida
# -----------------------------------------------------------------

## Lo llama wizard.gd cuando un mago se muere. El mago ya se ha
## retirado del grupo "mages" en ese punto, así que un grupo vacío
## significa "no queda ningún elemental normal".
func register_mage_kill() -> void:
	if _finished:
		return
	if _giant_spawned:
		_finish()
		return
	if get_tree().get_nodes_in_group("mages").is_empty():
		_spawn_giant()


func _spawn_giant() -> void:
	if _giant_spawned:
		return
	if giant_scene == null:
		push_error("[SpellSystem] falta giant_scene; no se puede invocar al jefe")
		_finish()
		return

	var cam := get_viewport().get_camera_3d()
	var forward: Vector3 = Vector3.FORWARD
	if cam != null:
		forward = -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	var origin := Vector3.ZERO
	if cam != null:
		origin = cam.global_position
	var pos: Vector3 = origin + forward * giant_spawn_distance
	pos.y = 0.0

	var giant: Node3D = giant_scene.instantiate()
	get_tree().current_scene.add_child(giant)
	giant.global_position = pos
	# El jefe mira al jugador, no al revés.
	if origin.distance_to(pos) > 0.01:
		giant.look_at(origin, Vector3.UP)

	# weakness_element vacío => inmune a las debilidades: cualquier
	# elemento le hace daño.
	giant.max_health = giant_max_health
	giant.death_cleanup_delay = giant_cleanup_delay
	giant.health = giant_max_health
	giant.shrinks_on_damage = true
	giant.base_scale = Vector3.ONE * giant_scale
	giant.scale = giant.base_scale

	_giant_spawned = true
	_set_feedback("¡El GRAN MAGO se alza! Aguanta lo que sea.")


func _finish() -> void:
	_finished = true
	# call_deferred: register_mage_kill() llega desde un body_entered, o
	# sea desde el paso de física. Cambiar de escena ahí empieza a
	# liberar los cuerpos y los que quedan reciben take_damage() sin
	# estar ya en el árbol.
	get_tree().call_deferred("change_scene_to_file", "res://outro.tscn")


# -----------------------------------------------------------------
# HUD
# -----------------------------------------------------------------

func _build_hud_text() -> String:
	var lines: Array[String] = []

	if _giant_spawned and not _finished:
		lines.append("GRAN MAGO: aguanta cualquier elemento")

	lines.append(_energy_line())

	if _feedback != "":
		lines.append(_feedback)

	return "\n".join(lines)


## Barra de energía con 8 bloques. Es texto plano, no geometría, así que
## no cuesta nada de FPS.
func _energy_line() -> String:
	if major_altar == null or not is_instance_valid(major_altar):
		return "Sin Altar Mayor"

	var fill: float = major_altar.get_fill()
	var lit := int(round(fill * 8.0))
	var bar := "▮".repeat(lit) + "▯".repeat(8 - lit)
	var pct := int(round(fill * 100.0))

	if not major_altar.is_online():
		return "ALTAR MAYOR APAGADO  %s  %d%%" % [bar, pct]
	return "ALTAR MAYOR  %s  %d%%" % [bar, pct]


func _set_hud(text: String) -> void:
	# Reasignar el text de un Label3D regenera su malla: sólo se toca
	# cuando el string cambia de verdad.
	if text == _hud_cache or _hud == null:
		return
	_hud_cache = text
	_hud.text = text


func _set_feedback(msg: String) -> void:
	_feedback = msg
	_feedback_timestamp = Time.get_ticks_msec() / 1000.0
	_hud_dirty = true


func _setup_hud() -> void:
	_hud_anchor = Node3D.new()
	_hud_anchor.name = "HUDAnchor"
	add_child(_hud_anchor)

	_hud = Label3D.new()
	_hud.font_size = hud_font_size
	_hud.outline_size = 24
	_hud.modulate = Color(1, 1, 1)
	_hud.outline_modulate = Color(0, 0, 0)
	_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hud.no_depth_test = true
	_hud.fixed_size = true
	_hud.pixel_size = 0.001
	_hud.position = Vector3(0, 0.28, -hud_distance)
	_hud.text = ""
	_hud_anchor.add_child(_hud)


# -----------------------------------------------------------------
# Mono (detalle)
# -----------------------------------------------------------------

func _spawn_mono() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var from := cam.global_position
	var to: Vector3 = from + (-cam.global_transform.basis.z) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		_set_feedback("No veo dónde ponerlo")
		return

	_create_mono_at(result.position, from)
	_set_feedback("¡Mono invocado!")


func _create_mono_at(pos: Vector3, look_from: Vector3) -> void:
	if mono_mesh == null:
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
		var oldest: Node = _mono_bodies.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
