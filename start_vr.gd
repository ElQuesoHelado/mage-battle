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

## Altura de la cámara de respaldo para el modo escritorio.
@export var desktop_camera_height: float = 1.7

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
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
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
		print("OpenXR not instantiated!")
		if quit_if_no_xr:
			get_tree().quit()
			return
		push_warning(
			"OpenXR no disponible: el juego sigue en modo escritorio. "
			+ "El seguimiento de manos y los hechizos por gestos quedan "
			+ "desactivados."
		)
		_setup_desktop_camera()


## Sin una cámara activa, el modo escritorio mostraría una pantalla
## negra. Se crea una Camera3D normal a la altura de la cabeza.
func _setup_desktop_camera() -> void:
	if get_viewport().get_camera_3d():
		return

	var cam := Camera3D.new()
	cam.name = "DesktopCamera"

	var origin := _find_xr_origin()
	if origin:
		# top_level para que la cámara no herede la escala del origen.
		cam.top_level = true
		origin.add_child(cam)
	else:
		add_child(cam)

	cam.position = Vector3(0.0, desktop_camera_height, 0.0)
	cam.current = true


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
