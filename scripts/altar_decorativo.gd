extends Node3D
class_name AltarDecorativo

## Altar puramente decorativo para la intro. NO tiene interacción: no
## carga, no dispara, no mira al jugador. La diferencia entre el que
## está encendido y el apagado es sólo visual:
##
##   encendido -> los cuatro elementos orbitan y flotan alrededor
##   apagado   -> los cuatro elementos están tumbados en el suelo, quietos
##
## Se construye todo por código en vez de en la escena para poder
## cambiar radio, altura y velocidad desde el inspector sin reescribir
## un .tscn.

@export_group("Estado")
## Si está apagado no se anima nada y las esferas se quedan en el suelo.
@export var encendido: bool = false

@export_group("Tamaños")
@export var radio_esfera: float = 0.11
@export var altura_nucleo: float = 0.34
@export var escala_base: float = 1.0

@export_group("Órbita (sólo si está encendido)")
## Radio pequeño y altura casi la del núcleo: así las esferas envuelven
## al altar. Con valores altos salían por encima de la cabeza.
@export var radio_orbita: float = 0.72
@export var altura_orbita: float = 0.14
## Radianes por segundo. Las cuatro esferas van espaciadas un cuarto de
## vuelta, así que nunca se pisan.
@export var velocidad_orbita: float = 0.9
## Amplitud del vaivén vertical.
@export var flotacion: float = 0.09
@export var velocidad_flotacion: float = 1.6

## Los cuatro elementos, en el orden en que se colocan alrededor. FUEGO,
## AGUA, RAYO y TIERRA, que es el ciclo de debilidades de SpellSystem.
const ELEMENTOS := ["fuego", "agua", "rayo", "tierra"]

var _esferas: Array[MeshInstance3D] = []
var _tiempo: float = 0.0


func _ready() -> void:
	scale = Vector3.ONE * escala_base
	_construir_altar()
	_construir_elementos()

	# El apagado no se anima: set_process(false) lo deja quieto desde el
	# primer fotograma y no gasta nada.
	set_process(encendido)


func _process(delta: float) -> void:
	_tiempo += delta
	var giro := _tiempo * velocidad_orbita
	var salto := sin(_tiempo * velocidad_flotacion) * flotacion

	for i in _esferas.size():
		var angulo := giro + TAU * float(i) / float(ELEMENTOS.size())
		var e := _esferas[i]
		if e == null or not is_instance_valid(e):
			continue
		# Va en coordenadas del padre, no globales: así el altar se
		# puede mover o rotar sin que las esferas se queden atrás.
		e.position = Vector3(
			cos(angulo) * radio_orbita,
			altura_nucleo + altura_orbita + salto,
			sin(angulo) * radio_orbita
		)


# -----------------------------------------------------------------
#  Construcción
# -----------------------------------------------------------------

func _construir_altar() -> void:
	var base := MeshInstance3D.new()
	base.name = "Base"
	var cil := CylinderMesh.new()
	cil.top_radius = 0.3
	cil.bottom_radius = 0.4
	cil.height = 0.22
	cil.radial_segments = 16
	base.mesh = cil
	base.position = Vector3(0, 0.11, 0)
	base.material_override = _material(Color(0.14, 0.13, 0.16), 0.0)
	add_child(base)

	var nucleo := MeshInstance3D.new()
	nucleo.name = "Nucleo"
	var esf := SphereMesh.new()
	esf.radius = 0.22
	esf.height = 0.44
	esf.radial_segments = 16
	esf.rings = 8
	nucleo.mesh = esf
	nucleo.position = Vector3(0, altura_nucleo, 0)
	# El núcleo apagado es una piedra gris; el encendido emite.
	var color_nucleo := Color(0.95, 0.9, 0.55) if encendido else Color(0.32, 0.31, 0.36)
	var energia := 1.6 if encendido else 0.0
	nucleo.material_override = _material(color_nucleo, energia)
	add_child(nucleo)

	# El anillo sólo se dibuja encendido. Apagado sería un aro fantasma
	# flotando sobre un altar muerto, que confunde más que ajuda.
	if encendido:
		var anillo := MeshInstance3D.new()
		anillo.name = "Anillo"
		var toro := TorusMesh.new()
		toro.inner_radius = 0.4
		toro.outer_radius = 0.52
		toro.rings = 24
		toro.ring_segments = 8
		anillo.mesh = toro
		anillo.position = Vector3(0, altura_nucleo, 0)
		anillo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# El anillo va translúcido: es un aro de luz, no un aro de plástico.
		var mat_anillo := _material(Color(0.95, 0.9, 0.55), 1.4)
		mat_anillo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_anillo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat_anillo.albedo_color.a = 0.85
		anillo.material_override = mat_anillo
		add_child(anillo)


func _construir_elementos() -> void:
	var malla := SphereMesh.new()
	malla.radius = radio_esfera
	malla.height = radio_esfera * 2.0
	malla.radial_segments = 12
	malla.rings = 6

	for i in ELEMENTOS.size():
		var elemento: String = ELEMENTOS[i]
		var e := MeshInstance3D.new()
		e.name = "Elemento_" + elemento
		e.mesh = malla
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var col: Color = SpellSystem.color_of(elemento)
		if encendido:
			e.material_override = _material(col, 2.2)
			# El ángulo inicial es el que le toca en la órbita; el
			# _process se encarga a partir del primer fotograma.
			var angulo := TAU * float(i) / float(ELEMENTOS.size())
			e.position = Vector3(
				cos(angulo) * radio_orbita,
				altura_nucleo + altura_orbita,
				sin(angulo) * radio_orbita
			)
		else:
			# Apagado: sin emisión y tumbadas en el suelo, quietas.
			e.material_override = _material(col.darkened(0.45), 0.0)
			var angulo_suelo := TAU * float(i) / float(ELEMENTOS.size())
			e.position = Vector3(
				cos(angulo_suelo) * radio_orbita,
				radio_esfera,
				sin(angulo_suelo) * radio_orbita
			)

		add_child(e)
		_esferas.append(e)


func _material(color: Color, energia: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	if energia > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energia
	return m
