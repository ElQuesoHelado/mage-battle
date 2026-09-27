extends Node3D
class_name ProyectilloEnemigo

## Proyectil que lanzan los magos al libro mágico.
##
## Es un Node3D que se mueve a mano, no un RigidBody3D. Con físicas
## tendría que esperar al impacto con la máscara de colisión, y un
## proyectil enemigo colisionando con los magos los rebotaría de lado:
## los magos se interponen entre el tirador y el libro. Midiendo la
## distancia al libro no hay rebotes, no hay máscaras que configurar y
## el impacto es determinista.

@export var speed: float = 7.0
## Puntos de daño al libro. Ver libro_magico.gd:max_health.
@export var damage: int = 1
## Si no llega a tocar el libro en este tiempo, se desvanece.
@export var lifetime_seconds: float = 6.0
## A esta distancia del centro del libro impacta.
@export var hit_radius: float = 0.35
## Grupo al que puede hacer daño. Deliberadamente NO es el mismo grupo
## que el de los hechizos del jugador: así los proyectiles enemigos no
## pueden herir a los magos, ni aunque uno se cruce delante.
@export var target_group: String = "libro_magico"
## Altura sobre la que nace, para salir de las manos y no de los pies.
@export var spawn_height: float = 1.45
@export var color: Color = Color(0.85, 0.25, 0.95)

var _target: Node3D
var _time: float = 0.0
var _spent: bool = false


func _ready() -> void:
	add_to_group("proyectillos_enemigos")
	_target = get_tree().get_first_node_in_group(target_group)


## Lo llama wizard.gd al aparecer la animación de hechizo.
func launch(from: Vector3, target: Node3D) -> void:
	global_position = from
	_target = target
	# Se orienta hacia el libro en el primer frame, que es cuando
	# importan: el meta, no la dirección de salida.
	_face()


func _process(delta: float) -> void:
	if _spent:
		return

	_time += delta
	if _time >= lifetime_seconds:
		queue_free()
		return

	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(target_group)
		if _target == null:
			queue_free()
			return

	var to_target: Vector3 = _target.global_position - global_position
	if to_target.length() <= hit_radius:
		_hit()
		return

	if to_target.length_squared() > 0.0001:
		global_position += to_target.normalized() * speed * delta
		_face()


func _face() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var d: Vector3 = _target.global_position - global_position
	if d.length_squared() > 0.0001:
		look_at(global_position + d, Vector3.UP)


func _hit() -> void:
	_spent = true
	if _target != null and is_instance_valid(_target) \
			and _target.has_method("take_damage"):
		_target.take_damage(damage)
	queue_free()
