extends Node
class_name Sfx

## Efectos de sonido del juego. Se busca por el grupo "sfx" desde
## cualquier nodo, así que wizard.gd no depende de su posición en el
## árbol.
##
## Tolera que los ficheros no existan: si assets/audio está vacío el
## juego sigue funcionando mudo, sólo avisa una vez por sonido.

## Se prueban varias extensiones porque el nombre exacto del archivo
## aún no está fijado. La primera que exista gana.
const EXTENSIONS := ["", ".formato", ".ogg", ".oga", ".wav", ".mp3", ".flac"]

@export var risa_base: String = "res://assets/audio/risa"
@export var grito_base: String = "res://assets/audio/grito"
@export var volume_db: float = 0.0
## Cuántos reproductores hay. Más de uno permite que un grito se
## solape con otro sin cortarse.
@export var polyphony: int = 4

var _streams: Dictionary = {}
var _warned: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	add_to_group("sfx")
	for i in maxi(1, polyphony):
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)


## Carga un sonido por su nombre ("risa", "grito"). Devuelve false si
## no se encuentra el archivo.
func play(name: String, pitch: float = 1.0, vol_offset_db: float = 0.0) -> bool:
	var stream: AudioStream = _get_stream(name)
	if stream == null:
		return false
	if _players.is_empty():
		return false

	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = maxf(0.01, pitch)
	p.volume_db = volume_db + vol_offset_db
	p.play()
	return true


## Variación de tono aleatoria, para que dos magos muertos seguidos no
## suenen idénticos.
func play_varied(name: String, spread: float = 0.12) -> bool:
	return play(name, 1.0 + randf_range(-spread, spread))


func has(name: String) -> bool:
	return _get_stream(name) != null


func _get_stream(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]

	var base: String = ""
	match name:
		"risa":
			base = risa_base
		"grito":
			base = grito_base
		_:
			base = "res://assets/audio/" + name

	var found := ""
	for i in EXTENSIONS.size():
		# El tipo se declara explícito: EXTENSIONS no está tipado, así
		# que sin esto la concatenación se inferiría como Variant y
		# Godot lo trata como error.
		var ext: String = EXTENSIONS[i]
		var candidate: String = base + ext
		if ResourceLoader.exists(candidate):
			found = candidate
			break

	if found == "":
		if not _warned.has(name):
			_warned[name] = true
			push_warning(
				"Sfx: no se encontró '%s' (probado con %s). "
				% [base, ", ".join(EXTENSIONS)]
				+ "El sonido quedará desactivado hasta que lo añadas."
			)
		_streams[name] = null
		return null

	var res: AudioStream = load(found)
	_streams[name] = res
	return res


## Instancia única accesible desde cualquier sitio.
static func instance() -> Sfx:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).get_first_node_in_group("sfx")
