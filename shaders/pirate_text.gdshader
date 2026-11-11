shader_type canvas_item;
// 게임 글씨 재질: 큰 제목은 두드려 편 금박(위는 밝고 아래는 짙은 금 + 가는 반사선 + 지나가는 광택),
// 색 있는 글씨는 칠한 나무/에나멜처럼 위가 밝고 아래가 어두운 입체감, 보통 글씨는 잉크 결.
uniform float metal = 1.0;          // 1 = 제목(금박), 0 = 보통 글씨
uniform float y0 = 0.0;             // 첫 줄 글씨 윗부분 (라벨 안 픽셀)
uniform float line_h = 40.0;        // 줄 높이 (픽셀)

varying vec2 lpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec4 base = COLOR;
	float lum = dot(base.rgb, vec3(0.3, 0.59, 0.11));
	float sat = max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b));
	// 줄 안에서의 세로 위치 (0 = 글자 위, 1 = 아래)
	float v = clamp(fract((lpos.y - y0) / line_h) * 1.25 - 0.12, 0.0, 1.0);
	float grain = 0.93 + 0.07 * noise(lpos * 0.45) + 0.04 * (noise(lpos * 2.3) - 0.5);
	vec3 col;
	if (lum < 0.3) {
		// 테두리 · 그림자 (어두운 색): 살짝 위가 밝게
		col = base.rgb * (1.1 - v * 0.3);
	} else if (metal > 0.5 && lum > 0.8 && sat < 0.15) {
		// 금박
		vec3 top = vec3(1.0, 0.95, 0.7);
		vec3 mid = vec3(0.98, 0.76, 0.3);
		vec3 bot = vec3(0.6, 0.36, 0.1);
		col = v < 0.45 ? mix(top, mid, v / 0.45) : mix(mid, bot, (v - 0.45) / 0.55);
		col += vec3(0.35, 0.3, 0.15) * smoothstep(0.05, 0.0, abs(v - 0.47));          // 가는 반사선
		float sweep = fract((lpos.x * 0.6 + lpos.y - TIME * 160.0) / 900.0);
		col += vec3(0.45, 0.4, 0.25) * smoothstep(0.05, 0.0, abs(sweep - 0.5));        // 지나가는 광택
		col *= grain;
	} else if (metal > 0.5) {
		// 색 있는 큰 글씨: 에나멜 입체감
		col = base.rgb * mix(1.2, 0.72, v) * grain;
		col += vec3(0.12) * smoothstep(0.06, 0.0, abs(v - 0.3));
	} else {
		// 보통 글씨: 잉크 결 + 아주 약한 입체감
		col = base.rgb * mix(1.06, 0.88, v) * (0.96 + 0.04 * noise(lpos * 0.8));
	}
	COLOR = vec4(col, base.a * t.a);
}
