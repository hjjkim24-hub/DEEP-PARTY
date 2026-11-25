shader_type spatial;
// 꽁꽁 언 잔교: 가운데는 투명하게 언 빙판 (금 간 자국 · 미끄러진 긁힌 자국 · 얼음 속 기포, 밑의 나무가 푸르스름하게 비침)
// 가장자리와 군데군데는 눈이 쌓임 (뭉실뭉실한 결 + 햇빛에 반짝이는 눈 결정).
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform float half_w = 4.8;

varying vec3 wp;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + 17.31));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// 보로노이: x = 가장 가까운 점까지, y = 경계까지 (금 간 선)
vec2 voro(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			float d = length(g + hash2(i + g) - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(d1, d2 - d1);
}

float snow_amt(vec2 p) {
	float ax = abs(p.x);
	float drift = smoothstep(half_w - 1.3 - fbm(vec2(p.y * 0.3, 1.0)) * 0.8, half_w - 0.45, ax);   // 가장자리 눈 더미
	float patch = smoothstep(0.69, 0.77, fbm(p * 0.42 + 5.0)) * 0.9;                                    // 군데군데 쌓인 눈
	float dust = smoothstep(0.62, 0.8, fbm(p * 1.7)) * 0.3;                                     // 얇게 흩뿌려진 눈
	return clamp(drift + patch + dust, 0.0, 1.0);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float sn = snow_amt(p);
	float snow = smoothstep(0.35, 0.7, sn);
	// ── 얼음 ──
	vec2 v1 = voro(p * 0.55);
	vec2 v2 = voro(p * 1.6 + 3.0);
	float crack = smoothstep(0.035, 0.0, v1.y) * smoothstep(0.35, 0.6, fbm(p * 0.8 + 2.0))   // 큰 금
		+ smoothstep(0.02, 0.0, v2.y) * 0.45 * step(0.55, fbm(p * 1.1));                       // 잔금
	// 미끄러진 자국: 다리 방향으로 길게 그어진 가는 흰 선들
	float sx = p.x * 6.0 + fbm(vec2(p.y * 0.15, p.x)) * 3.0;
	float scr = smoothstep(0.04, 0.0, abs(fract(sx) - 0.5) - 0.46) * step(0.7, noise(vec2(floor(sx), p.y * 0.12))) * 0.25;
	// 얼음 속 기포 (작은 흰 점)
	vec2 vb = voro(p * 9.0);
	float bub = smoothstep(0.09, 0.03, vb.x) * step(0.9, hash(floor(p * 9.0))) * 0.6;
	float frost = smoothstep(0.55, 0.85, fbm(p * 3.0 + 9.0)) * 0.22;   // 희뿌연 서리
	float ice_w = clamp(crack + scr + bub + frost, 0.0, 1.0);
	// 노멀: 얼음은 살짝 울퉁불퉁, 눈은 뭉실뭉실
	float e = 0.03;
	float h0 = fbm(p * 0.9) * 0.06 + sn * 0.5 + fbm(p * 5.0) * 0.12 * snow;
	float hx = fbm((p + vec2(e, 0.0)) * 0.9) * 0.06 + snow_amt(p + vec2(e, 0.0)) * 0.5 + fbm((p + vec2(e, 0.0)) * 5.0) * 0.12 * snow;
	float hz = fbm((p + vec2(0.0, e)) * 0.9) * 0.06 + snow_amt(p + vec2(0.0, e)) * 0.5 + fbm((p + vec2(0.0, e)) * 5.0) * 0.12 * snow;
	vec3 nw = normalize(vec3(-(hx - h0) / e, 1.0, -(hz - h0) / e));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// 눈 결정 반짝임: 보는 위치가 바뀌면 다른 결정이 반짝
	vec2 cell = floor(p * 36.0);
	float tw = hash(cell + floor(CAMERA_POSITION_WORLD.xz * 1.5) * 0.37);
	float sparkle = step(0.988, tw) * snow;
	vec3 ice_col = mix(vec3(0.36, 0.55, 0.72), vec3(0.92, 0.96, 1.0), ice_w);
	vec3 snow_col = vec3(0.94, 0.96, 1.0);
	ALBEDO = mix(ice_col, snow_col, snow);
	ROUGHNESS = mix(mix(0.015, 0.3, ice_w), 0.85, snow);
	SPECULAR = mix(0.6, 0.35, snow);
	EMISSION = vec3(1.0, 1.0, 0.95) * sparkle * 1.6 + vec3(0.02, 0.04, 0.06) * (1.0 - snow);
	ALPHA = mix(0.5 + ice_w * 0.4, 1.0, snow);
}
