shader_type canvas_item;
// 상자에서 쏟아지는 빛: 부드러운 빛기둥(빛줄기 사이사이 그늘), 눈부신 중심, 가로 광채, 빛 속을 떠다니는 먼지, 바닥에 번지는 빛
render_mode blend_add;

uniform vec2 origin = vec2(960.0, 540.0);   // 빛이 나오는 곳 (화면 픽셀)
uniform vec2 screen = vec2(1920.0, 1080.0);
uniform float scale = 400.0;                // 상자 크기 (픽셀)
uniform float power = 0.0;                  // 전체 세기
uniform float rays = 0.0;                   // 빛기둥 세기
uniform float core = 0.0;                   // 중심 빛 세기
uniform float spread = 0.9;                 // 빛기둥이 퍼지는 각도 (라디안, 위쪽 기준)

float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void fragment() {
	vec2 p = UV * screen;
	vec2 d = p - origin;
	float r = length(d);
	float a = atan(d.x, -d.y);                   // 0 = 바로 위
	// 위쪽으로 펼쳐지는 부채꼴 (가장자리는 부드럽게)
	float cone = smoothstep(spread, spread * 0.25, abs(a));
	// 빛줄기 무늬: 각도에 따라 굵고 가는 줄이 천천히 일렁임
	float rr = noise1(a * 11.0 + TIME * 0.35) * 0.55 + noise1(a * 29.0 - TIME * 0.6) * 0.3 + noise1(a * 71.0 + TIME) * 0.15;
	rr = pow(rr, 2.2) * 1.8;
	float fall = exp(-r / (scale * 2.4));
	float near = 1.0 - exp(-r / (scale * 0.12));
	float beam = cone * rr * near * fall;
	// 눈부신 중심 (여러 겹 번짐)
	float c1 = exp(-r / (scale * 0.05));
	float c2 = exp(-r / (scale * 0.22));
	float c3 = exp(-r / (scale * 0.9));
	vec3 col = vec3(1.0, 0.99, 0.94) * c1 * 1.6 + vec3(0.75, 1.0, 0.93) * c2 * 0.7 + vec3(0.18, 0.7, 0.6) * c3 * 0.4;
	col *= core;
	vec3 beam_col = mix(vec3(0.92, 1.0, 0.96), vec3(0.15, 0.72, 0.6), clamp(r / (scale * 2.2), 0.0, 1.0));
	col += beam_col * beam * rays;
	// 가로로 길게 뻗는 광채
	float st = exp(-abs(d.y) / (scale * 0.006)) * exp(-abs(d.x) / (scale * 0.55));
	col += vec3(0.65, 1.0, 0.95) * st * 0.3 * core;
	// 빛 속을 떠오르는 먼지
	vec2 g = (p + vec2(sin(p.y * 0.01 + TIME) * 6.0, TIME * 45.0)) / (scale * 0.05);
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(id.x * 13.1 + id.y * 71.7);
	vec2 o = (vec2(hash(id.x * 3.7 + id.y), hash(id.y * 5.3 - id.x)) - 0.5) * 0.6;
	float mote = step(0.94, h) * smoothstep(0.14, 0.0, length(f - o)) * (0.5 + 0.5 * sin(TIME * 3.0 + h * 50.0));
	col += vec3(0.85, 1.0, 0.95) * mote * cone * fall * rays * 1.3;
	// 바닥으로 번지는 빛 (아래쪽 납작한 타원)
	vec2 e = d / vec2(scale * 1.5, scale * 0.45);
	col += vec3(0.2, 0.75, 0.62) * exp(-dot(e, e)) * step(0.0, d.y) * 0.45 * core;
	COLOR = vec4(col * power, 1.0);
}
