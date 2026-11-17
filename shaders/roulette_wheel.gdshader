shader_type canvas_item;
// 크라켄의 보물상자 룰렛 원판: 금빛 보물 칸 · 검푸른 크라켄 칸이 번갈아. 나무 테 + 놋쇠 칸막이 · 가운데 놋쇠 축
// 원판 회전(angle)은 여기서 처리 → 광택(위왼쪽 빛)은 돌지 않고 제자리

uniform float angle = 0.0;
uniform float segs = 10.0;
uniform int highlight = -1;
uniform float flash = 0.0;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q);
	float aa = fwidth(d) * 1.2;
	if (d > 1.0 + aa) {
		discard;
	}
	// 원판 기준 각도 (0 = 위, 시계 방향)
	float a = atan(q.x, -q.y) - angle;
	a = mod(a, 6.2831853);
	float sw = 6.2831853 / segs;
	float fi = floor(a / sw);
	float fa = fract(a / sw);
	int seg = int(fi);
	bool chest = mod(fi, 2.0) < 0.5;
	// 빛: 위 왼쪽에서 (돌지 않음)
	vec3 L = normalize(vec3(-0.5, -0.7, 0.9));
	vec3 col;
	if (d < 0.17) {
		// 가운데 놋쇠 축: 동심원 홈 + 둥근 돔
		float dome = sqrt(max(1.0 - pow(d / 0.17, 2.0), 0.0));
		vec3 n = normalize(vec3(q / 0.17 * 0.8, dome));
		float lit = clamp(dot(n, L), 0.0, 1.0);
		col = mix(vec3(0.42, 0.26, 0.08), vec3(1.0, 0.86, 0.5), lit);
		col *= 0.9 + 0.1 * sin(d * 260.0);
		col += pow(max(dot(reflect(-L, n), vec3(0, 0, 1)), 0.0), 24.0) * 0.8;
	} else if (d < 0.2) {
		col = vec3(0.24, 0.14, 0.05) * (0.8 + 0.4 * smoothstep(0.17, 0.2, d));
	} else if (d < 0.84) {
		// 칸: 안쪽은 진하고 바깥으로 밝게 + 칸 가운데가 살짝 볼록
		float r = (d - 0.2) / 0.64;
		float bulge = sin(fa * 3.14159) * sin(r * 3.14159);
		vec3 base = chest ? mix(vec3(0.55, 0.3, 0.05), vec3(1.0, 0.76, 0.26), pow(r, 0.7)) : mix(vec3(0.02, 0.14, 0.1), vec3(0.08, 0.42, 0.28), pow(r, 0.8));
		if (!chest) {
			// 크라켄 칸: 비늘 같은 잔무늬
			vec2 sp = vec2(fa * 6.0, r * 9.0);
			float sc = smoothstep(0.35, 0.5, length(fract(sp + vec2(0.5 * floor(mod(sp.y, 2.0)), 0.0)) - 0.5));
			base *= 0.86 + 0.14 * sc;
		} else {
			// 금 칸: 은은한 결
			base *= 0.92 + 0.08 * n2(vec2(fa * 4.0, r * 12.0) + fi * 7.0);
		}
		vec3 n = normalize(vec3(q * 0.25 * bulge, 1.0));
		col = base * (0.75 + 0.35 * clamp(dot(n, L), 0.0, 1.0));
		if (seg == highlight) {
			col = mix(col, chest ? vec3(1.0, 0.95, 0.7) : vec3(0.55, 1.0, 0.5), flash * 0.55);
		}
		// 칸막이 (놋쇠, 입체)
		float edge = min(fa, 1.0 - fa) * sw * d;
		float bar = 1.0 - smoothstep(0.012, 0.02, edge);
		vec3 brass = mix(vec3(0.55, 0.36, 0.1), vec3(1.0, 0.85, 0.5), smoothstep(0.02, 0.0, edge) * 0.6 + 0.4);
		col = mix(col, brass, bar);
		col *= 1.0 - (1.0 - smoothstep(0.02, 0.045, edge)) * (1.0 - bar) * 0.35;   // 칸막이 옆 그늘
	} else if (d < 0.9) {
		// 놋쇠 테 (둥글게)
		float t = (d - 0.84) / 0.06;
		float hump = sin(t * 3.14159);
		vec3 n = normalize(vec3(q / d * cos(t * 3.14159) * 0.9, hump + 0.2));
		float lit = clamp(dot(n, L), 0.0, 1.0);
		col = mix(vec3(0.4, 0.24, 0.06), vec3(1.0, 0.85, 0.48), lit);
		col += pow(max(dot(reflect(-L, n), vec3(0, 0, 1)), 0.0), 30.0) * 0.6;
	} else {
		// 바깥 나무 테: 결 + 가장자리 어둡게
		float t = (d - 0.9) / 0.1;
		float grain = n2(vec2(atan(q.x, -q.y) * 40.0, d * 8.0)) * 0.5 + n2(vec2(atan(q.x, -q.y) * 140.0, d * 30.0)) * 0.5;
		col = mix(vec3(0.22, 0.11, 0.05), vec3(0.42, 0.24, 0.12), grain);
		col *= 0.7 + 0.45 * sin(t * 3.14159);
	}
	// 전체 광택 (위 왼쪽 큰 반사)
	float gloss = smoothstep(0.75, 0.0, length(q - vec2(-0.35, -0.45))) * 0.12;
	col += gloss * step(d, 0.9);
	COLOR = vec4(col, 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d));
}
