extends Node3D

@onready var player := $AudioStreamPlayer as AudioStreamPlayer

signal word_recognized(word: String)
signal game_finished                # <- nueva señal para avisar que acabó

# --- Configuración del juego ---
const MAGES_TO_WIN      := 3      # N magos a matar para terminar
const TELEPORT_INTERVAL := 10.0    # cada cuántos segundos se teletransportan
const TELEPORT_RADIUS   := 8.0    # radio máximo alrededor del centro
@export var teleport_center := Vector3.ZERO   # podés moverlo desde el editor

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

	# --- Vosk (igual que antes) ---
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


# -------- Teletransporte aleatorio --------
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

		var target := teleport_center + Vector3(
			cos(angle) * dist,
			0.0,
			sin(angle) * dist
		)

		# Si tu enemigo es CharacterBody3D, usá esto:
		# mage.global_position = target
		# Si es un Node3D común, lo de arriba funciona igual.
		mage.global_position = target


# -------- Conteo de kills --------
# Llamá a esta función desde el enemigo al morir.
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

	# Elegí UNA de estas opciones:
	get_tree().change_scene_to_file("res://outro.tscn")
	# get_tree().paused = true
	# queue_free()
	print("¡Juego terminado! Magos derrotados: ", _mages_killed)


# -------- Procesamiento de voz (igual que antes) --------
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
