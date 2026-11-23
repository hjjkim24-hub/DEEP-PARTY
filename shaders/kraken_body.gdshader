shader_type spatial;
// 거대 크라켄 몸통 (models/kraken_body.obj). 형광 초록 젤리 살.
// 불투명으로 그림: 반투명이면 몸의 겹친 면 · 판 위 소품과 그리는 순서가 꼬여 군데군데 깨져 보였음.
// 속이 비치는 느낌은 가장자리 빛(프레넬) + 속 핏줄 빛으로 냄
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
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
	ROUGHNESS = 0.3 + 0.12 * kn(q * 14.0);
	SPECULAR = 0.4;
	RIM = 0.4;
	RIM_TINT = 0.7;
}
