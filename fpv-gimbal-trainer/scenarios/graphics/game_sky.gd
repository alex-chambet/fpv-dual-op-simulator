class_name GameSky
extends RefCounted
## Sky of the scenarios: the colour gradient of the style (same formulas as ProceduralSkyMaterial), a sun with a
## halo, and a layer of fair-weather clouds lit by the sun (bright tops, grey undersides, silver lining near the
## sun) fading into the haze at the horizon. The clouds do not move (a moving sky would rebuild the ambient light
## every frame).

const CODE := """
shader_type sky;
render_mode use_debanding;

uniform vec3 top_color : source_color;
uniform vec3 horizon_color : source_color;
uniform vec3 ground_horizon : source_color;
uniform vec3 ground_bottom : source_color;
uniform float sky_curve = 0.15;
uniform float ground_curve = 0.02;
uniform float sun_angle_max = 0.44;
uniform float sun_curve = 0.15;
uniform sampler2D clouds_tex : filter_linear_mipmap, repeat_enable;
uniform float coverage = 0.35;
uniform float cloud_scale = 0.9;
uniform float cloud_shade = 0.55;
uniform vec2 cloud_offset = vec2(0.0);

float density(vec2 p) {
	float n = texture(clouds_tex, p).r * 0.62 + texture(clouds_tex, p * 2.7 + vec2(0.37, 0.11)).r * 0.26
			+ texture(clouds_tex, p * 7.9 + vec2(0.71, 0.53)).r * 0.12;
	return smoothstep(1.0 - coverage - 0.1, 1.0 - coverage + 0.22, n);
}

void sky() {
	vec3 d = EYEDIR;
	float v_angle = acos(clamp(d.y, -1.0, 1.0));
	vec3 col;
	if (d.y >= 0.0) {
		float c = 1.0 - v_angle / (PI * 0.5);
		col = mix(horizon_color, top_color, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	} else {
		float c = (v_angle - PI * 0.5) / (PI * 0.5);
		col = mix(ground_horizon, ground_bottom, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
	}
	vec3 sun_col = vec3(1.0);
	vec3 sun_dir = vec3(0.0, 1.0, 0.0);
	float sun_dot = 0.0;
	if (LIGHT0_ENABLED) {
		sun_dir = LIGHT0_DIRECTION;
		sun_col = LIGHT0_COLOR * LIGHT0_ENERGY;
		sun_dot = dot(d, sun_dir);
		float sun_angle = acos(clamp(sun_dot, -1.0, 1.0));
		if (sun_angle < LIGHT0_SIZE) {
			col = sun_col * 6.0;
		} else if (sun_angle < sun_angle_max) {
			float c2 = (sun_angle - LIGHT0_SIZE) / (sun_angle_max - LIGHT0_SIZE);
			col = mix(sun_col, col, clamp(1.0 - pow(1.0 - c2, 1.0 / sun_curve), 0.0, 1.0));
		}
		// wide forward-scattering glow
		col += sun_col * 0.12 * pow(max(sun_dot, 0.0), 6.0) * smoothstep(-0.05, 0.2, d.y);
	}
	if (d.y > 0.0 && coverage > 0.0) {
		// clouds on a flat layer: far clouds are squeezed towards the horizon
		vec2 p = d.xz / (d.y + 0.08) * 0.11 * cloud_scale + cloud_offset;
		float dens = density(p);
		if (dens > 0.002) {
			vec2 to_sun = normalize(sun_dir.xz + vec2(0.0001)) * 0.018 * cloud_scale;
			float thick = density(p + to_sun) * 0.55 + density(p + to_sun * 2.6) * 0.45;
			vec3 lit = sun_col * 0.78 + top_color * 0.45;
			vec3 shade = mix(horizon_color, top_color, 0.35) * 0.62 + sun_col * 0.08;
			vec3 ccol = mix(lit, shade, clamp(thick * cloud_shade * 1.6 * dens, 0.0, 1.0));
			// thin edges glow when the sun is behind them
			ccol += sun_col * pow(max(sun_dot, 0.0), 10.0) * (1.0 - dens) * 1.2;
			float fade = smoothstep(0.0, 0.16, d.y);
			ccol = mix(horizon_color * 1.05, ccol, smoothstep(0.0, 0.3, d.y));
			col = mix(col, ccol, clamp(dens * 1.15, 0.0, 1.0) * fade);
		}
	}
	COLOR = col;
}
"""

static var _shader: Shader
static var _clouds: NoiseTexture2D


static func make(style: EnvironmentStyle) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.008
		n.fractal_octaves = 5
		n.fractal_gain = 0.55
		_clouds = NoiseTexture2D.new()
		_clouds.noise = n
		_clouds.seamless = true
		_clouds.normalize = true
		_clouds.width = 512
		_clouds.height = 512
		_clouds.generate_mipmaps = true
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("top_color", style.sky_top_color)
	m.set_shader_parameter("horizon_color", style.sky_horizon_color)
	m.set_shader_parameter("ground_horizon", style.ground_horizon_color)
	m.set_shader_parameter("ground_bottom", style.ground_bottom_color)
	m.set_shader_parameter("sky_curve", style.sky_curve)
	m.set_shader_parameter("ground_curve", style.ground_curve)
	m.set_shader_parameter("sun_angle_max", deg_to_rad(style.sun_angle_max))
	m.set_shader_parameter("sun_curve", style.sun_curve)
	m.set_shader_parameter("clouds_tex", _clouds)
	m.set_shader_parameter("coverage", style.cloud_coverage)
	m.set_shader_parameter("cloud_scale", style.cloud_scale)
	m.set_shader_parameter("cloud_offset", Vector2(0.13, 0.41))
	return m
