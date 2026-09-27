@tool
extends Node3D
class_name SanctuaryEnvironment

@export_group("Botón de Regeneración Manual en Editor")
@export var rebuild_environment: bool = false:
	set(val):
		rebuild_environment = false
		if Engine.is_editor_hint():
			call_deferred("_force_rebuild")

@export_group("Dimensiones del Santuario (Mage Arena)")
@export var platform_size: Vector3 = Vector3(2.6, 0.3, 2.6)
@export var pillar_size: Vector3 = Vector3(0.4, 3.2, 0.4)
@export var pillar_offset: float = 1.0

@export_group("Entorno 360")
@export var terrain_size: Vector2 = Vector2(50.0, 50.0)
@export var num_rocks: int = 16
@export var rock_min_radius: float = 7.0
@export var rock_max_radius: float = 13.0

@export var num_trees: int = 32
@export var tree_min_radius: float = 12.0
@export var tree_max_radius: float = 24.0

@export_group("Colores del Terreno y Cristales")
@export var stone_color: Color = Color(0.25, 0.27, 0.30)
@export var crystal_color: Color = Color(0.2, 0.7, 1.0)
@export var torch_fire_color: Color = Color(1.0, 0.6, 0.2)

var spawn_positions: Array[Vector3] = []

# Variables de Animación Ritual en Tiempo Real
var time_passed: float = 0.0
var total_mana_charge: float = 0.0

var crystal_mesh: MeshInstance3D = null
var crystal_light: OmniLight3D = null
var crystal_material: StandardMaterial3D = null
var torch_lights: Array[OmniLight3D] = []
var orbiting_orbs: Array[MeshInstance3D] = []
var hourglasses: Array = []

# Rutas de modelos de KayKit
const PILLAR_MODEL_PATH := "res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/pillar_decorated.gltf"
const TORCH_MODEL_PATH := "res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/torch_lit.gltf"
const BANNER_MODEL_PATH := "res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/banner_blue.gltf"
const SHIELD_MODEL_PATH := "res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/sword_shield_gold.gltf"

const TREE_MODEL_PATHS: Array[String] = [
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Tree_1_A_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Tree_2_A_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Tree_3_A_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Tree_4_A_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Tree_Bare_1_A_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Tree_Bare_2_A_Color1.gltf",
]

const ROCK_MODEL_PATHS: Array[String] = [
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Rock_1_A_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Rock_2_A_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Rock_3_A_Color1.gltf",
]

const GRASS_MODEL_PATHS: Array[String] = [
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Grass_1_A_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Grass_1_B_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Grass_1_C_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Grass_1_D_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Grass_2_A_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Grass_2_B_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Grass_2_C_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Grass_2_D_Color1.gltf",
]

const BUSH_MODEL_PATHS: Array[String] = [
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Bush_1_A_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Bush_1_B_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Bush_2_A_Color1.gltf",
	"res://assets/Models/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/Bush_4_A_Color1.gltf",
]

const CASTLE_WALL_PATHS: Array[String] = [
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/wall.gltf",
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/wall_arched.gltf",
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/wall_broken.gltf",
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/wall_doorway.gltf",
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/wall_pillar.gltf",
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/wall_corner.gltf",
]

const ARENA_PROP_PATHS: Array[String] = [
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/chest.gltf",
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/barrel_large.gltf",
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/crates_stacked.gltf",
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/barrel_small_stack.gltf",
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/rubble_large.gltf",
	"res://assets/Models/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/rubble_half.gltf",
]


func _ready() -> void:
	# SI YA EXISTEN HIJOS EN LA ESCENA GUARDADA, NO BORRAR NI REGENERAR AUTOMÁTICAMENTE
	# Esto permite que tus ediciones manuales en el visor 3D se mantengan fijas y guardadas siempre.
	if get_child_count() == 0:
		_generate_all()
	else:
		_bind_dynamic_references()


func _bind_dynamic_references() -> void:
	torch_lights.clear()
	orbiting_orbs.clear()
	hourglasses.clear()
	crystal_mesh = get_node_or_null("Pedestal/MysticTimerCrystal") as MeshInstance3D
	crystal_light = get_node_or_null("Pedestal/OmniLight3D") as OmniLight3D
	if crystal_mesh:
		crystal_material = crystal_mesh.material_override as StandardMaterial3D

	# Buscar antorchas
	for c in get_children():
		if "Pillar" in c.name or "Tower" in c.name:
			var light := c.get_node_or_null("OmniLight3D") as OmniLight3D
			if light:
				torch_lights.append(light)


func _process(delta: float) -> void:
	time_passed += delta

	# 1. Animación Ritual de los 3 Relojes de Arena de Maná (3 min cada uno = 9 min total)
	var time_per_hg: float = 180.0
	var total_ritual_time: float = 540.0

	total_mana_charge = clampf(time_passed / total_ritual_time, 0.0, 1.0)
	var current_hg_idx: int = int(time_passed / time_per_hg)
	var current_hg_prog: float = fmod(time_passed, time_per_hg) / time_per_hg

	for i in range(hourglasses.size()):
		var hg: Dictionary = hourglasses[i]
		var top_sand: MeshInstance3D = hg.get("top_sand")
		var bottom_sand: MeshInstance3D = hg.get("bottom_sand")
		var stream: MeshInstance3D = hg.get("stream")
		var hg_gem: MeshInstance3D = hg.get("hg_gem")
		var rune_gem: MeshInstance3D = hg.get("rune_gem")
		var beam: MeshInstance3D = hg.get("beam")

		if i < current_hg_idx:
			if is_instance_valid(top_sand): top_sand.scale.y = 0.001
			if is_instance_valid(bottom_sand): bottom_sand.scale.y = 1.0
			if is_instance_valid(stream): stream.visible = false
			if is_instance_valid(beam): beam.visible = false
			_set_emissive(hg_gem, Color(0.2, 0.8, 1.0), 4.0)
			_set_emissive(rune_gem, Color(0.2, 0.8, 1.0), 5.0)

		elif i == current_hg_idx:
			if is_instance_valid(top_sand): top_sand.scale.y = max(0.001, 1.0 - current_hg_prog)
			if is_instance_valid(bottom_sand): bottom_sand.scale.y = min(1.0, current_hg_prog)
			if is_instance_valid(stream):
				stream.visible = true
				stream.scale.y = 1.0 + sin(time_passed * 10.0) * 0.05
			if is_instance_valid(beam):
				beam.visible = true
				var b_mat: StandardMaterial3D = beam.material_override
				if b_mat:
					b_mat.emission_energy_multiplier = 3.0 + sin(time_passed * 6.0) * 1.5
			_set_emissive(hg_gem, Color(1.0, 0.75, 0.2), 4.0)
			_set_emissive(rune_gem, Color(1.0, 0.75, 0.2), 3.0)

		else:
			if is_instance_valid(top_sand): top_sand.scale.y = 1.0
			if is_instance_valid(bottom_sand): bottom_sand.scale.y = 0.001
			if is_instance_valid(stream): stream.visible = false
			if is_instance_valid(beam): beam.visible = false
			_set_emissive(hg_gem, Color(0.2, 0.2, 0.25), 0.2)
			_set_emissive(rune_gem, Color(0.2, 0.2, 0.25), 0.2)

	# 2. Cristal Central de Teletransporte
	if is_instance_valid(crystal_mesh):
		crystal_mesh.rotation.y += delta * (1.5 + total_mana_charge * 3.5)
		crystal_mesh.position.y = 1.05 + total_mana_charge * 0.3 + sin(time_passed * (2.5 + total_mana_charge * 2.0)) * 0.08

		var pulse: float = (3.0 + total_mana_charge * 4.0) + sin(time_passed * (4.0 + total_mana_charge * 4.0)) * 1.0
		if is_instance_valid(crystal_material):
			crystal_material.emission_energy_multiplier = pulse
		if is_instance_valid(crystal_light):
			crystal_light.light_energy = pulse

	# 3. Órbitas Mágicas de energía en el altar
	for i in range(orbiting_orbs.size()):
		var orb := orbiting_orbs[i]
		if is_instance_valid(orb):
			var orb_speed: float = 2.0 + total_mana_charge * 2.5
			var orb_angle: float = time_passed * orb_speed + (i * TAU / 3.0)
			orb.position = Vector3(cos(orb_angle) * 0.65, 1.05 + total_mana_charge * 0.3 + sin(time_passed * 3.2 + i) * 0.06, sin(orb_angle) * 0.65)
			orb.rotation.y += delta * 3.0

	# 4. Parpadeo animado de fuego en antorchas
	if Engine.get_process_frames() % 2 == 0:
		for light in torch_lights:
			if is_instance_valid(light):
				light.light_energy = 2.5 + randf_range(-0.4, 0.4)


func _set_emissive(mesh_inst: MeshInstance3D, col: Color, energy: float) -> void:
	if not is_instance_valid(mesh_inst):
		return
	var mat := mesh_inst.material_override as StandardMaterial3D
	if not mat:
		mat = StandardMaterial3D.new()
		mesh_inst.material_override = mat
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy


func _set_owner_recursive(node: Node, root_scene: Node) -> void:
	if not is_instance_valid(node) or not is_instance_valid(root_scene):
		return
	if node != root_scene:
		node.owner = root_scene
	for child in node.get_children():
		_set_owner_recursive(child, root_scene)


func _add_node(parent: Node, child: Node) -> void:
	parent.add_child(child)
	if Engine.is_editor_hint():
		var root_scene: Node = null
		if get_tree() and get_tree().edited_scene_root:
			root_scene = get_tree().edited_scene_root
		elif self.owner:
			root_scene = self.owner
		if is_instance_valid(root_scene):
			_set_owner_recursive(child, root_scene)


func _force_rebuild() -> void:
	_generate_all()


func _generate_all() -> void:
	# Fijar semilla determinista fija para que las posiciones de árboles, rocas y murallas sean FIJAS y no cambien
	seed(12345)

	torch_lights.clear()
	orbiting_orbs.clear()
	hourglasses.clear()
	crystal_mesh = null
	crystal_light = null
	crystal_material = null

	var existing_children := get_children()
	for c in existing_children:
		remove_child(c)
		c.queue_free()

	_setup_environment_lighting()
	_create_sanctuary_base()
	_create_pillars_and_torches()
	_create_central_pedestal()
	_create_grass_terrain()
	_create_grass_tufts_360()
	_create_rocks_360()
	_create_trees_360()
	_create_castle_walls_360()
	_create_castle_towers_360()
	_create_arena_props()

	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		_set_owner_recursive(self, get_tree().edited_scene_root)

	print("[SanctuaryEnvironment] Arena de Magos generada con mapa fijo, estático y persistente.")


func _setup_environment_lighting() -> void:
	var world_env := get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if not world_env:
		world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		_add_node(get_parent(), world_env)

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.28, 0.58)
	sky_mat.sky_horizon_color = Color(0.55, 0.72, 0.88)
	sky_mat.ground_bottom_color = Color(0.12, 0.38, 0.15)
	sky_mat.ground_horizon_color = Color(0.55, 0.72, 0.88)

	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.fog_enabled = true
	env.fog_light_color = Color(0.52, 0.68, 0.85)
	env.fog_density = 0.006

	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 0.95
	env.glow_bloom = 0.15

	world_env.environment = env


func _load_model(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene:
			return scene.instantiate() as Node3D
	return null


func _get_terrain_height(x: float, z: float) -> float:
	var dist: float = Vector2(x, z).length()
	if dist <= 1.8:
		return 0.0

	var noise := FastNoiseLite.new()
	noise.seed = 1234
	noise.frequency = 0.03
	noise.fractal_octaves = 4

	var base_h: float = noise.get_noise_2d(x * 2.5, z * 2.5) * 1.8
	var blend: float = clampf((dist - 1.8) / 3.0, 0.0, 1.0)
	var final_h: float = base_h * blend

	if dist > 17.0:
		var mountain_noise := FastNoiseLite.new()
		mountain_noise.seed = 9999
		mountain_noise.frequency = 0.035
		mountain_noise.fractal_octaves = 3

		var m_factor: float = clampf((dist - 17.0) / 7.0, 0.0, 1.0)
		var m_height: float = (mountain_noise.get_noise_2d(x * 1.8, z * 1.8) + 1.0) * 4.0 + 1.5
		final_h = lerpf(final_h, m_height, m_factor)

	return final_h


func _create_sanctuary_base() -> void:
	var body := StaticBody3D.new()
	body.name = "SanctuaryBase"
	body.position = Vector3(0, -platform_size.y * 0.5, 0)

	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = platform_size

	var mat := StandardMaterial3D.new()
	mat.albedo_color = stone_color
	mat.roughness = 0.75
	mesh_inst.mesh = box_mesh
	mesh_inst.material_override = mat

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = platform_size
	col.shape = shape

	body.add_child(mesh_inst)
	body.add_child(col)
	_add_node(self, body)


func _create_pillars_and_torches() -> void:
	var offsets := [
		Vector3(-pillar_offset, 0, -pillar_offset), # NW
		Vector3(pillar_offset, 0, -pillar_offset),  # NE
		Vector3(-pillar_offset, 0, pillar_offset),   # SW
		Vector3(pillar_offset, 0, pillar_offset),    # SE
	]

	for i in range(offsets.size()):
		var body := StaticBody3D.new()
		body.name = "Pillar_%d" % (i + 1)
		body.position = offsets[i]

		var model := _load_model(PILLAR_MODEL_PATH)
		if model:
			model.scale = Vector3(0.5, 1.3, 0.5)
			body.add_child(model)
		else:
			var mesh_inst := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = pillar_size
			mesh_inst.mesh = box
			mesh_inst.position.y = pillar_size.y * 0.5
			body.add_child(mesh_inst)

		var torch := _load_model(TORCH_MODEL_PATH)
		if torch:
			torch.position = Vector3(0, 3.25, 0)
			torch.scale = Vector3(1.2, 1.2, 1.2)
			body.add_child(torch)

		var torch_light := OmniLight3D.new()
		torch_light.position = Vector3(0, 3.5, 0)
		torch_light.light_color = torch_fire_color
		torch_light.light_energy = 2.5
		torch_light.omni_range = 8.0
		body.add_child(torch_light)
		torch_lights.append(torch_light)

		var banner := _load_model(BANNER_MODEL_PATH)
		if banner:
			banner.position = Vector3(0, 2.2, 0.22)
			banner.scale = Vector3(0.8, 0.8, 0.8)
			body.add_child(banner)

		if i % 2 == 0:
			var shield := _load_model(SHIELD_MODEL_PATH)
			if shield:
				shield.position = Vector3(-0.22, 1.6, 0)
				shield.scale = Vector3(0.9, 0.9, 0.9)
				shield.rotation.y = -PI * 0.5
				body.add_child(shield)

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = pillar_size
		col.position.y = pillar_size.y * 0.5
		col.shape = shape

		body.add_child(col)
		_add_node(self, body)


func _create_central_pedestal() -> void:
	var body := StaticBody3D.new()
	body.name = "Pedestal"
	body.position = Vector3(0, 0.4, 0)

	var mesh_inst := MeshInstance3D.new()
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = 0.45
	cyl_mesh.bottom_radius = 0.55
	cyl_mesh.height = 0.8

	var mat := StandardMaterial3D.new()
	mat.albedo_color = stone_color.lightened(0.12)
	mesh_inst.mesh = cyl_mesh
	mesh_inst.material_override = mat

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.55
	shape.height = 0.8
	col.shape = shape

	body.add_child(mesh_inst)
	body.add_child(col)

	crystal_mesh = MeshInstance3D.new()
	crystal_mesh.name = "MysticTimerCrystal"
	var prism := PrismMesh.new()
	prism.size = Vector3(0.35, 0.6, 0.35)
	crystal_mesh.mesh = prism
	crystal_mesh.position = Vector3(0, 1.05, 0)

	crystal_material = StandardMaterial3D.new()
	crystal_material.albedo_color = crystal_color
	crystal_material.emission_enabled = true
	crystal_material.emission = crystal_color
	crystal_material.emission_energy_multiplier = 3.0
	crystal_mesh.material_override = crystal_material
	body.add_child(crystal_mesh)

	crystal_light = OmniLight3D.new()
	crystal_light.position = Vector3(0, 1.05, 0)
	crystal_light.light_color = crystal_color
	crystal_light.light_energy = 3.0
	crystal_light.omni_range = 6.0
	body.add_child(crystal_light)

	for i in range(3):
		var orb := MeshInstance3D.new()
		orb.name = "ManaOrb_%d" % i
		var p_mesh := PrismMesh.new()
		p_mesh.size = Vector3(0.12, 0.2, 0.12)
		orb.mesh = p_mesh

		var o_mat := StandardMaterial3D.new()
		var orb_col := Color(0.9, 0.7, 0.2) if i == 1 else crystal_color
		o_mat.albedo_color = orb_col
		o_mat.emission_enabled = true
		o_mat.emission = orb_col
		o_mat.emission_energy_multiplier = 4.0
		orb.material_override = o_mat

		body.add_child(orb)
		orbiting_orbs.append(orb)

	for i in range(3):
		var angle := i * TAU / 3.0
		var hg_pos := Vector3(cos(angle) * 0.33, 0.40, sin(angle) * 0.33)
		var hg_data := _create_single_hourglass(body, hg_pos, angle, i)
		hourglasses.append(hg_data)

	_add_node(self, body)


func _create_single_hourglass(parent: Node3D, pos: Vector3, rot_y: float, hg_index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Hourglass_%d" % hg_index
	root.position = pos
	root.rotation.y = rot_y
	parent.add_child(root)

	var brass_mat := StandardMaterial3D.new()
	brass_mat.albedo_color = Color(0.75, 0.58, 0.22)
	brass_mat.metallic = 0.85
	brass_mat.roughness = 0.3

	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.08
	cap_mesh.bottom_radius = 0.08
	cap_mesh.height = 0.02

	var cap_top := MeshInstance3D.new()
	cap_top.mesh = cap_mesh
	cap_top.position = Vector3(0, 0.32, 0)
	cap_top.material_override = brass_mat
	root.add_child(cap_top)

	var cap_bottom := MeshInstance3D.new()
	cap_bottom.mesh = cap_mesh
	cap_bottom.position = Vector3(0, 0.01, 0)
	cap_bottom.material_override = brass_mat
	root.add_child(cap_bottom)

	for i in range(3):
		var rod_angle := i * TAU / 3.0
		var rod := MeshInstance3D.new()
		var rod_mesh := CylinderMesh.new()
		rod_mesh.top_radius = 0.008
		rod_mesh.bottom_radius = 0.008
		rod_mesh.height = 0.30
		rod.mesh = rod_mesh
		rod.position = Vector3(cos(rod_angle) * 0.065, 0.16, sin(rod_angle) * 0.065)
		rod.material_override = brass_mat
		root.add_child(rod)

	var glass_mat := StandardMaterial3D.new()
	glass_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.85, 0.95, 1.0, 0.35)
	glass_mat.roughness = 0.1
	glass_mat.metallic = 0.2

	var glass_top := MeshInstance3D.new()
	var g_top_mesh := CylinderMesh.new()
	g_top_mesh.top_radius = 0.07
	g_top_mesh.bottom_radius = 0.008
	g_top_mesh.height = 0.14
	glass_top.mesh = g_top_mesh
	glass_top.position = Vector3(0, 0.24, 0)
	glass_top.material_override = glass_mat
	root.add_child(glass_top)

	var glass_bot := MeshInstance3D.new()
	var g_bot_mesh := CylinderMesh.new()
	g_bot_mesh.top_radius = 0.008
	g_bot_mesh.bottom_radius = 0.07
	g_bot_mesh.height = 0.14
	glass_bot.mesh = g_bot_mesh
	glass_bot.position = Vector3(0, 0.09, 0)
	glass_bot.material_override = glass_mat
	root.add_child(glass_bot)

	var sand_mat := StandardMaterial3D.new()
	sand_mat.albedo_color = Color(1.0, 0.8, 0.25)
	sand_mat.emission_enabled = true
	sand_mat.emission = Color(1.0, 0.7, 0.2)
	sand_mat.emission_energy_multiplier = 2.0

	var top_sand := MeshInstance3D.new()
	var s_top_mesh := CylinderMesh.new()
	s_top_mesh.top_radius = 0.065
	s_top_mesh.bottom_radius = 0.007
	s_top_mesh.height = 0.12
	top_sand.mesh = s_top_mesh
	top_sand.position = Vector3(0, 0.23, 0)
	top_sand.material_override = sand_mat
	root.add_child(top_sand)

	var bottom_sand := MeshInstance3D.new()
	var s_bot_mesh := CylinderMesh.new()
	s_bot_mesh.top_radius = 0.007
	s_bot_mesh.bottom_radius = 0.065
	s_bot_mesh.height = 0.12
	bottom_sand.mesh = s_bot_mesh
	bottom_sand.position = Vector3(0, 0.08, 0)
	bottom_sand.material_override = sand_mat
	root.add_child(bottom_sand)

	var stream := MeshInstance3D.new()
	var st_mesh := CylinderMesh.new()
	st_mesh.top_radius = 0.005
	st_mesh.bottom_radius = 0.005
	st_mesh.height = 0.14
	stream.mesh = st_mesh
	stream.position = Vector3(0, 0.16, 0)
	stream.material_override = sand_mat
	root.add_child(stream)

	var hg_gem := MeshInstance3D.new()
	var gem_prism := PrismMesh.new()
	gem_prism.size = Vector3(0.06, 0.09, 0.06)
	hg_gem.mesh = gem_prism
	hg_gem.position = Vector3(0, 0.36, 0)
	root.add_child(hg_gem)

	var rune_gem := MeshInstance3D.new()
	var r_mesh := PrismMesh.new()
	r_mesh.size = Vector3(0.08, 0.12, 0.08)
	rune_gem.mesh = r_mesh
	rune_gem.position = pos.normalized() * 0.42 + Vector3(0, 0.41, 0)
	parent.add_child(rune_gem)

	var beam := MeshInstance3D.new()
	var b_cyl := CylinderMesh.new()
	b_cyl.top_radius = 0.01
	b_cyl.bottom_radius = 0.01
	b_cyl.height = pos.length()
	beam.mesh = b_cyl

	var b_mat := StandardMaterial3D.new()
	b_mat.albedo_color = Color(0.2, 0.8, 1.0)
	b_mat.emission_enabled = true
	b_mat.emission = Color(0.2, 0.8, 1.0)
	b_mat.emission_energy_multiplier = 3.0
	beam.material_override = b_mat

	beam.position = pos * 0.5 + Vector3(0, 0.55, 0)
	var target_center := Vector3(0, 0.55, 0)
	if beam.position.distance_to(target_center) > 0.001:
		beam.look_at(target_center, Vector3.UP)
		beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	parent.add_child(beam)

	return {
		"root": root,
		"top_sand": top_sand,
		"bottom_sand": bottom_sand,
		"stream": stream,
		"hg_gem": hg_gem,
		"rune_gem": rune_gem,
		"beam": beam
	}


func _generate_lush_grass_texture() -> Texture2D:
	var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	var noise1 := FastNoiseLite.new()
	noise1.seed = 7777
	noise1.frequency = 0.018
	noise1.fractal_octaves = 3

	var noise2 := FastNoiseLite.new()
	noise2.seed = 8888
	noise2.frequency = 0.06
	noise2.fractal_octaves = 2

	var c_dark := Color(0.11, 0.38, 0.14)   # Verde bosque profundo
	var c_mid := Color(0.22, 0.58, 0.24)    # Verde césped natural
	var c_bright := Color(0.35, 0.72, 0.28) # Verde brote fresco

	for y in range(512):
		for x in range(512):
			var n1: float = (noise1.get_noise_2d(x, y) + 1.0) * 0.5
			var n2: float = (noise2.get_noise_2d(x, y) + 1.0) * 0.5
			
			var base_col: Color
			if n1 < 0.5:
				base_col = c_dark.lerp(c_mid, n1 * 2.0)
			else:
				base_col = c_mid.lerp(c_bright, (n1 - 0.5) * 2.0)
			
			var detail: float = (n2 - 0.5) * 0.12
			var final_col := base_col.lightened(detail)
			img.set_pixel(x, y, final_col)

	return ImageTexture.create_from_image(img)


func _create_grass_terrain() -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "GrassTerrain"
	mesh_inst.position = Vector3(0, -0.16, 0)

	var plane := PlaneMesh.new()
	plane.size = terrain_size
	plane.subdivide_width = 80
	plane.subdivide_depth = 80

	var st := SurfaceTool.new()
	st.create_from(plane, 0)
	var array_mesh: ArrayMesh = st.commit()
	var mdt := MeshDataTool.new()
	mdt.create_from_surface(array_mesh, 0)

	for i in range(mdt.get_vertex_count()):
		var v: Vector3 = mdt.get_vertex(i)
		v.y = _get_terrain_height(v.x, v.z)
		mdt.set_vertex(i, v)

	array_mesh.clear_surfaces()
	mdt.commit_to_surface(array_mesh)

	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.create_from(array_mesh, 0)
	st.generate_normals()
	mesh_inst.mesh = st.commit()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = _generate_lush_grass_texture()
	mat.uv1_scale = Vector3(14, 14, 14)
	mat.roughness = 0.95
	mesh_inst.material_override = mat

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := mesh_inst.mesh.create_trimesh_shape()
	col.shape = shape
	body.add_child(col)
	mesh_inst.add_child(body)

	_add_node(self, mesh_inst)


func _create_grass_tufts_360() -> void:
	var num_tufts := 750
	for i in range(num_tufts):
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(1.4, 23.0)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		pos.y = _get_terrain_height(pos.x, pos.z) - 0.22

		var grass_path: String = GRASS_MODEL_PATHS[i % GRASS_MODEL_PATHS.size()]
		var model := _load_model(grass_path)
		if model:
			model.position = pos
			var sx := randf_range(1.6, 3.2)
			var sy := randf_range(0.8, 1.4)
			var sz := randf_range(1.6, 3.2)
			model.scale = Vector3(sx, sy, sz)
			model.rotation.y = randf_range(0, TAU)
			_add_node(self, model)

	var num_bushes := 70
	for i in range(num_bushes):
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(3.0, 23.0)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		pos.y = _get_terrain_height(pos.x, pos.z) - 0.15

		var bush_path: String = BUSH_MODEL_PATHS[i % BUSH_MODEL_PATHS.size()]
		var model := _load_model(bush_path)
		if model:
			model.position = pos
			var s := randf_range(1.2, 2.2)
			model.scale = Vector3(s, s, s)
			model.rotation.y = randf_range(0, TAU)
			_add_node(self, model)


func _create_rocks_360() -> void:
	spawn_positions.clear()
	var step := TAU / num_rocks
	for i in range(num_rocks):
		var angle := i * step + randf_range(-0.2, 0.2)
		var dist := randf_range(rock_min_radius, rock_max_radius)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		pos.y = _get_terrain_height(pos.x, pos.z)

		var rock := StaticBody3D.new()
		rock.name = "Rock360_%d" % i
		rock.position = pos

		var model_path: String = ROCK_MODEL_PATHS[i % ROCK_MODEL_PATHS.size()]
		var model := _load_model(model_path)
		if model:
			var scale_f := randf_range(1.5, 2.5)
			model.scale = Vector3(scale_f, scale_f, scale_f)
			model.rotation.y = randf_range(0, TAU)
			rock.add_child(model)

		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 1.5
		col.position.y = 0.8
		col.shape = shape

		rock.add_child(col)
		_add_node(self, rock)

		spawn_positions.append(pos + pos.normalized() * 1.5)


func _create_trees_360() -> void:
	var step := TAU / num_trees
	for i in range(num_trees):
		var angle := i * step + randf_range(-0.15, 0.15)
		var dist := randf_range(tree_min_radius, tree_max_radius)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		pos.y = _get_terrain_height(pos.x, pos.z)

		var tree_path: String = TREE_MODEL_PATHS[i % TREE_MODEL_PATHS.size()]
		var model := _load_model(tree_path)
		if model:
			model.position = pos
			var scale_f := randf_range(1.8, 2.8)
			model.scale = Vector3(scale_f, scale_f, scale_f)
			model.rotation.y = randf_range(0, TAU)
			_add_node(self, model)


func _create_castle_walls_360() -> void:
	var wall_radius := 21.5
	var num_walls := 26
	var step := TAU / num_walls
	for i in range(num_walls):
		var angle := i * step
		var pos := Vector3(cos(angle) * wall_radius, 0.0, sin(angle) * wall_radius)
		pos.y = _get_terrain_height(pos.x, pos.z) - 0.2

		var wall_path: String = CASTLE_WALL_PATHS[i % CASTLE_WALL_PATHS.size()]
		var model := _load_model(wall_path)
		if model:
			model.position = pos
			model.scale = Vector3(1.8, 1.8, 1.8)
			model.rotation.y = angle + PI * 0.5 + randf_range(-0.05, 0.05)
			_add_node(self, model)


func _create_castle_towers_360() -> void:
	var tower_radius := 23.5
	var num_towers := 8
	var step := TAU / num_towers
	for i in range(num_towers):
		var angle := i * step + 0.2
		var pos := Vector3(cos(angle) * tower_radius, 0.0, sin(angle) * tower_radius)
		pos.y = _get_terrain_height(pos.x, pos.z)

		var model := _load_model(PILLAR_MODEL_PATH)
		if model:
			model.position = pos
			model.scale = Vector3(1.2, 2.5, 1.2)
			model.rotation.y = randf_range(0, TAU)
			_add_node(self, model)

			var torch := _load_model(TORCH_MODEL_PATH)
			if torch:
				torch.position = pos + Vector3(0, 6.2, 0)
				torch.scale = Vector3(1.5, 1.5, 1.5)
				_add_node(self, torch)

			var t_light := OmniLight3D.new()
			t_light.position = pos + Vector3(0, 6.5, 0)
			t_light.light_color = torch_fire_color
			t_light.light_energy = 3.0
			t_light.omni_range = 10.0
			_add_node(self, t_light)
			torch_lights.append(t_light)


func _create_arena_props() -> void:
	var num_props := 20
	for i in range(num_props):
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(4.0, 18.0)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		pos.y = _get_terrain_height(pos.x, pos.z)

		var prop_path: String = ARENA_PROP_PATHS[i % ARENA_PROP_PATHS.size()]
		var model := _load_model(prop_path)
		if model:
			model.position = pos
			var s := randf_range(1.0, 1.6)
			model.scale = Vector3(s, s, s)
			model.rotation.y = randf_range(0, TAU)
			_add_node(self, model)
