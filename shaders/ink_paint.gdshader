shader_type spatial;
// 먹물 땅따먹기: 칸 텍스처를 부드럽게 늘린 뒤 가장자리를 잡음으로 울퉁불퉁하게 잘라 "물감이 번진" 모양으로
uniform sampler2D paint : source_color, filter_linear;
uniform float grid = 72.0;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float wob = n(uv * grid * 0.9) * 0.6 + n(uv * grid * 2.7) * 0.4;
	vec4 c = texture(paint, uv + (vec2(n(uv * 40.0), n(uv * 40.0 + 7.0)) - 0.5) / grid * 0.9);
	float a = smoothstep(0.42, 0.55, c.a + (wob - 0.5) * 0.35);
	vec3 col = c.rgb / max(c.a, 0.05);
	// 가운데는 진하고 가장자리는 살짝 밝게 + 광택
	col *= 0.88 + 0.2 * n(uv * grid * 1.6);
	ALBEDO = col;
	ALPHA = a * 0.95;
	ROUGHNESS = 0.18;
	SPECULAR = 0.6;
	CLEARCOAT = 1.0;
}
