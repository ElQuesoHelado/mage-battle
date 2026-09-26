extends RigidBody3D
class_name Bolt

@export var speed: float = 28.0
## Daño en puntos de vida. Ver wizard.gd:max_health para el balance.
@export var damage: int = 1
@export var lifetime_seconds: float = 1.5
@export var radius: float = 0.10

var exploded := false
var launch_direction := Vector3.FORWARD

var core: MeshInstance3D
var glow: MeshInstance3D
var light: OmniLight3D
var sparks: GPUParticles3D
var trail: GPUParticles3D


func _ready() -> void:
	gravity_scale = 0.0
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


func _physics_process(_delta: float) -> void:
	if exploded:
		return
	if linear_velocity.length_squared() > 0.01:
		look_at(global_position + linear_velocity.normalized(), Vector3.UP)


func launch(direction: Vector3) -> void:
	launch_direction = direction.normalized()
	linear_velocity = launch_direction * speed
	_configure_trail_direction()


# ============================================================
# VISUALS
# ============================================================

func _create_visuals() -> void:
	_create_core()
	_create_glow()
	_create_light()
	_create_sparks()
	_create_trail()


func _create_core() -> void:
	core = MeshInstance3D.new()
	# Cápsula alargada en la dirección del movimiento.
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = radius * 5.0
	capsule.radial_segments = 8
	capsule.rings = 3
	core.mesh = capsule

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 1.0, 0.85)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.95, 0.4)
	material.emission_energy_multiplier = 8.0
	core.material_override = material

	# Orientar la cápsula hacia adelante (-Z).
	core.rotation_degrees = Vector3(90, 0, 0)

	add_child(core)


func _create_glow() -> void:
	glow = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius * 2.2
	sphere.height = radius * 4.4
	sphere.radial_segments = 10
	sphere.rings = 5
	glow.mesh = sphere

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 1.0, 0.6, 0.25)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.9, 0.3)
	material.emission_energy_multiplier = 4.0
	glow.material_override = material

	add_child(glow)


func _create_light() -> void:
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.95, 0.6)
	light.light_energy = 2.5
	light.omni_range = 3.5
	light.shadow_enabled = false
	add_child(light)


func _create_sparks() -> void:
	sparks = GPUParticles3D.new()
	sparks.amount = 18
	sparks.lifetime = 0.25
	sparks.randomness = 0.7
	sparks.local_coords = true

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 1.2
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 3.5
	process.gravity = Vector3.ZERO
	process.scale_min = 0.15
	process.scale_max = 0.35
	process.color = Color(1.0, 1.0, 0.7)
	sparks.process_material = process

	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 0.8, 0.9)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.95, 0.4)
	material.emission_energy_multiplier = 6.0
	mesh.material = material

	sparks.draw_pass_1 = mesh
	add_child(sparks)


func _create_trail() -> void:
	trail = GPUParticles3D.new()
	trail.amount = 26
	trail.lifetime = 0.20
	trail.randomness = 0.3
	trail.local_coords = true

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	process.direction = -launch_direction
	process.spread = 15.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 5.0
	process.gravity = Vector3.ZERO
	process.scale_min = 0.12
	process.scale_max = 0.28
	process.color = Color(1.0, 1.0, 0.7)
	trail.process_material = process

	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 0.8, 0.8)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.95, 0.4)
	material.emission_energy_multiplier = 5.0
	mesh.material = material

	trail.draw_pass_1 = mesh
	add_child(trail)


func _configure_trail_direction() -> void:
	if trail == null:
		return
	var process := trail.process_material as ParticleProcessMaterial
	if process:
		process.direction = -launch_direction


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
	await get_tree().create_timer(0.06).timeout
	queue_free()


func _create_impact_effect() -> void:
	var impact_particles := GPUParticles3D.new()
	impact_particles.amount = 22
	impact_particles.lifetime = 0.3
	impact_particles.one_shot = true

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 5.5
	process.gravity = Vector3(0.0, -5.0, 0.0)
	process.scale_min = 0.15
	process.scale_max = 0.4
	process.color = Color(1.0, 1.0, 0.7)
	impact_particles.process_material = process

	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 6
	mesh.rings = 3

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.95, 0.4)
	material.emission_energy_multiplier = 6.0
	mesh.material = material

	impact_particles.draw_pass_1 = mesh
	get_parent().add_child(impact_particles)
	impact_particles.global_position = global_position
	impact_particles.finished.connect(impact_particles.queue_free)
	impact_particles.emitting = true

	# Flash blanco (más fuerte y corto que fuego).
	var impact_light := OmniLight3D.new()
	impact_light.light_color = Color(1.0, 1.0, 0.8)
	impact_light.light_energy = 7.0
	impact_light.omni_range = 4.0
	impact_light.shadow_enabled = false
	get_parent().add_child(impact_light)
	impact_light.global_position = global_position
	get_tree().create_timer(0.06).timeout.connect(impact_light.queue_free)
