extends Node3D

@onready var player := $AudioStreamPlayer as AudioStreamPlayer

signal word_recognized(word: String)

var _effect: AudioEffectCapture
var _recognizer := VoskRecognizer.new()


func _ready() -> void:
	player.play()

	var model := load(
		"res://assets/vosk-model-small-es-0.42.vosk"
	) as VoskModel

	var mix_rate: float = ProjectSettings.get_setting(
		"audio/driver/mix_rate",
		44100
	)

	var grammar := PackedStringArray([
		"fuego",
		"agua",
		"mono",
		"[unk]"
	])

	var error := _recognizer.setup_with_grammar(
		model,
		mix_rate,
		grammar
	)

	if error != OK:
		push_error(
			"failed to set up Vosk recognizer with grammar"
		)
		return

	var bus_idx := AudioServer.get_bus_index("Record")

	for i in AudioServer.get_bus_effect_count(bus_idx):
		var fx := AudioServer.get_bus_effect(bus_idx, i)

		if fx is AudioEffectCapture:
			_effect = fx
			break

	if _effect == null:
		push_error(
			"no AudioEffectCapture found on bus 'Record'"
		)


func _process(_delta: float) -> void:
	if _effect == null:
		return

	var frames := _effect.get_frames_available()

	if frames <= 0:
		return

	var samples := _effect.get_buffer(frames)

	if _recognizer.accept_samples(samples) != OK:
		return

	var alternatives = _recognizer.get_final_result().get(
		"alternatives",
		[]
	)

	if alternatives.size() == 0:
		return

	var text: String = alternatives[0].get(
		"text",
		""
	)

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
