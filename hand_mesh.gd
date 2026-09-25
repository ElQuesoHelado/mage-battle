extends XRNode3D

@export_enum("Left","Right") var hand : int = 0

# Señales claras (renombradas)
signal pinch_entered
signal pinch_exited

# ─── Detección de pinza ──────────────────────────────────────
# Ajústalos con los valores que veas en consola:
#   - Mano abierta: distancia grande (ej: 0.11)
#   - Pinza cerrada: distancia pequeña (ej: 0.05)
@export var distancia_pinza: float = 0.05    # ← si dispara a 0.097, ponlo aquí
@export var distancia_soltar: float = 0.08   # ← debes separar más para soltar
@export var hold_time: float = 0.25          # exige mantener el gesto más tiempo

@export var debug_prints: bool = true

var _pinzando: bool = false
var _t_pinza: float = 0.0
var _t_suelta: float = 0.0


func _process(delta: float) -> void:
	# --- Hand tracking ---
	var new_tracker : String = "/user/hand_tracker/left" if hand == 0 \
		else "/user/hand_tracker/right"
	var hand_tracker : XRHandTracker = XRServer.get_tracker(new_tracker)

	if hand_tracker == null or not hand_tracker.has_tracking_data:
		if debug_prints:
			print("[MANO L] sin hand tracking")
		return

	if tracker != new_tracker:
		tracker = new_tracker
		pose = "default"

	# --- Distancia pulgar ↔ índice ---
	var thumb_tip : Transform3D = hand_tracker.get_hand_joint_transform(
		XRHandTracker.HAND_JOINT_THUMB_TIP
	)
	var index_tip : Transform3D = hand_tracker.get_hand_joint_transform(
		XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
	)
	var distancia := thumb_tip.origin.distance_to(index_tip.origin)

	if debug_prints:
		print("[MANO L] dist=%.3f  pinzando=%s" % [distancia, _pinzando])

	# --- Lógica con histéresis + hold time ---
	if not _pinzando:
		if distancia < distancia_pinza:
			_t_pinza += delta
			if _t_pinza >= hold_time:
				_pinzando = true
				_t_pinza = 0.0
				_t_suelta = 0.0
				pinch_entered.emit()
				print("[MANO L] ➜ PINZA (dist=%.3f)" % distancia)
		else:
			_t_pinza = 0.0
	else:
		if distancia > distancia_soltar:
			_t_suelta += delta
			if _t_suelta >= hold_time:
				_pinzando = false
				_t_suelta = 0.0
				_t_pinza = 0.0
				pinch_exited.emit()
				print("[MANO L] ➜ SUELTA (dist=%.3f)" % distancia)
		else:
			_t_suelta = 0.0
