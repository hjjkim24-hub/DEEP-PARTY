shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// 돛 · 깃발: 바람에 부푼 천 (UV 0..1, 메시는 XY 평면, +Z 로 부풂)
//   mode 0 사각 돛 (위 가로대에 매달림), 1 세모 돛, 2 깃발 (왼쪽이 깃대, 물결이 오른쪽으로)

uniform vec3 cloth : source_color = vec3(0.42, 0.07, 0.07);
uniform vec3 hem : source_color = vec3(0.2, 0.04, 0.04);
uniform sampler2D emblem : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 emblem_rect = vec4(0.25, 0.22, 0.5, 0.5);   // UV 안 위치 · 크기
uniform vec3 emblem_col : source_color = vec3(0.9, 0.84, 0.7);
uniform float emblem_on = 0.0;
uniform float billow = 1.0;
uniform float flutter = 0.08;
uniform int mode = 0;
uniform float tatter = 0.6;
uniform float seed = 0.0;
uniform vec2 size = vec2(10.0, 7.0);
uniform float glow = 0.0;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1, 0)), f.x), mix(h12(i + vec2(0, 1)), h12(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * n2(p);
		p *= 2.1;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	vec2 uv = UV;
	float t = TIME;
	float z = 0.0;
	if (mode == 2) {
		// 깃발: 깃대에서 멀수록 크게 출렁
		float w = sin(uv.x * 7.0 - t * 6.0 + seed) * 0.6 + sin(uv.x * 13.0 - t * 9.0 + uv.y * 3.0) * 0.25;
		z = w * uv.x * size.y * 0.16;
		VERTEX.y -= uv.x * uv.x * size.y * 0.12;
	} else {
		float b = sin(uv.x * PI) * sin(clamp(uv.y, 0.0, 1.0) * PI * 0.9 + 0.15);
		if (mode == 1) {
			b = sin(uv.x * PI) * (1.0 - uv.y) * 1.2;
		}
		z = billow * b * (1.0 + 0.05 * sin(t * 1.3 + seed));
		z += flutter * sin(uv.x * 9.0 + t * 4.0 + seed) * (uv.y) * sin(uv.x * PI);
	}
	VERTEX.z += z;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = uv * size;
	// 천 짜임 + 세로 솔기 + 얼룩
	float weave = (sin(p.x * 60.0) * 0.5 + 0.5) * (sin(p.y * 60.0) * 0.5 + 0.5);
	float seam = 1.0 - smoothstep(0.0, 0.05, abs(fract(p.x / 1.1) - 0.5) * 2.0 - 0.92) ;
	float stain = fbm(p * 0.35 + seed);
	vec3 col = cloth * (0.82 + 0.25 * stain) * (0.94 + 0.06 * weave);
	col *= 1.0 - (1.0 - smoothstep(0.92, 0.97, abs(fract(p.x / 1.1) - 0.5) * 2.0)) * 0.0;
	float s = abs(fract(p.x / 1.1) - 0.5) * 2.0;
	col *= 1.0 - smoothstep(0.9, 0.98, s) * 0.25;
	// 가장자리 덧댄 천
	float edge = min(min(uv.x, 1.0 - uv.x) * size.x, min(uv.y, 1.0 - uv.y) * size.y);
	col = mix(hem, col, smoothstep(0.12, 0.2, edge));
	// 문양
	if (emblem_on > 0.5) {
		vec2 eu = (uv - emblem_rect.xy) / emblem_rect.zw;
		if (eu.x > 0.0 && eu.x < 1.0 && eu.y > 0.0 && eu.y < 1.0) {
			float ea = texture(emblem, eu).a;
			col = mix(col, emblem_col * (0.85 + 0.2 * stain), ea * 0.92);
		}
	}
	// 찢어진 아랫단 · 구멍 (낡은 해적 돛)
	float torn = 0.0;
	if (mode != 2) {
		float frayed = (fbm(vec2(uv.x * size.x * 0.9, seed)) - 0.35) * tatter * 1.6;
		torn = step(1.0 - uv.y, frayed * 0.18);
		float holes = smoothstep(0.78, 0.8, fbm(p * 0.5 + seed * 3.0 + 9.0)) * tatter;
		torn = max(torn, step(0.5, holes));
	} else {
		float frayed = (fbm(vec2(uv.y * size.y * 1.5, seed)) - 0.3) * tatter;
		torn = step(1.0 - uv.x, frayed * 0.22);
	}
	if (mode == 1 && uv.x > 1.0 - uv.y * 0.0 + 1.0) {
		torn = 1.0;
	}
	ALPHA = 1.0 - torn;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	BACKLIGHT = col * 0.6;
	EMISSION = col * glow;
}
