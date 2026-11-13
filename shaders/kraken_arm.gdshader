shader_type spatial;
// 크라켄 촉수: 곧은 관(tentacle_tube)을 정점 셰이더에서 휘게 만듦 (마디 없이 매끈하게).
// 촉수는 로컬 +Y 로 뻗고, +Z 쪽으로 휨. 휘는 각도 θ(u) = pitch + curl·segs·(0.4u + 0.5u²) + 출렁임
// 배 쪽(+Z, 휘는 안쪽)에 빨판 두 줄을 셰이더로 그림.
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
#include "res://shaders/kraken_common.gdshaderinc"
uniform float arm_len = 8.0;
uniform float radius = 1.0;
uniform float tip = 0.12;          // 끝 굵기 비율
uniform float pitch = 0.0;
uniform float curl = 0.0;
uniform float segs = 10.0;
uniform float wave = 0.0;
uniform float wtime = 0.0;
uniform float sway = 0.0;           // 옆으로 살랑
varying float vs;                    // 뿌리부터 거리 (m)
varying vec2 vring;                  // 둘레 좌표 (각도는 조각에서 계산 — 이음새 없게)
varying float vrad;
varying vec3 lp;

float theta(float u) {
	return pitch + curl * segs * (0.4 * u + 0.5 * u * u) + wave * sin(wtime * 5.0 - u * segs * 0.7) * u;
}

float rad_at(float u) {
	return radius * mix(1.0, tip, pow(u, 0.85));
}

void vertex() {
	float u = clamp(VERTEX.y, 0.0, 1.0);    // 관 메쉬는 길이 1
	// 중심선: (z, y) 평면 위 곡선을 적분
	vec2 c = vec2(0.0);
	const int N = 28;
	float ds = u * arm_len / float(N);
	for (int i = 0; i < N; i++) {
		float uu = (float(i) + 0.5) / float(N) * u;
		float th = theta(uu);
		c += vec2(sin(th), cos(th)) * ds;
	}
	float th = theta(u);
	vec3 T = vec3(0.0, cos(th), sin(th));
	vec3 Nn = vec3(0.0, -sin(th), cos(th));
	vec3 B = vec3(1.0, 0.0, 0.0);
	float r = rad_at(u);
	vec2 rr = VERTEX.xz;              // 반지름 1 관의 둘레
	vec3 center = vec3(sin(u * 3.0 + wtime * 0.7) * sway * u * arm_len * 0.1, c.y, c.x);
	VERTEX = center + B * rr.x * r + Nn * rr.y * r;
	NORMAL = normalize(B * NORMAL.x + Nn * NORMAL.z + T * NORMAL.y);
	vs = u * arm_len;
	vring = rr;
	vrad = r;
	lp = vec3(rr.x * r, vs, rr.y * r);
}

void fragment() {
	vec3 q = lp * pattern_scale;
	float vang = atan(vring.x, vring.y);
	float belly = smoothstep(1.2, 0.3, abs(vang));
	// 빨판: 배 쪽 두 줄, 굵기에 맞춰 간격
	float spacing = vrad * 1.15;
	float row_off = 0.42;
	float sk = 0.0;
	vec2 bump = vec2(0.0);
	for (int side = -1; side <= 1; side += 2) {
		float a = vang - float(side) * row_off;
		float along = vs / spacing + (side > 0 ? 0.5 : 0.0);
		vec2 d = vec2(a * vrad / spacing, fract(along) - 0.5);
		float rr = length(d) / 0.34;
		float cup = smoothstep(1.0, 0.85, rr);
		sk = max(sk, cup * smoothstep(1.5, 0.6, abs(vang)));
		// 테두리는 볼록, 가운데는 오목
		bump += normalize(d + 1e-5) * (smoothstep(0.7, 0.95, rr) - smoothstep(0.95, 1.1, rr) - smoothstep(0.5, 0.0, rr) * 0.6) * cup;
	}
	float b1 = kn(q * 9.0) - 0.5;
	float wr = sin(vs * 6.0 / max(vrad, 0.1) + kn(q * 3.0) * 4.0);
	vec3 nb = vec3(bump.x * 0.8 + b1 * 0.3, wr * 0.12 + bump.y * 0.8, b1 * 0.3);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * (MODEL_MATRIX * vec4(nb * 0.4, 0.0))).xyz);
	vec3 alb;
	vec3 emi;
	float al;
	kraken_skin(q, dot(NORMAL, VIEW), belly, TIME, alb, emi, al);
	// 빨판: 연한 연두 테 + 가운데 어두운 구멍
	alb = mix(alb, vec3(0.75, 0.95, 0.5), sk * 0.7);
	emi += vec3(0.5, 1.0, 0.3) * sk * 0.25;
	ALBEDO = alb;
	EMISSION = emi;
	ALPHA = clamp(al + sk * 0.4, 0.0, 1.0);
	ROUGHNESS = 0.14 + 0.1 * kn(q * 14.0);
	SPECULAR = 0.6;
	RIM = 0.4;
	RIM_TINT = 0.7;
}
