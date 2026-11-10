shader_type spatial;
// 포탈 칸 윗면: 빙글빙글 도는 보라색 소용돌이 + 흰 테두리
uniform vec4 deep_color : source_color = vec4(0.16, 0.04, 0.32, 1.0);
uniform vec4 glow_color : source_color = vec4(0.72, 0.45, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.58, 0.38, 0.92, 1.0);
uniform vec4 border_color : source_color = vec4(0.93, 0.94, 0.9, 1.0);
uniform sampler2D border_tex : source_color, filter_linear_mipmap;
uniform float spin = 1.6;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x);
	// 팔 3개짜리 소용돌이가 안쪽으로 빨려 들어감
	float arms = sin(a * 3.0 + log(max(r, 0.02)) * 7.0 + TIME * spin * 3.0);
	float swirl = smoothstep(0.1, 0.9, arms * 0.5 + 0.5);
	float core = smoothstep(0.55, 0.0, r);
	float rim = smoothstep(0.65, 0.95, r);
	vec3 c = mix(deep_color.rgb, glow_color.rgb, swirl * (1.0 - r * 0.6));
	c = mix(c, vec3(1.0, 0.92, 1.0), core * 0.55);
	c = mix(c, edge_color.rgb, rim);
	float b = texture(border_tex, UV).a;
	c = mix(c, border_color.rgb, b);
	ALBEDO = c;
	ROUGHNESS = 0.2;
	EMISSION = (glow_color.rgb * swirl * 0.9 + vec3(1.0, 0.8, 1.0) * core * 1.2) * (1.0 - b) * (1.0 - rim * 0.6);
}
