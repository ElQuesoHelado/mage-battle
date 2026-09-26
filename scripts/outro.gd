extends Node3D

## Pantalla final. Antes esta escena usaba intro.gd, que buscaba un
## nodo 'Table/Gem' inexistente y reventaba en _ready().

@export var titulo: String = "¡VICTORIA!"
@export var subtitulo: String = "Has derrotado a los magos"

## Segundos hasta volver al juego. 0 = quedarse quieto.
@export var restart_seconds: float = 10.0
@export var next_scene: String = "res://main.tscn"

@export var hud_distance: float = 1.6
@export var title_font_size: int = 120
@export var subtitle_font_size: int = 44

var _anchor: Node3D


func _ready() -> void:
	_anchor = Node3D.new()
	_anchor.name = "OutroAnchor"
	# top_level para que el HUD no herede la escala/rotación del origen.
	_anchor.top_level = true
	add_child(_anchor)

	var cam := get_viewport().get_camera_3d()
	if cam:
		_anchor.global_transform = cam.global_transform

	_anchor.add_child(_make_label(titulo, title_font_size, Color(1.0, 0.85, 0.3), 0.35))
	_anchor.add_child(_make_label(subtitulo, subtitle_font_size, Color(1, 1, 1), -0.05))

	if restart_seconds > 0.0:
		_restart()


func _make_label(text: String, size: int, color: Color, height: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.outline_size = maxi(8, size / 4)
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.001
	label.position = Vector3(0, height, -hud_distance)
	return label


func _restart() -> void:
	await get_tree().create_timer(restart_seconds).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file(next_scene)
