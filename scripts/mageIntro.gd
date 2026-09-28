extends Node3D

signal invocation_done

signal cast_started

@onready var anim_tree: AnimationTree = $AnimationTree

@export var idle_duration: float = 20.0
@export var initial_delay: float = 1.0

var _sm: AnimationNodeStateMachinePlayback


func _ready() -> void:
	_sm = anim_tree["parameters/playback"]
	anim_tree.active = true
	anim_tree.animation_finished.connect(_on_anim_finished)

	await get_tree().create_timer(initial_delay).timeout

	_sm.travel("Idle")
	await get_tree().create_timer(idle_duration).timeout
	cast_started.emit()
	_sm.travel("Cast")


func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == &"Cast":
		invocation_done.emit()
		_sm.travel("Point")
