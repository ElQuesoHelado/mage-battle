extends Node3D
class_name VaritaDecorativa

## Varita de adorno para la intro. Dibuja figuras en el aire alrededor
## del altar encendido, una tras otra, y repite en bucle. NO dibuja de
## verdad: no lee la mano del jugador, no carga el altar, no dispara.
##
## El rastro usa EXACTAMENTE el mismo material y el mismo degradado que
## la varita del jugador (scripts/wand_drawing.gd), para que no se note
## que es otra cosa. Si cambias uno, hay que cambiar el otro.

@export_group("Ritmo")
## Segundos que espera con la varita quieta antes de empezar a dibujar.
@export var espera_inicial: float = 1.2
## Segundos de pausa entre figura y figura.
@export var espera_entre_figuras: float = 2.6
## Puntos por figura. Más puntos = trazo más suave.
@export var puntos_por_figura: int = 26

@export_group("Aspecto")
## 2 cm, igual que trail_width en wand_drawing.gd.
@export var trail_width: float = 0.03
@export var color_inicio: Color = Color(1.0, 0.3, 0.0)
@export var color_final: Color = Color(1.0, 1.0, 0.6)
## Malla del tubo de la varita.
@export var radio_tubo: float = 0.008
@export var largo_tubo: float = 0.22

@export_group("Órbita")
## Centro de la figura, en coordenadas de este nodo.
@export var centro_orbita: Vector3 = Vector3(0.0, 0.62, 0.0)
@export var radio_figura: float = 0.34
## Mezcla círculo/rayas de la figura actual. 0 = círculo, 1 = rayas.
## Con alterna_figuras activo va saltando sola entre los dos valores.
@export_range(0.0, 1.0) var mezcla_rayas: float = 0.0
## Si está activo, cada figura dibuja una cosa y la siguiente la
## contraria: un círculo, unas rayas, un círculo, unas rayas...
@export var alterna_figuras: bool = true
## Los dos valores con los que alterna.
@export var mezcla_circulo: float = 0.0
@export var mezcla_rayas_alt: float = 1.0

var _trail_mesh: MeshInstance3D
var _trail: ImmediateMesh
var _puntos: Array[Vector3] = []
var _tiempo: float = 0.0
var _fase: int = 0  # 0 = esperando, 1 = dibujando, 2 = figura hecha
var _indice: int = 0
var _figura: int = 0
var _tubo: MeshInstance3D
var _punta: Marker3D


func _ready() -> void:
	_construir_tubo()
	_construir_trail()
	_tiempo = -espera_inicial
	set_process(true)


func _process(delta: float) -> void:
	_tiempo += delta

	match _fase:
		0:
			# Espera: la varita se queda quieta en la posición de reposo.
			_colocar_punta(_punto_orbita(0.0))
			if _tiempo >= 0.0:
				_fase = 1
		1:
			_dibujar()
		2:
			# Acaba de terminar la figura: suelta el trazo, desaparece y
			# espera unos segundos antes de la siguiente.
			if _indice >= puntos_por_figura:
				_soltar()
				_fase = 0
				_tiempo = -espera_entre_figuras
			else:
				_indice += 1


# -----------------------------------------------------------------
#  Figuras
# -----------------------------------------------------------------

## t en 0..1 dentro de la figura actual.
func _progreso() -> float:
	return clampf(float(_indice) / float(maxi(1, puntos_por_figura)), 0.0, 1.0)


## Punto de la figura al porcentaje t. Se mezcla entre un círculo y un
## zigzag de rayas verticales según mezcla_rayas.
func _punto_orbita(t: float) -> Vector3:
	var angulo := t * TAU
	var circulo := Vector3(cos(angulo) * radio_figura, sin(angulo * 2.0) * radio_figura * 0.35, sin(angulo) * radio_figura)

	var rayas := 3.0
	var idx := int(t * rayas)
	var dentro := t * rayas - float(idx)
	# Sube y baja en cada raya, con un salto al pasar a la siguiente.
	var local := 1.0 - absf(dentro * 2.0 - 1.0)
	if idx % 2 == 1:
		local = 1.0 - local
	var zigzag := -radio_figura * 0.45 + local * radio_figura * 0.9
	var r := Vector3(-radio_figura + t * radio_figura * 2.0, zigzag, radio_figura * 0.35)

	return centro_orbita + circulo.lerp(r, mezcla_rayas)


func _dibujar() -> void:
	var p := _punto_orbita(_progreso())
	_colocar_punta(p)
	_anadir(p)
	_indice += 1
	if _indice >= puntos_por_figura:
		_fase = 2


## Al terminar la figura desaparece el trazo y se pasa a la siguiente.
func _soltar() -> void:
	_puntos.clear()
	if _trail:
		_trail.clear_surfaces()
	_figura += 1
	_indice = 0
	if _trail_mesh:
		_trail_mesh.visible = false
	if alterna_figuras:
		mezcla_rayas = mezcla_rayas_alt if mezcla_rayas < 0.5 else mezcla_circulo


func _anadir(p: Vector3) -> void:
	if _puntos.is_empty() or _puntos[_puntos.size() - 1].distance_to(p) > 0.004:
		_puntos.append(p)
	_pintar()


# -----------------------------------------------------------------
#  Trazo
# -----------------------------------------------------------------

## Copia de wand_drawing.gd: mismo material, mismo degradado naranja ->
## crema, misma banda de ancho constante.
func _pintar() -> void:
	if _trail == null or _trail_mesh == null:
		return
	_trail_mesh.visible = true
	_trail.clear_surfaces()
	var n := _puntos.size()
	if n < 2:
		return

	var half := trail_width * 0.5
	# El plano de dibujo es el XY local del nodo, así que "arriba" es Z.
	var up := Vector3(0.0, 0.0, 1.0)

	_trail.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var tangent: Vector3
		if i == 0:
			tangent = _puntos[1] - _puntos[0]
		elif i == n - 1:
			tangent = _puntos[n - 1] - _puntos[n - 2]
		else:
			tangent = _puntos[i + 1] - _puntos[i - 1]
		if tangent.length() < 0.0001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()

		var perp := tangent.cross(up)
		if perp.length() < 0.001:
			perp = tangent.cross(Vector3.RIGHT)
		perp = perp.normalized()

		var t := float(i) / float(n - 1)
		var c := color_inicio.lerp(color_final, t)

		_trail.surface_set_color(c)
		_trail.surface_add_vertex(_puntos[i] + perp * half)
		_trail.surface_set_color(c)
		_trail.surface_add_vertex(_puntos[i] - perp * half)
	_trail.surface_end()


## Mismo material que la varita del jugador, carácter por carácter.
func _material_trail() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.7, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.0)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	return mat


# -----------------------------------------------------------------
#  Construcción
# -----------------------------------------------------------------

func _construir_trail() -> void:
	_trail = ImmediateMesh.new()
	_trail_mesh = MeshInstance3D.new()
	_trail_mesh.name = "Trail"
	_trail_mesh.mesh = _trail
	_trail_mesh.material_override = _material_trail()
	_trail_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# SIN top_level a propósito: los puntos del trazo están en coordenadas
	# locales de este nodo, así que la malla tiene que heredar su
	# transform. Con top_level = true el rastro se dibujaría en el origen
	# del mundo en vez de alrededor del altar.
	#
	# No hay que temer que la varita arrastre el rastro: la malla es
	# hermana de Tubo/Punta, no hija, así que se queda quieta mientras
	# la varita se mueve.
	_trail_mesh.visible = false
	add_child.call_deferred(_trail_mesh)


func _construir_tubo() -> void:
	_tubo = MeshInstance3D.new()
	_tubo.name = "Tubo"
	var cil := CylinderMesh.new()
	cil.top_radius = radio_tubo
	cil.bottom_radius = radio_tubo * 1.3
	cil.height = largo_tubo
	cil.radial_segments = 8
	_tubo.mesh = cil
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.55, 0.32)
	mat.roughness = 0.6
	mat.metallic = 0.2
	_tubo.material_override = mat
	add_child(_tubo)

	# La punta es lo que traza: se coloca en el punto de la figura.
	_punta = Marker3D.new()
	_punta.name = "Punta"
	add_child(_punta)


## El tubo va DETRÁS de la punta, mirando hacia ella, como una varita
## sostenida. La punta es el origen del dibujo.
func _colocar_punta(p: Vector3) -> void:
	if _punta == null or _tubo == null:
		return
	_punta.position = p

	# Dirección del movimiento, para orientar la varita.
	var dir := Vector3.FORWARD
	if _puntos.size() >= 2:
		dir = (_puntos[_puntos.size() - 1] - _puntos[_puntos.size() - 2]).normalized()
	elif not _puntos.is_empty():
		dir = (p - _puntos[_puntos.size() - 1]).normalized()
	if dir.length() < 0.001:
		dir = Vector3.RIGHT

	_tubo.position = p - dir * largo_tubo * 0.5
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var eje := dir.cross(up).normalized()
	var nor := eje.cross(dir).normalized()
	# Base del cilindro es +Y, así que se orienta -Y hacia la punta.
	_tubo.basis = Basis(eje, -dir, nor)
