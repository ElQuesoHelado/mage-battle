extends RigidBody3D
class_name Fireball

@export var speed: float = 12.0
@export var damage: float = 25.0
@export var lifetime_seconds: float = 5.0
@export var radius: float = 0.20

var exploded := false
var launch_direction := Vector3.FORWARD

var core: MeshInstance3D
var glow: MeshInstance3D
var light: OmniLight3D
var particles: GPUParticles3D
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

	# Mantiene la bola orientada hacia su movimiento.
	if linear_velocity.length_squared() > 0.01:
		look_at(global_position + linear_velocity.normalized(), Vector3.UP)


func launch(direction: Vector3) -> void:
	launch_direction = direction.normalized()
	linear_velocity = launch_direction * speed

	_configure_trail_direction()


func _create_visuals() -> void:
	_create_core()
	_create_glow()
	_create_light()
	_create_fire_particles()
	_create_trail()



# ============================================================
# CORE
# ============================================================

func _create_core() -> void:
	core = MeshInstance3D.new()

	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0

	# Menos geometría = mejor para Quest 2.
	sphere.radial_segments = 12
	sphere.rings = 6

	core.mesh = sphere

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	material.albedo_color = Color(1.0, 0.85, 0.25)

	material.emission_enabled = true
	material.emission = Color(1.0, 0.35, 0.03)
	material.emission_energy_multiplier = 5.0

	core.material_override = material

	add_child(core)


# ============================================================
# OUTER GLOW
# ============================================================

func _create_glow() -> void:
	glow = MeshInstance3D.new()

	var sphere := SphereMesh.new()
	sphere.radius = radius * 3.6
	sphere.height = radius * 5.6

	sphere.radial_segments = 12
	sphere.rings = 6

	glow.mesh = sphere

	var material := StandardMaterial3D.new()

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	material.albedo_color = Color(1.0, 0.25, 0.02, 0.20)

	material.emission_enabled = true
	material.emission = Color(1.0, 0.15, 0.01)
	material.emission_energy_multiplier = 3.0

	glow.material_override = material

	add_child(glow)


# ============================================================
# LIGHT
# ============================================================

func _create_light() -> void:
	light = OmniLight3D.new()

	light.light_color = Color(1.0, 0.35, 0.08)
	light.light_energy = 1.5
	light.omni_range = 2.5

	# Importante para Quest 2.
	light.shadow_enabled = false

	add_child(light)


# ============================================================
# FIRE PARTICLES
# ============================================================

func _create_fire_particles() -> void:
	particles = GPUParticles3D.new()

	particles.amount = 24
	particles.lifetime = 0.35
	particles.randomness = 0.45

	particles.local_coords = true

	var process := ParticleProcessMaterial.new()

	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.7

	process.direction = Vector3.UP
	process.spread = 180.0

	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.0

	process.gravity = Vector3.ZERO

	process.scale_min = 0.25
	process.scale_max = 0.65

	process.color = Color(1.0, 0.35, 0.03)

	particles.process_material = process

	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.055
	particle_mesh.height = 0.11

	particle_mesh.radial_segments = 6
	particle_mesh.rings = 3

	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	material.albedo_color = Color(1.0, 0.45, 0.05, 0.85)

	material.emission_enabled = true
	material.emission = Color(1.0, 0.2, 0.01)
	material.emission_energy_multiplier = 4.0

	particle_mesh.material = material

	particles.draw_pass_1 = particle_mesh

	add_child(particles)


# ============================================================
# TRAIL
# ============================================================

func _create_trail() -> void:
	trail = GPUParticles3D.new()

	trail.amount = 18
	trail.lifetime = 0.30
	trail.randomness = 0.25

	trail.local_coords = true

	var process := ParticleProcessMaterial.new()

	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT

	process.direction = -launch_direction
	process.spread = 12.0

	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 3.0

	process.gravity = Vector3.ZERO

	process.scale_min = 0.20
	process.scale_max = 0.45

	process.color = Color(1.0, 0.20, 0.01)

	trail.process_material = process

	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.045
	particle_mesh.height = 0.09

	particle_mesh.radial_segments = 6
	particle_mesh.rings = 3

	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	material.albedo_color = Color(1.0, 0.25, 0.02, 0.7)

	material.emission_enabled = true
	material.emission = Color(1.0, 0.15, 0.01)
	material.emission_energy_multiplier = 3.0

	particle_mesh.material = material

	trail.draw_pass_1 = particle_mesh

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
		queue_free()
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

	# Pequeña demora para que el efecto sea visible.
	await get_tree().create_timer(0.08).timeout

	queue_free()


# ============================================================
# IMPACT EFFECT
# ============================================================

func _create_impact_effect() -> void:
	var impact_particles := GPUParticles3D.new()

	impact_particles.amount = 20
	impact_particles.lifetime = 0.35
	impact_particles.one_shot = true

	var process := ParticleProcessMaterial.new()

	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius

	process.direction = Vector3.UP
	process.spread = 180.0

	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 4.0

	process.gravity = Vector3(0.0, -3.0, 0.0)

	process.scale_min = 0.2
	process.scale_max = 0.6

	process.color = Color(1.0, 0.3, 0.02)

	impact_particles.process_material = process

	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.10

	mesh.radial_segments = 6
	mesh.rings = 3

	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	material.emission_enabled = true
	material.emission = Color(1.0, 0.2, 0.01)
	material.emission_energy_multiplier = 4.0

	mesh.material = material

	impact_particles.draw_pass_1 = mesh

	get_parent().add_child(impact_particles)

	impact_particles.global_position = global_position

	impact_particles.finished.connect(
		impact_particles.queue_free
	)

	impact_particles.emitting = true

	# Flash de luz en el impacto.
	var impact_light := OmniLight3D.new()

	impact_light.light_color = Color(1.0, 0.35, 0.05)
	impact_light.light_energy = 5.0
	impact_light.omni_range = 3.0
	impact_light.shadow_enabled = false

	get_parent().add_child(impact_light)

	impact_light.global_position = global_position

	get_tree().create_timer(0.08).timeout.connect(
		impact_light.queue_free
	)
