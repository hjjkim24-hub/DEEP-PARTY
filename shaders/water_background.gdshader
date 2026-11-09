shader_type canvas_item;
// 물속 배경: 위는 밝은 민트, 아래로 갈수록 깊은 에메랄드 + 일렁이는 빛무늬(코스틱)

uniform vec4 surface_color : source_color = vec4(0.42, 0.93, 0.80, 1.0);
uniform vec4 mid_color : source_color = vec4(0.04, 0.56, 0.50, 1.0);
uniform vec4 deep_color : source_color = vec4(0.01, 0.15, 0.17, 1.0);
uniform float caustic_strength = 0.32;
uniform float caustic_scale = 2.2;
uniform float caustic_speed = 0.35;
uniform vec2 aspect = vec2(1.7778, 1.0);
uniform vec2 parallax = vec2(0.0);

float caustic(vec2 uv, float time) {
	vec2 p = mod(uv * TAU, TAU) - 250.0;
	vec2 i = p;
	float c = 1.0;
	float inten = 0.005;
	for (int n = 0; n < 5; n++) {
		float t = time * (1.0 - (3.5 / float(n + 1)));
		i = p + vec2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));
		c += 1.0 / length(vec2(p.x / (sin(i.x + t) / inten), p.y / (cos(i.y + t) / inten)));
	}
	c /= 5.0;
	c = 1.17 - pow(c, 1.4);
	return pow(abs(c), 8.0);
}

void fragment() {
	vec2 uv = UV;
	float depth = uv.y;

	// 깊이에 따른 색
	vec3 col = mix(surface_color.rgb, mid_color.rgb, smoothstep(0.0, 0.5, depth));
	col = mix(col, deep_color.rgb, smoothstep(0.45, 1.0, depth));

	// 수면 근처 밝은 띠 (살짝 출렁임)
	float surf = uv.y + sin(uv.x * 22.0 + TIME * 1.3) * 0.006 + sin(uv.x * 9.0 - TIME * 0.8) * 0.008;
	col += vec3(0.35, 0.60, 0.50) * (1.0 - smoothstep(0.0, 0.08, surf)) * 0.55;
	col += vec3(0.20, 0.32, 0.26) * (1.0 - smoothstep(0.0, 0.25, depth)) * 0.35;

	// 일렁이는 빛무늬
	vec2 cuv = (uv + parallax * 0.015) * vec2(aspect.x / aspect.y, 1.0) * caustic_scale;
	cuv.y *= 1.35;
	float c1 = caustic(cuv, TIME * caustic_speed);
	float c2 = caustic(cuv * 0.6 + vec2(0.37, 0.11), TIME * caustic_speed * 0.7 + 4.0);
	float fade = 1.0 - smoothstep(0.0, 0.9, depth);
	col += vec3(0.62, 1.0, 0.88) * (c1 * 0.7 + c2 * 0.5) * caustic_strength * fade;

	COLOR = vec4(col, 1.0);
}
