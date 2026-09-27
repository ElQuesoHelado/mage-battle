extends Node3D
class_name Mono

## El mono es un chiste con daño. Antes era un StaticBody3D con colisión
## trimesh que se quedaba clavado en el suelo estorbando (y que había
## que podar a mano). Ahora es un Node3D pelado que se acerca al mago más
## cercano, explota y se autodestruye.
##
## Sin colisionador a propósito: no necesita estampar contra nada, sólo
## medir distancias. Eso además elimina un create_trimesh_shape() por
## cada mono, que era lo caro de esta función.

## Malla del orangután. La pone SpellSystem al instanciarlo.
@export var mesh: Mesh

## A qué velocidad se acerca al objetivo.
@export var speed: float = 3.6
## A esta distancia explota. Medida en horizontal, para que llegue al
## cuerpo y no a los pies.
@export var detonate_range: float = 0.6
## Se autodestruye aunque no encuentre a nadie. Sin esto un mono
## invocado al final de la partida se quedaría ahí para siempre.
@export var lifetime_seconds: float = 8.0
## Puntos de daño. Ver wizard.gd:max_health para el balance.
@export var damage: int = 1
## Grupo al que persigue.
@export var target_group: String = "mages"
## Altura sobre la que corre, para no ir pegado al suelo.
@export var run_height: float = 0.45
## Cuánto sube y baja al correr. Da el paso del bicho sin usar una
## animación.
@export var hop_height: float = 0.12
@export var hop_speed: float = 9.0
## Segundos que dura el pallaso de la explosión antes de desaparecer.
@export var death_delay: float = 0.35

var _target: Node3D
var _time: float = 0.0
var _spent: bool = false
## Altura sobre la que corre. Se fija en _ready().
var _base_y: float = 0.0


func _ready() -> void:
	add_to_group("monos")

	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _material()
		add_child(mi)

	# La altura de la que sale el salto. Se toma aquí y no en cada frame,
	# porque SpellSystem coloca el mono justo después de instanciarlo y a
	# ras de suelo.
	_base_y = global_position.y + run_height

	_target = _nearest_target()
	# Sin objetivo no se va a ningún sitio, pero tampoco desaparece de
	# golpe: da un par de segundos de grace por si el mago entra después
	# en el radio. El timeout de vida es la red de seguridad real.
	if _target == null:
		lifetime_seconds = minf(lifetime_seconds, 2.5)


func _process(delta: float) -> void:
	if _spent:
		return

	_time += delta
	if _time >= lifetime_seconds:
		_pop(false)
		return

	# El objetivo puede morir mientras corremos hacia él.
	if _target == null or not is_instance_valid(_target):
		_target = _nearest_target()
		if _target == null:
			return

	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	var flat_dist: float = to_target.length()

	if flat_dist <= detonate_range:
		_pop(true)
		return

	if flat_dist > 0.01:
		global_position += to_target / flat_dist * speed * delta

	# Salta y mira a por dónde va.
	global_position.y = _base_y + absf(sin(_time * hop_speed)) * hop_height
	if to_target.length_squared() > 0.0001:
		look_at(global_position + to_target, Vector3.UP)


## Detonación. `con_objetivo` decide si hace daño: si el mono se quedó
## sin objetivo a medio camino, estalla al aire y no hace nada.
func _pop(con_objetivo: bool) -> void:
	if _spent:
		return
	_spent = true

	if con_objetivo and _target != null and is_instance_valid(_target) \
			and _target.has_method("take_damage"):
		# No le importan los elementos: se le pasa al objetivo su propia
		# debilidad, así que el impacto siempre coincide. Funciona igual
		# con el jefe, que va rotando, sin tocar wizard.gd.
		_target.take_damage(damage, String(_target.weak_element))

	_spawn_pop()

	get_tree().create_timer(death_delay).timeout.connect(
		queue_free, CONNECT_ONE_SHOT
	)


## Chispas al detonar. Un solo sistema de partículas, sin luz: los
## materiales de los hechizos son UNSHADED y una OmniLight3D no los
## iluminaría, sólo encarecería la escena.
func _spawn_pop() -> void:
	var puffs := GPUParticles3D.new()
	puffs.amount = 14
	puffs.lifetime = 0.4
	puffs.one_shot = true
	puffs.local_coords = false

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.15
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 2.6
	process.gravity = Vector3(0, -5, 0)
	process.scale_min = 0.25
	process.scale_max = 0.6
	process.color = Color(0.55, 0.40, 0.25)

	puffs.process_material = process

	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.06
	puff_mesh.height = 0.12
	puff_mesh.radial_segments = 6
	puff_mesh.rings = 3

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.6, 0.45, 0.28, 0.85)

	puff_mesh.material = mat
	puffs.draw_pass_1 = puff_mesh

	# Se cuelga de la escena, no del mono: si no, se iría con él al
	# queue_free() y no se vería nada.
	get_parent().add_child(puffs)
	puffs.global_position = global_position
	puffs.emitting = true
	puffs.finished.connect(puffs.queue_free)


## El mago viviente más cercano. No el primero de la lista: el grupo
## viene en orden de creación, no de cercanía.
func _nearest_target() -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group(target_group):
		var n3 := node as Node3D
		if n3 == null:
			continue
		var d: float = n3.global_position.distance_squared_to(global_position)
		if d < best_dist:
			best_dist = d
			best = n3
	return best


func _material() -> StandardMaterial3D:
	# El .obj viene sin .mtl, así que la superficie sale sin material.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.30, 0.20)
	mat.roughness = 0.9
	return mat
