extends RigidBody3D
class_name WaterJet


@export var speed: float = 16.0
## Daño en puntos de vida. Ver wizard.gd:max_health para el balance.
@export var damage: int = 1
@export var lifetime_seconds: float = 2.5
@export var radius: float = 0.15

var exploded: bool = false
var launch_direction: Vector3 = Vector3.FORWARD

var body_mesh: MeshInstance3D
var head_mesh: MeshInstance3D
var foam_mesh: MeshInstance3D

var droplets: GPUParticles3D
var spray: GPUParticles3D


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
		look_at(
			global_position + linear_velocity.normalized(),
			Vector3.UP
		)


func launch(direction: Vector3) -> void:
	launch_direction = direction.normalized()
	linear_velocity = launch_direction * speed

	_configure_particle_direction()


# ============================================================
# VISUALS
# ============================================================

func _create_visuals() -> void:
	_create_water_body()
	_create_water_head()
	_create_foam()
	_create_droplets()
	_create_spray()


# ============================================================
# MAIN WATER BODY
# ============================================================

func _create_water_body() -> void:
	body_mesh = MeshInstance3D.new()

	var cylinder := CylinderMesh.new()

	# El cilindro será el cuerpo del chorro.
	cylinder.top_radius = radius * 0.55
	cylinder.bottom_radius = radius * 0.95
	cylinder.height = radius * 5.5

	cylinder.radial_segments = 10
	cylinder.rings = 3

	body_mesh.mesh = cylinder

	# CylinderMesh apunta en Y.
	# Lo ponemos en el eje de lanzamiento.
	body_mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)

	var material := _create_water_material(
		Color(0.55, 0.88, 1.0, 0.82)
	)

	body_mesh.material_override = material

	add_child(body_mesh)


# ============================================================
# WATER HEAD
# ============================================================

func _create_water_head() -> void:
	head_mesh = MeshInstance3D.new()

	var sphere := SphereMesh.new()

	# La cabeza es más ancha que el cuerpo.
	sphere.radius = radius * 1.35
	sphere.height = radius * 2.2

	sphere.radial_segments = 10
	sphere.rings = 5

	head_mesh.mesh = sphere

	# La ponemos delante del cuerpo.
	head_mesh.position = Vector3(
		0.0,
		0.0,
		-radius * 2.25
	)

	# La deformamos para que no parezca una esfera.
	head_mesh.scale = Vector3(
		1.15,
		1.0,
		0.65
	)

	var material := _create_water_material(
		Color(0.68, 0.94, 1.0, 0.88)
	)

	head_mesh.material_override = material

	add_child(head_mesh)


# ============================================================
# FOAM / WHITE WATER
# ============================================================

func _create_foam() -> void:
	foam_mesh = MeshInstance3D.new()

	var sphere := SphereMesh.new()

	sphere.radius = radius * 0.75
	sphere.height = radius * 1.2

	sphere.radial_segments = 7
	sphere.rings = 3

	foam_mesh.mesh = sphere

	# Varias pequeñas deformaciones visuales.
	foam_mesh.position = Vector3(
		radius * 0.35,
		radius * 0.35,
		-radius * 2.8
	)

	foam_mesh.scale = Vector3(
		1.4,
		0.65,
		0.8
	)

	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	material.albedo_color = Color(
		0.82,
		0.97,
		1.0,
		0.75
	)

	material.emission_enabled = true
	material.emission = Color(
		0.25,
		0.65,
		0.9
	)

	material.emission_energy_multiplier = 0.7

	foam_mesh.material_override = material

	add_child(foam_mesh)


# ============================================================
# DROPLETS
# ============================================================

func _create_droplets() -> void:
	droplets = GPUParticles3D.new()

	droplets.amount = 26
	droplets.lifetime = 0.45
	droplets.randomness = 0.65
	droplets.local_coords = true

	var process := ParticleProcessMaterial.new()

	process.emission_shape = (
		ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	)

	process.emission_sphere_radius = radius * 1.15

	process.direction = Vector3.FORWARD

	process.spread = 75.0

	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.4

	process.gravity = Vector3.ZERO

	process.scale_min = 0.10
	process.scale_max = 0.42

	process.color = Color(
		0.65,
		0.91,
		1.0,
		0.72
	)

	droplets.process_material = process

	var mesh := SphereMesh.new()

	mesh.radius = radius * 0.16
	mesh.height = radius * 0.45

	mesh.radial_segments = 5
	mesh.rings = 2

	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	material.albedo_color = Color(
		0.72,
		0.94,
		1.0,
		0.7
	)

	mesh.material = material

	droplets.draw_pass_1 = mesh

	add_child(droplets)


# ============================================================
# BACK SPRAY
# ============================================================

func _create_spray() -> void:
	spray = GPUParticles3D.new()

	spray.amount = 18
	spray.lifetime = 0.35
	spray.randomness = 0.45
	spray.local_coords = true

	var process := ParticleProcessMaterial.new()

	process.emission_shape = (
		ParticleProcessMaterial.EMISSION_SHAPE_POINT
	)

	process.direction = Vector3.BACK

	process.spread = 18.0

	process.initial_velocity_min = 0.7
	process.initial_velocity_max = 2.2

	process.gravity = Vector3.ZERO

	process.scale_min = 0.08
	process.scale_max = 0.28

	process.color = Color(
		0.55,
		0.86,
		1.0,
		0.55
	)

	spray.process_material = process

	var mesh := SphereMesh.new()

	mesh.radius = radius * 0.13
	mesh.height = radius * 0.40

	mesh.radial_segments = 5
	mesh.rings = 2

	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	material.albedo_color = Color(
		0.6,
		0.9,
		1.0,
		0.55
	)

	mesh.material = material

	spray.draw_pass_1 = mesh

	add_child(spray)


# ============================================================
# MATERIAL
# ============================================================

func _create_water_material(
	color: Color
) -> StandardMaterial3D:

	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	material.albedo_color = color

	# Muy poca emisión.
	# Queremos agua, no plasma.
	material.emission_enabled = true

	material.emission = Color(
		0.12,
		0.4,
		0.65
	)

	material.emission_energy_multiplier = 0.55

	return material


# ============================================================
# PARTICLE DIRECTION
# ============================================================

func _configure_particle_direction() -> void:
	if droplets != null:
		var droplet_process := (
			droplets.process_material
			as ParticleProcessMaterial
		)

		if droplet_process:
			droplet_process.direction = launch_direction

	if spray != null:
		var spray_process := (
			spray.process_material
			as ParticleProcessMaterial
		)

		if spray_process:
			spray_process.direction = -launch_direction


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
	for child: Node in get_children():

		if is_instance_of(child, t):
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

	_create_water_splash()

	await get_tree().create_timer(0.10).timeout

	queue_free()


# ============================================================
# WATER SPLASH
# ============================================================

func _create_water_splash() -> void:

	var splash := GPUParticles3D.new()

	splash.amount = 38
	splash.lifetime = 0.55
	splash.one_shot = true
	splash.explosiveness = 0.9

	var process := ParticleProcessMaterial.new()

	process.emission_shape = (
		ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	)

	process.emission_sphere_radius = radius * 0.8

	process.direction = Vector3.UP

	process.spread = 180.0

	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 5.0

	process.gravity = Vector3(
		0.0,
		-5.0,
		0.0
	)

	process.scale_min = 0.12
	process.scale_max = 0.5

	process.color = Color(
		0.6,
		0.9,
		1.0,
		0.78
	)

	splash.process_material = process

	var mesh := SphereMesh.new()

	mesh.radius = radius * 0.18
	mesh.height = radius * 0.5

	mesh.radial_segments = 5
	mesh.rings = 2

	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	material.albedo_color = Color(
		0.7,
		0.94,
		1.0,
		0.8
	)

	mesh.material = material

	splash.draw_pass_1 = mesh

	get_parent().add_child(splash)

	splash.global_position = global_position

	splash.finished.connect(
		splash.queue_free
	)

	splash.emitting = true
