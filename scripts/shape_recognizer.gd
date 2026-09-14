class_name ShapeRecognizer
extends RefCounted

const CORNER_ANGLE_THRESHOLD_DEG := 55.0
const DOUGLAS_PEUCKER_EPSILON := 0.035
const CIRCLE_VARIANCE_THRESHOLD := 0.45


static func recognize(points_3d: Array[Vector3], plane_normal: Vector3) -> String:
	if points_3d.size() < 6:
		return "unknown"

	var centroid := Vector3.ZERO
	for p in points_3d:
		centroid += p
	centroid /= points_3d.size()

	var points_2d := _project_to_plane(points_3d, plane_normal, centroid)
	var simplified := _douglas_peucker(points_2d, DOUGLAS_PEUCKER_EPSILON)
	var corners := _count_corners(simplified)
	var circularity := _circularity_score(points_2d)

	print("[ShapeRecognizer] puntos=%d simplificado=%d esquinas=%d circularidad=%.3f" % [
		points_3d.size(), simplified.size(), corners, circularity
	])

	if circularity <= CIRCLE_VARIANCE_THRESHOLD and corners <= 1:
		return "circle"

	if corners == 2:
		return "triangle"

	if corners == 3:
		return "square"

	if circularity <= CIRCLE_VARIANCE_THRESHOLD * 1.4:
		return "circle"

	return "unknown"


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


static func _douglas_peucker(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() < 3:
		return points

	var dmax := 0.0
	var index := 0
	var end := points.size() - 1
	for i in range(1, end):
		var d := _perp_distance(points[i], points[0], points[end])
		if d > dmax:
			dmax = d
			index = i

	var result := PackedVector2Array()
	if dmax > epsilon:
		var left := _douglas_peucker(points.slice(0, index + 1), epsilon)
		var right := _douglas_peucker(points.slice(index, end + 1), epsilon)
		result.append_array(left.slice(0, left.size() - 1))
		result.append_array(right)
	else:
		result.append(points[0])
		result.append(points[end])
	return result


static func _perp_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length() < 0.00001:
		return p.distance_to(a)
	var t := (p - a).dot(ab) / ab.length_squared()
	var proj := a + ab * t
	return p.distance_to(proj)


static func _count_corners(simplified: PackedVector2Array) -> int:
	if simplified.size() < 3:
		return 0
	var corners := 0
	for i in range(1, simplified.size() - 1):
		var a := simplified[i - 1]
		var b := simplified[i]
		var c := simplified[i + 1]
		var v1 := (b - a).normalized()
		var v2 := (c - b).normalized()
		var angle := rad_to_deg(v1.angle_to(v2))
		if angle > CORNER_ANGLE_THRESHOLD_DEG:
			corners += 1
	return corners


static func _circularity_score(points_2d: PackedVector2Array) -> float:
	if points_2d.is_empty():
		return 999.0

	var min_x := 999.0
	var max_x := -999.0
	var min_y := 999.0
	var max_y := -999.0
	for p in points_2d:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_y = min(min_y, p.y)
		max_y = max(max_y, p.y)
	var center := Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)

	var mean_r := 0.0
	for p in points_2d:
		mean_r += p.distance_to(center)
	mean_r /= points_2d.size()
	if mean_r < 0.001:
		return 999.0

	var r_min := 999.0
	var r_max := 0.0
	var variance := 0.0
	for p in points_2d:
		var r := p.distance_to(center)
		r_min = min(r_min, r)
		r_max = max(r_max, r)
		var diff := r - mean_r
		variance += diff * diff
	variance /= points_2d.size()

	var score := sqrt(variance) / mean_r
	print("[ShapeRecognizer] radio_medio=%.3f r_min=%.3f r_max=%.3f score=%.3f" % [
		mean_r, r_min, r_max, score
	])
	return score


## Calcula la normal del mejor plano que pasa por los puntos del trazo,
## usando el método de Newell. Se usa para que la bola de fuego salga
## perpendicular al plano del dibujo (como si el círculo fuera un portal).
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
