shader_type canvas_item;
// 미리 그려 둔 바다 밑 장면 위에 "움직이는 빛무늬(코스틱)"를 얹는 셰이더.
// pos_tex 에 바닥/물체 표면의 월드 좌표가 들어 있어서, 빛무늬가 바닥과 보드판 표면을 따라 자연스럽게 일렁여요.

uniform sampler2D pos_tex : filter_nearest;   // RGB 에 x, z 를 12비트씩 압축
uniform sampler2D mask_tex : filter_linear;   // 빛이 닿는 세기
uniform float strength = 0.5;
uniform float scale = 0.85;
uniform float speed = 0.33;
uniform vec4 light_color : source_color = vec4(0.72, 1.0, 0.9, 1.0);

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
	vec4 base = texture(TEXTURE, UV);
	vec3 e = floor(texture(pos_tex, UV).rgb * 255.0 + 0.5);
	float xq = e.r * 16.0 + floor(e.g / 16.0);
	float zq = mod(e.g, 16.0) * 256.0 + e.b;
	vec2 world = vec2(xq / 4095.0 * 20.0 - 8.0, zq / 4095.0 * 48.0 - 40.0);
	float m = texture(mask_tex, UV).r;
	float c = caustic(world * scale, TIME * speed) * 0.7
		+ caustic(world * scale * 0.63 + vec2(0.31, 0.17), TIME * speed * 0.8 + 3.0) * 0.5;
	base.rgb += light_color.rgb * c * m * strength;
	COLOR = base;
}
