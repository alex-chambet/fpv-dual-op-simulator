extends Control
## Line chart of the overall score of successive sessions (oldest -> newest), with a moving average.

var scores: Array[float] = []
var window := 5

const COL_GRID := Color(1, 1, 1, 0.12)
const COL_LINE := Color(0.45, 0.7, 1.0, 0.55)
const COL_AVG := Color(1.0, 0.75, 0.2, 1.0)


func set_scores(values: Array[float]) -> void:
	scores = values
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var left := 34.0
	var rect := Rect2(left, 8.0, size.x - left - 8.0, size.y - 24.0)
	for v in [0, 50, 100]:
		var y: float = rect.position.y + rect.size.y * (1.0 - v / 100.0)
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), COL_GRID, 1.0)
		draw_string(font, Vector2(2, y + 4), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	if scores.is_empty():
		draw_string(font, rect.position + Vector2(10, rect.size.y * 0.5), "No session yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.5))
		return
	var n := scores.size()
	var pts := PackedVector2Array()
	var avg := PackedVector2Array()
	for i in n:
		var x := rect.position.x + (rect.size.x * 0.5 if n == 1 else rect.size.x * i / float(n - 1))
		pts.append(Vector2(x, rect.position.y + rect.size.y * (1.0 - clampf(scores[i], 0.0, 100.0) / 100.0)))
		var lo := maxi(0, i - window + 1)
		var sum := 0.0
		for j in range(lo, i + 1):
			sum += scores[j]
		var m := sum / float(i - lo + 1)
		avg.append(Vector2(x, rect.position.y + rect.size.y * (1.0 - m / 100.0)))
	if n > 1:
		draw_polyline(pts, COL_LINE, 1.5)
		draw_polyline(avg, COL_AVG, 2.5)
	for p in pts:
		draw_circle(p, 3.0, COL_LINE.lightened(0.3))
	draw_string(font, Vector2(rect.position.x, size.y - 4), "oldest", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
	draw_string(font, Vector2(rect.end.x - 40, size.y - 4), "latest", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
	draw_string(font, Vector2(rect.position.x + 60, size.y - 4), "- line: each session   - orange: average of %d" % window, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
