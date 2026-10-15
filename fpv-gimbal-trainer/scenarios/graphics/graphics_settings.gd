class_name GraphicsSettings
extends RefCounted
## Graphics settings (Paramètres > Graphismes, and in game Échap > Graphismes), saved with the menu preferences:
##  - display: window mode, vertical sync, frame-rate cap, render scale (FSR 1 upscaling below 100 %);
##  - quality: a preset (Basse / Moyenne / Haute / Ultra) that sets every detail below; each detail can then be
##    changed on its own (the preset then shows "Personnalisé"): anti-aliasing, texture filtering, shadows, ambient
##    occlusion, indirect light, light shafts, tree distance, grass and small details, spectators;
##  - image: brightness, contrast, saturation, lens vignette, chromatic aberration, film grain (ui/camera_look.gd);
##  - display of the game: opacity and size of the HUD, opacity and colours of the frame (FrameGuide).

const PREFS_PATH := "user://menu_prefs.json"

## The last preset chosen, 0 low .. 3 ultra; `custom` once a detail differs from it.
static var quality := 2
static var custom := false
const LABELS := ["Basse", "Moyenne", "Haute", "Ultra"]

# --- Display
static var window_mode := 2
const WINDOW_LABELS := ["Plein écran", "Fenêtre sans bordure", "Fenêtre"]
static var vsync := true
static var fps_cap := 0
const FPS_CAPS := [0, 30, 60, 120, 144, 240]
const FPS_LABELS := ["Aucune", "30 i/s", "60 i/s", "120 i/s", "144 i/s", "240 i/s"]
static var render_scale := 0
const SCALES := [1.0, 0.85, 0.77, 0.67, 0.59, 0.5]
const SCALE_LABELS := ["100 % (natif)", "85 %", "77 % (FSR qualité)", "67 % (FSR équilibré)", "59 % (FSR performance)",
		"50 %"]

# --- Details (set by the preset)
static var aa := 2
const AA_LABELS := ["Aucun", "FXAA (rapide)", "SMAA", "TAA (plus doux)"]
static var aniso := 3
const ANISO_LABELS := ["2x", "4x", "8x", "16x"]
static var shadows := 3
const SHADOW_LABELS := ["Désactivées", "Basses", "Moyennes", "Hautes", "Ultra"]
static var ssao := 2
const SSAO_LABELS := ["Désactivée", "Basse", "Moyenne", "Haute"]
static var ssil := false
static var shafts := false
static var trees := 2
const TREE_LABELS := ["Courte", "Moyenne", "Longue", "Très longue"]
static var grass := 2
const GRASS_LABELS := ["Aucune", "Peu", "Normale", "Dense"]
static var crowd := 2
const CROWD_LABELS := ["Peu", "Moyen", "Beaucoup", "Foule"]
## Per preset: aa, aniso, shadows, ssao, ssil, shafts, trees, grass, crowd.
const PRESETS := [
	[1, 0, 1, 0, false, false, 0, 0, 0],
	[2, 1, 2, 1, false, false, 1, 1, 1],
	[2, 3, 3, 2, false, false, 2, 2, 2],
	[2, 3, 4, 3, true, true, 3, 3, 3],
]

# --- Image
static var brightness := 0.0    ## exposure offset, EV (-1 .. +1)
static var contrast := 1.0      ## 0.8 .. 1.25
static var saturation := 1.0    ## 0.5 .. 1.5
static var vignette := true
static var aberration := true
static var grain := true

# --- Display of the game
static var hud_opacity := 1.0   ## 0.2 .. 1
static var hud_size := 1
const HUD_SIZE_LABELS := ["Petite", "Normale", "Grande"]
const HUD_SCALES := [0.8, 1.0, 1.3]
static var frame_opacity := 1.0  ## 0.3 .. 1
static var frame_colors := 0
const FRAME_COLOR_LABELS := ["Néon (cyan, jaune, rose)", "Daltonisme (bleu, jaune, vermillon)",
		"Contraste élevé (blanc, jaune, rouge)"]


# --- Preset and details ------------------------------------------------------------------------------

## Sets the preset and every detail it covers.
static func set_preset(q: int) -> void:
	quality = clampi(q, 0, 3)
	var p: Array = PRESETS[quality]
	aa = p[0]
	aniso = p[1]
	shadows = p[2]
	ssao = p[3]
	ssil = p[4]
	shafts = p[5]
	trees = p[6]
	grass = p[7]
	crowd = p[8]
	custom = false


## A detail of the quality by name (aa, aniso, shadows, ssao, ssil, shafts, trees, grass, crowd).
static func detail(key: String) -> Variant:
	match key:
		"aa": return aa
		"aniso": return aniso
		"shadows": return shadows
		"ssao": return ssao
		"ssil": return ssil
		"shafts": return shafts
		"trees": return trees
		"grass": return grass
		"crowd": return crowd
	return 0


static func set_detail(key: String, v: Variant) -> void:
	match key:
		"aa": aa = int(v)
		"aniso": aniso = int(v)
		"shadows": shadows = int(v)
		"ssao": ssao = int(v)
		"ssil": ssil = bool(v)
		"shafts": shafts = bool(v)
		"trees": trees = int(v)
		"grass": grass = int(v)
		"crowd": crowd = int(v)
	update_custom()


## After a detail changed: the preset becomes "custom" when the details no longer match it.
static func update_custom() -> void:
	custom = PRESETS[clampi(quality, 0, 3)] != [aa, aniso, shadows, ssao, ssil, shafts, trees, grass, crowd]


## Grass clumps per square metre near the camera (0 = no 3D grass).
static func grass_density() -> float:
	return [0.0, 2.0, 4.0, 5.5][clampi(grass, 0, 3)]


## Size of the square of 3D grass around the camera, m.
static func grass_extent() -> float:
	return [0.0, 70.0, 100.0, 130.0][clampi(grass, 0, 3)]


## Distance up to which the trees use their detailed model, m.
static func tree_detail_distance() -> float:
	return [60.0, 110.0, 170.0, 260.0][clampi(trees, 0, 3)]


## Multiplier of the number of small plants / stones scattered by the environments.
static func detail_amount() -> float:
	return [0.3, 0.6, 1.0, 1.4][clampi(grass, 0, 3)]


## Share of the places of a crowd that get someone.
static func crowd_density() -> float:
	return [0.4, 0.6, 0.8, 0.92][clampi(crowd, 0, 3)]


## Colours of the frame: in frame, near the edge, out of frame, thirds grid.
static func frame_palette() -> Array:
	match frame_colors:
		1:
			return [Color(0.0, 0.45, 0.70), Color(0.94, 0.89, 0.26), Color(0.84, 0.37, 0.0), Color(1, 1, 1, 0.5)]
		2:
			return [Color(1, 1, 1), Color(1.0, 0.9, 0.0), Color(1.0, 0.1, 0.1), Color(1, 1, 1, 0.6)]
	return [Neon.GOOD, Neon.MID, Neon.BAD, Color(Neon.PINK, 0.5)]


# --- Saving -------------------------------------------------------------------------------------------

static func _read_prefs() -> Dictionary:
	if FileAccess.file_exists(PREFS_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PREFS_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}


static func save() -> void:
	var prefs := _read_prefs()
	prefs["quality"] = quality
	prefs["graphics"] = {
		"custom": custom, "window_mode": window_mode, "vsync": vsync, "fps_cap": fps_cap,
		"render_scale": render_scale, "aa": aa, "aniso": aniso, "shadows": shadows, "ssao": ssao, "ssil": ssil,
		"shafts": shafts, "trees": trees, "grass": grass, "crowd": crowd, "brightness": brightness,
		"contrast": contrast, "saturation": saturation, "vignette": vignette, "aberration": aberration,
		"grain": grain, "hud_opacity": hud_opacity, "hud_size": hud_size, "frame_opacity": frame_opacity,
		"frame_colors": frame_colors,
	}
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prefs, "\t"))


## Reads the settings from the menu preferences (older files only have the preset).
static func load_prefs(prefs: Dictionary) -> void:
	set_preset(int(prefs.get("quality", quality)))
	var g: Dictionary = prefs.get("graphics", {}) if typeof(prefs.get("graphics", {})) == TYPE_DICTIONARY else {}
	if g.is_empty():
		return
	window_mode = clampi(int(g.get("window_mode", window_mode)), 0, WINDOW_LABELS.size() - 1)
	vsync = bool(g.get("vsync", vsync))
	fps_cap = clampi(int(g.get("fps_cap", fps_cap)), 0, FPS_CAPS.size() - 1)
	render_scale = clampi(int(g.get("render_scale", render_scale)), 0, SCALES.size() - 1)
	if bool(g.get("custom", false)):
		aa = clampi(int(g.get("aa", aa)), 0, AA_LABELS.size() - 1)
		aniso = clampi(int(g.get("aniso", aniso)), 0, ANISO_LABELS.size() - 1)
		shadows = clampi(int(g.get("shadows", shadows)), 0, SHADOW_LABELS.size() - 1)
		ssao = clampi(int(g.get("ssao", ssao)), 0, SSAO_LABELS.size() - 1)
		ssil = bool(g.get("ssil", ssil))
		shafts = bool(g.get("shafts", shafts))
		trees = clampi(int(g.get("trees", trees)), 0, 3)
		grass = clampi(int(g.get("grass", grass)), 0, 3)
		crowd = clampi(int(g.get("crowd", crowd)), 0, 3)
		update_custom()
	brightness = clampf(float(g.get("brightness", brightness)), -1.0, 1.0)
	contrast = clampf(float(g.get("contrast", contrast)), 0.8, 1.25)
	saturation = clampf(float(g.get("saturation", saturation)), 0.5, 1.5)
	vignette = bool(g.get("vignette", vignette))
	aberration = bool(g.get("aberration", aberration))
	grain = bool(g.get("grain", grain))
	hud_opacity = clampf(float(g.get("hud_opacity", hud_opacity)), 0.2, 1.0)
	hud_size = clampi(int(g.get("hud_size", hud_size)), 0, HUD_SCALES.size() - 1)
	frame_opacity = clampf(float(g.get("frame_opacity", frame_opacity)), 0.3, 1.0)
	frame_colors = clampi(int(g.get("frame_colors", frame_colors)), 0, FRAME_COLOR_LABELS.size() - 1)


# --- Applying -----------------------------------------------------------------------------------------

## Window mode, vertical sync and frame-rate cap (the main window). Only calls window_set_mode when the window
## isn't already in the target mode: on macOS, native fullscreen is a toggle, so re-issuing the same fullscreen
## mode (e.g. every time this is called on returning to the menu after a session) drops the window out of it.
static func apply_display() -> void:
	var modes: Array[DisplayServer.WindowMode] = [DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
			DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_WINDOWED]
	var target := modes[clampi(window_mode, 0, 2)]
	if DisplayServer.window_get_mode() != target:
		DisplayServer.window_set_mode(target)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = FPS_CAPS[clampi(fps_cap, 0, FPS_CAPS.size() - 1)]


## Applies the settings to the world environment, the sun and the viewport of a scene.
static func apply(e: Environment, sun: DirectionalLight3D, vp: Viewport) -> void:
	if vp != null:
		vp.screen_space_aa = [Viewport.SCREEN_SPACE_AA_DISABLED, Viewport.SCREEN_SPACE_AA_FXAA,
				Viewport.SCREEN_SPACE_AA_SMAA, Viewport.SCREEN_SPACE_AA_DISABLED][clampi(aa, 0, 3)]
		vp.use_taa = aa == 3
		vp.anisotropic_filtering_level = [Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X, Viewport.ANISOTROPY_8X,
				Viewport.ANISOTROPY_16X][clampi(aniso, 0, 3)]
		var s: float = SCALES[clampi(render_scale, 0, SCALES.size() - 1)]
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = s
		vp.fsr_sharpness = 0.2
	var sh := clampi(shadows, 0, 4)
	if sh > 0:
		RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096, 4096, 8192][sh], true)
		RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD,
				RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
				RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][sh])
	var ao := clampi(ssao, 0, 3)
	RenderingServer.environment_set_ssao_quality([RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
			RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
			RenderingServer.ENV_SSAO_QUALITY_HIGH][ao], true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
	if e != null:
		e.ssao_enabled = ao >= 1
		e.ssil_enabled = ssil
		e.ssil_radius = 6.0
		e.ssil_intensity = 0.8
		# light shafts between the trees: volumetric fog lit by the sun, strongly forward-scattering
		var density: float = e.get_meta("light_shafts", 0.0)
		e.volumetric_fog_enabled = shafts and density > 0.0
		if e.volumetric_fog_enabled:
			e.volumetric_fog_density = density
			e.volumetric_fog_albedo = Color(0.92, 0.94, 0.96)
			e.volumetric_fog_anisotropy = 0.6
			e.volumetric_fog_length = 90.0
			e.volumetric_fog_detail_spread = 2.0
			e.volumetric_fog_ambient_inject = 0.05
			e.volumetric_fog_sky_affect = 0.0
	if sun != null:
		sun.shadow_enabled = sh > 0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sh <= 1 \
				else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_blend_splits = sh >= 3


## Re-applies the settings to the running scene (after a change in the pause menu).
static func apply_live(tree: SceneTree) -> void:
	var scn := tree.current_scene
	if scn != null and scn.has_method("apply_graphics"):
		scn.apply_graphics()
