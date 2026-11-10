shader_type spatial;
// 칸 윗면: 유약 바른 색 + 흰 테두리 + 도드라진 무늬 + 물빛
uniform vec4 tile_color : source_color = vec4(0.27, 0.59, 0.9, 1.0);
uniform vec4 ink_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform vec4 border_color : source_color = vec4(0.93, 0.94, 0.9, 1.0);
uniform sampler2D icon_tex : source_color, filter_linear_mipmap;
uniform sampler2D border_tex : source_color, filter_linear_mipmap;
uniform float icon_scale = 0.62;
varying vec3 wpos;

float caustic(vec2 p, float t) {
	float a = sin(p.x * 3.1 + sin(p.y * 2.3 + t) * 1.7 + t);
	float b = sin(p.y * 3.7 + sin(p.x * 1.9 - t * 1.3) * 1.5 - t * 0.8);
	return pow(max(a * b, 0.0), 2.5);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	vec3 c = tile_color.rgb;
	float glow = 1.0 - length(uv - 0.5) * 1.2;
	c += vec3(0.04) * glow;
	float b = texture(border_tex, uv).a;
	c = mix(c, border_color.rgb, b);
	vec2 iuv = (uv - 0.5) / icon_scale + 0.5;
	float ic = 0.0;
	if (iuv.x > 0.0 && iuv.x < 1.0 && iuv.y > 0.0 && iuv.y < 1.0) {
		ic = texture(icon_tex, iuv).a;
	}
	c = mix(c, ink_color.rgb, ic);
	ALBEDO = c;
	ROUGHNESS = mix(0.18, 0.35, b);
	SPECULAR = 0.7;
	float t = TIME * 0.5;
	EMISSION = vec3(0.35, 0.62, 0.52) * (caustic(wpos.xz * 0.35, t) + 0.6 * caustic(wpos.xz * 0.6 + 3.1, t * 1.3)) * 0.18;
}
