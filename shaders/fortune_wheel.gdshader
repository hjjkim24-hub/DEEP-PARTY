shader_type spatial;
render_mode cull_back;
// 크라켄의 행운 바퀴 앞면 (QuadMesh, 로컬 XY 평면): 칠한 나무판. 금박 칠 보물 칸 · 짙은 초록 옻칠 크라켄 칸이 번갈아
// 칠이 군데군데 벗겨져 나뭇결이 드러나고, 그림은 붓으로 그린 듯. 0 = 위, 시계 방향으로 칸 번호

uniform sampler2D chest_tex : source_color, filter_linear_mipmap;
uniform sampler2D kraken_tex : source_color, filter_linear_mipmap;
uniform float segs = 10.0;
uniform float radius = 1.8;
uniform int highlight = -1;
uniform float flash = 0.0;

varying vec3 lp;

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
float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * n2(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 q = lp.xy / radius;
	float d = length(q);
	if (d > 1.0) {
		discard;
	}
	float phi = atan(q.x, q.y);
	if (phi < 0.0) {
		phi += 6.2831853;
	}
	float sw = 6.2831853 / segs;
	float fi = floor(phi / sw);
	float fa = fract(phi / sw);
	bool chest = mod(fi, 2.0) < 0.5;
	// 나무판 (세로 결)
	float g = fbm(vec2(q.x * 2.0, q.y * 26.0)) * 0.7 + fbm(vec2(q.x * 9.0, q.y * 90.0)) * 0.3;
	vec3 wood = mix(vec3(0.24, 0.13, 0.06), vec3(0.46, 0.28, 0.14), g);
	// 칠: 금박 (안쪽이 짙고 바깥이 밝은 금) / 짙은 초록 옻칠
	float r = clamp((d - 0.2) / 0.72, 0.0, 1.0);
	vec3 paint;
	if (chest) {
		paint = mix(vec3(0.56, 0.36, 0.1), vec3(0.93, 0.72, 0.32), 0.35 + 0.65 * r);
		paint *= 0.9 + 0.12 * fbm(q * 14.0 + fi);          // 금박을 이어 붙인 결
	} else {
		paint = mix(vec3(0.03, 0.15, 0.1), vec3(0.08, 0.32, 0.21), 0.3 + 0.7 * r);
		paint *= 0.92 + 0.1 * fbm(q * 10.0 + fi * 3.0);
	}
	// 그림 (칸 가운데, 바깥쪽이 그림의 위)
	float pc = (fi + 0.5) * sw;
	vec2 dirc = vec2(sin(pc), cos(pc));
	vec2 side = vec2(cos(pc), -sin(pc));
	vec2 rel = q - dirc * 0.6;
	vec2 iuv = vec2(dot(rel, side), -dot(rel, dirc)) / 0.36 + 0.5;
	float ia = 0.0;
	if (iuv.x > 0.0 && iuv.x < 1.0 && iuv.y > 0.0 && iuv.y < 1.0) {
		ia = chest ? texture(chest_tex, iuv).a : texture(kraken_tex, iuv).a;
	}
	// 붓 자국처럼 가장자리가 살짝 거칠게
	ia = smoothstep(0.35, 0.65, ia + (n2(q * 160.0) - 0.5) * 0.25);
	vec3 ink = chest ? vec3(0.22, 0.1, 0.03) : vec3(0.78, 0.95, 0.6);
	vec3 col = mix(paint, ink, ia);
	// 칸 둘레 가는 금선 (칠 위에 그린 테두리)
	float edge = min(fa, 1.0 - fa) * sw * d;
	float line = (1.0 - smoothstep(0.018, 0.026, edge)) * step(0.22, d) * step(d, 0.9);
	float ring = (1.0 - smoothstep(0.006, 0.014, abs(d - 0.88))) + (1.0 - smoothstep(0.006, 0.014, abs(d - 0.24)));
	vec3 gold_line = vec3(0.9, 0.7, 0.3);
	col = mix(col, gold_line, clamp(line + ring, 0.0, 1.0) * 0.9);
	// 바깥 띠 (검붉은 칠 + 금 점)
	if (d > 0.9) {
		col = mix(vec3(0.22, 0.03, 0.03), vec3(0.36, 0.06, 0.05), fbm(q * 20.0));
		float dots = 1.0 - smoothstep(0.012, 0.02, length(vec2((fract(phi / sw * 2.0) - 0.5) * sw * 0.5 * d, d - 0.95)));
		col = mix(col, gold_line, dots);
	}
	// 오래 써서 칠이 벗겨진 곳 (칸 가장자리 · 바깥쪽에 많이)
	float wear = fbm(q * 7.0 + 3.1) * 0.65 + fbm(q * 31.0) * 0.35;
	wear += (1.0 - smoothstep(0.0, 0.06, edge)) * 0.25 + smoothstep(0.8, 1.0, d) * 0.15;
	float chip = smoothstep(0.66, 0.72, wear);
	col = mix(col, wood * 0.9, chip * 0.85);
	// 때 · 그을음
	col *= 0.86 + 0.14 * fbm(q * 3.0 + 9.0);
	ALBEDO = col;
	float gold_amt = (chest ? (1.0 - ia) : 0.0) * (1.0 - chip) * step(d, 0.9);
	METALLIC = max(gold_amt * 0.6, clamp(line + ring, 0.0, 1.0) * 0.8);
	ROUGHNESS = mix(chest ? 0.35 : 0.22, 0.7, chip) + 0.08 * n2(q * 50.0);
	SPECULAR = 0.55;
	// 칠의 두께 (붓질 결 · 그림 돋음)
	vec3 nb = vec3((n2(q * 90.0) - 0.5) * 0.12, (n2(q * 90.0 + 5.0) - 0.5) * 0.12, 1.0);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * (MODEL_MATRIX * vec4(nb.x, nb.y, 0.0, 0.0))).xyz * 0.6);
	if (int(fi) == highlight) {
		EMISSION = (chest ? vec3(1.0, 0.75, 0.3) : vec3(0.45, 1.0, 0.4)) * flash * 0.6;
	}
}
