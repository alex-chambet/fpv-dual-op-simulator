shader_type spatial;
// Copie du shader des rochers du jeu (scenarios/graphics/rocks.gd), à une chose près : son échelle
// de texture était figée (`wpos * 0.55`, soit un motif qui se répète tous les 1,8 m). C'est le bon
// réglage pour un bloc d'un à trois mètres — c'est tout ce que le jeu pose — mais sur une paroi de
// douze mètres le motif s'étale et la roche tourne à la peau de léopard.
//
// Ici l'échelle est un paramètre, et `facet_rock.gd` en règle une par tranche de taille. Le reste
// est identique : triplanaire sur la position du monde (strates, fissures), neige sur les faces
// hautes, aucune UV nécessaire.

uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D cell_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 rock_a : source_color = vec3(0.5, 0.49, 0.47);
uniform vec3 rock_b : source_color = vec3(0.27, 0.26, 0.25);
uniform float snow = 0.0;
/// Taille du motif : 0.55 pour un caillou, ~0.15 pour une paroi de douze mètres.
uniform float tex_scale = 0.55;
/// Force du relief ajouté par la normale. Faible sur les grandes parois : il brouillait les arêtes,
/// qui sont justement ce qu'on vient chercher.
uniform float bump = 0.45;
/// Relief de GRANDE longueur d'onde (quatre fois celle de `bump`). C'est lui qui donne du modelé à
/// une paroi de douze mètres : le relief fin, lui, disparaît au-delà de vingt mètres de distance —
/// les mipmaps le moyennent — et c'est ce qui rendait les grandes parois lisses. Celui-ci survit,
/// parce qu'il est à l'échelle de la paroi, et il ne brouille pas les arêtes pour la même raison.
uniform float bump_coarse = 0.55;

varying vec3 wpos;
varying vec3 wnrm;


void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	vec3 bw = pow(abs(wnrm), vec3(4.0));
	bw /= bw.x + bw.y + bw.z;
	vec3 p = wpos * tex_scale;
	float n = texture(detail_tex, p.zy * vec2(1.0, 2.2)).r * bw.x + texture(detail_tex, p.xz).r * bw.y
			+ texture(detail_tex, p.xy * vec2(1.0, 2.2)).r * bw.z;
	float c = texture(cell_tex, p.zy * 1.7).r * bw.x + texture(cell_tex, p.xz * 1.7).r * bw.y
			+ texture(cell_tex, p.xy * 1.7).r * bw.z;
	// deuxième octave, quatre fois plus large : les grandes plages claires et sombres d'une paroi
	// (bancs mouillés, lichen, faces fraîchement cassées), que le motif fin ne sait pas dessiner
	vec3 q = p * 0.25;
	float n2 = texture(detail_tex, q.zy).r * bw.x + texture(detail_tex, q.xz).r * bw.y
			+ texture(detail_tex, q.xy).r * bw.z;
	float cr = texture(cell_tex, q.zy * 0.8).r * bw.x + texture(cell_tex, q.xz * 0.8).r * bw.y
			+ texture(cell_tex, q.xy * 0.8).r * bw.z;
	vec3 col = mix(rock_b, rock_a, smoothstep(0.2, 0.8, n * 0.65 + n2 * 0.35))
			* (0.7 + 0.4 * smoothstep(0.05, 0.45, c));
	// les grandes fissures : le fond d'une diaclase ne voit pas le ciel, il est bien plus sombre
	col *= 0.62 + 0.38 * smoothstep(0.02, 0.30, cr);
	float sn = smoothstep(0.3, 0.6, wnrm.y + (n - 0.5) * 0.4) * snow;
	col = mix(col, vec3(0.9, 0.93, 0.98), sn);
	vec2 a = texture(normal_tex, p.zy * 2.0).rg * 2.0 - 1.0;
	vec2 b = texture(normal_tex, p.xz * 2.0).rg * 2.0 - 1.0;
	vec2 d = texture(normal_tex, p.xy * 2.0).rg * 2.0 - 1.0;
	vec3 off = vec3(0.0, a.x, a.y) * bw.x + vec3(b.x, 0.0, b.y) * bw.y + vec3(d.x, d.y, 0.0) * bw.z;
	vec2 a2 = texture(normal_tex, q.zy * 0.5).rg * 2.0 - 1.0;
	vec2 b2 = texture(normal_tex, q.xz * 0.5).rg * 2.0 - 1.0;
	vec2 d2 = texture(normal_tex, q.xy * 0.5).rg * 2.0 - 1.0;
	vec3 off2 = vec3(0.0, a2.x, a2.y) * bw.x + vec3(b2.x, 0.0, b2.y) * bw.y + vec3(d2.x, d2.y, 0.0) * bw.z;
	vec3 nw = normalize(wnrm + (off * bump + off2 * bump_coarse) * (1.0 - sn * 0.7));
	ALBEDO = col;
	ROUGHNESS = mix(0.88, 0.7, sn) - 0.10 * smoothstep(0.6, 0.95, n);
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
