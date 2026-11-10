shader_type spatial;
// 두 색 줄무늬 (고깔모자·튜브·목도리용). mode 0 = 높이 방향, 1 = 둘레 방향
uniform vec4 color_a : source_color = vec4(0.95, 0.42, 0.40, 1.0);
uniform vec4 color_b : source_color = vec4(0.98, 0.94, 0.86, 1.0);
uniform float count = 8.0;
uniform int mode = 0;
uniform float roughness_v = 0.45;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float u = mode == 0 ? lp.y * count : (atan(lp.x, lp.z) / 6.2831853 + 0.5) * count;
	float s = step(0.5, fract(u));
	ALBEDO = mix(color_a.rgb, color_b.rgb, s);
	ROUGHNESS = roughness_v;
}
