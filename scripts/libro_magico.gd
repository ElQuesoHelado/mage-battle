extends Node3D
class_name LibroMagico

signal estado_cambiado(indice: int)

@export var modelos: Array[Node3D] = []
@export var auto_recolectar: bool = true

# Rutas opcionales. Si no existen, se usan fallbacks.
@export var ruta_contenedor_modelos: NodePath = ^"Modelos"

## Texto que resume las reglas. Se muestra junto con el libro al
## abrirlo, para que el jugador no tenga que memorizar el ciclo.
@export var texto_reglas: Label3D

## El libro flota en el centro de la arena.
@export var float_height: float = 0.05
@export var float_speed: float = 1.1

var estado_actual: int = 0
var _abierto: bool = false
var _time: float = 0.0
var _base_y: float = 0.0


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

	if texto_reglas != null:
		texto_reglas.text = SpellSystem.RULE_TEXT + "\n" + SpellSystem.ENERGY_TEXT
		texto_reglas.visible = false

	_base_y = position.y
	visible = false


func _process(delta: float) -> void:
	# Flotación suave. Se usa position (local), no global_position, para
	# que el libro siga a su padre si lo cuelgan de una mano.
	_time += delta
	position.y = _base_y + sin(_time * float_speed) * float_height


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
#  API pública
# ─────────────────────────────────────────────────────────────
func abrir() -> void:
	if _abierto:
		return
	_abierto = true
	visible = true
	if not modelos.is_empty():
		modelos[estado_actual].visible = true
	if texto_reglas != null:
		texto_reglas.visible = true


func cerrar() -> void:
	if not _abierto:
		return
	_abierto = false
	if not modelos.is_empty():
		modelos[estado_actual].visible = false
		estado_actual = (estado_actual + 1) % modelos.size()
		estado_cambiado.emit(estado_actual)
	if texto_reglas != null:
		texto_reglas.visible = false
	visible = false


func reiniciar_estado() -> void:
	estado_actual = 0
