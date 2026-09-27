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

## Rota su debilidad en cada golpe que recibe daño. Es lo del jefe
## gigante: va pasando por los cuatro elementos, y su color va con la
## debilidad, así que el color ES la pista.
##
## Los magos normales lo dejan en false y su debilidad es fija.
@export var rotates_weakness: bool = false
## Orden por el que va rotando. Al ser fijo se puede aprender.
@export var weakness_order: PackedStringArray = [
	"fuego", "agua", "rayo", "tierra",
]

## Mira al jugador. El ángulo objetivo se recalcula cada
## face_refresh_seconds y luego se interpola, para no repetir un
## cálculo por frame sin que además el modelo dé tirones.
@export var face_player: bool = true
@export var face_refresh_seconds: float = 2.0
@export var face_speed: float = 4.0
## Grados a sumar por si el modelo sale mirando al revés.
@export var face_offset_degrees: float = 0.0

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

@export_group("Ataque")
## Si está a false el mago no dispara a nadie. El jefe sí dispara, pero
## más despacio: lo pone SpellSystem al invocarlo.
@export var can_attack: bool = true
## Segundos entre disparos. El primero no espera esto entero: cada mago
## arranca con un desfase aleatorio para que no disparen a la vez.
@export var attack_interval: float = 6.0
## Rango del desfase inicial. Si es 0, todos disparan a la vez.
@export_range(0.0, 8.0) var attack_jitter: float = 3.5
## Distancia máxima a la que llega a disparar.
@export var attack_range: float = 16.0
## El proyectil sale a mitad de animación, no al empezarla, para que se
## vea el gesto antes que el disparo.
@export var shot_delay: float = 0.6
## Duración de la animación "Spell" en wizard.tscn (2,73 s). Se usa para
## volver a idle: la máquina de estados no tiene transición de vuelta, y
## sin esto el mago se queda congelado en el último fotograma.
@export var spell_length: float = 2.7
## Proyectil que lanza. Lo pone SpellSystem, igual que la escena del
## jefe, para no tener la ruta escrita en la escena.
@export var attack_projectile: PackedScene
## Grupo al que dispara. El libro mágico, que es lo que hay que proteger.
@export var attack_target_group: String = "libro_magico"
## Altura desde la que sale el disparo, para que salga de las manos y no
## de los pies.
@export var shot_height: float = 1.45

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var playback: AnimationNodeStateMachinePlayback = animation_tree["parameters/playback"]

var health: int
var is_dead: bool = false

var _weakness_label: Label3D
## Posición dentro de weakness_order del jefe.
var _weakness_index: int = 0
## Ángulo Y al que se quiere mirar. Lo recalcula un temporizador, no
## el bucle de física.
var _target_yaw: float = 0.0
var _face_timer: Timer
## Temporizador de ataque. Es one_shot: al dispararse, _begin_attack()
## encadena los dos temporizadores del disparo y vuelve a armar éste.
var _attack_timer: Timer
## El ataque en curso. Evita que dos disparos se solapen y de paso
## permite cancelarlos al morir.
var _casting: bool = false
## face_player se desactiva mientras se ataca, para poder apuntar al
## libro. Aquí se guarda para devolverlo.
var _face_player_saved: bool = true


func _ready() -> void:
	health = max_health
	animation_tree.active = true
	playback.start("idle")
	add_to_group("mages")
	# Grupo de "dañable por el jugador". Los hechizos del jugador sólo
	# golpean a este grupo, y así no le hacen daño a su propio libro ni a
	# cualquier otra cosa que tenga un take_damage por ahí.
	add_to_group("enemigo")
	scale = base_scale

	# El jefe decide su debilidad ANTES de pintarse. Si _tint() corriera
	# antes, vería weak_element vacío y saldría sin pintar de blanco
	# hasta el primer golpe.
	if rotates_weakness:
		add_to_group("giant")
		_weakness_index = _order_index(weak_element)
		weak_element = weakness_order[_weakness_index]

	_tint()
	_build_weakness_label()

	if face_player:
		_target_yaw = _yaw_to_player()
		_face_timer = Timer.new()
		_face_timer.wait_time = maxf(0.2, face_refresh_seconds)
		_face_timer.autostart = true
		_face_timer.timeout.connect(_refresh_face_target)
		add_child(_face_timer)

	if can_attack and attack_interval > 0.0:
		_attack_timer = Timer.new()
		_attack_timer.one_shot = true
		_attack_timer.timeout.connect(_on_attack_timer)
		add_child(_attack_timer)
		# Cada mago con su propio ritmo. Si arrancaran todos a la vez
		# el libro caería en un segundo y medio y no parecería un juego
		# sino una cuenta atrás.
		_attack_timer.start(_first_attack_delay())


## Cuánto espera el primer disparo. Un valor fijo por mago, para que no
## cambie cada vez que se rearma el temporizador.
func _first_attack_delay() -> float:
	if attack_jitter <= 0.0:
		return attack_interval
	return attack_interval - randf_range(0.0, minf(attack_jitter, attack_interval))


# -----------------------------------------------------------------
# Ataque
# -----------------------------------------------------------------

func _on_attack_timer() -> void:
	if is_dead or is_queued_for_deletion() or _casting:
		return

	var target := get_tree().get_first_node_in_group(attack_target_group)
	if target == null or not is_instance_valid(target):
		# Sin libro no hay a quién dispararle. Se rearma igualmente, por
		# si vuelve a aparecer.
		_attack_timer.start(attack_interval)
		return

	var from := global_position + Vector3.UP * shot_height
	if from.distance_to((target as Node3D).global_position) > attack_range:
		_attack_timer.start(attack_interval)
		return

	_begin_attack(target as Node3D)


## Encadena los tres tiempos del hechizo del mago: la animación, el
## disparo a mitad de ella y la vuelta a idle al acabarla.
func _begin_attack(target: Node3D) -> void:
	if attack_projectile == null:
		# Sin escena de proyectil no hay ataque, pero tampoco un error por
		# frame: se rearmal el temporizador y ya está.
		_attack_timer.start(attack_interval)
		return

	_casting = true
	play_spell()

	# Durante el gesto no puede seguir mirando al jugador, o el disparo
	# saldría de lado mientras él se vuelve hacia el libro.
	_face_player_saved = face_player
	face_player = false
	if global_position.distance_to(target.global_position) > 0.01:
		look_at(target.global_position, Vector3.UP)
		_target_yaw = rotation.y

	# connect() en vez de await: los mismos motivos que en _die(). Una
	# corrutina que reanuda sobre un nodo ya liberado es un error de
	# verdad, y aquí el mago se puede morir entre el play y el disparo.
	get_tree().create_timer(shot_delay).timeout.connect(
		_fire_shot.bind(target), CONNECT_ONE_SHOT
	)
	get_tree().create_timer(spell_length).timeout.connect(
		_return_to_idle, CONNECT_ONE_SHOT
	)


func _fire_shot(target: Node3D) -> void:
	if is_dead or is_queued_for_deletion() or not is_inside_tree():
		return
	if target == null or not is_instance_valid(target):
		return

	var shot := attack_projectile.instantiate() as Node3D
	if shot == null:
		return

	# Las propiedades antes de añadirlo, por el mismo motivo que el jefe:
	# el _ready() del proyectil ya busca su objetivo.
	get_tree().current_scene.add_child(shot)
	if shot.has_method("launch"):
		shot.launch(global_position + Vector3.UP * shot_height, target)
	else:
		shot.global_position = global_position + Vector3.UP * shot_height


## Vuelve a idle. A mano porque la máquina de estados de wizard.tscn no
## tiene transiciones: sin auto_advance ni una Spell→idle, la animación
## termina y el modelo se queda congelado en el último fotograma para
## siempre.
func _return_to_idle() -> void:
	if is_dead or is_queued_for_deletion():
		return
	_casting = false
	play_idle()
	face_player = _face_player_saved
	_target_yaw = _yaw_to_player()
	if _attack_timer != null:
		_attack_timer.start(attack_interval)


## Ángulo Y con el que el nodo debe quedar mirando al jugador.
## look_at() apunta el -Z, que es hacia donde mira el modelo.
func _yaw_to_player() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return rotation.y
	var to_player: Vector3 = cam.global_position - global_position
	to_player.y = 0.0
	if to_player.length() < 0.05:
		return rotation.y
	var target: float = atan2(-to_player.x, -to_player.z)
	return target + deg_to_rad(face_offset_degrees)


func _refresh_face_target() -> void:
	if is_dead or is_queued_for_deletion():
		return
	_target_yaw = _yaw_to_player()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Giro suave hacia el ángulo cacheado. Una operación por mago.
	if face_player:
		var weight: float = clampf(face_speed * delta, 0.0, 1.0)
		rotation.y = lerp_angle(rotation.y, _target_yaw, weight)

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

	# La debilidad sólo avanza cuando el golpe ha hecho daño. Si
	# advanced también al fallar, el color cambiaría en cada intento y
	# no habría forma de apuntar a él.
	if rotates_weakness and health > 0:
		_advance_weakness()

	if health == 0:
		_die()


## Pasa a la siguiente debilidad del ciclo. El color y la etiqueta se
## repintan porque van ligados a `weak_element`.
func _advance_weakness() -> void:
	if weakness_order.is_empty():
		return
	_weakness_index = (_weakness_index + 1) % weakness_order.size()
	weak_element = weakness_order[_weakness_index]
	_tint()
	_update_weakness_label()
	_set_feedback_weakness()


## Avisa por la escena de que el jefe ha cambiado de color, para que el
## HUD lo muestre aunque esté detrás del jugador.
func _set_feedback_weakness() -> void:
	var director := get_tree().get_first_node_in_group("spell_system")
	if director != null and director.has_method("notify_weakness_changed"):
		director.notify_weakness_changed(weak_element)


## Índice de un elemento dentro de weakness_order.
func _order_index(element: String) -> int:
	var idx: int = weakness_order.find(element)
	return idx if idx >= 0 else 0


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

	_update_weakness_label()
	add_child(_weakness_label)


## Repinta la etiqueta. Se separa de la construcción porque el jefe la
## cambia cada vez que gira su debilidad.
func _update_weakness_label() -> void:
	if _weakness_label == null:
		return
	if weak_element.is_empty():
		_weakness_label.text = "ANY"
		_weakness_label.modulate = Color(0.85, 0.3, 0.85)
	else:
		_weakness_label.text = "↓ %s" % SpellSystem.label_of(weak_element)
		_weakness_label.modulate = SpellSystem.color_of(weak_element)
