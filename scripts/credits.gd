extends RefCounted
## 크레딧 · 라이선스 고지 (설정 > 크레딧 화면, 그리고 설치 폴더의 LICENSES.txt)
##   Credits.bbcode(ko)     화면용 (BBCode)
##   Credits.plain_text()   LICENSES.txt 용 (영어, 엔진 · 서드파티 · 폰트 라이선스 전문 포함)
## 음악 · 효과음을 바꾸면 audio/CREDITS.md 와 아래 MUSIC 목록을 같이 고쳐 주세요.

const FONT_LICENSE_PATH := "res://fonts/FONT_LICENSE.txt"

## [영어 이름, 한국어 이름, 곡 제목]  — 모두 FreePD.com, CC0
const MUSIC := [
	["Main Menu", "메인 메뉴", "Land of Pirates"],
	["Board", "보드", "Aquatic City Vanished"],
	["Kraken's Ship", "크라켄의 배", "Evil Incoming"],
	["Minigame Intro", "미니게임 소개", "Busybody"],
	["Results", "결과", "Fanfare X"],
	["Tentacle Dodge", "촉수 피하기", "Action Strike"],
	["Cannon Volley", "대포 사격", "Heroic Adventure"],
	["Treasure Dive", "보물 줍기", "The Lagoon"],
	["Chest Shuffle", "보물상자 섞기", "Managing Mischief"],
	["Tentacle Tug", "촉수 줄다리기", "Hit n Smash"],
	["Powder Keg", "화약통 넘기기", "Night Attack"],
	["Anchor Drop", "닻 내리기", "Windy Old Weather"],
	["Ink Splat", "먹물 땅따먹기", "Funky Energy Loop"],
	["Clam Snatch", "조개 낚아채기", "Neptunian Princess"],
]
## 예비 곡 (지금은 쓰는 게임 없음)
const MUSIC_EXTRA := "Going Bananas, Wakka Wakka, Gotta Keep On Movin, Funshine, Adventures of Flying Jack"

const FONTS := [
	["Pirata One", "Rodrigo Fuenzalida, Nicolas Massi"],
	["Almendra", "Ana Sanfelippo"],
	["Poppins", "Indian Type Foundry"],
	["Gowun Batang", "Yanghee Ryu"],
]


static func _t(ko: bool, en: String, kr: String) -> String:
	return kr if ko else en


## [제목, 줄들] — 크레딧은 짧게 "이름 — 출처/라이선스"
static func _credit_sections(ko: bool) -> Array:
	var music := []
	for m in MUSIC:
		music.append("%s — %s" % [m[1] if ko else m[0], m[2]])
	music.append("%s — %s" % [_t(ko, "Extra", "예비 곡"), MUSIC_EXTRA])
	var fonts := []
	for f in FONTS:
		fonts.append("%s — %s" % [f[0], f[1]])
	return [
		[_t(ko, "Engine", "엔진"), [
			"Godot Engine — MIT",
			_t(ko, "Godot logo — Andrea Calabró, CC BY 4.0 (recolored)", "Godot 로고 — Andrea Calabró, CC BY 4.0 (색 변경)"),
		]],
		[_t(ko, "Music — FreePD.com (CC0)", "음악 — FreePD.com (CC0)"), music],
		[_t(ko, "Sound Effects", "효과음"), [
			"Kenney (kenney.nl) — CC0",
			"CC0-Public-Domain-Sounds (github.com/lavenderdotpet) — CC0",
			"Organic Wooshes — Ben Burnes, CC0",
		]],
		[_t(ko, "Fonts — SIL OFL 1.1", "글꼴 — SIL OFL 1.1"), fonts],
	]


## 엔진 + 엔진 안의 서드파티 라이브러리 라이선스 (실행 중인 엔진에서 바로 꺼내 늘 최신)
static func engine_license_text() -> String:
	var out := PackedStringArray()
	out.append("This game uses Godot Engine, available under the following license:\n")
	out.append(Engine.get_license_text())
	out.append("\n\n==== Third-party components included in Godot Engine ====\n")
	for comp in Engine.get_copyright_info():
		out.append("\n- %s" % comp["name"])
		for part in comp["parts"]:
			for c in part["copyright"]:
				out.append("    © %s" % c)
			out.append("    License: %s" % part["license"])
	out.append("\n\n==== License texts ====")
	var lic: Dictionary = Engine.get_license_info()
	var names := lic.keys()
	names.sort()
	for n in names:
		out.append("\n---- %s ----\n%s" % [n, lic[n]])
	return "\n".join(out)


static func font_license_text() -> String:
	var f := FileAccess.open(FONT_LICENSE_PATH, FileAccess.READ)
	return f.get_as_text() if f else ""


## 화면용 BBCode
static func bbcode(ko: bool) -> String:
	var out := PackedStringArray()
	out.append("[font_size=30][b]DEEP PARTY[/b][/font_size]\n")
	for sec in _credit_sections(ko):
		out.append("\n[font_size=22][b][color=#8ff0dc]%s[/color][/b][/font_size]" % sec[0])
		for line in sec[1]:
			out.append("• " + String(line).replace("[", "[lb]"))
	out.append("\n[font_size=22][b][color=#8ff0dc]%s[/color][/b][/font_size]" % _t(ko, "Licenses", "라이선스 전문"))
	out.append("[font_size=14]" + (engine_license_text() + "\n\n==== Fonts (SIL OFL 1.1) ====\n\n" + font_license_text()).replace("[", "[lb]") + "[/font_size]")
	return "\n".join(out)


## 설치 폴더의 LICENSES.txt (영어)
static func plain_text() -> String:
	var out := PackedStringArray()
	out.append("DEEP PARTY — Credits and third-party licenses\n")
	for sec in _credit_sections(false):
		out.append("\n== %s ==" % sec[0])
		for line in sec[1]:
			out.append("  " + String(line))
	out.append("\n\n========================================\n")
	out.append(engine_license_text())
	out.append("\n\n========================================\nFonts — SIL Open Font License 1.1\n========================================\n")
	out.append(font_license_text())
	return "\n".join(out)
