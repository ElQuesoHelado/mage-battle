extends CharacterBody3D

signal died
## Se emite cuando un elemental recibe un golpe de un elemento que no
## le afecta. SpellSystem lo usa para avisar por el HUD.
signal damage_rejected(weak_element: String)

@export var max_health: int = 3
@export var gravity: float = 20.0
@export var move_speed: float = 4.0

## Elemento al que es vulnerable. Si se deja vacía no tiene debilidad:
## cualquier elemento le hace daño. Es el caso del jefe gigante.
## No se usa @export_enum porque no admite la opción vacía, que es
## justo el valor que necesita el jefe.
@export var weak_element: String = ""

## Reduce el tamaño del mago conforme le queda vida (jefe gigante).
@export var shrinks_on_damage: bool = false
## Tamaño a vida completa.
@export var base_scale: Vector3 = Vector3.ONE
## Factor mínimo de tamaño, para que el jefe no desaparezca del todo.
@export var min_scale_factor: float = 0.35

## Cuánto tarda el cadáver en desaparecer tras morir. Es un tiempo
## fijo, no una espera por animación: garantiza que el mago siempre se
## va de la escena, exista o no la animación "death".
@export var death_cleanup_delay: float = 1.0

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var playback: AnimationNodeStateMachinePlayback = animation_tree["parameters/playback"]

var health: int
var is_dead: bool = false

var _weakness_label: Label3D


func _ready() -> void:
	health = max_health
	animation_tree.active = true
	playback.start("idle")
	add_to_group("mages")
	scale = base_scale
	_tint()
	_build_weakness_label()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func play_idle() -> void:
	if is_dead:
		return
	playback.travel("idle")


func play_spell() -> void:
	if is_dead:
		return
	playback.travel("Spell")


func play_death() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	playback.travel("death")


## `element` es el hechizo que impactó. Si el mago tiene debilidad y no
## coincide, no recibe daño.
func take_damage(amount: int = 1, element: String = "") -> void:
	# Durante un cambio de escena los cuerpos se liberan mientras todavía
	# hay señales de colisión en cola. Si el mensaje llegara a un mago
	# que ya no está en el árbol, el propio take_damage pidiendo su
	# transformación dispararía "!is_inside_tree()".
	if is_dead or is_queued_for_deletion() or not is_inside_tree():
		return

	if not weak_element.is_empty() and element != weak_element:
		damage_rejected.emit(weak_element)
		return

	# Un golpe que no le afecta no suena: el sonido es la confirmación
	# de que el elemento era el correcto.
	_play_sound("grito", 0.14)

	health -= amount
	if health < 0:
		health = 0
	if shrinks_on_damage:
		_apply_scale()
	if health == 0:
		_die()


## Escala proporcional a la vida que queda.
func _apply_scale() -> void:
	if max_health <= 0:
		return
	var factor: float = float(health) / float(max_health)
	factor = maxf(factor, min_scale_factor)
	scale = base_scale * factor
	if _weakness_label != null:
		_weakness_label.position.y = 2.2 * factor


func _die() -> void:
	if is_dead:
		return
	play_death()
	_play_sound("risa", 0.12)
	died.emit()

	# Se sale del grupo ANTES de avisar: SpellSystem usa el grupo
	# "mages" vacío como señal de que ya no queda ningún elemental
	# normal y toca invocar al jefe.
	remove_from_group("mages")
	set_deferred("collision_layer", 0)

	var director := get_tree().get_first_node_in_group("spell_system")
	if director != null and director.has_method("register_mage_kill"):
		director.register_mage_kill()

	# connect() en vez de await: un temporizador en vez de esperar a la
	# animación. Si "death" no existiera en el árbol de estados,
	# await animation_finished no se emitiría nunca y el mago se
	# quedaría congelado para siempre. Sin corrutina no hay reanudación
	# sobre un nodo ya liberado.
	if death_cleanup_delay <= 0.0 or get_tree() == null:
		queue_free()
		return
	get_tree().create_timer(death_cleanup_delay).timeout.connect(
		queue_free, CONNECT_ONE_SHOT
	)


# -----------------------------------------------------------------
# Color
# -----------------------------------------------------------------

## Pinta el mago del color del altar que lo mata, es decir del elemento
## al que es vulnerable. Así el color dice directamente qué hechizo
## sirve, sin tener que recordar el ciclo.
##
## Las 5 mallas del mago comparten un único material, así que basta con
## un material_override por malla. El jefe se queda sin colorear.
func _tint() -> void:
	if weak_element.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SpellSystem.color_of(weak_element)
	mat.roughness = 0.8
	mat.emission_enabled = true
	mat.emission = SpellSystem.color_of(weak_element)
	# Un toque de emisión sólo: si no, en la penumbra del escenario el
	# color no se distingue del material blanco original.
	mat.emission_energy_multiplier = 0.25

	for mesh in _meshes(self):
		mesh.material_override = mat


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


# -----------------------------------------------------------------
# Sonido
# -----------------------------------------------------------------

## Suena un efecto si el nodo Sfx está en la escena. Si no está, o si
## el archivo no existe, no pasa nada: el juego funciona mudo.
func _play_sound(name: String, spread: float) -> void:
	var sfx := Sfx.instance()
	if sfx == null:
		return
	if spread > 0.0:
		sfx.play_varied(name, spread)
	else:
		sfx.play(name)


# -----------------------------------------------------------------
# Interfaz
# -----------------------------------------------------------------

## Etiqueta flotante con la debilidad. Es lo que permite al jugador
## saber a qué hechizo apuntar sin tener que recordar el ciclo.
func _build_weakness_label() -> void:
	_weakness_label = Label3D.new()
	_weakness_label.font_size = 72
	_weakness_label.outline_size = 18
	_weakness_label.outline_modulate = Color(0, 0, 0)
	_weakness_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Sin no_depth_test: con 4-5 de estas etiquetas, dibujar por delante
	# de todo obliga al renderer a repintar el fondo entero cada vez.
	# Respetan la profundidad, que además es lo correcto: si un mago
	# está detrás de una pared, su etiqueta tampoco se ve.
	_weakness_label.fixed_size = true
	_weakness_label.pixel_size = 0.0012
	_weakness_label.position = Vector3(0.0, 2.2, 0.0)

	if weak_element.is_empty():
		_weakness_label.text = "ANY"
		_weakness_label.modulate = Color(0.85, 0.3, 0.85)
	else:
		_weakness_label.text = "↓ %s" % SpellSystem.label_of(weak_element)
		_weakness_label.modulate = SpellSystem.color_of(weak_element)

	add_child(_weakness_label)
