extends RigidBody3D
class_name Rock

@export var speed: float = 10.0
## Daño en puntos de vida. La roca es el hechizo más lento pero el
## único que reparte 2 puntos, así que mata en la mitad de golpes.
@export var damage: int = 2
@export var lifetime_seconds: float = 6.0
@export var radius: float = 0.22

var exploded := false
var launch_direction := Vector3.FORWARD

var core: MeshInstance3D
var debris: GPUParticles3D


func _ready() -> void:
	# A diferencia de fuego/agua/rayo, la roca SÍ cae.
	gravity_scale = 1.8
	mass = 4.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4

	_create_visuals()

	if not _has_child_of_type(CollisionShape3D):
		_add_placeholder_collision()

	body_entered.connect(_on_body_entered)

	get_tree().create_timer(lifetime_seconds).timeout.connect(
		_on_lifetime_expired
	)


func launch(direction: Vector3) -> void:
	launch_direction = direction.normalized()
	linear_velocity = launch_direction * speed
	# Pequeña componente hacia arriba para que describa un arco.
	linear_velocity.y += 1.5


# ============================================================
# VISUALS
# ============================================================

func _create_visuals() -> void:
	_create_core()
	_create_debris()


func _create_core() -> void:
	core = MeshInstance3D.new()

	# Icosaedro irregular: se ve "rocoso" sin necesidad de un mesh custom.
	var ico := SphereMesh.new()
	ico.radius = radius
	ico.height = radius * 2.0
	ico.radial_segments = 4      # deliberadamente bajo, da facetas
	ico.rings = 3
	core.mesh = ico

	# Lo deformamos un poco para que no sea esférico perfecto.
	core.scale = Vector3(1.0, 0.85, 1.15)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.albedo_color = Color(0.35, 0.28, 0.22)
	material.roughness = 1.0
	material.metallic = 0.0
	core.material_override = material

	add_child(core)


func _create_debris() -> void:
	debris = GPUParticles3D.new()
	debris.amount = 8
	debris.lifetime = 0.6
	debris.randomness = 0.6
	debris.local_coords = true
	debris.emitting = true

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 1.1
	process.direction = Vector3.DOWN
	process.spread = 60.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.6
	process.gravity = Vector3(0.0, -4.0, 0.0)
	process.scale_min = 0.3
	process.scale_max = 0.7
	process.color = Color(0.4, 0.32, 0.25, 0.7)
	debris.process_material = process

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, 0.05)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.albedo_color = Color(0.32, 0.26, 0.20)
	mesh.material = material

	debris.draw_pass_1 = mesh
	add_child(debris)


# ============================================================
# COLLISION
# ============================================================

func _add_placeholder_collision() -> void:
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = radius
	shape.shape = sphere_shape
	add_child(shape)


func _has_child_of_type(t) -> bool:
	for c in get_children():
		if is_instance_of(c, t):
			return true
	return false


# ============================================================
# IMPACT
# ============================================================

func _on_body_entered(body: Node) -> void:
	if exploded:
		return
	if body == self:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_explode()


func _on_lifetime_expired() -> void:
	if exploded:
		return
	_explode()


func _explode() -> void:
	if exploded:
		return
	exploded = true
	linear_velocity = Vector3.ZERO
	freeze = true
	_create_impact_effect()
	await get_tree().create_timer(0.12).timeout
	queue_free()


func _create_impact_effect() -> void:
	var impact := GPUParticles3D.new()
	impact.amount = 30
	impact.lifetime = 0.7
	impact.one_shot = true

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.6
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 2.5
	process.initial_velocity_max = 5.0
	process.gravity = Vector3(0.0, -6.0, 0.0)
	process.scale_min = 0.3
	process.scale_max = 0.8
	process.color = Color(0.4, 0.32, 0.24)
	impact.process_material = process

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 0.07, 0.07)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.albedo_color = Color(0.35, 0.28, 0.20)
	mesh.material = material

	impact.draw_pass_1 = mesh
	get_parent().add_child(impact)
	impact.global_position = global_position
	impact.finished.connect(impact.queue_free)
	impact.emitting = true

	# Nube de polvo (esfera translúcida que se expande y desvanece).
	var dust := MeshInstance3D.new()
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = radius * 2.5
	dust_mesh.height = radius * 5.0
	dust_mesh.radial_segments = 8
	dust_mesh.rings = 4
	dust.mesh = dust_mesh

	var dust_mat := StandardMaterial3D.new()
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.albedo_color = Color(0.5, 0.42, 0.32, 0.5)
	dust.material_override = dust_mat

	get_parent().add_child(dust)
	dust.global_position = global_position

	var tween := dust.create_tween()
	tween.set_parallel(true)
	tween.tween_property(dust, "scale", Vector3(2.5, 2.5, 2.5), 0.5)
	tween.tween_property(dust_mat, "albedo_color:a", 0.0, 0.5)
	tween.chain().tween_callback(dust.queue_free)
