class_name MenuTile
extends Button
## A big menu tile in the style of the FPV simulators' menus: a slanted card with a picture (or a drawn icon), a dark
## gradient at the bottom and the title in bold italics. It lights up when hovered or focused (mouse, keyboard or
## controller) and when `selected`.

const BLUE := Color(0.12, 0.55, 1.0)
const AMBER := Color(1.0, 0.68, 0.12)
const BG := Color(0.05, 0.07, 0.12)

var title := ""
var subtitle := ""
## Small text in the top right corner (e.g. the difficulty).
var badge := ""
var picture: Texture2D
## Drawn icon when there is no picture: "gear", "history", "dice", "play", "sandbox".
var icon_kind := ""
var skew := 18.0
var title_size := 28
var selected := false:
	set(v):
		selected = v
		queue_redraw()

static var _bold: FontVariation


static func bold_italic() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.9
		_bold.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
	return _bold


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
	# background: the picture, cropped to fill the tile, or a plain dark card
	if picture != null:
		var ps := picture.get_size()
		var scale := maxf(w / ps.x, h / ps.y)
		var crop := Vector2(w, h) / scale / ps  # visible part, in uv
		var off := (Vector2.ONE - crop) * 0.5
		var uvs := PackedVector2Array()
		for p in pts:
			uvs.append(off + p / Vector2(w, h) * crop)
		var tint := Color(1, 1, 1) if hot else Color(0.78, 0.8, 0.85)
		draw_polygon(pts, PackedColorArray([tint, tint, tint, tint]), uvs, picture)
	else:
		var c := BG.lightened(0.08) if hot else BG
		draw_colored_polygon(pts, c)
	# dark gradient under the title
	var g0 := h * 0.5
	var top_l := Vector2(skew * (1.0 - g0 / h), g0)
	var top_r := Vector2(w - skew * g0 / h, g0)
	draw_polygon(PackedVector2Array([top_l, top_r, Vector2(w - skew, h), Vector2(0.0, h)]),
			PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.78), Color(0, 0, 0, 0.78)]))
	if icon_kind != "":
		_draw_icon(Vector2(w * 0.5, h * 0.43), minf(w, h) * 0.24, AMBER.lightened(0.15) if hot else AMBER)
	# border
	var border := AMBER if hot else BLUE
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, border, 4.0 if hot else 2.5, true)
	# texts
	var font := bold_italic()
	var x := 22.0
	draw_string(font, Vector2(x, h - 20.0), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 40.0, title_size,
			Color(1, 1, 1))
	if subtitle != "":
		draw_string(ThemeDB.fallback_font, Vector2(x + 4.0, h - 26.0 - title_size), subtitle, HORIZONTAL_ALIGNMENT_LEFT,
				w - 50.0, 15, Color(1, 1, 1, 0.8))
	if badge != "":
		var bw := ThemeDB.fallback_font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var bp := Vector2(w - bw - 18.0, 30.0)
		draw_rect(Rect2(bp - Vector2(8.0, 20.0), Vector2(bw + 16.0, 28.0)), Color(0, 0, 0, 0.55))
		draw_string(ThemeDB.fallback_font, bp, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, AMBER)


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
