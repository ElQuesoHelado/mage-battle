extends Node3D
class_name WaterJet

## Chorro de agua: un nodo que avanza en la dirección de disparo mientras
## emite partículas hacia adelante. Lleva un Area3D consigo para hacer daño
## a lo que toque durante su recorrido.

@export var lifetime_seconds: float = 1.5
@export var speed: float = 10.0
@export var damage_per_hit: float = 8.0
@export var particle_amount: int = 80
@export var particle_lifetime: float = 0.6
@export var particle_radius: float = 0.015
@export var area_radius: float = 0.18
@export var spread_deg: float = 6.0
@export var gravity_strength: float = -2.0

var _age: float = 0.0
var _direction: Vector3 = Vector3.FORWARD
var _particles: GPUParticles3D
var _area: Area3D


func _ready() -> void:
	_build_particles()
	_build_area()


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = particle_amount
	_particles.lifetime = particle_lifetime
	_particles.one_shot = false
	_particles.explosiveness = 0.9
	_particles.local_coords = false

	# Mesh de cada gota
	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = particle_radius
	drop_mesh.height = particle_radius * 2.0
	_particles.draw_pass_1 = drop_mesh

	# Material de la gota
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.85)
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.emission_enabled = true
	drop_mat.emission = Color(0.1, 0.5, 1.0)
	drop_mat.emission_energy_multiplier = 1.5
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_particles.material_override = drop_mat

	# Material de proceso: cómo se mueven las partículas
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 0, -1)
	process.spread = spread_deg
	process.initial_velocity_min = speed * 0.8
	process.initial_velocity_max = speed * 1.2
	process.gravity = Vector3(0, gravity_strength, 0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	# Que mueran al cabo de un tiempo (el propio lifetime del nodo ya lo hace)
	process.color = Color(1, 1, 1, 1)
	_particles.process_material = process

	add_child(_particles)
	_particles.emitting = true


func _build_area() -> void:
	_area = Area3D.new()
	var area_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = area_radius
	area_shape.shape = sphere
	_area.add_child(area_shape)
	_area.monitoring = true
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)


## Orienta el chorro y lo lanza. El nodo avanzará solo en cada frame.
func launch(direction: Vector3) -> void:
	_direction = direction.normalized()
	# Rotamos el nodo para que su -Z local coincida con la dirección de
	# disparo. Las partículas salen hacia -Z por convención.
	var up_ref := Vector3.UP
	if abs(_direction.dot(up_ref)) > 0.99:
		up_ref = Vector3.RIGHT
	var right := up_ref.cross(_direction).normalized()
	var up := _direction.cross(right).normalized()
	global_transform.basis = Basis(right, up, -_direction)


func _process(delta: float) -> void:
	_age += delta
	global_position += _direction * speed * delta
	if _age >= lifetime_seconds:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body == self:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage_per_hit)
