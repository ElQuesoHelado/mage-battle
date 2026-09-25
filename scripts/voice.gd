extends Node3D

@onready var player := $AudioStreamPlayer as AudioStreamPlayer

signal word_recognized(word: String)
signal game_finished

# --- Configuración del juego ---
const MAGES_TO_WIN      := 3
const TELEPORT_INTERVAL := 10.0
const TELEPORT_RADIUS   := 8.0
@export var teleport_center := Vector3.ZERO

# ─── Libro mágico ────────────────────────────────────────────
@export var mano_izquierda: Node3D     # nodo XRNode3D de la mano izquierda
@export var libro: Node3D              # instancia de libroMagico.tscn

# --- Vosk ---
var _effect: AudioEffectCapture
var _recognizer := VoskRecognizer.new()
var _mages_killed := 0
var _game_over := false


func _ready() -> void:
	player.play()

	# --- Timer de teletransporte ---
	var tp_timer := Timer.new()
	tp_timer.wait_time = TELEPORT_INTERVAL
	tp_timer.autostart = true
	tp_timer.timeout.connect(_teleport_mages)
	add_child(tp_timer)

	# ─── LIBRO: configurar y conectar ANTES de Vosk ─────────
	# (así aunque Vosk falle, el libro igual queda conectado)
	if libro:
		libro.visible = false
		print("[Main] libro asignado, visible=false al inicio")
	else:
		push_error("[Main] 'libro' NO asignado en el inspector")

	if mano_izquierda == null:
		push_error("[Main] 'mano_izquierda' NO asignado en el inspector")
	else:
		print("[Main] mano_izquierda = ", mano_izquierda.name,
			"  tiene pinch_entered? ", mano_izquierda.has_signal("pinch_entered"))
		if mano_izquierda.has_signal("pinch_entered"):
			mano_izquierda.pinch_entered.connect(_on_pinch_entered)
			mano_izquierda.pinch_exited.connect(_on_pinch_exited)
			print("[Main] Conectado a pinch_entered / pinch_exited")
		else:
			push_error("[Main] la mano izquierda no expone pinch_entered. ¿Le pegaste el script?")

	# --- Vosk ---
	var model := load(
		"res://assets/vosk-model-small-es-0.42.vosk"
	) as VoskModel

	var mix_rate: float = ProjectSettings.get_setting(
		"audio/driver/mix_rate",
		44100
	)

	var grammar := PackedStringArray([
		"fuego", "agua", "rayo", "roca", "mono", "[unk]"
	])

	var error := _recognizer.setup_with_grammar(model, mix_rate, grammar)
	if error != OK:
		push_error("failed to set up Vosk recognizer with grammar")
		return

	var bus_idx := AudioServer.get_bus_index("Record")
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var fx := AudioServer.get_bus_effect(bus_idx, i)
		if fx is AudioEffectCapture:
			_effect = fx
			break

	if _effect == null:
		push_error("no AudioEffectCapture found on bus 'Record'")


# -------- Señales de pinza --------
func _on_pinch_entered() -> void:
	print("[Main] ➜ _on_pinch_entered")
	if libro == null:
		push_error("[Main] libro es NULL")
		return
	print("[Main]   libro.visible(antes)=", libro.visible)
	print("[Main]   libro.has_method(abrir)? ", libro.has_method("abrir"))
	libro.abrir()
	print("[Main]   libro.visible(después)=", libro.visible)


func _on_pinch_exited() -> void:
	print("[Main] ➜ _on_pinch_exited")
	if libro == null:
		return
	print("[Main]   libro.visible(antes)=", libro.visible)
	libro.cerrar()
	print("[Main]   libro.visible(después)=", libro.visible)


# -------- Teletransporte --------
func _teleport_mages() -> void:
	if _game_over:
		return
	var mages := get_tree().get_nodes_in_group("mages")
	if mages.is_empty():
		return
	for mage in mages:
		if not is_instance_valid(mage):
			continue
		var angle := randf() * TAU
		var dist  := randf_range(2.0, TELEPORT_RADIUS)
		mage.global_position = teleport_center + Vector3(
			cos(angle) * dist, 0.0, sin(angle) * dist
		)


# -------- Conteo de kills --------
func register_mage_kill() -> void:
	if _game_over:
		return
	_mages_killed += 1
	print("Magos eliminados: %d / %d" % [_mages_killed, MAGES_TO_WIN])
	if _mages_killed >= MAGES_TO_WIN:
		_finish_game()


func _finish_game() -> void:
	_game_over = true
	game_finished.emit()
	get_tree().change_scene_to_file("res://outro.tscn")
	print("¡Juego terminado! Magos derrotados: ", _mages_killed)


# -------- Vosk --------
func _process(_delta: float) -> void:
	if _effect == null:
		return
	var frames := _effect.get_frames_available()
	if frames <= 0:
		return
	var samples := _effect.get_buffer(frames)
	if _recognizer.accept_samples(samples) != OK:
		return
	var alternatives = _recognizer.get_final_result().get("alternatives", [])
	if alternatives.size() == 0:
		return
	var text: String = alternatives[0].get("text", "")
	if text == "":
		return
	text = text.to_lower()
	print("[VoiceRecognizer] reconocido: ", text)
	if text.contains("fuego"):
		word_recognized.emit("fuego")
	elif text.contains("agua"):
		word_recognized.emit("agua")
	elif text.contains("mono"):
		word_recognized.emit("mono")
	elif text.contains("rayo"):
		word_recognized.emit("rayo")
	elif text.contains("roca"):
		word_recognized.emit("roca")
