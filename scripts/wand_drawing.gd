extends Node3D
class_name WandDrawing

@export var xr_controller: XRController3D
@export var trigger_action: String = "trigger"

@export var trigger_on_threshold: float = 0.6
@export var trigger_off_threshold: float = 0.4

@export var reference_forward_node: Node3D

@export var min_point_distance: float = 0.02
@export var min_points_for_shape: int = 10
@export var min_path_length: float = 0.15

@export var draw_trail: bool = true
@export var trail_material: StandardMaterial3D

@export var hand_tracker_name: String = "/user/hand_tracker/right"

## Si es true, la bola sale en la dirección del dedo índice. Si es false,
## sale perpendicular al plano del dibujo (como un portal).
@export var use_finger_direction_for_cast: bool = false

signal shape_recognized(shape_name: String, points: Array)
signal drawing_started
signal drawing_cancelled

var last_cast_direction: Vector3 = Vector3.FORWARD
var last_cast_origin: Vector3 = Vector3.ZERO
var last_plane_normal: Vector3 = Vector3.FORWARD

var _points: Array[Vector3] = []
var _is_drawing: bool = false
var _plane_normal: Vector3 = Vector3.FORWARD

var _trail_mesh: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _hand_tracker: XRHandTracker

const MAX_POINTS := 400


func _ready() -> void:
	await get_tree().process_frame
	_hand_tracker = XRServer.get_tracker(hand_tracker_name) as XRHandTracker
	if not _hand_tracker:
		push_warning("WandDrawing: no se encontró XRHandTracker '%s'" % hand_tracker_name)

	if draw_trail:
		_immediate_mesh = ImmediateMesh.new()
		_trail_mesh = MeshInstance3D.new()
		_trail_mesh.mesh = _immediate_mesh
		_trail_mesh.material_override = trail_material if trail_material else _default_trail_material()
		_trail_mesh.top_level = true
		get_tree().current_scene.add_child.call_deferred(_trail_mesh)


func _default_trail_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.0)
	return mat


func _find_xr_origin() -> XROrigin3D:
	var n: Node = self
	while n:
		if n is XROrigin3D:
			return n
		n = n.get_parent()
	return null


func get_aim_direction() -> Vector3:
	if _hand_tracker and _hand_tracker.has_tracking_data:
		var palm := _hand_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
		var index_tip := _hand_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
		var dir := index_tip.origin - palm.origin
		if dir.length() > 0.001:
			var origin_node := _find_xr_origin()
			if origin_node:
				return (origin_node.global_transform.basis * dir).normalized()
			return dir.normalized()
	return -global_transform.basis.z


@export var debug_log_trigger_state: bool = true
var _debug_timer: float = 0.0


func _process(delta: float) -> void:
	if not xr_controller:
		push_warning("WandDrawing: falta asignar xr_controller en el inspector")
		return

	var analog_value: float = xr_controller.get_float(trigger_action)
	var is_pressed: bool = xr_controller.is_button_pressed(trigger_action)

	var pressed: bool
	if _is_drawing:
		pressed = is_pressed or analog_value >= trigger_off_threshold
	else:
		pressed = is_pressed or analog_value >= trigger_on_threshold

	if debug_log_trigger_state:
		_debug_timer += delta
		if _debug_timer >= 1.0:
			_debug_timer = 0.0
			#print("[WandDrawing][DEBUG] pressed=", pressed,
				#" analog=", analog_value,
				#" is_drawing=", _is_drawing,
				#" puntos=", _points.size(),
				#" tip_pos=", global_position,
				#" aim=", get_aim_direction())

	if pressed and not _is_drawing:
		_start_drawing()
	elif pressed and _is_drawing:
		_add_point(global_position)
	elif not pressed and _is_drawing:
		_finish_drawing()


func _start_drawing() -> void:
	_is_drawing = true
	_points.clear()
	_plane_normal = get_aim_direction()
	_add_point(global_position)
	print("[WandDrawing] INICIO trazo")
	drawing_started.emit()


func _add_point(p: Vector3) -> void:
	if _points.size() >= MAX_POINTS:
		return
	if _points.is_empty() or _points[-1].distance_to(p) >= min_point_distance:
		_points.append(p)
		_update_trail()


func _update_trail() -> void:
	if not draw_trail or not _immediate_mesh:
		return
	_immediate_mesh.clear_surfaces()
	if _points.size() < 2:
		return
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in _points:
		_immediate_mesh.surface_add_vertex(p)
	_immediate_mesh.surface_end()


func _finish_drawing() -> void:
	_is_drawing = false
	_plane_normal = _estimate_plane_normal(_points)
	last_plane_normal = _plane_normal
	last_cast_origin = global_position

	if use_finger_direction_for_cast:
		last_cast_direction = get_aim_direction()
	else:
		# La bola sale perpendicular al plano del dibujo, como un portal.
		# Forzamos que la normal apunte hacia adelante (hacia donde mira
		# la cámara), para que no dependa del sentido en que dibujaste.
		var n := _plane_normal
		var cam := get_viewport().get_camera_3d()
		if cam and n.dot(-cam.global_transform.basis.z) < 0.0:
			n = -n
		last_cast_direction = n

	var path_length := _compute_path_length(_points)
	print("[WandDrawing] FIN trazo: puntos=", _points.size(), " longitud=", path_length)
	print("[WandDrawing][FIN] last_plane_normal=", last_plane_normal)
	print("[WandDrawing][FIN] last_cast_direction=", last_cast_direction)
	print("[WandDrawing][FIN] last_cast_origin=", last_cast_origin)

	if _points.size() < min_points_for_shape or path_length < min_path_length:
		print("[WandDrawing] trazo DESCARTADO")
		_clear_trail()
		drawing_cancelled.emit()
		return

	var shape := ShapeRecognizer.recognize(_points, _plane_normal)
	print("[WandDrawing] figura reconocida: ", shape, " (", _points.size(), " puntos)")

	shape_recognized.emit(shape, _points.duplicate())
	_clear_trail()


func _estimate_plane_normal(pts: Array[Vector3]) -> Vector3:
	if pts.size() < 3:
		return _plane_normal
	var n := Vector3.ZERO
	var count := pts.size()
	for i in range(count):
		var a := pts[i]
		var b := pts[(i + 1) % count]
		n.x += (a.y - b.y) * (a.z + b.z)
		n.y += (a.z - b.z) * (a.x + b.x)
		n.z += (a.x - b.x) * (a.y + b.y)
	if n.length() < 0.001:
		return _plane_normal
	return n.normalized()


func _clear_trail() -> void:
	_points.clear()
	if _immediate_mesh:
		_immediate_mesh.clear_surfaces()


func _compute_path_length(pts: Array[Vector3]) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total
