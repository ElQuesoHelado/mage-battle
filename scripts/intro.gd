extends Node3D

# Referencias a nodos de la escena (ajusta los nombres a los tuyos)
@onready var gem: RigidBody3D = $Gem

var _time := 0.0
var _gem_base_y := 0.0


func _ready() -> void:
	if gem:
		# Guardamos su altura inicial para el efecto de flotación
		_gem_base_y = gem.global_position.y
		# Que no caiga por gravedad mientras flota
		gem.freeze = true
		gem.gravity_scale = 0.0
		# Opcional: que no pueda ser empujada por el jugador
		gem.lock_rotation = false


func _process(delta: float) -> void:
	_time += delta
	if gem:
		# Flotación senoidal suave
		gem.global_position.y = _gem_base_y + sin(_time * 1.5) * 0.08
		# Rotación lenta sobre su eje Y
		gem.rotate_y(delta * 0.4)
