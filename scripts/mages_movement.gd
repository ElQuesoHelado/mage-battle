extends Node3D

signal died  # se emite cuando el mago muere

@export var max_health: int = 3
var health: int

func _ready() -> void:
	health = max_health

func take_damage(amount: int = 1) -> void:
	health -= amount
	print(name, " vida: ", health)

	# Feedback visual rápido (parpadeo rojo)
	_flash()

	if health <= 0:
		died.emit()      # avisa antes de desaparecer
		queue_free()     # elimina el mago de la escena

func _flash() -> void:
	# Opcional: parpadea el mesh para que se note el golpe
	for child in get_children():
		if child is MeshInstance3D:
			var mat: Material = child.get_active_material(0)			
			if mat is StandardMaterial3D:
				var m: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
				child.material_override = m
				m.albedo_color = Color(1, 0.2, 0.2)
				await get_tree().create_timer(0.15).timeout
				if is_instance_valid(child):
					child.material_override = null
