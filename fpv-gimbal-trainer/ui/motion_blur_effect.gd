class_name MotionBlurEffect
extends CompositorEffect
## Per-object motion blur (compute shaders run by the renderer after the opaque and transparent passes).
##
## Every pixel is blurred along ITS OWN motion on screen during the shutter time, read from the motion vectors of the
## renderer (they hold the movement of the camera AND of each object). A car followed by the camera hardly moves on
## screen, so it stays sharp while the landscape streaks behind it; a car crossing a still shot is blurred over a sharp
## background. The sky has no motion vectors: its motion comes from the rotation of the camera.
##
## Reconstruction filter after McGuire et al. 2012 / Jimenez 2014 (the method of the game engines):
##  1. prepare: copy of the image, blur radius (pixels) and distance (m) of every pixel;
##  2. tiles: largest radius in each tile (tile = largest allowed radius), then among the 3 x 3 neighbouring tiles;
##  3. gather: each pixel averages samples taken along the neighbourhood's and its own motion; a sample counts only if
##     its blur reaches the pixel (a sharp object in front hides the streaks of the background, a moving object in
##     front smears over a sharp background). Missing samples are filled with the pixel itself.
## The colour is the HDR image before tonemapping, so bright lights streak like on a real sensor.

## Shutter time / frame time (blur length = motion during one frame x this). 0 = no blur this frame. Set by MotionBlur.
var shutter_scale := 0.0
var near := 0.05
var far := 4000.0
## 0 normal; 1 checks the motion vectors against the camera rotation (green ok, red wrong, blue sky);
## 2 checks the depth: green where the distance is debug_value (+-5 %), red elsewhere.
var debug_mode := 0
var debug_value := 0.0

## Largest blur radius, fraction of the image width (the blur length is twice that).
const MAX_RADIUS := 0.04
const MAX_PAIRS := 20
const CTX := &"motion_blur"

const HEADER := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(push_constant, std430) uniform Params {
	vec4 rel0;   // rotation current camera -> previous camera (columns)
	vec4 rel1;
	vec4 rel2;
	vec4 lens;   // tan(half fov x), tan(half fov y), near, far
	vec4 info;   // width, height, shutter scale, largest radius (px)
	vec4 info2;  // tile size (px), max sample pairs, debug mode, axis (tiles) / debug value (prepare)
} p;
"""

const PREPARE := """
layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2) uniform sampler2D velocity_tex;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D copy_image;
layout(rgba16f, set = 0, binding = 4) uniform restrict writeonly image2D vz_image;

// Screen motion of a point at infinity, from the camera rotation only. Same convention as the renderer's motion
// vectors: uv units, previous - current.
vec2 rotation_motion(vec2 uv) {
	vec3 dir = vec3((uv.x * 2.0 - 1.0) * p.lens.x, (1.0 - uv.y * 2.0) * p.lens.y, -1.0);
	vec3 q = mat3(p.rel0.xyz, p.rel1.xyz, p.rel2.xyz) * dir;
	if (q.z > -0.001) {
		return vec2(0.0);
	}
	vec2 prev = vec2(0.5 + 0.5 * q.x / (-q.z * p.lens.x), 0.5 - 0.5 * q.y / (-q.z * p.lens.y));
	return prev - uv;
}

void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec2 size = p.info.xy;
	if (pix.x >= int(size.x) || pix.y >= int(size.y)) {
		return;
	}
	vec4 color = imageLoad(color_image, pix);
	vec2 uv = (vec2(pix) + 0.5) / size;
	float d = texelFetch(depth_tex, pix, 0).x;
	bool sky = d <= 0.0;  // reversed depth: the far plane is 0
	vec2 motion = sky ? rotation_motion(uv) : texelFetch(velocity_tex, pix, 0).xy;
	float z = sky ? p.lens.w : p.lens.z * p.lens.w / (p.lens.z + d * (p.lens.w - p.lens.z));
	int debug = int(p.info2.z);
	if (debug == 1) {
		vec2 a = rotation_motion(uv) * size;
		vec2 b = motion * size;
		color = sky ? vec4(0.0, 0.0, 1.0, 1.0) : (length(a - b) < 0.05 * max(length(a), 2.0) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0));
	} else if (debug == 2) {
		color = abs(z - p.info2.w) < 0.05 * p.info2.w ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
	}
	imageStore(copy_image, pix, color);
	vec2 v = motion * size * (0.5 * p.info.z);  // blur radius vector, pixels
	float len = length(v);
	if (len > p.info.w) {
		v *= p.info.w / len;
	}
	imageStore(vz_image, pix, vec4(v, z, 0.0));
}
"""

## Largest radius over a row (axis 0) or a column (axis 1) of tile-size pixels.
const TILE := """
layout(set = 0, binding = 0) uniform sampler2D src_tex;
layout(rg16f, set = 0, binding = 1) uniform restrict writeonly image2D dst_image;

void main() {
	ivec2 o = ivec2(gl_GlobalInvocationID.xy);
	ivec2 dst = imageSize(dst_image);
	if (o.x >= dst.x || o.y >= dst.y) {
		return;
	}
	ivec2 src = textureSize(src_tex, 0);
	int k = int(p.info2.x);
	bool vertical = p.info2.w > 0.5;
	vec2 best = vec2(0.0);
	float best_len = 0.0;
	for (int i = 0; i < k; i++) {
		ivec2 s = vertical ? ivec2(o.x, o.y * k + i) : ivec2(o.x * k + i, o.y);
		if (s.x >= src.x || s.y >= src.y) {
			break;
		}
		vec2 v = texelFetch(src_tex, s, 0).xy;
		float l = dot(v, v);
		if (l > best_len) {
			best_len = l;
			best = v;
		}
	}
	imageStore(dst_image, o, vec4(best, 0.0, 0.0));
}
"""

const NEIGHBOR := """
layout(set = 0, binding = 0) uniform sampler2D tile_tex;
layout(rg16f, set = 0, binding = 1) uniform restrict writeonly image2D dst_image;

void main() {
	ivec2 o = ivec2(gl_GlobalInvocationID.xy);
	ivec2 n = textureSize(tile_tex, 0);
	if (o.x >= n.x || o.y >= n.y) {
		return;
	}
	vec2 best = vec2(0.0);
	float best_len = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 v = texelFetch(tile_tex, clamp(o + ivec2(dx, dy), ivec2(0), n - 1), 0).xy;
			float l = dot(v, v);
			if (l > best_len) {
				best_len = l;
				best = v;
			}
		}
	}
	imageStore(dst_image, o, vec4(best, 0.0, 0.0));
}
"""

const GATHER := """
layout(set = 0, binding = 0) uniform sampler2D copy_tex;
layout(set = 0, binding = 1) uniform sampler2D vz_tex;
layout(set = 0, binding = 2) uniform sampler2D neighbor_tex;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D color_image;

float noise_at(vec2 q) {
	return fract(52.9829189 * fract(dot(q, vec2(0.06711056, 0.00583715))));
}

void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec2 size = p.info.xy;
	if (pix.x >= int(size.x) || pix.y >= int(size.y)) {
		return;
	}
	vec4 center = texelFetch(copy_tex, pix, 0);
	float k = p.info2.x;
	float noise = noise_at(vec2(pix));
	// tile of the pixel, jittered by up to a quarter of a tile so the tile edges do not show
	vec2 jitter = (vec2(noise, noise_at(vec2(pix.y, pix.x) + 17.0)) - 0.5) * 0.5 * k;
	ivec2 nt = textureSize(neighbor_tex, 0);
	ivec2 tile = clamp(ivec2((vec2(pix) + 0.5 + jitter) / k), ivec2(0), nt - 1);
	vec2 vn = texelFetch(neighbor_tex, tile, 0).xy;
	float len_n = length(vn);
	if (len_n < 0.5 || p.info2.z > 0.5) {
		imageStore(color_image, pix, center);
		return;
	}
	vec4 cvz = texelFetch(vz_tex, pix, 0);
	vec2 vc = cvz.xy;
	float len_c = length(vc);
	float zc = cvz.z;
	vec2 dir_c = len_c > 0.5 ? vc : vn;
	// about one sample pair every 2 px at 1600 px wide (the same spacing on screen at any resolution)
	int pairs = int(clamp(ceil(len_n / max(2.0, size.x / 800.0)), 4.0, p.info2.y));
	vec2 texel = 1.0 / size;
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < pairs; i++) {
		vec2 dir = (i % 2 == 0) ? vn : dir_c;
		float t = (float(i) + noise) / float(pairs);
		for (int side = 0; side < 2; side++) {
			vec2 off = dir * (side == 0 ? t : -t);
			vec2 suv = clamp((vec2(pix) + 0.5 + off) * texel, texel * 0.5, 1.0 - texel * 0.5);
			vec4 svz = textureLod(vz_tex, suv, 0.0);
			float dist = length(off);
			// x: the sample is behind the pixel (the pixel's own blur covers it), y: it is in front (its blur covers the pixel)
			float dz = (svz.z - zc) / max(0.03 * min(zc, svz.z), 0.1);
			vec2 depth_cmp = clamp(vec2(0.5 + dz, 0.5 - dz), 0.0, 1.0);
			vec2 spread_cmp = clamp(vec2(len_c, length(svz.xy)) - dist + 1.0, 0.0, 1.0);
			float w = dot(depth_cmp, spread_cmp);
			acc += w * textureLod(copy_tex, suv, 0.0).rgb;
			wsum += w;
		}
	}
	float n = float(pairs * 2);
	imageStore(color_image, pix, vec4((acc + center.rgb * max(n - wsum, 0.0)) / n, center.a));
}
"""

var _rd: RenderingDevice
var _shaders := {}
var _pipelines := {}
var _linear := RID()
var _nearest := RID()
var _prev_basis := Basis.IDENTITY
var _has_prev := false


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true
	RenderingServer.call_on_render_thread(_create)


func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	for key in ["prepare", "tile", "neighbor", "gather"]:
		var body: String = {"prepare": PREPARE, "tile": TILE, "neighbor": NEIGHBOR, "gather": GATHER}[key]
		var src := RDShaderSource.new()
		src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		src.source_compute = HEADER + body
		var spirv := _rd.shader_compile_spirv_from_source(src)
		if spirv == null or spirv.compile_error_compute != "":
			push_error("Motion blur shader '%s': %s" % [key, spirv.compile_error_compute if spirv else "?"])
			return
		var shader := _rd.shader_create_from_spirv(spirv, "motion_blur_" + key)
		if not shader.is_valid():
			return
		_shaders[key] = shader
		_pipelines[key] = _rd.compute_pipeline_create(shader)
	var st := RDSamplerState.new()
	st.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	st.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_nearest = _rd.sampler_create(st)
	st.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	st.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_linear = _rd.sampler_create(st)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for s in _shaders.values():  # frees the pipelines and uniform sets made from them too
			if s.is_valid():
				_rd.free_rid(s)
		for s in [_linear, _nearest]:
			if s.is_valid():
				_rd.free_rid(s)


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or _rd == null or _pipelines.size() < 4:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data()
	if buffers == null or scene == null:
		return
	# rotation of the camera since the previous frame (motion of the sky)
	var basis := scene.get_cam_transform().basis.orthonormalized()
	var rel := _prev_basis.transposed() * basis if _has_prev else Basis.IDENTITY
	_prev_basis = basis
	_has_prev = true
	if shutter_scale <= 0.0 and debug_mode == 0:
		return
	var size := buffers.get_internal_size()
	if size.x < 16 or size.y < 16:
		return
	var proj := scene.get_cam_projection()
	var k := maxi(4, ceili(size.x * MAX_RADIUS))
	var tiles := Vector2i(ceili(size.x / float(k)), ceili(size.y / float(k)))
	_ensure_textures(buffers, size, tiles)

	var push := PackedFloat32Array([
		rel.x.x, rel.x.y, rel.x.z, 0.0,
		rel.y.x, rel.y.y, rel.y.z, 0.0,
		rel.z.x, rel.z.y, rel.z.z, 0.0,
		1.0 / absf(proj.x.x), 1.0 / absf(proj.y.y), near, far,
		size.x, size.y, shutter_scale, float(k),
		float(k), float(MAX_PAIRS), float(debug_mode), debug_value,
	])
	var copy := buffers.get_texture(CTX, &"copy")
	var vz := buffers.get_texture(CTX, &"vz")
	var rows := buffers.get_texture(CTX, &"rows")
	var tile_max := buffers.get_texture(CTX, &"tile_max")
	var neighbor := buffers.get_texture(CTX, &"neighbor")
	var full := Vector2i(ceili(size.x / 8.0), ceili(size.y / 8.0))
	var small := Vector2i(ceili(tiles.x / 8.0), ceili(tiles.y / 8.0))
	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		var velocity := buffers.get_velocity_layer(view)
		if not color.is_valid() or not depth.is_valid() or not velocity.is_valid():
			return
		_run("prepare", [_image(0, color), _sampled(1, _nearest, depth), _sampled(2, _nearest, velocity),
				_image(3, copy), _image(4, vz)], push, full)
		if debug_mode == 0:
			push[23] = 0.0
			_run("tile", [_sampled(0, _nearest, vz), _image(1, rows)], push, Vector2i(small.x, full.y))
			push[23] = 1.0
			_run("tile", [_sampled(0, _nearest, rows), _image(1, tile_max)], push, small)
			_run("neighbor", [_sampled(0, _nearest, tile_max), _image(1, neighbor)], push, small)
		_run("gather", [_sampled(0, _linear, copy), _sampled(1, _nearest, vz), _sampled(2, _nearest, neighbor),
				_image(3, color)], push, full)


func _ensure_textures(buffers: RenderSceneBuffersRD, size: Vector2i, tiles: Vector2i) -> void:
	if buffers.has_texture(CTX, &"neighbor"):
		var f := buffers.get_texture_format(CTX, &"neighbor")
		if f.width == tiles.x and f.height == tiles.y and buffers.get_texture_format(CTX, &"copy").width == size.x:
			return
		buffers.clear_context(CTX)
	var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var rgba := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	var rg := RenderingDevice.DATA_FORMAT_R16G16_SFLOAT
	var one := RenderingDevice.TEXTURE_SAMPLES_1
	buffers.create_texture(CTX, &"copy", rgba, usage, one, size, 1, 1, true, false)
	buffers.create_texture(CTX, &"vz", rgba, usage, one, size, 1, 1, true, false)
	buffers.create_texture(CTX, &"rows", rg, usage, one, Vector2i(tiles.x, size.y), 1, 1, true, false)
	buffers.create_texture(CTX, &"tile_max", rg, usage, one, tiles, 1, 1, true, false)
	buffers.create_texture(CTX, &"neighbor", rg, usage, one, tiles, 1, 1, true, false)


func _image(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u


func _sampled(binding: int, sampler: RID, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(sampler)
	u.add_id(tex)
	return u


func _run(key: String, uniforms: Array, push: PackedFloat32Array, groups: Vector2i) -> void:
	var typed: Array[RDUniform] = []
	typed.assign(uniforms)
	var uset := UniformSetCacheRD.get_cache(_shaders[key], 0, typed)
	var bytes := push.to_byte_array()
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipelines[key])
	_rd.compute_list_bind_uniform_set(cl, uset, 0)
	_rd.compute_list_set_push_constant(cl, bytes, bytes.size())
	_rd.compute_list_dispatch(cl, groups.x, groups.y, 1)
	_rd.compute_list_end()
