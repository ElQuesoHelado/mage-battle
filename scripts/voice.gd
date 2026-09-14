extends Node3D

@onready var speech_recognizer := $SpeechRecognizer as SpeechRecognizer
@onready var player := $AudioStreamPlayer as AudioStreamPlayer
@onready var camera := $XROrigin3D/XRCamera3D as XRCamera3D

const MONO_MESH := preload("res://assets/Orangutan.obj")

func _ready() -> void:
	player.play()

func _on_speech_recognizer_result(confidence: float, text: String) -> void:
	print("result: ", text)
	#if text.to_lower().contains("mono"):
	spawn_mono()

func _on_speech_recognizer_partial_result(text: String) -> void:
	print("partial: ", text)

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
