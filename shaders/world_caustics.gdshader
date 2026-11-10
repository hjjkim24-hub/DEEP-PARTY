shader_type canvas_item;
// 바닥 위에 일렁이는 물빛 무늬 (월드 지도용). 지도 크기에 맞춰 무늬 크기가 일정하게.
uniform vec2 map_size = vec2(4800.0, 3200.0);
uniform float cell = 260.0;
uniform float strength = 0.16;

float caustic(vec2 p, float t) {
	float a = sin(p.x * 3.1 + sin(p.y * 2.3 + t) * 1.7 + t);
	float b = sin(p.y * 3.7 + sin(p.x * 1.9 - t * 1.3) * 1.5 - t * 0.8);
	return pow(max(a * b, 0.0), 2.5);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 p = UV * map_size / cell;
	float t = TIME * 0.45;
	float c = caustic(p, t) + 0.6 * caustic(p * 1.7 + 3.1, t * 1.3);
	COLOR = vec4(base.rgb + c * strength * vec3(0.55, 1.0, 0.88), base.a);
}
