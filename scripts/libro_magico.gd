extends Node3D
class_name LibroMagico

signal estado_cambiado(indice: int)
## Se emite una vez, cuando el libro se queda sin vida. SpellSystem lo
## conecta a la pantalla de derrota.
signal destruido

@export var modelos: Array[Node3D] = []
@export var auto_recolectar: bool = true

# Rutas opcionales. Si no existen, se usan fallbacks.
@export var ruta_contenedor_modelos: NodePath = ^"Modelos"

## Antes aquí había un Label3D con las reglas y el ciclo de debilidades
## ("FUEGO→AGUA · AGUA→RAYO…"). Era demasiado texto en el visor y tapaba
## la arena, así que se quitó del nodo. La etiqueta de vida
## (_build_health_label) sigue en pie: ésa sí se queda.

## El libro flota en el centro de la arena.
@export var float_height: float = 0.05
@export var float_speed: float = 1.1

@export_group("Vida")
## Puntos de vida. El libro es lo único que hay que proteger: si cae,
## derrota.
@export var max_health: int = 12
## Etiqueta flotante con la vida. El HUD también la muestra, pero el
## jugador puede estar mirando al libro y no a la etiqueta del centro.
@export var show_health_label: bool = true
## Contardo al recibir daño: el libro da un bote.
@export var hit_pulse: float = 0.14
## Por debajo de este porcentaje la etiqueta se pone en rojo.
@export var danger_ratio: float = 0.34
@export var health_label_height: float = 0.95

var estado_actual: int = 0
var health: int

var _abierto: bool = false
var _time: float = 0.0
var _base_y: float = 0.0
var _health_label: Label3D
## Segundos que le queda al efecto de golpe. Se cuenta hacia atrás.
var _pulse_left: float = 0.0


func _ready() -> void:
	if auto_recolectar and modelos.is_empty():
		_recolectar_modelos()

	if modelos.is_empty():
		push_error("[LibroMagico] No se encontró ningún modelo. Revisa la jerarquía de libroMagico.tscn.")
	else:
		print("[LibroMagico] Modelos detectados: ", modelos.size())

	for m in modelos:
		if is_instance_valid(m):
			m.visible = false

	_base_y = position.y
	health = max_health

	# Grupo por el que los magos lo encuentran para dispararle. Y
	# deliberadamente NO está en el grupo de los enemigos: los hechizos
	# del jugador sólo dañan a aquel.
	add_to_group("libro_magico")

	_build_health_label()

	# El libro ya no se esconde esperando a que el jugador lo abra. Antes
	# sólo aparecía al pellizcar con la mano izquierda, y eso no
	# funciona ya: es el blanco que los magos atacan y hay que verlo
	# desde el primer segundo para saber qué hay que proteger.
	visible = true
	if not modelos.is_empty():
		modelos[0].visible = true


func _process(delta: float) -> void:
	# Flotación suave. Se usa position (local), no global_position, para
	# que el libro siga a su padre si lo cuelgan de una mano.
	_time += delta
	position.y = _base_y + sin(_time * float_speed) * float_height

	# El bote del golpe se apaga solo.
	if _pulse_left > 0.0:
		_pulse_left = maxf(0.0, _pulse_left - delta)
		var k: float = _pulse_left / maxf(hit_pulse, 0.001)
		scale = Vector3.ONE * (1.0 + hit_pulse * k)
	elif scale != Vector3.ONE:
		scale = Vector3.ONE


func _recolectar_modelos() -> void:
	# 1) Intentar por la ruta configurada
	var contenedor: Node = null
	if ruta_contenedor_modelos != NodePath(""):
		contenedor = get_node_or_null(ruta_contenedor_modelos)

	# 2) Fallback: buscar un nodo llamado "Modelos" en cualquier hijo directo
	if contenedor == null:
		contenedor = find_child("Modelos", true, false)

	# 3) Fallback: buscar un nodo llamado "Ancla" y dentro de él un "Modelos"
	if contenedor == null:
		var ancla := find_child("Ancla", true, false)
		if ancla:
			contenedor = ancla.find_child("Modelos", true, false)

	# 4) Recolectar
	if contenedor != null:
		for hijo in contenedor.get_children():
			if hijo is Node3D:
				modelos.append(hijo)
	else:
		# 5) Último recurso: hijos directos de este nodo que sean Node3D
		#    excluyendo contenedores conocidos (Ancla, Modelos, audio, luces)
		for hijo in get_children():
			if hijo is Node3D and not _es_contenedor(hijo):
				modelos.append(hijo)

	if modelos.is_empty():
		push_warning("[LibroMagico] auto_recolectar activo pero no se encontraron hijos Node3D. Asigna los modelos manualmente en el inspector.")


func _es_contenedor(nodo: Node) -> bool:
	var n := String(nodo.name).to_lower()
	return n == "ancla" or n == "modelos" or n.begins_with("audio") or n.begins_with("luz") or n.begins_with("light") or n.begins_with("particul")


# ─────────────────────────────────────────────────────────────
#  Daño
# ─────────────────────────────────────────────────────────────

## Lo llaman los proyectiles enemigos.
##
## El segundo parámetro se acepta y se ignora a propósito: los hechizos
## del jugador pasan (daño, elemento), así que si alguno llegara aquí no
## debe reventar por número de argumentos. De hecho no llegan, porque
## los proyectiles del jugador sólo dañan al grupo de enemigos.
func take_damage(amount: int = 1, _element: String = "") -> void:
	if health <= 0:
		return
	# Misma guarda que en wizard.gd: durante un cambio de escena llegan
	# impactos de cuerpos que ya se están liberando.
	if is_queued_for_deletion() or not is_inside_tree():
		return

	health = maxi(0, health - amount)
	_pulse_left = hit_pulse
	_update_health_label()

	var director := get_tree().get_first_node_in_group("spell_system")
	if director != null and director.has_method("notify_book_damaged"):
		director.notify_book_damaged(health)

	if health == 0:
		visible = false
		if _health_label != null:
			_health_label.visible = false
		destruido.emit()


# ─────────────────────────────────────────────────────────────
#  API pública
# ─────────────────────────────────────────────────────────────
## Pellizcar con la mano izquierda abre y cierra las reglas. Ya no
## muestra texto (se quitó el Label3D del ciclo de debilidades); abrir
## y cerrar ya no hace nada visible, pero cerrar sí sigue pasando de
## página, que es lo que le da vida al libro.
func abrir() -> void:
	_abierto = true


func cerrar() -> void:
	if not _abierto:
		return
	_abierto = false
	# La página sigue pasando al cerrar: era lo que hacía el libro de
	# antes y da un poco de vida sin coste.
	if not modelos.is_empty():
		modelos[estado_actual].visible = false
		estado_actual = (estado_actual + 1) % modelos.size()
		modelos[estado_actual].visible = visible
		estado_cambiado.emit(estado_actual)


func reiniciar_estado() -> void:
	estado_actual = 0
	for i in modelos.size():
		var m: Node3D = modelos[i]
		if is_instance_valid(m):
			m.visible = i == 0 and visible


# ─────────────────────────────────────────────────────────────
#  Interfaz
# ─────────────────────────────────────────────────────────────

func _build_health_label() -> void:
	if not show_health_label:
		return
	_health_label = Label3D.new()
	_health_label.font_size = 56
	_health_label.outline_size = 16
	_health_label.outline_modulate = Color(0, 0, 0)
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Con depth: sólo hay una etiqueta de este tipo en escena, y respectar
	# la profundidad es lo correcto.
	_health_label.fixed_size = true
	_health_label.pixel_size = 0.0012
	_health_label.position = Vector3(0.0, health_label_height, 0.0)

	# Va bajo "Ancla" y no como hijo directo de la raíz: así el barrido
	# que busca la carpeta "Modelos" no lo confunde con un modelo más.
	var ancla := get_node_or_null("Ancla")
	var padre: Node = ancla if ancla != null else self
	_update_health_label()
	padre.add_child(_health_label)


func _update_health_label() -> void:
	if _health_label == null:
		return
	_health_label.text = "LIBRO  %d/%d" % [health, max_health]
	var bajo: bool = max_health > 0 and float(health) / float(max_health) <= danger_ratio
	_health_label.modulate = Color(1.0, 0.25, 0.2) if bajo else Color(0.75, 1.0, 0.8)
