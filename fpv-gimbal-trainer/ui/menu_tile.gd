class_name MenuTile
extends Button
## A big menu tile in the style of the FPV simulators' menus, in the neon retro look (Neon): a slanted card with a
## picture (or a drawn icon), a purple gradient at the bottom and the title in bold italics. Cyan neon border; it
## turns hot pink and glows when hovered or focused (mouse, keyboard or controller) and when `selected`.

const BLUE := Neon.CYAN
const AMBER := Neon.PINK
const BG := Color(0.08, 0.02, 0.16, 0.92)

var title := ""
var subtitle := ""
## Small text in the top right corner (e.g. the difficulty).
var badge := ""
var picture: Texture2D
## Drawn icon when there is no picture: "gear", "history", "dice", "play".
var icon_kind := ""
var skew := 18.0
var title_size := 28
var selected := false:
	set(v):
		selected = v
		queue_redraw()


static func bold_italic() -> FontVariation:
	return Neon.title_font()


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)
	# no default focus frame or hover box: the tile draws its own
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())


func _draw() -> void:
	var w := size.x
	var h := size.y
	var hot := is_hovered() or has_focus() or selected
	var pts := PackedVector2Array([Vector2(skew, 0.0), Vector2(w, 0.0), Vector2(w - skew, h), Vector2(0.0, h)])
	var outline := pts.duplicate()
	outline.append(pts[0])
	# neon glow around a lit tile (drawn first, under the card)
	if hot:
		draw_polyline(outline, Color(Neon.PINK, 0.12), 18.0, true)
		draw_polyline(outline, Color(Neon.PINK, 0.25), 9.0, true)
	# background: the picture, cropped to fill the tile, or a plain night-purple card
	if picture != null:
		var ps := picture.get_size()
		var scale := maxf(w / ps.x, h / ps.y)
		var crop := Vector2(w, h) / scale / ps  # visible part, in uv
		var off := (Vector2.ONE - crop) * 0.5
		var uvs := PackedVector2Array()
		for p in pts:
			uvs.append(off + p / Vector2(w, h) * crop)
		var tint := Color(1, 1, 1) if hot else Color(0.78, 0.72, 0.9)
		draw_polygon(pts, PackedColorArray([tint, tint, tint, tint]), uvs, picture)
	else:
		draw_colored_polygon(pts, BG.lightened(0.06) if hot else BG)
	# purple gradient under the title
	var g0 := h * 0.45
	var top_l := Vector2(skew * (1.0 - g0 / h), g0)
	var top_r := Vector2(w - skew * g0 / h, g0)
	var deep := Color(0.1, 0.0, 0.2, 0.88)
	draw_polygon(PackedVector2Array([top_l, top_r, Vector2(w - skew, h), Vector2(0.0, h)]),
			PackedColorArray([Color(deep, 0.0), Color(deep, 0.0), deep, deep]))
	if icon_kind != "":
		var r := minf(w, h) * 0.24
		var c := Vector2(w * 0.5, h * 0.42)
		_draw_icon(c, r * 1.04, Color(Neon.PINK, 0.35))  # halo
		_draw_icon(c, r, Neon.SUN.lightened(0.2) if hot else Neon.SUN)
	draw_polyline(outline, Neon.PINK if hot else Color(Neon.CYAN, 0.85), 3.0 if hot else 2.0, true)
	# texts: white title with a thin dark rim and a drop shadow (pink when the tile is lit)
	var font := Neon.title_font()
	var x := 24.0
	var title_pos := Vector2(x, h - 20.0)
	var up := title.to_upper()
	var sh := Vector2(2.0, 3.0) * maxf(title_size / 28.0, 1.0)
	draw_string_outline(font, title_pos + sh, up, HORIZONTAL_ALIGNMENT_LEFT, w - 40.0, title_size, 3,
			Color(Neon.PINK, 0.7) if hot else Color(0, 0, 0.05, 0.6))
	draw_string(font, title_pos + sh, up, HORIZONTAL_ALIGNMENT_LEFT, w - 40.0, title_size,
			Color(Neon.PINK, 0.7) if hot else Color(0, 0, 0.05, 0.6))
	draw_string_outline(font, title_pos, up, HORIZONTAL_ALIGNMENT_LEFT, w - 40.0, title_size, 3, Color(0.06, 0.02, 0.14, 0.9))
	draw_string(font, title_pos, up, HORIZONTAL_ALIGNMENT_LEFT, w - 40.0, title_size, Color(1, 1, 1))
	if subtitle != "":
		draw_string(Neon.body_font(), Vector2(x + 4.0, h - 28.0 - title_size), subtitle, HORIZONTAL_ALIGNMENT_LEFT,
				w - 50.0, 16, Color(Neon.CYAN.lightened(0.5), 0.9))
	if badge != "":
		var bf := Neon.bold_font()
		var bw := bf.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var bp := Vector2(w - bw - 18.0, 30.0)
		draw_rect(Rect2(bp - Vector2(8.0, 20.0), Vector2(bw + 16.0, 28.0)), Color(0.08, 0.0, 0.16, 0.75))
		draw_string(bf, bp, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Neon.SUN)

func _draw_icon(c: Vector2, r: float, col: Color) -> void:
	match icon_kind:
		"gear":
			for k in 8:
				var a := TAU * k / 8.0
				var d := Vector2(cos(a), sin(a))
				var t := Vector2(-d.y, d.x)
				draw_colored_polygon(PackedVector2Array([c + d * r * 0.7 + t * r * 0.16, c + d * r * 1.02 + t * r * 0.12,
						c + d * r * 1.02 - t * r * 0.12, c + d * r * 0.7 - t * r * 0.16]), col)
			draw_arc(c, r * 0.62, 0.0, TAU, 48, col, r * 0.26, true)
		"history":
			draw_arc(c, r * 0.85, -PI * 0.3, PI * 1.45, 48, col, r * 0.16, true)
			var a0 := -PI * 0.3
			var tip := c + Vector2(cos(a0), sin(a0)) * r * 0.85
			draw_colored_polygon(PackedVector2Array([tip + Vector2(r * 0.32, 0.0), tip + Vector2(-r * 0.22, -r * 0.3),
					tip + Vector2(-r * 0.12, r * 0.3)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.25, -r * 0.35), c + Vector2(r * 0.38, 0.0),
					c + Vector2(-r * 0.25, r * 0.35)]), col)
		"dice":
			var s := r * 0.8
			draw_rect(Rect2(c - Vector2(s, s), Vector2(2.0 * s, 2.0 * s)), col, false, r * 0.13)
			for p in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.0, 0.0), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
				draw_circle(c + p * s, r * 0.13, col)
		"play":
			draw_arc(c, r, 0.0, TAU, 48, col, r * 0.12, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.32, -r * 0.48), c + Vector2(r * 0.52, 0.0),
					c + Vector2(-r * 0.32, r * 0.48)]), col)
