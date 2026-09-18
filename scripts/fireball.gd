extends RigidBody3D
class_name Fireball

@export var speed: float = 6.0
@export var damage: float = 25.0
@export var lifetime_seconds: float = 10.0
@export var radius: float = 0.12


func _ready() -> void:
	gravity_scale = 0.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4

	if not _has_child_of_type(MeshInstance3D):
		_add_placeholder_mesh()
	if not _has_child_of_type(CollisionShape3D):
		_add_placeholder_collision()

	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime_seconds).timeout.connect(_on_lifetime_expired)


func launch(direction: Vector3) -> void:
	linear_velocity = direction.normalized() * speed


func _has_child_of_type(t) -> bool:
	for c in get_children():
		if is_instance_of(c, t):
			return true
	return false


func _add_placeholder_mesh() -> void:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh_instance.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.05)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.05)
	mat.emission_energy_multiplier = 3.0
	mesh_instance.material_override = mat
	add_child(mesh_instance)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.1)
	light.omni_range = 2.0
	light.light_energy = 2.0
	add_child(light)


func _add_placeholder_collision() -> void:
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = radius
	shape.shape = sphere_shape
	add_child(shape)


func _on_body_entered(body: Node) -> void:
	if body == self:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_explode()


func _on_lifetime_expired() -> void:
	_explode()


func _explode() -> void:
	queue_free()
