shader_type sky;
// 물속 하늘: 위는 밝은 물빛, 수평선은 청록, 아래는 깊은 바다 + 일렁이는 수면 무늬
uniform vec3 top_color : source_color = vec3(0.3, 0.74, 0.76);
uniform vec3 horizon_color : source_color = vec3(0.05, 0.3, 0.33);
uniform vec3 bottom_color : source_color = vec3(0.01, 0.07, 0.09);

void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(horizon_color, top_color, smoothstep(0.0, 0.85, y));
	c = mix(c, bottom_color, smoothstep(0.0, -0.45, y));
	float sun = pow(max(dot(EYEDIR, normalize(vec3(0.25, 1.0, 0.15))), 0.0), 18.0);
	c += vec3(0.55, 0.9, 0.85) * sun * 0.55;
	if (y > 0.02) {
		vec2 uv = EYEDIR.xz / y;
		float w = sin(uv.x * 2.6 + TIME * 0.35 + sin(uv.y * 1.7)) * sin(uv.y * 3.1 - TIME * 0.27 + sin(uv.x * 1.3));
		c += vec3(0.12, 0.24, 0.22) * smoothstep(0.55, 1.0, w) * smoothstep(0.08, 0.6, y);
	}
	COLOR = c;
}
