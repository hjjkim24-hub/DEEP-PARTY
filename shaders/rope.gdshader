shader_type spatial;
// 꼰 밧줄: 세 가닥이 비스듬히 꼬인 무늬 + 잔털 · 물 먹은 곳은 짙어짐. UV.x = 길이 방향, UV.y = 둘레 (0~1)
render_mode cull_back, specular_schlick_ggx;

uniform vec3 col : source_color = vec3(0.5, 0.41, 0.27);
uniform float twist = 40.0;     // UV.x 1 당 꼬임 수
uniform float water_y = 0.0;

varying vec3 wp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float s = fract(UV.x * twist + UV.y * 3.0);
	float strand = sin(s * 3.14159);
	float fiber = hash(floor(vec2(UV.x * twist * 6.0, UV.y * 24.0)));
	vec3 c = col * mix(0.55, 1.08, strand) * mix(0.9, 1.08, fiber);
	float wet = 1.0 - smoothstep(-0.02, 0.18, wp.y - water_y);
	c *= mix(1.0, 0.55, wet);
	c = mix(c, vec3(0.14, 0.2, 0.1), smoothstep(0.05, -0.15, wp.y - water_y) * 0.6);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.4, wet);
	// 꼬인 골을 따라 살짝 볼록하게
	NORMAL = normalize(NORMAL + (TANGENT * cos(s * 3.14159) * 0.35));
}
