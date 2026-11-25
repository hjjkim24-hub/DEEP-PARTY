shader_type spatial;
// 살얼음 끼고 눈 덮인 잔교: 다리 전체에 얇은 희뿌연 얼음막 + 쓸린 소용돌이 자국 + 군데군데 쌓인 눈 (작은 눈 뭉치들)
// + 비스듬히 보면 살짝 무지갯빛. 막은 매끈해서 하늘 · 햇빛이 번들번들 비침.
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform float half_w = 4.8;

varying vec3 wp;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(mod(p, 289.0)) * 43758.5453);
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
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
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// 거품 방울: 보로노이 셀 = 방울 하나, 셀 경계 = 방울 벽
vec3 bubbles(vec2 p, float t, out vec2 to_c) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			o = 0.5 + 0.38 * sin(t * 0.6 + 6.2831 * o);   // 방울이 아주 천천히 꿈틀
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = i + g;
				to_c = g + o - f;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2 - d1, hash(id));
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float t = TIME;
	// 걸레로 쓱쓱 문지른 소용돌이 · 쓸린 자국 (막 두께)
	vec2 warp = vec2(fbm(p * 0.35), fbm(p * 0.35 + 7.3)) * 4.0;
	float swirl = 0.5 + 0.5 * sin(length(fract((p + warp) / 3.2) - 0.5) * 22.0 + fbm(p * 0.8) * 5.0);
	float streak = fbm(vec2(p.x * 0.6, p.y * 1.8) + warp * 0.5);
	float film = clamp(0.35 + 0.45 * swirl * streak + 0.25 * fbm(p * 1.3), 0.0, 1.0);
	// 거품 덩어리: 가장자리 쪽에 많이, 가운데는 작게 듬성듬성
	float edge_x = smoothstep(half_w - 1.6, half_w - 0.15, abs(p.x));
	float clump = fbm(p * 0.6 + 3.0) + edge_x * 0.3;
	float foam = smoothstep(0.63, 0.75, clump);
	vec2 tc;
	vec2 tc2;
	vec3 bb = bubbles(p * 5.5, t, tc);              // 큰 방울 (지름 ~15cm)
	vec3 bs = bubbles(p * 13.0 + 4.0, t * 1.3, tc2); // 작은 방울
	float r1 = 0.5 + 0.25 * bb.z;                     // 방울마다 크기 다름
	float in1 = smoothstep(r1, r1 - 0.12, bb.x);       // 방울 안쪽
	float in2 = smoothstep(0.42, 0.3, bs.x);
	float use_big = step(0.35, bb.z);                 // 큰 방울 자리 / 작은 방울 자리
	float dome = mix(in2, in1, use_big);
	vec2 dn = mix(tc2 * 2.2, tc * 1.6, use_big) * dome; // 방울 볼록한 면의 기울기
	float gap = 1.0 - dome;                           // 방울 사이 틈은 살짝 그늘
	float suds = foam * clamp(dome + 0.25, 0.0, 1.0);
	// 거품 없는 곳에도 흩어진 작은 방울
	float speck = in2 * step(0.97, bs.z) * (1.0 - foam) * 0.4;
	vec2 grad = vec2(fbm(p * 2.0 + vec2(0.05, 0.0)) - fbm(p * 2.0), fbm(p * 2.0 + vec2(0.0, 0.05)) - fbm(p * 2.0)) * 0.6;
	vec2 bump = -grad - dn * (foam + speck) * 0.9;
	vec3 nw = normalize(vec3(bump.x, 1.0, bump.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// 무지갯빛 (얇은 비누막 간섭) — 비스듬히 볼수록 강하게
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float th = film * 2.4 + fbm(p * 0.9 + 11.0) * 1.6 + fr;
	vec3 rainbow = 0.5 + 0.5 * cos(6.2832 * (th + vec3(0.0, 0.33, 0.67)));
	float edge_fade = smoothstep(half_w + 0.02, half_w - 0.12, abs(p.x));
	vec3 milk = vec3(0.93, 0.95, 0.97);
	vec3 sud_col = mix(vec3(0.72, 0.76, 0.82), vec3(0.98), dome);   // 방울 틈은 푸르스름한 그늘
	ALBEDO = mix(milk, sud_col, foam);
	EMISSION = rainbow * (0.03 + 0.08 * fr) * film * (1.0 - foam) + rainbow * 0.05 * fr * dome * foam;
	ROUGHNESS = mix(0.04, 0.12, foam);
	SPECULAR = 0.6;
	ALPHA = clamp(0.05 + film * film * 0.3 + foam * (0.55 + 0.4 * dome) + speck * 0.45, 0.0, 0.95) * edge_fade;
}
