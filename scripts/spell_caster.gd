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

## El cuerpo del mago se pinta con el color OPUESTO al de su debilidad,
## para que el color del hechizo nunca se confunda con el color del
## enemigo. Son dos intercambios: fuego<->agua y rayo<->tierra. Ojo: esto
## NO cambia COLOR, que es la paleta elemental y la siguen usando los
## proyectiles y el HUD.
const TINT_COLOR := {
	"fuego":  Color(0.15, 0.55, 1.00),
	"agua":   Color(1.00, 0.35, 0.08),
	"rayo":   Color(0.60, 0.38, 0.16),
	"tierra": Color(1.00, 0.90, 0.25),
}

## Texto corto que resume la regla, para el HUD.
const RULE_TEXT := "FUEGO→AGUA · AGUA→RAYO · RAYO→TIERRA · TIERRA→FUEGO"
const ENERGY_TEXT := "Dibuja un trazo largo para encender el ALTAR MAYOR"

## Resultado de la última partida. Lo lee outro.gd al cambiar de escena.
## Una static var evita tener que montar un autoload sólo para pasar un
## booleano de una escena a la siguiente.
static var last_result_victoria: bool = true


static func label_of(element: String) -> String:
	return LABEL.get(element, element.to_upper())


static func color_of(element: String) -> Color:
	return COLOR.get(element, Color.WHITE)


## Color con el que se pinta el cuerpo de un mago débil a "element".
static func tint_of(element: String) -> Color:
	return TINT_COLOR.get(element, Color.WHITE)


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
## recarga el jugador dibujando un trazo largo con la varita.
@export var major_altar: AltarMayor
@export var cast_cost: float = 20.0
## En false se puede hechizar sin energía. Sólo para depurar.
@export var require_energy: bool = true

@export_group("Olas de magos")
## Escena de mago. Antes había cuatro magos fijos en main.tscn; ahora
## se instancia uno por elemento de cada ola, así que el orden de la
## partida está en una tabla y no en la jerarquía de la escena.
@export var wizard_scene: PackedScene
## Cada entrada es una ola. Dentro, el elemento al que es vulnerable
## cada mago.
@export var waves: Array[PackedStringArray] = [
	PackedStringArray(["agua", "fuego"]),
	PackedStringArray(["tierra", "rayo"]),
]
## Dónde salen. Se van reusing en orden, así que con dos puntos y olas
## de dos magos cada uno va a un sitio.
@export var wizard_spawn_points: Array[Vector3] = [
	Vector3(-1.6, 0.1, -4.4),
	Vector3(1.6, 0.1, -4.4),
]
@export var wizard_max_health: int = 3
## Tamaño de los magos de cada ola. wizard.tscn viene a escala 1.0, y
## a esa distancia los magos se perdían contra el fondo del bosque.
## 1.0 -> 1.2 -> 1.56 -> 1.4. Bajado de 1.56 porque a esa escala el
## mago se comía demasiado campo de visión en el visor.
@export var wizard_scale: float = 1.4
## Proyectil que lanzan los magos al libro. Se pasa a cada mago recién
## creado para que wizard.gd no lleve rutas escritas.
@export var enemy_projectile: PackedScene
## Segundos de respiro entre que cae la última ola y entra la siguiente.
## Es lo que marca el ritmo de la partida: sin esto, matar dos magos
## seguido y ver aparecer dos más al instante es un muro.
@export var wave_break_seconds: float = 2.5

@export_group("Jefe gigante")
@export var giant_scene: PackedScene
## Con la debilidad rotando, sólo uno de cada cuatro elementos le hace
## daño. Con 14 PV hacían falta unos 22 trazos de mano sólo para matarlo.
@export var giant_max_health: int = 8
## Subido de 2.6 a 4.06 (x1.2 y luego x1.3) para que se lea como jefe
## gigante y no como un mago normal estirado.
@export var giant_scale: float = 4.06
## Distancia a la que aparece el jefe, por delante del jugador.
## estaba en 4.5 m; un metro más lejos para que el jefe no aparezca
## encima de la cara y dé tiempo a verlo entrar.
@export var giant_spawn_distance: float = 5.5
@export var giant_cleanup_delay: float = 2.0
## El jefe dispara más despacio que los magos normales: es más grande
## y su animación se lee peor de lejos.
@export var giant_attack_interval: float = 9.0

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
## Tope de monos vivos. Ahora cada uno se autodestruye, así que esto es
## sólo una red de seguridad para invocar veinte veces seguidas.
@export var mono_max_count: int = 6
## Daño del mono. Es poco contra magos normales, pero cuesta la misma
## energía que un hechizo, así que no sirve para ganar la partida.
@export var mono_damage: int = 1
## Distancia a la que aparece, por delante del jugador.
@export var mono_spawn_distance: float = 1.6

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
## Índice de la ola que se está jugando. -1 = aún no ha empezado ninguna.
var _wave_index: int = -1
## El libro mágico, o null si la escena no lo trae. Es lo que hay que
## proteger: si cae, derrota.
var _book: LibroMagico

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
	_begin_battle.call_deferred()


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

	# La energía la recarga el trazo que se hace con la varita, que cuelga
	# del mando derecho.
	var wand := get_tree().get_first_node_in_group("wand_drawing")
	if wand != null and wand.has_signal("stroke_finished"):
		if not wand.stroke_finished.is_connected(_on_stroke_finished):
			wand.stroke_finished.connect(_on_stroke_finished)
	else:
		push_warning("[SpellSystem] no se encontró WandDrawing: el altar no se podrá recargar")


## Conexión con el libro y arranque de la primera ola.Va diferido por lo
## mismo que el altar: los grupos sólo existen un frame después.
func _begin_battle() -> void:
	_book = get_tree().get_first_node_in_group("libro_magico") as LibroMagico
	if _book == null:
		push_warning("[SpellSystem] no se encontró el libro mágico: no habrá condición de derrota")
	else:
		_book.destruido.connect(_on_book_destroyed)

	_spawn_wave(_wave_index + 1)


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


## Lo llama el jefe cuando gira su debilidad, para que el HUD se
## entere aunque esté detrás del jugador.
func notify_weakness_changed(_weak_element: String) -> void:
	_hud_dirty = true


## Lo llama el libro al recibir un golpe, para que el HUD repinte la vida.
func notify_book_damaged(_health: int) -> void:
	_hud_dirty = true


# -----------------------------------------------------------------
# Trazo → energía
# -----------------------------------------------------------------

func _on_stroke_finished(gain: float) -> void:
	if major_altar == null or not is_instance_valid(major_altar):
		return
	major_altar.add_charge(gain)


func _on_energy_gained(amount: float) -> void:
	_set_feedback("+%.0f de energía" % amount)


# -----------------------------------------------------------------
# Voz → hechizo
# -----------------------------------------------------------------

func _on_word_recognized(word: String) -> void:
	var w := word.to_lower().strip_edges()

	if w == "mono":
		# El mono también cuesta energía. Antes salía por aquí antes del
		# control, y como hace daño de verdad se podía spamear gratis
		# hasta matar una ola entera sin decir un hechizo.
		if _finished or not _puede_pagar() or _cooldown > 0.0:
			return
		_spawn_mono()
		return

	if not LABEL.has(w):
		return

	if _finished:
		return

	if not _puede_pagar():
		return

	if _cooldown > 0.0:
		return

	# Tope de proyectiles: preferimos un aviso a hundir el frame rate.
	if get_tree().get_nodes_in_group("projectiles").size() >= max_projectiles:
		_set_feedback("Demasiados hechizos en vuelo")
		return

	_cast(w)


## El control de energía, en un sitio, para que el mono y los hechizos
## cuesten exactamente lo mismo y no se separen a partir por caminos
## distintos. Pone el aviso en el HUD y devuelve si se puede pagar.
func _puede_pagar() -> bool:
	if not require_energy:
		return true
	if major_altar == null or not is_instance_valid(major_altar):
		_set_feedback("No hay Altar Mayor")
		return false
	if not major_altar.is_online():
		_set_feedback("Sin energía: dibuja un trazo largo en el aire")
		return false
	if major_altar.energia < cast_cost:
		_set_feedback("Energía insuficiente (%d)" % int(major_altar.energia))
		return false
	return true


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
## significa "se ha limpiado la ola".
##
## Dos magos que mueren en el mismo frame no se cuelan: el primero ve
## al otro todavía en el grupo y no avanza.
func register_mage_kill() -> void:
	if _finished:
		return
	if _giant_spawned:
		_finish(true)
		return
	if not get_tree().get_nodes_in_group("mages").is_empty():
		return

	var next := _wave_index + 1
	if next < waves.size():
		_wave_index = next
		# Un respiro entre olas. Sin él, matar dos magos seguidos y ver
		# aparecer dos más al instante convierte la partida en un muro.
		get_tree().create_timer(wave_break_seconds).timeout.connect(
			_spawn_wave.bind(next), CONNECT_ONE_SHOT
		)
		_set_feedback("Oleada %d de %d" % [next + 1, waves.size()])
	else:
		_spawn_giant()


## Instancia los magos de una ola. Las propiedades se fijan ANTES de
## añadir al árbol: wizard.gd decide su debilidad y se pinta con ella en
## su _ready(), así que si se llega tarde el mago sale con el material
## blanco original.
func _spawn_wave(index: int) -> void:
	if _finished or wizard_scene == null:
		return
	if index < 0 or index >= waves.size():
		_spawn_giant()
		return

	var elements: PackedStringArray = waves[index]
	for i in elements.size():
		var w: Node3D = wizard_scene.instantiate()
		w.weak_element = elements[i]
		w.max_health = wizard_max_health
		w.base_scale = Vector3.ONE * wizard_scale
		w.attack_projectile = enemy_projectile

		get_tree().current_scene.add_child(w)
		var point: Vector3 = wizard_spawn_points[i % wizard_spawn_points.size()]
		w.global_position = point
		# Y mira al jugador desde el sitio donde aparece, no antes.
		var cam := get_viewport().get_camera_3d()
		if cam != null and w.global_position.distance_to(cam.global_position) > 0.01:
			w.look_at(cam.global_position, Vector3.UP)

	_wave_index = index


func _spawn_giant() -> void:
	if _giant_spawned:
		return
	if giant_scene == null:
		push_error("[SpellSystem] falta giant_scene; no se puede invocar al jefe")
		_finish(true)
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

	# Estas propiedades se fijan ANTES de añadirlo al árbol: wizard.gd
	# decide su debilidad inicial y se pinta con ella dentro de
	# _ready(), así que arrives tarde y saldría con la del material
	# original en vez de la del jefe.
	giant.rotates_weakness = true
	giant.max_health = giant_max_health
	giant.death_cleanup_delay = giant_cleanup_delay
	giant.health = giant_max_health
	giant.shrinks_on_damage = true
	giant.base_scale = Vector3.ONE * giant_scale
	giant.scale = giant.base_scale
	# El jefe también dispara al libro, pero más despacio: es enorme y
	# su animación se lee peor de lejos que la de un mago normal.
	giant.attack_projectile = enemy_projectile
	giant.attack_interval = giant_attack_interval

	get_tree().current_scene.add_child(giant)
	giant.global_position = pos
	# El jefe mira al jugador, no al revés.
	if origin.distance_to(pos) > 0.01:
		giant.look_at(origin, Vector3.UP)

	_giant_spawned = true
	_set_feedback(".")


## El libro se quedó sin vida: derrota.
func _on_book_destroyed() -> void:
	_finish(false)


func _finish(victoria: bool) -> void:
	if _finished:
		return
	_finished = true
	last_result_victoria = victoria
	_set_feedback("¡Victoria!" if victoria else "El libro se ha deshecho")
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

	# El libro puede estar a la izquierda y fuera de la vista, así que su
	# vida también va en el HUD, no sólo en la etiqueta que lleva encima.
	if _book != null and is_instance_valid(_book) and not _finished:
		lines.append(_book_line())

	# El jefe puede estar detrás del jugador, así que su debilidad
	# se repite en el HUD además de estar en su etiqueta.
	if _giant_spawned and not _finished:
		var weak := _giant_weakness()
		if weak.is_empty():
			lines.append(".")
		else:
			lines.append(".")

	lines.append(_energy_line())

	if _feedback != "":
		lines.append(_feedback)

	return "\n".join(lines)


## Vida del libro, sólo en porcentaje. Antes llevaba ocho bloques de
## barra además del número, y en el visor ese texto tan largo se comía
## medio campo de visión.
func _book_line() -> String:
	var cur: int = _book.health
	var total: int = maxi(1, _book.max_health)
	if _book.health <= 0:
		return "LIBRO MAGICO DESTRUIDO"
	var pct := int(round(float(cur) / float(total) * 100.0))
	return "." % pct


func _giant_weakness() -> String:
	var giant := get_tree().get_first_node_in_group("giant")
	if giant == null:
		return ""
	return String(giant.weak_element)


## Energía del Altar Mayor, también sólo en porcentaje.
func _energy_line() -> String:
	if major_altar == null or not is_instance_valid(major_altar):
		return "Sin Altar Mayor"

	var fill: float = major_altar.get_fill()
	var pct := int(round(fill * 100.0))

	if not major_altar.is_online():
		return "Sin mana  %d%%" % pct
	return "Mana al:  %d%%" % pct


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
# Mono
# -----------------------------------------------------------------

## Aparece por delante del jugador, a ras de suelo, y a partir de ahí
## se encarga solo: Mono busca al mago más cercano, corre hacia él y
## explota. Aquí sólo se coloca y se cobra.
func _spawn_mono() -> void:
	if mono_mesh == null:
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	# Si ya hay demasiados, se va el más viejo. Ahora cada mono se
	# autodestruye al detonar, así que esto es sólo una red de seguridad.
	var vivos: Array[Node] = get_tree().get_nodes_in_group("monos")
	while vivos.size() >= mono_max_count:
		var oldest: Node = vivos.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	var forward: Vector3 = -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD

	var mono := Mono.new()
	mono.mesh = mono_mesh
	mono.damage = mono_damage

	get_tree().current_scene.add_child(mono)
	mono.global_position = cam.global_position + forward.normalized() * mono_spawn_distance
	mono.global_position.y = 0.0

	# Se cobra lo mismo que un hechizo: si no, "mono" sería un atajo
	# gratis para matar la partida sin decir un solo elemento.
	if major_altar != null and is_instance_valid(major_altar):
		major_altar.spend(cast_cost)
	_cooldown = cooldown_seconds
	_set_feedback("¡Mono!")
