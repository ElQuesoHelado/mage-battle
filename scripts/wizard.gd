extends CharacterBody3D

signal died

@export var max_health: int = 3
@export var gravity: float = 20.0
@export var move_speed: float = 4.0
## Cuánto tarda el cadáver en desaparecer tras morir. Es un tiempo
## fijo, no una espera por animación: garantiza que el mago siempre se
## va de la escena, exista o no la animación "death".
@export var death_cleanup_delay: float = 1.0

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var playback: AnimationNodeStateMachinePlayback = animation_tree["parameters/playback"]

var health: int
var is_dead: bool = false


func _ready() -> void:
	health = max_health
	animation_tree.active = true
	playback.start("idle")
	add_to_group("mages")


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func play_idle() -> void:
	if is_dead:
		return
	playback.travel("idle")


func play_spell() -> void:
	if is_dead:
		return
	playback.travel("Spell")


func play_death() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	playback.travel("death")


func take_damage(amount: int = 1) -> void:
	if is_dead:
		return
	health -= amount
	if health < 0:
		health = 0
	if health == 0:
		_die()


func _die() -> void:
	play_death()
	died.emit()

	var main := get_tree().current_scene
	if main and main.has_method("register_mage_kill"):
		main.register_mage_kill()

	# Se sale del grupo para que el teletransporte lo ignore y se anula
	# la capa de colisión para que el cadáver no frene los proyectiles.
	remove_from_group("mages")
	set_deferred("collision_layer", 0)

	# Espera fija en vez de await animation_finished: si la animación
	# "death" no existiera en el árbol de estados, el signal nunca
	# llegaría y el mago se quedaría congelado en el escenario para
	# siempre. Con death_cleanup_delay el bastante se va sí o sí.
	if death_cleanup_delay > 0.0:
		await get_tree().create_timer(death_cleanup_delay).timeout
	queue_free()
