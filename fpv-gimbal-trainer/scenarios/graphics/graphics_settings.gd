class_name GraphicsSettings
extends RefCounted
## Graphics quality (pause menu > Graphismes), saved with the menu preferences. It sets the anti-aliasing,
## shadows, ambient occlusion, indirect light, texture filtering and the amount of vegetation (grass, plants).

## 0 low, 1 medium, 2 high, 3 ultra.
static var quality := 2
const LABELS := ["Basse", "Moyenne", "Haute", "Ultra"]
const PREFS_PATH := "user://menu_prefs.json"


static func save() -> void:
	var prefs := {}
	if FileAccess.file_exists(PREFS_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PREFS_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			prefs = parsed
	prefs["quality"] = quality
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prefs, "\t"))


## Grass clumps per square metre near the camera (0 = no 3D grass).
static func grass_density() -> float:
	return [0.0, 2.0, 4.0, 5.5][clampi(quality, 0, 3)]


## Size of the square of 3D grass around the camera, m.
static func grass_extent() -> float:
	return [0.0, 70.0, 100.0, 130.0][clampi(quality, 0, 3)]


## Distance up to which the trees use their detailed model, m.
static func tree_detail_distance() -> float:
	return [60.0, 110.0, 170.0, 260.0][clampi(quality, 0, 3)]


## Multiplier of the number of small plants / stones scattered by the environments.
static func detail_amount() -> float:
	return [0.3, 0.6, 1.0, 1.4][clampi(quality, 0, 3)]


## Applies the settings to the world environment, the sun and the viewport of a scene.
static func apply(e: Environment, sun: DirectionalLight3D, vp: Viewport) -> void:
	var q := clampi(quality, 0, 3)
	if vp != null:
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 0 else Viewport.SCREEN_SPACE_AA_SMAA
		vp.anisotropic_filtering_level = [Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X, Viewport.ANISOTROPY_16X,
				Viewport.ANISOTROPY_16X][q]
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD,
			RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH][q])
	RenderingServer.environment_set_ssao_quality([RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
			RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
			RenderingServer.ENV_SSAO_QUALITY_HIGH][q], true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
	if e != null:
		e.ssao_enabled = q >= 1
		e.ssil_enabled = q >= 3
		e.ssil_radius = 6.0
		e.ssil_intensity = 0.8
		# light shafts between the trees: volumetric fog lit by the sun, strongly forward-scattering
		var shafts: float = e.get_meta("light_shafts", 0.0)
		e.volumetric_fog_enabled = q >= 3 and shafts > 0.0
		if e.volumetric_fog_enabled:
			e.volumetric_fog_density = shafts
			e.volumetric_fog_albedo = Color(0.92, 0.94, 0.96)
			e.volumetric_fog_anisotropy = 0.6
			e.volumetric_fog_length = 90.0
			e.volumetric_fog_detail_spread = 2.0
			e.volumetric_fog_ambient_inject = 0.05
			e.volumetric_fog_sky_affect = 0.0
	if sun != null:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == 0 \
				else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_blend_splits = q >= 2


## Re-applies the settings to the running scene (after a change in the pause menu).
static func apply_live(tree: SceneTree) -> void:
	var scn := tree.current_scene
	if scn != null and scn.has_method("apply_graphics"):
		scn.apply_graphics()
