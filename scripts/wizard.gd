extends CharacterBody3D

signal died

@export var max_health: int = 3
@export var gravity: float = 20.0
@export var move_speed: float = 4.0

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var playback: AnimationNodeStateMachinePlayback = animation_tree["parameters/playback"]

var health: int
var is_dead: bool = false

func _ready() -> void:
	health = max_health
	animation_tree.active = true
	playback.start("idle")

func _physics_process(delta: float) -> void:
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
	print(name, " vida: ", health)
	if health <= 0:
		_die()

func _die() -> void:
	play_death()
	died.emit()
	if animation_player and animation_player.has_animation("death"):
		await animation_player.animation_finished
	queue_free()
