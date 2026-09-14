extends Node3D
class_name SpellCaster

@export var wand_drawing: WandDrawing
@export var wand_tip: Node3D

@export_group("Hechizos")
@export var fireball_scene: PackedScene
@export var water_jet_scene: PackedScene

@export_group("Ajustes de disparo")
@export var forward_offset: float = 0.1
@export var cooldown_seconds: float = 0.4

var _cooldown_timer: float = 0.0


func _ready() -> void:
	if wand_drawing:
		wand_drawing.shape_recognized.connect(_on_shape_recognized)
	else:
		push_warning("SpellCaster: falta asignar wand_drawing en el inspector")


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func _on_shape_recognized(shape_name: String, _points: Array) -> void:
	print("[SpellCaster] figura recibida: ", shape_name)

	if _cooldown_timer > 0.0:
		return

	match shape_name:
		"circle":
			_cast_projectile(fireball_scene, "fireball")
		"triangle":
			_cast_projectile(water_jet_scene, "water_jet")
		"square":
			pass  # TODO: hechizo de tierra
		_:
			pass


## Dispara un proyectil genérico. Sirve tanto para la bola de fuego como
## para el chorro de agua, porque ambos tienen `launch(direction)`.
func _cast_projectile(scene: PackedScene, label: String) -> void:
	if not scene:
		push_error("SpellCaster: falta asignar la escena '%s' en el inspector" % label)
		return
	if not wand_tip:
		push_error("SpellCaster: asigna wand_tip en el inspector")
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

	print("[SpellCaster] disparando ", label, ": origin=", origin, " forward=", forward)

	projectile.global_position = origin + forward * forward_offset
	projectile.launch(forward)

	_cooldown_timer = cooldown_seconds
