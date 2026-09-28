extends Node3D

@onready var player := $AudioStreamPlayer as AudioStreamPlayer

signal word_recognized(word: String)

# --- Configuración del juego ---
## Los magos se teletransportan cada cierto tiempo. Apagado por
## defecto: con el sistema de debilidades hay que apuntar a un mago
## concreto, y moverlos cada 10 s lo vuelve injugable.
@export var teleport_enabled: bool = false
const TELEPORT_INTERVAL := 10.0
const TELEPORT_RADIUS   := 8.0
@export var teleport_center := Vector3.ZERO

# ─── Libro mágico ───────────────────────────────────────────
@export var mano_izquierda: Node3D     # nodo XRNode3D de la mano izquierda
@export var libro: Node3D              # instancia de libroMagico.tscn

# --- Vosk ---
## Umbral de energía (RMS 0..1) por debajo del cual consideramos que
## hay silencio. La sintaxis normal está muy por encima de 0.02.
const SILENCE_RMS := 0.012
## Silencio acumulado (en muestras) que cierra la frase.
const ENDPOINT_SAMPLES := 8000

@export var debug_prints: bool = false

var _effect: AudioEffectCapture
var _recognizer := VoskRecognizer.new()
var _speaking := false
var _silence_run := 0


func _ready() -> void:
	player.play()

	# --- Timer de teletransporte (opcional) ---
	if teleport_enabled:
		var tp_timer := Timer.new()
		tp_timer.wait_time = TELEPORT_INTERVAL
		tp_timer.autostart = true
		tp_timer.timeout.connect(_teleport_mages)
		add_child(tp_timer)

	# ─── LIBRO: configurar y conectar ANTES de Vosk ─────────
	# (así aunque Vosk falle, el libro igual queda conectado)
	# Antes aquí se hacía libro.visible = false, porque el libro sólo
	# aparecía al pellizcar con la izquierda y así no estorbaba. Ya no
	# vale: el libro es el blanco que los magos atacan, y si empieza
	# invisible el jugador no tiene ni idea de qué hay que proteger.
	if libro == null:
		push_error("[Main] 'libro' NO asignado en el inspector")

	if mano_izquierda == null:
		push_error("[Main] 'mano_izquierda' NO asignado en el inspector")
	elif not mano_izquierda.has_signal("pinch_entered"):
		push_error("[Main] la mano izquierda no expone pinch_entered")
	else:
		mano_izquierda.pinch_entered.connect(_on_pinch_entered)
		mano_izquierda.pinch_exited.connect(_on_pinch_exited)
		mano_izquierda.tree_exited.connect(_on_mano_izquierda_gone)

	# --- Vosk ---
	var model := load(
		"res://assets/vosk-model-small-es-0.42.vosk"
	) as VoskModel

	var mix_rate: float = ProjectSettings.get_setting(
		"audio/driver/mix_rate",
		44100
	)

	var grammar := PackedStringArray([
		"fuego", "agua", "rayo", "tierra", "roca", "mono", "[unk]"
	])

	var error := _recognizer.setup_with_grammar(model, mix_rate, grammar)
	if error != OK:
		push_error("failed to set up Vosk recognizer with grammar")
		return

	var bus_idx := AudioServer.get_bus_index("Record")
	if bus_idx < 0:
		push_error("no existe el bus de audio 'Record'")
		return

	for i in AudioServer.get_bus_effect_count(bus_idx):
		var fx := AudioServer.get_bus_effect(bus_idx, i)
		if fx is AudioEffectCapture:
			_effect = fx
			break

	if _effect == null:
		push_error("no AudioEffectCapture found on bus 'Record'")


# -------- Señales de pinza --------
func _on_pinch_entered() -> void:
	if libro == null:
		return
	libro.abrir()


func _on_pinch_exited() -> void:
	if libro == null:
		return
	libro.cerrar()


## Al cambiar de escena la mano izquierda se libera. Sin esta guarda,
# un pinch_exited emitido durante la transición llegaría a un libro que
# ya no existe.
func _on_mano_izquierda_gone() -> void:
	mano_izquierda = null


# -------- Teletransporte (opcional) --------
func _teleport_mages() -> void:
	var mages := get_tree().get_nodes_in_group("mages")
	if mages.is_empty():
		return
	for mage in mages:
		if not is_instance_valid(mage):
			continue
		var angle := randf() * TAU
		var dist  := randf_range(2.0, TELEPORT_RADIUS)
		mage.global_position = teleport_center + Vector3(
			cos(angle) * dist, 0.0, sin(angle) * dist
		)


# -------- Vosk --------
# Antes se llamaba get_final_result() en cada fragmento de audio, lo
# que flushaba el reconocedor a mitad de palabra y provocaba resultados
# duplicados o perdidos. Ahora se manda todo el audio a Vosk y sólo se
# pide el resultado cuando el silencio indica que la frase terminó.
func _process(_delta: float) -> void:
	if _effect == null:
		return
	var frames := _effect.get_frames_available()
	if frames <= 0:
		return
	var samples := _effect.get_buffer(frames)
	_speak(samples)


func _speak(samples: PackedVector2Array) -> void:
	if _rms(samples) < SILENCE_RMS:
		_silence_run += samples.size()
		if _speaking and _silence_run >= ENDPOINT_SAMPLES:
			_end_utterance()
	else:
		_silence_run = 0
		_speaking = true

	# Se alimenta siempre; el resultado se consulta sólo al cerrar frase.
	if _recognizer.accept_samples(samples) != OK:
		return


func _end_utterance() -> void:
	_speaking = false
	_silence_run = 0

	var alternatives = _recognizer.get_final_result().get("alternatives", [])
	if alternatives.is_empty():
		return
	var text: String = alternatives[0].get("text", "")
	if text == "":
		return

	text = text.to_lower()
	if debug_prints:
		print("[VoiceRecognizer] reconocido: ", text)

	# "tierra" y "roca" son el mismo elemento: se acepta cualquiera de
	# las dos palabras, pero siempre se emite la clave canónica.
	if text.contains("fuego"):
		word_recognized.emit("fuego")
	elif text.contains("agua"):
		word_recognized.emit("agua")
	elif text.contains("rayo"):
		word_recognized.emit("rayo")
	elif text.contains("tierra"):
		word_recognized.emit("tierra")
	elif text.contains("roca"):
		word_recognized.emit("tierra")
	elif text.contains("mono"):
		word_recognized.emit("mono")


## Energía media del bloque. Vosk devuelve estéreo; se promedia L y R.
func _rms(samples: PackedVector2Array) -> float:
	if samples.is_empty():
		return 0.0
	var acc := 0.0
	for s in samples:
		acc += (s.x * s.x + s.y * s.y) * 0.5
	return sqrt(acc / float(samples.size()))
