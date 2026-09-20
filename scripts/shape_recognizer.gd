class_name ShapeRecognizer
extends RefCounted

## Reconocedor tipo $1 Unistroke simplificado, con matching por
## desplazamiento circular. El trazo se normaliza (centro + escala)
## y se remuestrea a N puntos. Se compara contra cada plantilla probando
## TODOS los puntos de inicio posibles y ambas direcciones.
##
## Eso lo hace robusto a:
##   - que el usuario empiece a dibujar por cualquier vértice,
##   - que dibuje en sentido horario o antihorario,
##   - formas curvas (círculo, corazón) donde el "primer punto" no es fiable.

const N := 32
const MATCH_THRESHOLD := 0.20


static func recognize(points_3d: Array[Vector3], plane_normal: Vector3) -> String:
	if points_3d.size() < 6:
		return "unknown"

	var centroid := Vector3.ZERO
	for p in points_3d:
		centroid += p
	centroid /= points_3d.size()

	var pts := _project_to_plane(points_3d, plane_normal, centroid)
	pts = _normalize(_resample(pts, N))

	var templates := _get_templates()
	var best_name := "unknown"
	var best_score := INF

	print("[ShapeRecognizer] --- scores ---")
	for shape_name in templates.keys():
		var tmpl: PackedVector2Array = _normalize(_resample(templates[shape_name], N))
		var score := _best_match_distance(pts, tmpl)
		print("[ShapeRecognizer]   %-9s => %.3f" % [shape_name, score])
		if score < best_score:
			best_score = score
			best_name = shape_name

	var result := best_name if best_score < MATCH_THRESHOLD else "unknown"
	print("[ShapeRecognizer] elegido=%s (%.3f, umbral=%.3f)"
		% [result, best_score, MATCH_THRESHOLD])
	return result


# ---------------------------------------------------------------------------
# Matching
# ---------------------------------------------------------------------------

## Distancia mínima probando todas las rotaciones de inicio y ambas direcciones.
static func _best_match_distance(pts: PackedVector2Array, tmpl: PackedVector2Array) -> float:
	var d_fwd := _min_offset_distance(pts, tmpl)
	var rev := pts.duplicate()
	rev.reverse()
	var d_rev := _min_offset_distance(rev, tmpl)
	return minf(d_fwd, d_rev)


## Prueba los N desplazamientos circulares y devuelve el de menor distancia.
static func _min_offset_distance(pts: PackedVector2Array, tmpl: PackedVector2Array) -> float:
	var best := INF
	var n := pts.size()
	for offset in range(n):
		var total := 0.0
		for i in range(n):
			total += pts[(i + offset) % n].distance_to(tmpl[i])
		var d := total / float(n)
		if d < best:
			best = d
	return best


# ---------------------------------------------------------------------------
# Plantillas
# ---------------------------------------------------------------------------

static func _get_templates() -> Dictionary:
	return {
		"circle":   _make_circle(),
		"triangle": _make_triangle(),
		"lt": 		_make_lt(),
		"star":     _make_star(),
		"heart":    _make_heart(),
		"bolt":     _make_bolt(),
	}


static func _make_circle() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(N):
		var a := TAU * float(i) / float(N)
		pts.append(Vector2(cos(a), sin(a)))
	return pts


static func _make_triangle() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(3):
		var a := -PI * 0.5 + TAU * float(i) / 3.0
		pts.append(Vector2(cos(a), sin(a)))
	pts.append(pts[0])
	return pts


static func _make_lt() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2( 1.0, -1.0),   # arriba derecha
		Vector2(-1.0,  0.0),   # punta izquierda
		Vector2( 1.0,  1.0),   # abajo derecha
	])

static func _make_star() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(10):
		var a := -PI * 0.5 + PI * float(i) / 5.0
		var r := 1.0 if i % 2 == 0 else 0.42
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	pts.append(pts[0])
	return pts


static func _make_heart() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var samples := 40
	for i in range(samples):
		var t := TAU * float(i) / float(samples)
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t)
			- 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(Vector2(x, y) / 16.0)
	pts.append(pts[0])
	return pts


## Rayo: zigzag en Z. Más vértices que antes para que no sea "difuso"
## y no le gane a cualquier trazo abierto.
## Rayo: zigzag compacto de 3 segmentos (4 puntos).
## Mantenerlo con pocos puntos evita que se "reparta" por todo el cuadro
## y gane contra trazos que no son bolt.
static func _make_bolt() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.4, -1.0),   # arriba izquierda
		Vector2( 0.4, -0.35),  # quiebre 1 (derecha)
		Vector2(-0.4,  0.35),  # quiebre 2 (izquierda)
		Vector2( 0.4,  1.0),   # abajo derecha
	])


# ---------------------------------------------------------------------------
# Preprocesado
# ---------------------------------------------------------------------------

static func _project_to_plane(points: Array[Vector3], normal: Vector3, centroid: Vector3) -> PackedVector2Array:
	var n := normal.normalized()
	if n.length() < 0.001:
		n = Vector3.FORWARD
	var u := n.cross(Vector3.UP)
	if u.length() < 0.001:
		u = n.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := n.cross(u).normalized()
	var out := PackedVector2Array()
	for p in points:
		var d := p - centroid
		out.append(Vector2(d.dot(u), d.dot(v)))
	return out


static func _resample(points: PackedVector2Array, n: int) -> PackedVector2Array:
	if points.size() < 2:
		return points

	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])

	if total < 0.0001:
		var same := PackedVector2Array()
		for _i in range(n):
			same.append(points[0])
		return same

	var interval := total / float(n - 1)
	var out := PackedVector2Array()
	out.append(points[0])

	var D := 0.0
	var prev := points[0]
	for i in range(1, points.size()):
		var curr := points[i]
		var d := prev.distance_to(curr)
		if d < 0.00001:
			continue
		while D + d >= interval:
			var t := (interval - D) / d
			var q := prev.lerp(curr, t)
			out.append(q)
			prev = q
			d = prev.distance_to(curr)
			D = 0.0
		D += d
		prev = curr

	while out.size() < n:
		out.append(points[points.size() - 1])

	return out


static func _normalize(points: PackedVector2Array) -> PackedVector2Array:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)

	var size: float = maxf(max_x - min_x, max_y - min_y)
	if size < 0.0001:
		return points

	var cx := (min_x + max_x) * 0.5
	var cy := (min_y + max_y) * 0.5

	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2((p.x - cx) / size, (p.y - cy) / size))
	return out


# ---------------------------------------------------------------------------
# Normal del plano (método de Newell)
# ---------------------------------------------------------------------------

static func estimate_plane_normal(points_3d: Array[Vector3]) -> Vector3:
	if points_3d.size() < 3:
		return Vector3.FORWARD
	var n := Vector3.ZERO
	var count := points_3d.size()
	for i in range(count):
		var a := points_3d[i]
		var b := points_3d[(i + 1) % count]
		n.x += (a.y - b.y) * (a.z + b.z)
		n.y += (a.z - b.z) * (a.x + b.x)
		n.z += (a.x - b.x) * (a.y + b.y)
	if n.length() < 0.001:
		return Vector3.FORWARD
	return n.normalized()
