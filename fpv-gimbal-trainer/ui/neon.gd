class_name Neon
extends RefCounted
## The look of the game's interface (menus, HUD, pause, results...): neon retro / synthwave. A dark purple night,
## hot pink, cyan and a sunset yellow-orange, glowing borders and texts, a wide italic retro-futuristic typeface
## (Bahnschrift, shipped with Windows; another sans-serif elsewhere). The maps and environments keep their own look.
## apply() sets the theme on the whole game (every Button, OptionButton, Label, panel... inherits it); the custom
## drawn parts (menu tiles, frame guide, charts) use the palette below.

const PINK := Color(1.0, 0.2, 0.72)
const CYAN := Color(0.15, 0.95, 1.0)
const PURPLE := Color(0.58, 0.3, 1.0)
const SUN := Color(1.0, 0.8, 0.25)
const ORANGE := Color(1.0, 0.45, 0.25)
const NIGHT := Color(0.035, 0.01, 0.08)
const PANEL := Color(0.08, 0.02, 0.15, 0.9)
const TEXT := Color(0.98, 0.93, 1.0)
const TEXT_DIM := Color(0.86, 0.78, 0.96, 0.75)
const GOOD := Color(0.25, 1.0, 0.85)    ## a good score / in frame
const MID := Color(1.0, 0.82, 0.3)      ## an average score / near the edge
const BAD := Color(1.0, 0.25, 0.45)     ## a bad score / out of frame

static var _theme: Theme
static var _body: Font
static var _title: FontVariation
static var _bold: FontVariation
static var _bg_shader: Shader
static var _chrome_shader: Shader


static var _applied := false


## Sets the neon theme on the whole game. A CanvasLayer (HUD, pause, results) breaks the inheritance of the theme of
## the root window, so the theme is also merged into the engine's default theme, and its typeface becomes the
## default one: every control of every scene gets the look.
static func apply(tree: SceneTree) -> void:
	if not _applied:
		_applied = true
		var base := body_font()  # (made before the fallback font is replaced: the original stays its fallback)
		ThemeDB.get_default_theme().merge_with(theme())
		ThemeDB.fallback_font = base
		ThemeDB.fallback_font_size = 18
	if tree.root.theme != theme():
		tree.root.theme = theme()


static var _bahn_file: FontFile
static var _bahn_checked := false


## Bahnschrift (a DIN-like typeface shipped with Windows) at a weight (300..700) and a width (75 = condensed ..
## 100 = normal). It is a variable font: it is loaded from its file and its axes are set (asked by name, the system
## would give a regular face or another typeface). Elsewhere: a system sans-serif of that weight.
static func _bahnschrift(weight: int, width: int) -> FontVariation:
	if not _bahn_checked:
		_bahn_checked = true
		var path := OS.get_environment("WINDIR").replace("\\", "/") + "/Fonts/bahnschrift.ttf"
		if OS.get_environment("WINDIR") != "" and FileAccess.file_exists(path):
			var ff := FontFile.new()
			if ff.load_dynamic_font(path) == OK:
				ff.fallbacks = [ThemeDB.fallback_font]
				_bahn_file = ff
	var v := FontVariation.new()
	if _bahn_file != null:
		v.base_font = _bahn_file
		var ts := TextServerManager.get_primary_interface()
		v.variation_opentype = {ts.name_to_tag("wght"): weight, ts.name_to_tag("wdth"): width}
	else:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["DIN Alternate", "Roboto Condensed", "Arial Narrow", "Arial"])
		f.font_weight = weight
		f.fallbacks = [ThemeDB.fallback_font]
		v.base_font = f
	return v


static func body_font() -> Font:
	if _body == null:
		_body = _bahnschrift(400, 100)
	return _body


## Heavy and semi-condensed, upright (a slant made by shearing the glyphs looks uneven: each letter leans and
## shifts on its own): titles, tiles, big buttons.
static func title_font() -> FontVariation:
	if _title == null:
		_title = _bahnschrift(700, 87)
		_title.spacing_glyph = 1
	return _title


## Semi-bold (not slanted): labels of options, values.
static func bold_font() -> FontVariation:
	if _bold == null:
		_bold = _bahnschrift(600, 100)
		_bold.spacing_glyph = 1
	return _bold


## A flat box: background, border, glow (shadow) and margins.
static func box(bg: Color, border: Color, width := 2, glow := 0, radius := 4, margin := 12.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(border.r, border.g, border.b, 0.45)
	sb.shadow_size = glow
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.5
	sb.content_margin_bottom = margin * 0.5
	sb.anti_aliasing = true
	return sb


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 18
	# texts: light, with a soft purple halo (readable on snow as on the night sky)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0.25, 0.02, 0.4, 0.75))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 0)
	t.set_constant("shadow_outline_size", "Label", 6)
	# buttons (and everything that looks like one)
	for kind in ["Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox"]:
		var flat: bool = kind in ["CheckButton", "CheckBox"]
		t.set_stylebox("normal", kind, StyleBoxEmpty.new() if flat else box(Color(0.1, 0.03, 0.2, 0.85), PURPLE, 2, 0))
		t.set_stylebox("hover", kind, StyleBoxEmpty.new() if flat else box(Color(0.17, 0.05, 0.3, 0.92), CYAN, 2, 8))
		t.set_stylebox("pressed", kind, StyleBoxEmpty.new() if flat else box(Color(0.45, 0.06, 0.4, 0.95), PINK, 2, 10))
		t.set_stylebox("hover_pressed", kind, StyleBoxEmpty.new() if flat else box(Color(0.5, 0.08, 0.45, 0.95), PINK, 2, 12))
		t.set_stylebox("disabled", kind, StyleBoxEmpty.new() if flat else box(Color(0.08, 0.04, 0.12, 0.6), Color(0.35, 0.3, 0.45), 1, 0))
		var focus := box(Color(0, 0, 0, 0), CYAN, 2, 10)
		focus.draw_center = false
		t.set_stylebox("focus", kind, focus)
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, Color(0.85, 1.0, 1.0))
		t.set_color("font_pressed_color", kind, Color(1, 1, 1))
		t.set_color("font_hover_pressed_color", kind, Color(1, 1, 1))
		t.set_color("font_focus_color", kind, Color(0.85, 1.0, 1.0))
		t.set_color("font_disabled_color", kind, Color(0.6, 0.55, 0.7, 0.6))
	# drop-down lists
	t.set_stylebox("panel", "PopupMenu", box(Color(0.06, 0.01, 0.12, 0.97), PINK, 2, 12, 4, 8.0))
	t.set_stylebox("hover", "PopupMenu", box(Color(0.55, 0.08, 0.5, 0.7), Color(0, 0, 0, 0), 0, 0, 2, 8.0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 1, 1))
	t.set_color("font_disabled_color", "PopupMenu", Color(0.6, 0.55, 0.7, 0.6))
	t.set_font_size("font_size", "PopupMenu", 17)
	# panels and windows
	var panel := box(PANEL, PINK, 2, 18, 6, 20.0)
	panel.shadow_color = Color(PINK.r, PINK.g, PINK.b, 0.3)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	# text fields
	t.set_stylebox("normal", "LineEdit", box(Color(0.06, 0.01, 0.12, 0.9), PURPLE, 2, 0))
	t.set_stylebox("focus", "LineEdit", box(Color(0.06, 0.01, 0.12, 0.9), CYAN, 2, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	# separators, scroll bars, sliders
	var line := StyleBoxLine.new()
	line.color = Color(PINK.r, PINK.g, PINK.b, 0.55)
	line.thickness = 2
	t.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = Color(PINK.r, PINK.g, PINK.b, 0.55)
	vline.thickness = 2
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)
	for sb_kind in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_kind, box(Color(0.1, 0.03, 0.2, 0.6), Color(0, 0, 0, 0), 0, 0, 4, 4.0))
		t.set_stylebox("grabber", sb_kind, box(Color(PINK.r, PINK.g, PINK.b, 0.6), Color(0, 0, 0, 0), 0, 0, 4, 4.0))
		t.set_stylebox("grabber_highlight", sb_kind, box(PINK, Color(0, 0, 0, 0), 0, 0, 4, 4.0))
		t.set_stylebox("grabber_pressed", sb_kind, box(CYAN, Color(0, 0, 0, 0), 0, 0, 4, 4.0))
	t.set_stylebox("slider", "HSlider", box(Color(0.15, 0.05, 0.28), PURPLE, 1, 0, 3, 2.0))
	t.set_stylebox("grabber_area", "HSlider", box(PINK, Color(0, 0, 0, 0), 0, 6, 3, 2.0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(CYAN, Color(0, 0, 0, 0), 0, 8, 3, 2.0))
	t.set_stylebox("background", "ProgressBar", box(Color(0.1, 0.03, 0.2, 0.8), PURPLE, 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(PINK, Color(0, 0, 0, 0), 0, 6))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.06, 0.01, 0.12, 0.95), CYAN, 1, 6))
	_theme = t
	return t


## A title label: heavy slanted capitals in 80s chrome (turquoise over a white horizon, purple and pink below), a
## thin dark rim and a drop shadow. Without chrome: white with the same rim and shadow.
static func title(l: Label, font_size: int, chrome := true) -> Label:
	l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.02, 0.14, 0.95))
	l.add_theme_constant_override("outline_size", maxi(2, font_size / 26))
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.05, 0.6))
	l.add_theme_constant_override("shadow_outline_size", maxi(2, font_size / 26))
	l.add_theme_constant_override("shadow_offset_x", maxi(2, font_size / 22))
	l.add_theme_constant_override("shadow_offset_y", maxi(2, font_size / 18))
	if chrome:
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		var m := chrome_material()
		l.material = m
		var fit := func(): m.set_shader_parameter("span", maxf(l.size.y, 1.0))
		l.resized.connect(fit)
		fit.call()
	return l


## Small spaced capitals in cyan (subtitles, headings).
static func caps(l: Label, font_size: int, col := CYAN) -> Label:
	l.text = l.text.to_upper()
	l.add_theme_font_override("font", bold_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(col.r, col.g, col.b, 0.35))
	l.add_theme_constant_override("shadow_outline_size", 8)
	return l


## Material of the chrome titles: a sunset gradient (yellow, orange, pink) from the top to the bottom of the label,
## on the white fill of the letters only (the outline and the halo keep their colour). `span` = height of the label.
static func chrome_material() -> ShaderMaterial:
	if _chrome_shader == null:
		_chrome_shader = Shader.new()
		_chrome_shader.code = """
shader_type canvas_item;
uniform float span = 80.0;
varying float ly;
void vertex() {
	ly = VERTEX.y;
}
void fragment() {
	// 80s chrome: turquoise sky fading to a white horizon line, then a hard cut to deep purple, magenta, pale pink
	float t = clamp(ly / span, 0.0, 1.0);
	t = clamp((t - 0.2) / 0.62, 0.0, 1.0);
	vec3 grad;
	if (t < 0.52) {
		float k = t / 0.52;
		grad = mix(vec3(0.05, 0.62, 0.58), vec3(0.45, 0.95, 0.88), smoothstep(0.0, 0.8, k));
		grad = mix(grad, vec3(0.95, 1.0, 1.0), smoothstep(0.82, 1.0, k));
	} else {
		float k = (t - 0.52) / 0.48;
		grad = mix(vec3(0.3, 0.1, 0.42), vec3(0.85, 0.12, 0.62), smoothstep(0.0, 0.6, k));
		grad = mix(grad, vec3(1.0, 0.82, 0.95), smoothstep(0.75, 1.0, k));
	}
	float fill = step(0.95, min(COLOR.r, min(COLOR.g, COLOR.b)));
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(mix(COLOR.rgb, grad, fill), COLOR.a) * tex;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _chrome_shader
	return m


## The animated synthwave night behind the menus: sky, stars, striped sun, neon mountains, moving grid.
static func backdrop() -> ColorRect:
	if _bg_shader == null:
		_bg_shader = Shader.new()
		_bg_shader.code = BACKDROP_SHADER
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = _bg_shader
	r.material = m
	var upd := func():
		m.set_shader_parameter("aspect", r.size.x / maxf(r.size.y, 1.0))
	r.resized.connect(upd)
	return r


const BACKDROP_SHADER := """
shader_type canvas_item;
uniform float aspect = 1.7778;
uniform float horizon = 0.6;
uniform float dim = 0.0;   // darkens everything (pages with a lot of text)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float tri(float t) { return 1.0 - abs(fract(t) * 2.0 - 1.0); }

float ridge(float x) {
	return 0.085 * tri(x * 0.9 + 0.17) + 0.05 * tri(x * 2.3 + 0.61) + 0.022 * tri(x * 5.7 + 0.3);
}

void fragment() {
	vec2 uv = UV;
	float hz = horizon;
	vec3 col;
	if (uv.y < hz) {
		float t = uv.y / hz;
		col = mix(vec3(0.02, 0.005, 0.07), vec3(0.2, 0.02, 0.28), smoothstep(0.1, 0.75, t));
		col = mix(col, vec3(0.75, 0.12, 0.42), smoothstep(0.72, 1.0, t));
		// stars, twinkling
		vec2 cell = floor(vec2(uv.x * aspect, uv.y) * 260.0);
		float h = hash(cell);
		col += step(0.9965, h) * (1.0 - smoothstep(0.3, 0.9, t)) * (0.55 + 0.45 * sin(TIME * 1.7 + h * 80.0)) * vec3(0.9, 0.85, 1.0);
		// sun with its stripes
		vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - (hz - 0.08));
		float R = 0.24;
		float r = length(p);
		float y = p.y / R;
		vec3 sun = mix(vec3(1.0, 0.9, 0.35), vec3(1.0, 0.18, 0.6), smoothstep(-0.9, 0.9, y));
		float gap = (y > -0.1) ? step(fract(y * 7.0 - TIME * 0.18), 0.12 + 0.35 * smoothstep(-0.1, 1.0, y)) : 0.0;
		float disc = (1.0 - smoothstep(R - 0.002, R + 0.002, r)) * (1.0 - gap);
		col += vec3(1.0, 0.25, 0.55) * exp(-max(r - R, 0.0) * 9.0) * 0.45;
		col = mix(col, sun * 1.25, disc);
		// mountains in front of the sun, with a neon ridge
		float x = (uv.x - 0.5) * aspect;
		float top = hz - ridge(x + 3.0);
		if (uv.y > top) {
			float k = (uv.y - top) / max(hz - top, 1e-4);
			col = mix(vec3(0.16, 0.03, 0.3), vec3(0.05, 0.0, 0.12), k);
			col += vec3(0.3, 0.08, 0.6) * (1.0 - smoothstep(0.0, 0.25, fract(x * 18.0 + k * 3.0) * k)) * 0.15;
		}
		float edge = 1.0 - smoothstep(0.0, 0.004, abs(uv.y - top));
		col += mix(vec3(0.2, 0.9, 1.0), vec3(1.0, 0.25, 0.75), 0.5 + 0.5 * sin(x * 2.0)) * edge * 1.2;
	} else {
		// perspective grid running towards the viewer
		float d = uv.y - hz;
		float z = 0.09 / max(d, 1e-4);
		float gx = (uv.x - 0.5) * aspect * z * 2.2;
		float gz = z + TIME * 0.9;
		float fx = abs(fract(gx) - 0.5);
		float fz = abs(fract(gz) - 0.5);
		float wx = fwidth(gx) * 1.2;
		float wz = fwidth(gz) * 1.2;
		float lx = smoothstep(0.5 - wx * 1.5 - 0.015, 0.5, fx);
		float lz = smoothstep(0.5 - wz * 1.5 - 0.015, 0.5, fz);
		float fade = exp(-z * 0.12);
		col = mix(vec3(0.04, 0.0, 0.09), vec3(0.09, 0.0, 0.16), smoothstep(0.0, 0.4, d));
		col += vec3(1.0, 0.2, 0.75) * max(lx, lz) * fade * 1.3;
		col += vec3(1.0, 0.3, 0.6) * exp(-d * 30.0) * 0.55;
	}
	// scan lines and vignette
	col *= 0.92 + 0.08 * sin(FRAGCOORD.y * 2.2);
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 0.9;
	col *= 1.0 - dim;
	COLOR = vec4(col, 1.0);
}
"""
