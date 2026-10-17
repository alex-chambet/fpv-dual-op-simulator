class_name GroundMaterials
extends RefCounted
## Shader materials of the ground: terrain (grass / dry grass / dirt / rock by slope, farmland parcels), snow,
## asphalt, road paint, gravel shoulder and dirt trail. Everything is procedural (shared noise textures sampled
## in world space at several scales, so nothing repeats visibly); the fine detail fades with the distance.
## The terrain and snow shaders read the GroundMask (roads, verges, piste) when one is bound.

const COMMON := """
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D cell_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_mask : filter_linear, repeat_disable;
uniform vec4 mask_frame = vec4(0.0, 0.0, 1.0, 1.0);
uniform float use_mask = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec4 mask_at(vec2 xz) {
	if (use_mask < 0.5) {
		return vec4(0.0);
	}
	vec2 uv = (xz - mask_frame.xy) * mask_frame.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec4(0.0);
	}
	return texture(ground_mask, uv);
}

uniform float fields = 0.0;
uniform float field_size = 120.0;
uniform float field_angle = 0.4;

// Farmland: Voronoi parcels. x = kind of crop (hash: < 0.32 meadow, < 0.5 wheat, < 0.64 young crop in rows,
// < 0.8 ploughed, < 0.9 rapeseed, else stubble), y = metres to the border (roughly), zw = direction of the rows.
vec4 parcel(vec2 xz) {
	float ca = cos(field_angle), sa = sin(field_angle);
	vec2 q = vec2(ca * xz.x - sa * xz.y, sa * xz.x + ca * xz.y) / field_size * vec2(1.0, 0.62);
	vec2 i = floor(q);
	vec2 f = fract(q);
	float d1 = 9.0, d2 = 9.0;
	vec2 best = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + hash22(i + g) * 0.8 + 0.1 - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; best = i + g; } else if (d < d2) { d2 = d; }
		}
	}
	float ang = hash12(best + 9.7) * 3.1416;
	return vec4(hash12(best * 1.37 + 4.1), (sqrt(d2) - sqrt(d1)) * field_size * 0.5, cos(ang), sin(ang));
}

// world-space detail normal (for surfaces facing up), returned in view space
vec3 detail_normal(vec3 n_world, vec2 xz, float strength, mat4 view) {
	vec2 a = texture(normal_tex, xz * 0.31).rg * 2.0 - 1.0;
	vec2 b = texture(normal_tex, xz * 1.17 + 0.37).rg * 2.0 - 1.0;
	vec2 d = (a * 0.6 + b * 0.4) * strength;
	vec3 n = normalize(n_world + vec3(d.x, 0.0, d.y));
	return normalize((view * vec4(n, 0.0)).xyz);
}
"""

const TERRAIN := """
shader_type spatial;
render_mode cull_disabled;
#COMMON
uniform vec3 grass_a : source_color = vec3(0.16, 0.28, 0.07);
uniform vec3 grass_b : source_color = vec3(0.3, 0.4, 0.12);
uniform vec3 dry : source_color = vec3(0.5, 0.46, 0.26);
uniform vec3 dirt : source_color = vec3(0.32, 0.25, 0.17);
uniform vec3 rock_a : source_color = vec3(0.46, 0.45, 0.43);
uniform vec3 rock_b : source_color = vec3(0.24, 0.23, 0.22);
uniform vec3 fringe_color : source_color = vec3(0.42, 0.38, 0.3);
uniform float dry_amount = 0.4;
uniform float dirt_amount = 0.25;
uniform float rock_start = 0.32;
uniform float rock_end = 0.5;
uniform float normal_strength = 0.35;

float stripes(float phase, float sharpness) {
	float s = 0.5 + 0.5 * sin(phase);
	float w = fwidth(phase);
	return mix(pow(s, sharpness), 0.5, clamp(w * 0.9, 0.0, 1.0));
}

// Crop colour of the farmland, rgb, and in .a how much it replaces the grass.
vec4 farmland(vec2 xz, float near_road, float fine) {
	vec4 pc = parcel(xz);
	float h = pc.x;
	float edge = pc.y;
	vec2 dir = pc.zw;
	float along = dot(xz, dir);
	vec3 c;
	float rows = 0.0;
	if (h < 0.32) {
		return vec4(0.0);  // meadow: the grass of the terrain
	} else if (h < 0.5) {      // ripe wheat
		rows = stripes(along * 10.5, 2.0);
		c = mix(vec3(0.5, 0.38, 0.13), vec3(0.66, 0.52, 0.2), fine) * (0.84 + 0.16 * rows);
	} else if (h < 0.64) {     // young green crop in rows
		rows = stripes(along * 8.4, 3.0);
		c = mix(vec3(0.3, 0.27, 0.17), mix(vec3(0.2, 0.42, 0.1), vec3(0.32, 0.52, 0.14), fine), 0.25 + 0.75 * rows);
	} else if (h < 0.8) {      // ploughed soil
		rows = stripes(along * 7.0, 1.5);
		c = mix(vec3(0.22, 0.16, 0.11), vec3(0.36, 0.27, 0.19), 0.35 * fine + 0.65 * rows);
	} else if (h < 0.9) {      // rapeseed in flower
		c = mix(vec3(0.62, 0.55, 0.04), vec3(0.78, 0.7, 0.1), fine);
	} else {                   // stubble
		rows = stripes(along * 12.0, 1.0);
		c = mix(vec3(0.46, 0.41, 0.25), vec3(0.6, 0.53, 0.33), 0.5 * fine + 0.5 * rows);
	}
	// the colours above are sRGB
	c = pow(c, vec3(2.2));
	// uneven ripeness / moisture inside a parcel
	float patchy = texture(macro_tex, xz * 0.017 + h * 7.0).r;
	c *= 0.84 + 0.3 * patchy;
	if (h >= 0.5 && h < 0.64) {
		c = mix(c, c * vec3(0.8, 1.05, 0.75), smoothstep(0.55, 0.75, patchy));
	}
	// tractor tramlines (two wheel tracks 1.8 m apart every 24 m) inside the parcel, headland along the border
	if (h < 0.64 || h >= 0.8) {
		float m = fract(along / 24.0) * 24.0;
		float tw = abs(min(m, 24.0 - m) - 0.9);
		float track = (1.0 - smoothstep(0.16, 0.3, tw)) * (1.0 - smoothstep(0.08, 0.3, fwidth(along)));
		c = mix(c, c * vec3(0.55, 0.5, 0.45), track * smoothstep(8.0, 10.0, edge));
	}
	c *= mix(0.88, 1.0, smoothstep(5.0, 9.0, edge));
	float w = smoothstep(1.5, 4.0, edge) * (1.0 - near_road);
	return vec4(c, w);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float dist = length(VERTEX);
	vec2 xz = wpos.xz;
	float m_big = texture(macro_tex, xz * 0.0021).r;
	float m_mid = texture(macro_tex, xz * 0.0117 + 0.31).r;
	float d1 = texture(detail_tex, xz * 0.083).r;
	float d2 = texture(detail_tex, xz * 0.47 + 0.5).r;
	float far_fade = smoothstep(25.0, 110.0, dist);
	float fine = mix(d2, 0.5, far_fade);
	float clumps = mix(texture(cell_tex, xz * 0.9).r, 0.5, smoothstep(10.0, 45.0, dist));
	vec4 mk = mask_at(xz);

	vec3 g = mix(grass_a, grass_b, smoothstep(0.25, 0.75, m_mid * 0.65 + d1 * 0.35));
	g = mix(g, dry, smoothstep(0.5, 0.85, m_big * 0.75 + d1 * 0.25) * dry_amount);
	g *= 0.78 + 0.3 * fine + 0.12 * clumps;
	float dirt_w = smoothstep(0.68, 0.76, m_mid * 0.5 + d1 * 0.5) * dirt_amount;
	vec3 col = mix(g, dirt * (0.8 + 0.4 * fine), dirt_w);
	float rough = 0.94;
	float nstr = normal_strength;

	if (fields > 0.5) {
		vec4 farm = farmland(xz, mk.g, fine);
		col = mix(col, farm.rgb, farm.a);
	}
	// worn ground along roads and trails
	float fr = clamp(mk.b * (0.75 + 0.5 * d1), 0.0, 1.0);
	col = mix(col, fringe_color * (0.8 + 0.4 * fine), fr * 0.85);

	float slope = 1.0 - wnrm.y;
	vec3 n_rock = wnrm;
	float rock_w = smoothstep(rock_start, rock_end, slope + (d1 - 0.5) * 0.14 + (m_mid - 0.5) * 0.1);
	float soft2 = 0.32 * smoothstep(30.0, 180.0, dist);
	if (rock_w > 0.001) {
		vec3 bw = pow(abs(wnrm), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		float rx = texture(detail_tex, wpos.zy * vec2(0.09, 0.3)).r;
		float ry = texture(detail_tex, xz * 0.12).r;
		float rz = texture(detail_tex, wpos.xy * vec2(0.09, 0.3)).r;
		float r = rx * bw.x + ry * bw.y + rz * bw.z;
		float cracks = texture(cell_tex, (wpos.xz + wpos.yy * 0.7) * 0.18).r;
		vec3 rock = mix(rock_b, rock_a, smoothstep(0.2, 0.8, r)) * (0.75 + 0.35 * smoothstep(0.1, 0.5, cracks)) * (0.88 + 0.24 * fine);
		// large scale (seen from afar on the valley walls): strata, dark streaks down the slope, warmer patches
		float hz = (xz.x + xz.y) * 0.7;
		float strata = texture(detail_tex, vec2(wpos.y * 0.013 + m_mid * 0.6, hz * 0.0015)).r;
		float gully = texture(detail_tex, vec2(hz * 0.009, wpos.y * 0.0018)).r;
		rock *= 0.74 + 0.42 * smoothstep(0.3, 0.7, strata);
		rock *= 1.0 - 0.45 * smoothstep(0.5, 0.78, gully);
		rock = mix(rock, rock * vec3(1.15, 1.03, 0.88), smoothstep(0.5, 0.8, m_big));
		// grassy ledges across the walls and grass on their gentler parts
		float ledge = texture(detail_tex, vec2(hz * 0.004, wpos.y * 0.028 + m_mid)).r;
		rock_w *= 1.0 - 0.85 * smoothstep(0.6, 0.7, ledge) * (1.0 - smoothstep(0.62, 0.9, slope));
		rock_w *= 1.0 - 0.55 * smoothstep(0.55, 0.75, m_mid * 0.6 + d1 * 0.4) * (1.0 - smoothstep(0.45, 0.7, slope));
		col = mix(col, rock, rock_w);
		rough = mix(rough, 0.82, rock_w);
		nstr = mix(nstr, normal_strength * 2.2, rock_w);
		// relief of the walls (the mesh itself is smooth): buttresses and hollows of 20-40 m from the macro noise
		// projected on the two wall planes; their gradient bends the normal, the hollows are darker
		const float STEP = 0.002;
		vec2 px = wpos.zy * vec2(0.0035, 0.006);
		vec2 pz = wpos.xy * vec2(0.0035, 0.006);
		float hx = texture(macro_tex, px).r;
		float hzz = texture(macro_tex, pz).r;
		vec2 gx = vec2(texture(macro_tex, px + vec2(STEP, 0.0)).r - hx, texture(macro_tex, px + vec2(0.0, STEP)).r - hx) / STEP;
		vec2 gz = vec2(texture(macro_tex, pz + vec2(STEP, 0.0)).r - hzz, texture(macro_tex, pz + vec2(0.0, STEP)).r - hzz) / STEP;
		float wsum = bw.x + bw.z + 1e-4;
		float relief = (hx * bw.x + hzz * bw.z) / wsum;
		col = mix(col, col * (0.62 + 0.6 * relief), rock_w * smoothstep(0.3, 0.6, slope));
		vec2 nx = texture(normal_tex, wpos.zy * vec2(0.03, 0.07)).rg * 2.0 - 1.0;
		vec2 nz = texture(normal_tex, wpos.xy * vec2(0.03, 0.07)).rg * 2.0 - 1.0;
		vec3 bend = (vec3(0.0, gx.y, gx.x) * bw.x + vec3(gz.x, gz.y, 0.0) * bw.z) * -0.03
				+ (vec3(0.0, nx.y, nx.x) * bw.x + vec3(nz.x, nz.y, 0.0) * bw.z) * 0.35;
		n_rock += bend * rock_w;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	NORMAL = detail_normal(normalize(n_rock), xz, nstr * (1.0 - far_fade * 0.7), VIEW_MATRIX);
}
"""

const SNOW := """
shader_type spatial;
render_mode cull_disabled;
#COMMON
uniform vec3 snow_a : source_color = vec3(0.76, 0.82, 0.93);
uniform vec3 snow_b : source_color = vec3(0.95, 0.965, 0.99);
uniform vec3 rock_a : source_color = vec3(0.4, 0.39, 0.38);
uniform vec3 rock_b : source_color = vec3(0.2, 0.19, 0.19);
uniform float rock_start = 0.42;
uniform float rock_end = 0.58;
uniform float groom_spacing = 0.06;
// strength of the wind ripples (a grazing sun makes them stand out a lot: lower at dawn / dusk)
uniform float ripple = 1.0;
// tracks of the riders who skied the slope before (freeride face): 0 = none
uniform float old_tracks = 0.0;
// rock painted by the ground mask (red channel) where the environment says the rock shows: 0 = none
uniform float rock_paint = 0.0;
// beyond |x| > far_rock_x (the mountain side around a freeride face), outcrops streaking down the fall line
uniform float far_rock_x = 1.0e6;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Old ski tracks: in lanes down the fall line, a rider's line on some of them (two grooves 24 cm apart, swinging
// in turns of 18 to 30 m), over some stretches only. Two families of lanes so the lines cross.
float old_track(vec2 xz, float dist) {
	float trk = 0.0;
	for (int f = 0; f < 2; f++) {
		float lw = f == 0 ? 37.0 : 53.0;
		float sh = float(f) * 17.0;
		float lane = floor((xz.x + sh) / lw);
		float h = hash12(vec2(lane, float(f) * 7.1 + 1.0));
		float wl = 18.0 + 12.0 * h;
		float cx = (lane + 0.5) * lw - sh + (3.0 + 4.0 * hash12(vec2(lane, 3.3 + float(f)))) * sin(xz.y * 6.2832 / wl + h * 40.0);
		float on = step(0.4, h) * smoothstep(0.38, 0.52, texture(macro_tex, vec2(lane * 0.37 + float(f) * 0.5, xz.y * 0.003)).r);
		float d = abs(abs(xz.x - cx) - 0.12);
		float w = 0.05 + fwidth(xz.x) * 0.6;
		trk = max(trk, on * (1.0 - smoothstep(w, w + 0.05, d)));
	}
	return trk * (1.0 - smoothstep(70.0, 260.0, dist));
}

void fragment() {
	float dist = length(VERTEX);
	vec2 xz = wpos.xz;
	float m_big = texture(macro_tex, xz * 0.003).r;
	float m_mid = texture(macro_tex, xz * 0.015 + 0.2).r;
	float d1 = texture(detail_tex, xz * 0.1).r;
	float far_fade = smoothstep(40.0, 220.0, dist);
	vec4 mk = mask_at(xz);
	float piste = mk.g;
	vec3 col = mix(snow_a, snow_b, smoothstep(0.2, 0.8, m_mid * 0.6 + d1 * 0.4));
	col *= mix(0.96 + 0.04 * m_big, 1.0, piste * 0.5);
	if (old_tracks > 0.0) {
		col *= 1.0 - 0.16 * old_tracks * old_track(xz, dist) * (1.0 - piste);
	}
	// passes of the groomer: lanes of about 5.5 m along the fall line, each a little different
	float lane_x = xz.x / 5.5 + (texture(macro_tex, xz * vec2(0.004, 0.0015)).r - 0.5) * 1.5;
	float lane = floor(lane_x);
	float edge_l = 1.0 - smoothstep(0.0, 0.05 + fwidth(lane_x), abs(fract(lane_x) - 0.03));
	col *= 1.0 - piste * (0.025 * hash12(vec2(lane, 3.0)) + 0.04 * edge_l);

	// normal: wind ripples off the piste, groomer corduroy (along the fall line) on it
	vec2 rip = ((texture(normal_tex, xz * vec2(0.09, 0.22)).rg * 2.0 - 1.0) * 0.55
			+ (texture(normal_tex, xz * 0.6).rg * 2.0 - 1.0) * 0.25) * ripple;
	float ph = xz.x * 6.2832 / groom_spacing;
	float aa = clamp(1.0 - fwidth(ph) * 0.6, 0.0, 1.0);
	float wobble = (texture(detail_tex, xz * vec2(0.05, 0.01)).r - 0.5) * 6.0;
	float cord = cos(ph + wobble) * aa;
	vec2 dn = mix(rip, vec2(cord * 0.25 * (1.0 - smoothstep(4.0, 14.0, dist)), 0.0) + rip * 0.3, piste) * (1.0 - far_fade * 0.75);
	vec3 n = normalize(wnrm + vec3(dn.x, 0.0, dn.y));

	float slope = 1.0 - wnrm.y;
	float rock_w = smoothstep(rock_start, rock_end, slope + (d1 - 0.5) * 0.2);
	// exposed rock painted by the environment (cliffs, outcrops: red of the ground mask), broken by snow
	// the thresholds that paint the rock widen with distance: a hard threshold on a noise texture
	// turns into salt and pepper once a texel is smaller than a pixel, which is what made the far
	// side of the face sparkle grey
	float soft = 0.04 + 0.4 * smoothstep(25.0, 160.0, dist);
	if (rock_paint > 0.0) {
		rock_w = max(rock_w, rock_paint * mk.r * smoothstep(0.32 - soft * 0.5, 0.5 + soft * 0.5, texture(detail_tex, xz * 0.19).r + slope * 0.5));
		float beyond = smoothstep(far_rock_x, far_rock_x + 60.0, abs(xz.x));
		{
			// rocky sectors (snowfields between them), rock streaking down the fall line in them, more on the steep parts;
			// sparser on the face itself, never on the subject's line (blue of the ground mask)
			float lo = mix(0.6, 0.5, beyond);
			float sector = smoothstep(lo, lo + 0.12, texture(macro_tex, xz * 0.0007 + 0.37).r) * (1.0 - mk.b);
			float streak = texture(macro_tex, vec2(xz.x * 0.004, xz.y * 0.0012)).r * 0.7 + texture(detail_tex, xz * 0.015).r * 0.3;
			rock_w = max(rock_w, sector * smoothstep(0.64 - soft, 0.64 + soft, streak + slope * 0.35)
					* smoothstep(0.4 - soft, 0.4 + soft, texture(detail_tex, xz * 0.19).r + slope * 0.5));
		}
	}
	float soft2 = 0.32 * smoothstep(30.0, 180.0, dist);
	if (rock_w > 0.001) {
		// seen from every side (triplanar), with strata and cracks, so a cliff is not a smear
		vec3 bw = pow(abs(wnrm), vec3(4.0));
		bw /= bw.x + bw.y + bw.z;
		vec3 pp = wpos * 0.11;
		float r = texture(detail_tex, pp.zy * vec2(1.0, 2.0)).r * bw.x + texture(detail_tex, pp.xz).r * bw.y
				+ texture(detail_tex, pp.xy * vec2(1.0, 2.0)).r * bw.z;
		float cr = texture(cell_tex, pp.zy * 2.3).r * bw.x + texture(cell_tex, pp.xz * 2.3).r * bw.y
				+ texture(cell_tex, pp.xy * 2.3).r * bw.z;
		cr = mix(cr, 0.5, smoothstep(40.0, 200.0, dist));   // the cracks blur out with distance
		float strata = 0.82 + 0.3 * texture(detail_tex, vec2(wpos.y * 0.09, (wpos.x + wpos.z) * 0.004)).r;
		vec3 rock = mix(rock_b, rock_a, smoothstep(0.25, 0.75, r)) * (0.75 + 0.35 * smoothstep(0.05, 0.4, cr)) * strata;
		// snow stays on the ledges and in the hollows of the rock
		rock_w *= smoothstep(0.35 - soft2, 0.6 + soft2, r + (1.0 - slope) * 0.3);
		col = mix(col, rock, rock_w);
		vec2 nx = texture(normal_tex, wpos.zy * vec2(0.12, 0.25)).rg * 2.0 - 1.0;
		vec2 nz = texture(normal_tex, wpos.xy * vec2(0.12, 0.25)).rg * 2.0 - 1.0;
		vec2 ny = texture(normal_tex, xz * 0.12).rg * 2.0 - 1.0;
		n = normalize(n + (vec3(0.0, nx.y, nx.x) * bw.x + vec3(nz.x, nz.y, 0.0) * bw.z + vec3(ny.x, 0.0, ny.y) * bw.y)
				* 0.6 * rock_w * (1.0 - far_fade * 0.5));
	}
	// sparkles: tiny facets catching the sun
	float sp = texture(cell_tex, xz * 7.3).r;
	float glint = smoothstep(0.93, 0.99, sp) * (1.0 - far_fade) * (1.0 - rock_w);
	ALBEDO = col;
	ROUGHNESS = mix(0.62, 0.9, rock_w) - glint * 0.4;
	SPECULAR = 0.5 + glint * 0.5;
	SSS_STRENGTH = 0.25 * (1.0 - rock_w);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
"""

## Asphalt ribbon: UV.x across the road (0..1), UV.y along (m x 0.25).
const ASPHALT := """
shader_type spatial;
render_mode cull_disabled;
#COMMON
uniform vec3 base : source_color = vec3(0.2, 0.2, 0.21);
uniform vec3 worn : source_color = vec3(0.29, 0.28, 0.27);
uniform vec3 patch_color : source_color = vec3(0.17, 0.17, 0.178);
uniform vec3 gravel_color : source_color = vec3(0.42, 0.39, 0.33);
uniform float half_width = 3.7;
uniform float edge_crumble = 0.25;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float dist = length(VERTEX);
	float u = UV.x;
	float x = (u - 0.5) * 2.0 * half_width;   // metres from the centre line
	float s = UV.y * 4.0;                      // metres along
	vec2 xz = wpos.xz;
	float far_fade = smoothstep(15.0, 70.0, dist);
	float grain = mix(texture(detail_tex, xz * 2.7).r, 0.5, far_fade);
	float grain2 = mix(texture(cell_tex, xz * 4.1).r, 0.5, far_fade);
	float m = texture(macro_tex, vec2(s * 0.006, x * 0.02)).r;
	vec3 col = mix(base, worn, smoothstep(0.35, 0.75, m) * 0.6);
	// wheel tracks: polished, a bit darker, in the middle of each lane
	float lane = abs(abs(x) - half_width * 0.5);
	float track = smoothstep(0.75, 0.45, abs(lane - 0.62)) * 0.5;
	col *= 1.0 - track * 0.18;
	col *= 0.88 + 0.22 * grain + 0.08 * (grain2 - 0.5);
	// repair patches: rectangles of fresh black asphalt
	vec2 cell = floor(vec2(x / (half_width * 0.5), s / 9.0));
	float h = hash12(cell + 17.0);
	vec2 inner = fract(vec2(x / (half_width * 0.5), s / 9.0));
	if (h > 0.96 && inner.x > 0.1 && inner.x < 0.8 && inner.y > 0.15 && inner.y < 0.15 + (h - 0.96) * 14.0) {
		col = patch_color * (0.9 + 0.2 * grain);
	}
	// cracks: thin lines along the contours of a noise, only in some places
	float cn = texture(macro_tex, xz * 0.11).r;
	float crack = (1.0 - smoothstep(0.0, 0.006 + fwidth(cn) * 1.2, abs(cn - 0.5))) * smoothstep(0.62, 0.75, texture(macro_tex, xz * 0.013 + 0.5).r);
	col *= 1.0 - crack * 0.35 * (1.0 - far_fade);
	// crumbling edge into the gravel
	float e = half_width - abs(x);
	float rag = (texture(detail_tex, xz * 0.9).r - 0.5) * 0.5 + (grain2 - 0.5) * 0.3;
	float gravel = 1.0 - smoothstep(0.0, edge_crumble, e + rag * edge_crumble);
	col = mix(col, gravel_color * (0.8 + 0.4 * grain), gravel);
	ALBEDO = col;
	ROUGHNESS = mix(0.86, 0.72, track) + grain * 0.08;
	SPECULAR = 0.4;
	NORMAL = detail_normal(vec3(0.0, 1.0, 0.0), xz * 3.0, 0.18 * (1.0 - far_fade), VIEW_MATRIX);
}
"""

## Road paint: worn white.
const PAINT := """
shader_type spatial;
#COMMON
uniform vec3 paint : source_color = vec3(0.86, 0.86, 0.82);
uniform vec3 under : source_color = vec3(0.24, 0.24, 0.24);

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = wpos.xz;
	float dist = length(VERTEX);
	float w = texture(detail_tex, xz * 1.9).r * 0.6 + texture(cell_tex, xz * 5.0).r * 0.4;
	float wear = smoothstep(0.62, 0.78, w) * (1.0 - smoothstep(30.0, 80.0, dist));
	ALBEDO = mix(paint, under, wear * 0.85);
	ROUGHNESS = 0.55 + wear * 0.3;
	SPECULAR = 0.45;
}
"""

## Gravel / dust shoulder: UV.x across.
const GRAVEL := """
shader_type spatial;
render_mode cull_disabled;
#COMMON
uniform vec3 gravel : source_color = vec3(0.45, 0.42, 0.35);
uniform vec3 dark : source_color = vec3(0.28, 0.26, 0.22);
uniform vec3 grass : source_color = vec3(0.25, 0.33, 0.12);
uniform float half_width = 5.0;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = wpos.xz;
	float dist = length(VERTEX);
	float far_fade = smoothstep(15.0, 70.0, dist);
	float x = abs(UV.x - 0.5) * 2.0 * half_width;
	float st = mix(texture(cell_tex, xz * 6.0).r, 0.5, far_fade);
	float n = texture(detail_tex, xz * 0.7).r;
	vec3 col = mix(dark, gravel, smoothstep(0.2, 0.8, st * 0.6 + n * 0.4));
	// tufts of grass towards the outer edge, and a ragged border
	float out_d = half_width - x;
	float g = smoothstep(1.4, 0.3, out_d + (n - 0.5) * 1.2) * smoothstep(0.3, 0.6, texture(macro_tex, xz * 0.08).r + 0.15);
	col = mix(col, grass * (0.8 + 0.4 * st), g);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	ALPHA = 1.0 - smoothstep(0.0, 0.5, -(out_d - 0.6 + (n - 0.5) * 1.0));
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL = detail_normal(vec3(0.0, 1.0, 0.0), xz * 3.5, 0.35 * (1.0 - far_fade), VIEW_MATRIX);
}
"""

## Dirt trail: compacted ruts, stones, needles, ragged edges blending into the forest floor.
const TRAIL := """
shader_type spatial;
render_mode cull_disabled;
#COMMON
uniform vec3 dirt : source_color = vec3(0.36, 0.27, 0.18);
uniform vec3 dark : source_color = vec3(0.22, 0.16, 0.1);
uniform vec3 litter : source_color = vec3(0.4, 0.27, 0.14);
uniform float half_width = 1.2;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = wpos.xz;
	float dist = length(VERTEX);
	float far_fade = smoothstep(12.0, 60.0, dist);
	float x = (UV.x - 0.5) * 2.0 * half_width;
	float n = texture(detail_tex, xz * 0.8).r;
	float st = mix(texture(cell_tex, xz * 5.0).r, 0.5, far_fade);
	vec3 col = mix(dark, dirt, smoothstep(0.2, 0.8, n));
	// two compacted, darker ruts
	float rut = smoothstep(0.28, 0.08, abs(abs(x) - half_width * 0.38));
	col *= 1.0 - rut * 0.22;
	// stones and pine needles
	col = mix(col, vec3(0.55, 0.52, 0.47), smoothstep(0.86, 0.93, st) * (1.0 - rut * 0.5));
	float lit = smoothstep(0.55, 0.75, texture(macro_tex, xz * 0.5).r) * smoothstep(0.2, 0.9, abs(x) / half_width);
	col = mix(col, litter * (0.8 + 0.4 * n), lit * 0.7);
	float edge = half_width - abs(x) + (n - 0.5) * 0.7 + (st - 0.5) * 0.25;
	ALBEDO = col;
	ROUGHNESS = 0.97;
	ALPHA = smoothstep(0.0, 0.25, edge);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL = detail_normal(vec3(0.0, 1.0, 0.0), xz * 2.5, 0.5 * (1.0 - far_fade), VIEW_MATRIX);
}
"""

static var _shaders := {}
static var _tex := {}


static func _noise_tex(key: String, type: int, freq: float, octaves: int, size: int, normal := false,
		cellular_return := -1) -> NoiseTexture2D:
	if _tex.has(key):
		return _tex[key]
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = key.hash() & 0xffff
	if cellular_return >= 0:
		n.cellular_return_type = cellular_return
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	var t := NoiseTexture2D.new()
	t.noise = n
	t.seamless = true
	t.width = size
	t.height = size
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	else:
		t.normalize = true
	_tex[key] = t
	return t


## Shared seamless noise textures: "macro" (large patches), "detail" (small scale), "cell" (cellular: stones,
## cracks), "normal" (normal map).
static func noise(key: String) -> NoiseTexture2D:
	match key:
		"macro":
			return _noise_tex("macro", FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 5, 512)
		"cell":
			return _noise_tex("cell", FastNoiseLite.TYPE_CELLULAR, 0.06, 1, 512, false, FastNoiseLite.RETURN_DISTANCE)
		"normal":
			return _noise_tex("normal", FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.04, 4, 512, true)
	return _noise_tex("detail", FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.03, 4, 512)


static func _material(key: String, code: String) -> ShaderMaterial:
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = code.replace("#COMMON", COMMON)
		_shaders[key] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[key]
	for t in ["macro", "detail", "cell", "normal"]:
		m.set_shader_parameter(t + "_tex", noise(t))
	return m


static func _with(m: ShaderMaterial, params: Dictionary) -> ShaderMaterial:
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


## Terrain: grass_a / grass_b / dry / dirt / rock_a / rock_b / fringe_color, dry_amount, dirt_amount,
## rock_start / rock_end (1 - normal.y), normal_strength, fields (1 = farmland parcels), field_size, field_angle.
static func terrain(params := {}) -> ShaderMaterial:
	return _with(_material("terrain", TERRAIN), params)


static func snow(params := {}) -> ShaderMaterial:
	return _with(_material("snow", SNOW), params)


static func asphalt(params := {}) -> ShaderMaterial:
	return _with(_material("asphalt", ASPHALT), params)


static func paint(params := {}) -> ShaderMaterial:
	return _with(_material("paint", PAINT), params)


static func gravel(params := {}) -> ShaderMaterial:
	return _with(_material("gravel", GRAVEL), params)


static func trail(params := {}) -> ShaderMaterial:
	return _with(_material("trail", TRAIL), params)
