extends Node

@export	var nodes: Array[Node3D] = []
@export	var radius: float = 0.5
@export	var speed: float = 6

var centers: Array[Vector3]=[]
var angle: float =0.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	nodes = [$Wizard, $Wizard2, $Wizard3, $Wizard4]
	#print("Nodos: ", nodes.size())
	for n in nodes:
		centers.append(n.position)
		#print(n.position)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	angle +=speed * delta
	for i in nodes.size():
		nodes[i].position = centers[i] + Vector3(cos(angle)* radius, 0, sin(angle)*radius)
