class_name EnvironmentStyle
extends Resource
## Look and layout of an environment, as data: one .tres per environment tag in
## res://scenarios/environments/styles/<tag>.tres. The tags neige, route_montagne and foret use a
## dedicated builder; every other tag uses the generic builder (ground, markings, a few props)
## configured by this sheet. To add an environment, duplicate a style file and edit it.

@export var tag := ""
@export var display_name := ""
@export_enum("generic", "snow", "mountain_road", "forest", "departementale") var builder := "generic"

@export_group("Sky and light")
@export var sky_top_color := Color(0.385, 0.454, 0.55)
@export var sky_horizon_color := Color(0.646, 0.656, 0.67)
@export var sky_curve := 0.15
@export var ground_horizon_color := Color(0.646, 0.656, 0.67)
@export var ground_bottom_color := Color(0.2, 0.169, 0.133)
@export var ground_curve := 0.02
@export var sun_angle_max := 30.0
@export var sun_curve := 0.15
@export var sun_color := Color(1, 1, 1)
@export var sun_energy := 1.6
@export var sun_angular_distance := 0.5
@export_range(5.0, 85.0, 1.0, "suffix:°") var sun_elevation := 40.0
@export_range(-180.0, 180.0, 1.0, "suffix:°") var sun_azimuth := 30.0
@export var shadow_max_distance := 250.0
@export var ambient_energy := 0.9

@export_group("Post-processing")
@export var ssao_radius := 2.0
@export var ssao_intensity := 2.5
@export var glow_intensity := 0.4
@export var glow_bloom := 0.0
@export var glow_hdr_threshold := 1.1
@export var adjustment_contrast := 1.05
@export var adjustment_saturation := 1.08

@export_group("Fog")
@export var fog_enabled := true
@export var fog_color := Color(0.72, 0.8, 0.9)
@export var fog_density := 0.0016
@export var fog_sun_scatter := 0.2
@export var fog_sky_affect := 0.6
@export var fog_aerial_perspective := 0.0

@export_group("Ground (generic builder)")
## flat / rolling / slope (downhill along +Z) / wall (steep climb along +Z) / ridge / river /
## mountains (huge hills, for flying) / water.
@export_enum("flat", "rolling", "slope", "wall", "ridge", "river", "mountains", "water") var terrain_kind := "flat"
@export var ground_color_dark := Color(0.3, 0.33, 0.22)
@export var ground_color_light := Color(0.55, 0.52, 0.42)
@export var ground_relief := 0.8
@export var ground_roughness := 0.9
@export var ground_texture_frequency := 0.03
## Grade of the slope / wall (height per metre along Z).
@export var slope := 0.0
## Amplitude of the bumps / hills, m.
@export var bump := 0.0
## River: half width of the channel, m.
@export var river_half_width := 14.0
## Terrain margin around the paths, m.
@export var margin := 60.0
## Terrain cell size, m (0 = automatic).
@export var cell := 0.0
@export var has_water := false
@export var water_color := Color(0.1, 0.35, 0.5)
@export var water_level := 0.0

@export_group("Markings, walls and props (generic builder)")
@export_enum("none", "pitch", "rink", "tennis", "court") var markings := "none"
@export var marking_color := Color(1, 1, 1)
## Perimeter around the playing zone: none / boards (low rink boards) / walls (tall) / fence (posts).
@export_enum("none", "boards", "walls", "fence") var perimeter := "none"
@export_enum("none", "trees", "rocks", "boxes", "buildings", "stands", "posts", "buoys", "clouds") var prop_kind := "none"
@export var prop_count := 20
@export var prop_color := Color(0.4, 0.4, 0.4)
## What hides the subject on a line of sight (obstacles of the training sessions).
@export_enum("trees", "rocks", "walls", "players", "clouds", "none") var occluder_kind := "rocks"
