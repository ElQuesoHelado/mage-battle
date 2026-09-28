extends Node3D
class_name AltarMayor

## Altar central. Es el único que habilita el lanzamiento: hay que
## dibujarle un círculo con el puño para cargarlo, y su energía se
## gasta sola con el tiempo.
##
## La parte visual está en scenes/altar_mayor.tscn.

# ─── Economía de energía ──────────────────────────────────────
## Energía máxima. De aquí sale el número de la barra del HUD.
@export var energia_max: float = 100.0
## Energía mínima para poder lanzar. Igual al coste de un hechizo.
@export var min_to_cast: float = 20.0

# ─── Detección ────────────────────────────────────────────────
## Radio horizontal a la que el jugador cuenta como "en el altar".
## Como la escena no tiene locomoción y el altar está justo delante,
## esto sólo importa si el jugador se aleja caminando.
@export var radius: float = 2.0

## Pinta el estado con este color cuando tiene energía.
@export var color_encendido := Color(0.95, 0.90, 0.55)

signal player_entered
signal player_exited
## Se emite cuando un círculo recarga el altar. Recibe la energía
## ganada para que el HUD pueda confirmar.
signal energy_gained(amount: float)

var energia: float = 0.0
var _player_inside: bool = false
var _pulse: float = 0.0
var _nucleo: MeshInstance3D
var _halo: MeshInstance3D
var _anillo: MeshInstance3D
var _estado: Label3D
var _mat_encendido: StandardMaterial3D
## Último porcentaje pintado en la etiqueta. -1 fuerza el refresco.
var _last_pct: int = -1


func _ready() -> void:
	# Permite que SpellSystem lo encuentre aunque no se asigne a mano.
	add_to_group("altar_mayor")
	_nucleo = get_node_or_null("Nucleo") as MeshInstance3D
	_halo = get_node_or_null("Halo") as MeshInstance3D
	_anillo = get_node_or_null("Anillo") as MeshInstance3D
	_estado = get_node_or_null("Estado") as Label3D

	_mat_encendido = StandardMaterial3D.new()
	_mat_encendido.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_encendido.albedo_color = color_encendido
	_mat_encendido.emission_enabled = true
	_mat_encendido.emission = color_encendido
	_mat_encendido.emission_energy_multiplier = 4.0

	# Arranca apagado: hay que hacer el primer círculo.
	_apply_visual()
	_update_label()


func _process(delta: float) -> void:
	# Sin desgaste por tiempo: la energía sólo baja al lanzar. Aquí ya
	# no hay nada que descontar, sólo se animan el nucleo y el anillo.
	var inside := _is_player_inside()
	if inside != _player_inside:
		_player_inside = inside
		if inside:
			player_entered.emit()
		else:
			player_exited.emit()

	_pulse += delta
	_animate()

	# El texto sólo se reescribe cuando cambia el porcentaje entero. Con
	# el drenaje continuo la energía cambia en cada frame, y regenerar la
	# malla de un Label3D 90 veces por segundo es de las cosas más caras
	# que se pueden hacer aquí.
	var pct := int(round(get_fill() * 100.0))
	if pct != _last_pct:
		_last_pct = pct
		_update_label()
		_apply_visual()


# ─── API ───────────────────────────────────────────────────────

## Recarga por trazo. La cantidad la calcula wand_drawing a partir de
## la longitud del movimiento de la mano. Devuelve lo que realmente se
## ganó (0 si ya estaba lleno).
func add_charge(amount: float) -> float:
	var before := energia
	energia = minf(energia_max, energia + amount)
	var gained := energia - before
	if gained > 0.0:
		energy_gained.emit(gained)
	_last_pct = -1
	_update_label()
	_apply_visual()
	return gained


## Intenta gastar. Devuelve false si no hay energía suficiente, en cuyo
## caso no se gasta nada.
func spend(amount: float) -> bool:
	if not is_online() or energia < amount:
		return false
	energia -= amount
	_last_pct = -1
	_update_label()
	_apply_visual()
	return true


## true si hay energía para lanzar.
func is_online() -> bool:
	return energia >= min_to_cast


func is_player_inside() -> bool:
	return _player_inside


## Proporción 0..1, para la barra del HUD.
func get_fill() -> float:
	if energia_max <= 0.0:
		return 0.0
	return clampf(energia / energia_max, 0.0, 1.0)


# ─── Visual ────────────────────────────────────────────────────

func _animate() -> void:
	var factor := get_fill()
	var s := 0.35 + 0.65 * factor
	if _nucleo != null:
		# El pulso sólo se nota cuando hay energía; apagado late suave.
		var pulse := 1.0 + 0.06 * sin(_pulse * 3.0) * (0.3 + factor)
		_nucleo.scale = Vector3(s, s, s) * pulse
	if _halo != null:
		_halo.scale = Vector3(s, s, s) * 1.4
	if _anillo != null:
		_anillo.scale = Vector3.ONE * (0.9 + 0.12 * factor)


## El núcleo se pinta con el material encendido cuando hay energía; en
## estado apagado se deja material_override a null para que mande el
## material apagado que trae la escena.
func _apply_visual() -> void:
	if _nucleo == null or _mat_encendido == null:
		return
	var want: Material = _mat_encendido if is_online() else null
	if _nucleo.material_override != want:
		_nucleo.material_override = want


func _update_label() -> void:
	if _estado == null:
		return
	if is_online():
		_estado.text = "Grita tu magia %d%%" % int(round(get_fill() * 100.0))
		_estado.modulate = color_encendido
	else:
		_estado.text = "Dibuja magia"
		_estado.modulate = Color(0.7, 0.7, 0.75, 1.0)


# ─── Proximidad ────────────────────────────────────────────────

func _is_player_inside() -> bool:
	var player := _player_position()
	if player == Vector3.INF:
		return false
	var dx: float = player.x - global_position.x
	var dz: float = player.z - global_position.z
	return Vector2(dx, dz).length() <= radius


func _player_position() -> Vector3:
	var origin := _find_xr_origin()
	if origin != null:
		return origin.global_position
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return Vector3.INF


func _find_xr_origin() -> XROrigin3D:
	var n: Node = self
	while n != null:
		if n is XROrigin3D:
			return n
		n = n.get_parent()
	var parent := get_parent()
	if parent != null:
		for sibling in parent.get_children():
			if sibling is XROrigin3D:
				return sibling
	return null
