shader_type canvas_item;
// 미니게임 소개 화면 배경: 깊은 남색 → 청록 무대 조명, 비스듬히 흐르는 줄무늬, 반짝이
uniform vec4 top_color : source_color = vec4(0.03, 0.12, 0.22, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.01, 0.04, 0.08, 1.0);
uniform vec4 spot_color : source_color = vec4(0.12, 0.55, 0.55, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.5, 0.95, 0.85, 1.0);
uniform vec2 aspect = vec2(1.7778, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec3 c = mix(top_color.rgb, bottom_color.rgb, uv.y);
	// 위에서 내리쬐는 무대 조명 두 개
	vec2 p = uv * aspect;
	for (int i = 0; i < 2; i++) {
		float x = (i == 0 ? 0.55 : 1.25) + sin(TIME * 0.4 + float(i) * 2.0) * 0.12;
		float d = abs(p.x - x - (p.y - 0.0) * (i == 0 ? 0.25 : -0.25));
		float beam = smoothstep(0.32 + p.y * 0.25, 0.0, d) * (1.0 - uv.y * 0.6);
		c += spot_color.rgb * beam * 0.35;
	}
	// 비스듬한 줄무늬 (천천히 흐름)
	float s = sin((p.x + p.y) * 26.0 - TIME * 1.5);
	c += stripe_color.rgb * smoothstep(0.92, 1.0, s) * 0.035;
	// 반짝이
	vec2 g = floor(p * 40.0);
	float h = hash(g);
	float tw = step(0.985, h) * (0.5 + 0.5 * sin(TIME * 3.0 + h * 60.0));
	c += vec3(0.7, 1.0, 0.95) * tw * 0.35;
	// 가장자리 어둡게
	vec2 q = uv - 0.5;
	c *= 1.0 - dot(q, q) * 0.9;
	COLOR = vec4(c, 1.0);
}
