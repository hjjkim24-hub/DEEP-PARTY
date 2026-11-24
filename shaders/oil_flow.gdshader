shader_type spatial;
// 잔교 위로 흘러내리는 투명한 기름막: 결 따라 길게 갈라진 기름 줄기가 위(결승선)에서 아래(출발선)로 흐름.
// 줄기 속은 밑의 나무가 일렁여 비치고(굴절), 매끈한 면에 하늘 · 햇빛이 번들번들 반사됨.
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 tint : source_color = vec3(0.95, 0.8, 0.42);
uniform float speed = 1.1;      // 흐르는 속도 (m/s, +z 방향)
uniform float half_w = 4.8;

varying vec3 wp;

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

// 기름 두께: 결 방향(z)으로 길쭉한 줄기 + 그 위를 따라 내려가는 작은 물결
float thick(vec2 p, float t) {
	float wob = fbm(vec2(p.y * 0.12, 3.0)) * 2.2;          // 줄기가 좌우로 살짝 굽이침
	float lanes = fbm(vec2((p.x + wob) * 1.25, p.y * 0.08));  // 줄기 자리 (천천히 바뀜)
	float riv = smoothstep(0.46, 0.66, lanes);
	float ripple = fbm(vec2((p.x + wob) * 2.6, (p.y - t) * 0.9));          // 흘러내리는 결
	float lobes = fbm(vec2((p.x + wob) * 1.4 + 11.0, (p.y - t * 0.8) * 0.35)); // 덩어리져 밀려 내려오는 앞머리
	return riv * (0.55 + 0.45 * ripple) * (0.6 + 0.6 * lobes) + 0.12 * ripple;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float t = TIME * speed;
	float h = thick(p, t);
	float e = 0.04;
	float hx = thick(p + vec2(e, 0.0), t) - h;
	float hz = thick(p + vec2(0.0, e), t) - h;
	vec3 nw = normalize(vec3(-hx / e * 0.13, 1.0, -hz / e * 0.13));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// 가장자리 근처는 얇아짐 (흘러 넘쳐 떨어지는 곳)
	float edge = smoothstep(half_w, half_w - 0.5, abs(p.x));
	float a = clamp(h * 1.25, 0.0, 1.0) * edge;
	// 굴절: 기름 줄기 속으로 비치는 나무가 일렁임
	vec2 off = nw.xz * 0.028 * a;
	vec3 bg = texture(screen_tex, SCREEN_UV + off).rgb;
	ALBEDO = tint * 0.04;
	EMISSION = bg * mix(vec3(1.0), tint, 0.3 * a);
	ROUGHNESS = mix(0.18, 0.03, a);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	// 기름 줄기 가장자리(볼록한 테두리)는 빛을 더 받아 반짝
	float rim = clamp(length(vec2(hx, hz)) / e * 0.35, 0.0, 1.0);
	EMISSION += vec3(1.0, 0.97, 0.88) * rim * 0.12 * edge;
	ALPHA = clamp(a * 0.55 + rim * 0.3 * edge, 0.0, 0.8);
}
