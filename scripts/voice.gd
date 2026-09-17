extends Node3D

#@onready var speech_recognizer := $SpeechRecognizer as SpeechRecognizer
@onready var player := $AudioStreamPlayer as AudioStreamPlayer
@onready var camera := $XROrigin3D/XRCamera3D as XRCamera3D

const MONO_MESH := preload("res://assets/Orangutan.obj")

var _effect: AudioEffectCapture
var _recognizer := VoskRecognizer.new()

func _ready() -> void:
	player.play()

	var model := load("res://assets/vosk-model-small-es-0.42.vosk") as VoskModel
	var mix_rate: float = ProjectSettings.get_setting("audio/driver/mix_rate", 44100)

	var grammar := PackedStringArray(["mono","fuego", "esperma", "[unk]"])
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

func _process(_delta: float) -> void:
	if _effect == null:
		return

	var samples := _effect.get_buffer(_effect.get_frames_available())
	if _recognizer.accept_samples(samples) == OK:
		var alternatives = _recognizer.get_final_result().get("alternatives", [])
		if alternatives.size() > 0:
			var text: String = alternatives[0].get("text", "")
			if text == "":
				return
			text = text.to_lower()
			if text.contains("mono"):
				spawn_mono()
			if text.contains("fuego"):
				spawn_mono()

func spawn_mono() -> void:
	var from := camera.global_transform.origin
	var forward := -camera.global_transform.basis.z
	var to := from + forward * 100.0  # alcance del rayo, ajusta si tu escena es más grande

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)

	if result.is_empty():
		return  # no encontró el piso en esa dirección de mirada

	_create_mono_at(result.position)

func _create_mono_at(pos: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = MONO_MESH

	var body := StaticBody3D.new()
	body.global_transform.origin = pos

	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = MONO_MESH.create_trimesh_shape()

	body.add_child(mesh_instance)
	body.add_child(collision_shape)

	get_tree().current_scene.add_child(body)

	body.look_at(camera.global_transform.origin, Vector3.UP)
