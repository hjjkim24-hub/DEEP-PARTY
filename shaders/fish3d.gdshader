shader_type spatial;
// 물고기 떼: 인스턴스마다 원을 그리며 헤엄 (위치·방향을 셰이더에서 계산) + 꼬리 흔들기
// INSTANCE_CUSTOM: x = 궤도 각, y = 반지름 차이, z = 높이 차이, w = 개인 위상(0~1)
render_mode cull_disabled;
uniform vec3 center = vec3(0.0, 4.0, 0.0);
uniform float radius = 8.0;
uniform float speed = 0.25;
uniform vec3 color_a : source_color = vec3(1.0, 0.82, 0.25);
uniform vec3 color_b : source_color = vec3(0.3, 0.6, 1.0);
uniform vec3 belly : source_color = vec3(1.0, 0.97, 0.9);
varying float ly;
varying float pick;
varying float tailv;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float th = TIME * speed + c.x;
	float r = radius + c.y;
	vec3 p = center + vec3(cos(th) * r, c.z + sin(TIME * 0.9 + c.w * 6.28) * 0.25, sin(th) * r);
	vec3 T = normalize(vec3(-sin(th), 0.0, cos(th)) * sign(speed));
	float a = atan(T.x, T.z);
	vec3 v = VERTEX;
	ly = v.y;
	tailv = 1.0 - UV.y;
	v.x += sin(TIME * 10.0 + c.w * 20.0 + v.z * 9.0) * 0.07 * tailv * tailv;
	float ca = cos(a);
	float sa = sin(a);
	VERTEX = vec3(v.x * ca + v.z * sa, v.y, -v.x * sa + v.z * ca) + p;
	vec3 n = NORMAL;
	NORMAL = vec3(n.x * ca + n.z * sa, n.y, -n.x * sa + n.z * ca);
	pick = c.w;
}

void fragment() {
	vec3 base = mix(color_a, color_b, step(0.55, pick));
	vec3 col = mix(base, belly, smoothstep(0.0, -0.05, ly) * 0.7);
	col *= 0.85 + 0.25 * smoothstep(0.02, 0.08, ly);
	ALBEDO = col;
	ROUGHNESS = 0.3;
	SPECULAR = 0.7;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
