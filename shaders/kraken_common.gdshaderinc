// 크라켄 공통 피부: 형광 초록 반투명 젤리 같은 살 + 속에 비치는 독 핏줄 + 숨 쉬듯 빛나는 반점
// (kraken_body / kraken_arm 이 같이 씀)
uniform vec3 neon : source_color = vec3(0.35, 1.0, 0.3);
uniform vec3 deep : source_color = vec3(0.02, 0.2, 0.08);
uniform vec3 vein_col : source_color = vec3(0.75, 1.0, 0.2);
uniform float glow = 0.0;          // 공격 직전 확 달아오름
uniform float pattern_scale = 1.0;
uniform float opacity = 0.82;

float kh(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float kn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(kh(i), kh(i + vec3(1, 0, 0)), f.x), mix(kh(i + vec3(0, 1, 0)), kh(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(kh(i + vec3(0, 0, 1)), kh(i + vec3(1, 0, 1)), f.x), mix(kh(i + vec3(0, 1, 1)), kh(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float kfbm(vec3 p) {
	return kn(p) * 0.5 + kn(p * 2.03) * 0.25 + kn(p * 4.1) * 0.125 + kn(p * 8.3) * 0.0625;
}
// 가지 뻗은 핏줄 (능선 노이즈)
float veins(vec3 p) {
	float v = 1.0 - abs(kfbm(p) * 2.0 - 1.0);
	float w = 1.0 - abs(kfbm(p * 2.3 + 11.0) * 2.0 - 1.0);
	return pow(v, 9.0) + pow(w, 12.0) * 0.6;
}

// 피부 계산: 색(albedo), 빛(emission), 투명도(alpha). q = 무늬 좌표, nv = 시선과 노멀의 내적
void kraken_skin(vec3 q, float nv, float belly, float t, out vec3 alb, out vec3 emi, out float alpha) {
	float fres = pow(1.0 - clamp(nv, 0.0, 1.0), 2.2);
	float n1 = kfbm(q * 1.3);
	float vn = veins(q * 1.6);
	float spots = smoothstep(0.8, 0.86, kn(q * 5.0 + 17.0)) * (1.0 - belly);
	float breathe = 0.55 + 0.45 * sin(t * 1.4 + n1 * 7.0);
	// 속(어둡고 깊은 초록) → 가장자리(형광)
	vec3 body = mix(deep, neon * 0.55, 0.25 + 0.35 * n1);
	body = mix(body, vec3(0.6, 0.85, 0.35), belly * 0.35);
	alb = mix(body, vein_col * 0.5, vn * 0.6);
	emi = neon * fres * 0.9
		+ vein_col * vn * (0.35 + 0.25 * breathe)
		+ vec3(0.55, 1.0, 0.2) * spots * breathe * 0.9
		+ neon * glow * (0.6 + fres);
	// 가운데는 속이 비치고 가장자리 · 핏줄은 진함
	alpha = clamp(mix(opacity * 0.7, 1.0, fres) + vn * 0.25 + spots * 0.3, 0.0, 1.0);
}
