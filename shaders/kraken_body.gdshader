shader_type spatial;
// 거대 크라켄 몸통 (models/kraken_body.obj). 반투명 형광 초록
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
#include "res://shaders/kraken_common.gdshaderinc"
varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 q = lp * pattern_scale;
	// 피부 결 (주름 · 오돌토돌)
	float b1 = kn(q * 9.0) - 0.5;
	float b2 = kn(q * 23.0 + 5.0) - 0.5;
	float wr = sin(lp.y * 18.0 + kn(q * 3.0) * 5.0);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(vec3(b1, wr * 0.15 + b2, b2) * 0.35, 0.0)).xyz);
	float belly = smoothstep(0.2, -0.6, ln.y) * 0.8;
	vec3 alb;
	vec3 emi;
	float a;
	kraken_skin(q, dot(NORMAL, VIEW), belly, TIME, alb, emi, a);
	ALBEDO = alb;
	EMISSION = emi;
	ALPHA = a;
	ROUGHNESS = 0.16 + 0.12 * kn(q * 14.0);
	SPECULAR = 0.6;
	RIM = 0.4;
	RIM_TINT = 0.7;
}
