extends Node3D
class_name AimIndicator

@export var wand_path: NodePath

@export var max_distance: float = 20.0
@export var line_radius: float = 0.006
@export var reticle_radius: float = 0.04
@export var color: Color = Color(1.0, 0.5, 0.1)
@export var enabled: bool = true
@export var show_reticle: bool = true
@export var show_duration: float = 5.0   # segundos tras reconocer figura

var _wand: Node3D
var _ray: RayCast3D
var _line: MeshInstance3D
var _reticle: MeshInstance3D

## Hasta cuándo (en ms de Time.get_ticks_msec()) debe permanecer visible.
## 0 = oculto.
var _hide_at_msec: int = 0


func _ready() -> void:
	_resolve_wand()
	_build_ray()
	_build_line()
	if show_reticle:
		_build_reticle()
	_connect_wand_signals()


func _resolve_wand() -> void:
	if wand_path:
		_wand = get_node_or_null(wand_path)
	if _wand == null:
		var n: Node = get_parent()
		while n and not n.has_method("get_aim_direction"):
			n = n.get_parent()
		_wand = n
	if _wand == null:
		push_warning("AimIndicator: no se encontró WandDrawing.")


func _connect_wand_signals() -> void:
	if _wand == null:
		return
	if _wand.has_signal("drawing_started"):
		_wand.drawing_started.connect(_on_drawing_started)
	if _wand.has_signal("shape_recognized"):
		_wand.shape_recognized.connect(_on_shape_recognized)


func _on_drawing_started() -> void:
	# Mientras dibuja, el indicador se oculta.
	_hide_at_msec = 0


func _on_shape_recognized(_shape_name: String = "", _points: Array = []) -> void:
	# Aparece durante show_duration segundos desde este momento.
	_hide_at_msec = Time.get_ticks_msec() + int(show_duration * 1000.0)


# ============================================================
# CONSTRUCCIÓN
# ============================================================

func _build_ray() -> void:
	_ray = RayCast3D.new()
	_ray.enabled = true
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.top_level = true
	add_child(_ray)


func _build_line() -> void:
	_line = MeshInstance3D.new()

	var cyl := CylinderMesh.new()
	cyl.top_radius = line_radius
	cyl.bottom_radius = line_radius
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	_line.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line.material_override = mat

	_line.top_level = true
	_line.visible = false
	add_child(_line)


func _build_reticle() -> void:
	_reticle = MeshInstance3D.new()

	var sphere := SphereMesh.new()
	sphere.radius = reticle_radius
	sphere.height = reticle_radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	_reticle.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_receive_shadows = true
	_reticle.material_override = mat

	_reticle.top_level = true
	_reticle.visible = false
	add_child(_reticle)


# ============================================================
# LOOP
# ============================================================

func _process(_delta: float) -> void:
	if not enabled or _wand == null:
		_hide()
		return

	# ¿Sigue dentro de la ventana visible?
	if Time.get_ticks_msec() >= _hide_at_msec:
		_hide()
		return

	# Origen y dirección: la propia varita.
	var origin: Vector3 = _wand.global_position
	var direction: Vector3 = _wand.get_aim_direction()
	if direction.length() < 0.0001:
		_hide()
		return
	direction = direction.normalized()

	# Raycast para encontrar el punto de impacto.
	_ray.global_transform = Transform3D(Basis(), origin)
	_ray.target_position = direction * max_distance
	_ray.force_raycast_update()

	var end: Vector3
	if _ray.is_colliding():
		end = _ray.get_collision_point()
	else:
		end = origin + direction * max_distance

	var delta_v := end - origin
	var distance := delta_v.length()
	if distance < 0.05:
		_hide()
		return

	var dir := delta_v / distance

	var up_ref := Vector3.UP
	if abs(dir.dot(up_ref)) > 0.99:
		up_ref = Vector3.RIGHT
	var right := dir.cross(up_ref).normalized()
	var forward := right.cross(dir).normalized()
	var basis := Basis(right, dir * distance, forward)

	_line.global_transform = Transform3D(basis, origin + dir * distance * 0.5)
	_line.visible = true

	if _reticle:
		_reticle.global_position = end
		_reticle.visible = true


func _hide() -> void:
	if _line:
		_line.visible = false
	if _reticle:
		_reticle.visible = false
