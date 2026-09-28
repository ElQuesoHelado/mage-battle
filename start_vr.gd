extends Node3D

signal session_started
signal focus_lost
signal focus_gained
signal pose_recentered

## Set the highest refresh rate we wish to enable.
## We'll find the closest matching one.
@export var maximum_refresh_rate: int = 90

## Si es true, el juego se cierra cuando no hay runtime de OpenXR.
## Déjalo en false para poder abrir el proyecto en un PC sin visor:
## el juego sigue en modo escritorio y se puede revisar la escena.
@export var quit_if_no_xr: bool = false

## Si es true, fuerza el arranque en modo escritorio aunque haya soporte OpenXR en la PC.
@export var force_desktop_mode: bool = false

## Altura de la cámara de respaldo para el modo escritorio.
@export var desktop_camera_height: float = 1.7
@export var camera_speed: float = 6.0
@export var mouse_sensitivity: float = 0.003

var xr_interface: OpenXRInterface
var xr_is_focused: bool = false
var xr_is_active: bool = false


## Get our OpenXR Interface.
func get_xr_interface() -> OpenXRInterface:
	return xr_interface


## true si hay sesión de VR real. El HUD y la interfaz lo usan para
## cambiar de comportamiento en modo escritorio.
func is_xr_active() -> bool:
	return xr_is_active


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var use_vr := false
	if not force_desktop_mode:
		xr_interface = XRServer.find_interface("OpenXR")
		if xr_interface and xr_interface.is_initialized():
			use_vr = true

	if use_vr:
		print("OpenXR instantiated successfully.")
		var vp: Viewport = get_viewport()

		# Enable XR on our viewport.
		vp.use_xr = true

		# Make sure V-Sync is off, as V-Sync is handled by OpenXR.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

		# Enable variable rate shading.
		if RenderingServer.get_rendering_device():
			vp.vrs_mode = Viewport.VRS_XR
		elif int(ProjectSettings.get_setting("xr/openxr/foveation_level")) == 0:
			push_warning("OpenXR: Recommend setting Foveation level to High in Project Settings")

		# Connect the OpenXR events.
		xr_interface.session_begun.connect(_on_openxr_session_begun)
		xr_interface.session_visible.connect(_on_openxr_visible_state)
		xr_interface.session_focussed.connect(_on_openxr_focused_state)
		xr_interface.session_stopping.connect(_on_openxr_stopping)
		xr_interface.pose_recentered.connect(_on_openxr_pose_recentered)
		xr_is_active = true
	else:
		# No hay runtime de OpenXR: PC sin visor, o runtime mal
		# configurado en el sistema.
		print("OpenXR no disponible o modo escritorio activo.")
		if quit_if_no_xr:
			get_tree().quit()
			return
		push_warning(
			"OpenXR no disponible: el juego sigue en modo escritorio. "
			+ "El seguimiento de manos y los hechizos por gestos quedan "
			+ "desactivados."
		)
		var vp: Viewport = get_viewport()
		vp.use_xr = false
		call_deferred("_setup_desktop_camera")


## Sin una cámara activa, el modo escritorio mostraría una pantalla
## gris/negra. Se crea una Camera3D normal a la altura de la cabeza.
func _setup_desktop_camera() -> void:
	var vp := get_viewport()
	if vp:
		vp.use_xr = false

	# Desactivar y remover cualquier XRCamera3D para que DesktopCamera sea la única activa
	var origin := _find_xr_origin()
	if origin:
		for child in origin.get_children():
			if child is Camera3D and child.name != "DesktopCamera":
				child.current = false
				child.queue_free()

	var existing_cam := get_viewport().get_camera_3d()
	if existing_cam != null and existing_cam.name == "DesktopCamera":
		existing_cam.make_current()
		return

	if existing_cam != null and existing_cam is XRCamera3D:
		existing_cam.current = false

	var cam := Camera3D.new()
	cam.name = "DesktopCamera"
	cam.set_script(load("res://scripts/desktop_free_camera.gd"))

	var root := get_tree().current_scene
	if root:
		root.add_child(cam)
	elif origin:
		cam.top_level = true
		origin.add_child(cam)
	else:
		add_child(cam)

	cam.global_position = Vector3(0.0, 1.8, 3.5)
	cam.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)
	cam.make_current()
	cam.current = true
	if cam.has_method("_sync_rotation"):
		cam._sync_rotation()
	print("[StartVR] DesktopCamera activada con script propio y lista para volar.")


## StartVR es hermano del XROrigin3D, no hijo, así que hay que mirar
## también entre los hermanos.
func _find_xr_origin() -> XROrigin3D:
	var n: Node = self
	while n:
		if n is XROrigin3D:
			return n
		n = n.get_parent()

	var parent := get_parent()
	if parent:
		for sibling in parent.get_children():
			if sibling is XROrigin3D:
				return sibling
	return null


# Handle OpenXR session ready.
func _on_openxr_session_begun() -> void:
	# Get the reported refresh rate.
	var current_refresh_rate := xr_interface.get_display_refresh_rate()
	if current_refresh_rate > 0:
		print("OpenXR: Refresh rate reported as ", str(current_refresh_rate))
	else:
		print("OpenXR: No refresh rate given by XR runtime")

	# See if we have a better refresh rate available.
	var new_rate := current_refresh_rate
	var available_rates: Array = xr_interface.get_available_display_refresh_rates()
	if available_rates.is_empty():
		print("OpenXR: Target does not support refresh rate extension")
	elif available_rates.size() == 1:
		# Only one available, so use it.
		new_rate = available_rates[0]
	else:
		for rate in available_rates:
			if rate > new_rate and rate <= maximum_refresh_rate:
				new_rate = rate

	# Did we find a better rate?
	if current_refresh_rate != new_rate:
		print("OpenXR: Setting refresh rate to ", str(new_rate))
		xr_interface.set_display_refresh_rate(new_rate)
		current_refresh_rate = new_rate

	# Now match our physics rate. This is currently needed to avoid jittering,
	# due to physics interpolation not being used.
	Engine.physics_ticks_per_second = roundi(current_refresh_rate)

	session_started.emit()


# Handle OpenXR visible state.
func _on_openxr_visible_state() -> void:
	# We always pass this state at startup,
	# but the second time we get this, it means our player took off their headset.
	if xr_is_focused:
		print("OpenXR lost focus")

		xr_is_focused = false

		# Pause our game.
		process_mode = Node.PROCESS_MODE_DISABLED

		focus_lost.emit()


# Handle OpenXR focused state.
func _on_openxr_focused_state() -> void:
	print("OpenXR gained focus")
	xr_is_focused = true

	# Unpause our game.
	process_mode = Node.PROCESS_MODE_INHERIT

	focus_gained.emit()


# Handle OpenXR stopping state.
func _on_openxr_stopping() -> void:
	# Our session is being stopped.
	print("OpenXR is stopping")


# Handle OpenXR pose recentered signal.
func _on_openxr_pose_recentered() -> void:
	# User recentered view, we have to react to this by recentering the view.
	# This is game implementation dependent.
	pose_recentered.emit()
