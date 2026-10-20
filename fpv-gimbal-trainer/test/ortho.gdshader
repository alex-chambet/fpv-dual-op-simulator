shader_type spatial;
render_mode unshaded, cull_disabled;
// Plaque l'orthophoto IGN sur le terrain. Les coordonnées du monde du jeu sont converties en
// Lambert-93 (rotation + translation, les mêmes qui ont servi à découper le MNT), puis en UV dans
// la dalle. Deux dalles : la proche (44 cm/px sur 1,8 km) et, au-delà, la lointaine (3,9 m/px sur
// 16 km). Sans éclairage : on cherche à comparer un motif à une image vidéo, pas à faire joli.

uniform sampler2D near_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D far_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 near_frame;   // E0, N1, 1/largeur, 1/hauteur
uniform vec4 far_frame;
uniform vec4 l93_basis;    // dEx, dNx, dEz, dNz
uniform vec2 l93_origin;   // E, N de l'origine du monde

varying vec3 wpos;


void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float e = l93_origin.x + wpos.x * l93_basis.x + wpos.z * l93_basis.z;
	float n = l93_origin.y + wpos.x * l93_basis.y + wpos.z * l93_basis.w;
	vec2 uf = vec2((e - far_frame.x) * far_frame.z, (far_frame.y - n) * far_frame.w);
	vec2 un = vec2((e - near_frame.x) * near_frame.z, (near_frame.y - n) * near_frame.w);
	vec3 col = texture(far_tex, clamp(uf, 0.0, 1.0)).rgb;
	if (un.x > 0.0 && un.x < 1.0 && un.y > 0.0 && un.y < 1.0) {
		col = texture(near_tex, un).rgb;
	}
	ALBEDO = col;
}
