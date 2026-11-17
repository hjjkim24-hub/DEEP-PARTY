shader_type sky;
// 크라켄의 배: 구름 바다 위 밤하늘 (별 · 은하수 · 달 · 달무리)

uniform vec3 moon_dir = vec3(-0.5, 0.34, -0.8);
uniform vec3 zenith : source_color = vec3(0.012, 0.018, 0.06);
uniform vec3 horizon : source_color = vec3(0.10, 0.09, 0.21);
uniform vec3 below : source_color = vec3(0.035, 0.04, 0.09);

float h13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
vec3 h33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}
float n3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h13(i), h13(i + vec3(1, 0, 0)), f.x), mix(h13(i + vec3(0, 1, 0)), h13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h13(i + vec3(0, 0, 1)), h13(i + vec3(1, 0, 1)), f.x), mix(h13(i + vec3(0, 1, 1)), h13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * n3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}
float stars(vec3 d, float scale, float density, float tm) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	float s = 0.0;
	for (int k = 0; k < 2; k++) {
		vec3 cc = c + vec3(float(k) * 0.5);
		vec3 cell = floor(p + float(k) * 0.5);
		float h = h13(cell + 11.0);
		if (h > density) {
			vec3 sp = cell + h33(cell) - float(k) * 0.5;
			float dist = length(p - sp);
			float tw = 0.65 + 0.35 * sin(tm * (1.5 + h * 4.0) + h * 60.0);
			s += smoothstep(0.09, 0.0, dist) * tw * (0.4 + 2.2 * (h - density) / (1.0 - density));
		}
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.5));
	// 달 쪽 하늘은 살짝 밝게
	vec3 md = normalize(moon_dir);
	float mc = dot(d, md);
	col += vec3(0.1, 0.12, 0.2) * pow(max(mc, 0.0), 6.0) * 0.6;
	if (h > -0.05) {
		float up = smoothstep(-0.02, 0.18, h);
		// 은하수: 하늘을 비스듬히 가로지르는 띠 + 먼지 결
		vec3 bn = normalize(vec3(0.35, 0.45, 0.82));
		float band = exp(-pow(dot(d, bn), 2.0) * 18.0);
		float dust = fbm(d * 7.0);
		float lanes = smoothstep(0.45, 0.75, fbm(d * 14.0 + 4.0));
		col += vec3(0.16, 0.14, 0.26) * band * (dust * 0.9 - lanes * 0.35) * up;
		float st = stars(d, 260.0, 0.93, TIME) + stars(d, 520.0, 0.95, TIME) * 0.6 + stars(d, 110.0, 0.985, TIME) * 1.5;
		st *= (0.4 + band * 1.4) * up;
		col += vec3(0.85, 0.9, 1.0) * st * 1.6;
	}
	// 달: 둥근 원판 + 바다(어두운 무늬) + 달무리
	float mr = 0.032;
	float ang = acos(clamp(mc, -1.0, 1.0));
	if (ang < mr * 1.02) {
		vec3 lp = (d - md * mc) / mr;
		float maria = fbm(lp * 3.0 + 7.0);
		vec3 mcol = vec3(1.0, 0.97, 0.88) * (1.15 - smoothstep(0.45, 0.75, maria) * 0.35);
		float edge = smoothstep(mr * 1.02, mr * 0.96, ang);
		col = mix(col, mcol * 3.2, edge);
	}
	col += vec3(0.55, 0.62, 0.85) * exp(-ang * 26.0) * 0.55 + vec3(0.25, 0.3, 0.5) * exp(-ang * 6.0) * 0.18;
	if (h < 0.0) {
		col = mix(col, below, smoothstep(0.0, -0.25, h));
	}
	COLOR = col;
}
