extends PickupAbleBody3D

func _ready() -> void:
	picked_up.connect(_on_picked_up)

func _on_picked_up() -> void:
	await get_tree().create_timer(0.3).timeout
	get_tree().call_deferred("change_scene_to_file", "res://main.tscn")
