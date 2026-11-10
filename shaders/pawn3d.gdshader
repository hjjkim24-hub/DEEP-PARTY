shader_type spatial;
// 3D 말 몸통: 반질반질한 칠 + 무늬 (0 없음, 1 줄무늬, 2 다이아몬드)
uniform vec4 base_color : source_color = vec4(1.0, 0.48, 0.42, 1.0);
uniform vec4 pattern_color : source_color = vec4(1.0);
uniform int pattern = 0;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 c = base_color.rgb;
	float th = atan(lp.x, lp.z);
	if (pattern == 1) {
		float s = smoothstep(0.45, 0.55, fract(lp.y * 9.0));
		c = mix(c, pattern_color.rgb, s * step(0.1, lp.y) * step(lp.y, 0.62));
	} else if (pattern == 2) {
		vec2 q = vec2(th * 2.0, lp.y * 7.0);
		vec2 f = abs(fract(q) - 0.5);
		float d = 1.0 - smoothstep(0.26, 0.3, f.x + f.y);
		c = mix(c, pattern_color.rgb, d * step(0.1, lp.y) * step(lp.y, 0.62));
	}
	ALBEDO = c;
	ROUGHNESS = 0.22;
	SPECULAR = 0.7;
}
