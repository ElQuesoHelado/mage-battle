class_name ShapeRecognizer extends RefCounted

## Reconocedor tipo "$1 Unistroke Recognizer" simplificado.
## Compara el trazo del usuario contra plantillas (círculo, triángulo,
## cuadrado, estrella) y devuelve la más parecida.
##
## Ajusta MATCH_THRESHOLD si tienes falsos positivos o falsos negativos:
##   - Muchos "unknown" -> baja el umbral (0.20)
##   - Confunde formas   -> súbelo (0.30)

const N := 32                    # puntos por trazo tras remuestreo
const MATCH_THRESHOLD := 0.25    # menor = más estricto


static func recognize(points_3d: Array[Vector3], plane_normal: Vector3) -> String:
	if points_3d.size() < 6:
		return "unknown"

	var centroid := Vector3.ZERO
	for p in points_3d:
		centroid += p
	centroid /= points_3d.size()

	# 1. Proyectar el trazo 3D al plano del dibujo
	var pts := _project_to_plane(points_3d, plane_normal, centroid)

	# 2. Normalizar: remuestrear -> centrar/escalar -> rotar
	pts = _rotate_to_indicative(_normalize(_resample(pts, N)))

	# 3. Comparar contra cada plantilla
	var templates := _get_templates()
	var best_name := "unknown"
	var best_score := INF

	for shape_name in templates.keys():
		var tmpl: PackedVector2Array = _rotate_to_indicative(
			_normalize(_resample(templates[shape_name], N))
		)

		# Comparación directa
		var score_fwd := _path_distance(pts, tmpl)

		# Y comparación con el trazo invertido (por si el usuario dibujó al revés)
		var rev := pts.duplicate()
		rev.reverse()
		var score_rev := _path_distance(rev, tmpl)

		var score: float = min(score_fwd, score_rev)
		print("[ShapeRecognizer] %-8s => %.3f" % [shape_name, score])

		if score < best_score:
			best_score = score
			best_name = shape_name

	var result := best_name if best_score < MATCH_THRESHOLD else "unknown"
	print("[ShapeRecognizer] elegido=%s score=%.3f (umbral=%.3f)" % [result, best_score, MATCH_THRESHOLD])
	return result


# ---------------------------------------------------------------------------
# Plantillas (puntos base; se normalizan en cada comparación)
# ---------------------------------------------------------------------------

static func _get_templates() -> Dictionary:
	return {
		"circle":   _make_circle(),
		"triangle": _make_triangle(),
		"square":   _make_square(),
		"star":     _make_star(),
	}


static func _make_circle() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(N):
		var a := TAU * i / N - PI * 0.5    # empezar arriba
		pts.append(Vector2(cos(a), sin(a)))
	pts.append(pts[0])                     # cerrar el trazo
	return pts


static func _make_triangle() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(3):
		var a := -PI * 0.5 + TAU * i / 3.0
		pts.append(Vector2(cos(a), sin(a)))
	pts.append(pts[0])
	return pts


static func _make_square() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-1, -1),
		Vector2( 1, -1),
		Vector2( 1,  1),
		Vector2(-1,  1),
		Vector2(-1, -1),
	])


static func _make_star() -> PackedVector2Array:
	var outer := 1.0
	var inner := 0.42
	var pts := PackedVector2Array()
	for i in range(10):
		var a := -PI * 0.5 + PI * i / 5.0
		var r := outer if i % 2 == 0 else inner
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	pts.append(pts[0])
	return pts


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


## Reparte n puntos equidistantes a lo largo del trazo.
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


## Centra el trazo en el origen y lo escala a tamaño unitario.
static func _normalize(points: PackedVector2Array) -> PackedVector2Array:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for p in points:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_y = min(min_y, p.y)
		max_y = max(max_y, p.y)

	var size: float = max(max_x - min_x, max_y - min_y)
	if size < 0.0001:
		return points

	var cx := (min_x + max_x) * 0.5
	var cy := (min_y + max_y) * 0.5

	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2((p.x - cx) / size, (p.y - cy) / size))
	return out


## Rota el trazo para que su primer punto quede siempre hacia la derecha
## del centroide. Así dos trazos iguales pero empezados en puntos
## distintos coinciden.
static func _rotate_to_indicative(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return points

	var c := Vector2.ZERO
	for p in points:
		c += p
	c /= float(points.size())

	var angle := atan2(c.y - points[0].y, c.x - points[0].x)
	var cos_a := cos(-angle)
	var sin_a := sin(-angle)

	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2(
			p.x * cos_a - p.y * sin_a,
			p.x * sin_a + p.y * cos_a
		))
	return out


## Distancia media punto-a-punto entre dos trazos del mismo tamaño.
static func _path_distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return INF
	var d := 0.0
	for i in range(a.size()):
		d += a[i].distance_to(b[i])
	return d / float(a.size())


# ---------------------------------------------------------------------------
# Normal del plano (método de Newell)
# ---------------------------------------------------------------------------

## Calcula la normal del mejor plano que pasa por los puntos del trazo.
## Se usa para que la bola de fuego salga perpendicular al plano del dibujo.
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
