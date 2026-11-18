shader_type spatial;
// 미니게임 바닷속 모래 바닥: 모래 텍스처 + 물결무늬 + 일렁이는 빛 무늬(코스틱)
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.72);
uniform float tex_scale = 0.22;
uniform float caustic_k = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float caustic(vec2 p, float t) {
	vec2 q = p;
	float c = 0.0;
	for (int i = 0; i < 3; i++) {
		q += vec2(sin(q.y * 1.3 + t + float(i)), cos(q.x * 1.1 - t * 0.8 + float(i) * 1.7)) * 0.55;
		c += abs(sin(q.x * 1.6) * cos(q.y * 1.6));
	}
	return pow(clamp(1.0 - c / 3.0, 0.0, 1.0), 6.0);
}

void fragment() {
	vec2 uv = wpos.xz * tex_scale;
	vec3 a = texture(sand_albedo, uv).rgb;
	vec3 a2 = texture(sand_albedo, uv * 0.31 + 0.37).rgb;
	ALBEDO = mix(a, a2, 0.4) * tint;
	NORMAL_MAP = texture(sand_normal, uv).rgb;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = 0.92;
	float t = TIME * 0.6;
	float cs = caustic(wpos.xz * 0.45, t) + caustic(wpos.xz * 0.8 + 3.0, t * 1.3) * 0.6;
	EMISSION = vec3(0.55, 0.85, 0.8) * cs * 0.35 * caustic_k;
}
