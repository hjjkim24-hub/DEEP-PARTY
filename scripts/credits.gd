extends RefCounted
## 크레딧 · 라이선스 고지 (설정 > 크레딧 화면, 그리고 설치 폴더의 LICENSES.txt)
##   Credits.bbcode(ko)     화면용 (BBCode)
##   Credits.plain_text()   LICENSES.txt 용 (영어, 엔진 · 서드파티 · 폰트 라이선스 전문 포함)
## 음악 · 효과음을 바꾸면 audio/CREDITS.md 와 아래 MUSIC 목록을 같이 고쳐 주세요.

const FONT_LICENSE_PATH := "res://fonts/FONT_LICENSE.txt"

## [파일, 곡 제목]  — 모두 FreePD.com, 퍼블릭 도메인(CC0)
const MUSIC := [
	["Main menu", "Land of Pirates"],
	["Board", "Aquatic City Vanished"],
	["Kraken's ship", "Evil Incoming"],
	["Minigame intro", "Busybody"],
	["Results", "Fanfare X"],
	["Tentacle Dodge", "Action Strike"],
	["Cannon Volley", "Heroic Adventure"],
	["Treasure Dive", "The Lagoon"],
	["Chest Shuffle", "Managing Mischief"],
	["Tentacle Tug", "Hit n Smash"],
	["Powder Keg", "Night Attack"],
	["Anchor Drop", "Windy Old Weather"],
	["Ink Splat", "Funky Energy Loop"],
	["Clam Snatch", "Neptunian Princess"],
	["Extra tracks", "Going Bananas, Wakka Wakka, Gotta Keep On Movin, Funshine, Adventures of Flying Jack"],
]

const FONTS := [
	["Pirata One", "Rodrigo Fuenzalida, Nicolas Massi"],
	["Almendra", "Ana Sanfelippo"],
	["Poppins", "The Poppins Project Authors (Indian Type Foundry)"],
	["Gowun Batang", "The Gowun Batang Project Authors (Yanghee Ryu)"],
]


static func _t(ko: bool, en: String, kr: String) -> String:
	return kr if ko else en


## 사람이 읽는 크레딧 (화면 · 파일 공통). 엔진/폰트 라이선스 전문은 따로 붙임
static func _credit_sections(ko: bool) -> Array:
	var music := []
	for m in MUSIC:
		music.append("%s — \"%s\"" % [m[0], m[1]])
	var fonts := []
	for f in FONTS:
		fonts.append("%s — %s" % [f[0], f[1]])
	return [
		[_t(ko, "Engine", "엔진"), [
			_t(ko, "Made with Godot Engine (godotengine.org), MIT License. Full license texts are at the end of this page.",
				"Godot 엔진(godotengine.org)으로 만들었습니다. MIT 라이선스이며, 전문은 이 화면 맨 아래에 있습니다."),
			_t(ko, "Godot logo by Andrea Calabró, licensed under CC BY 4.0 (creativecommons.org/licenses/by/4.0). The text color was changed to white.",
				"Godot 로고: Andrea Calabró, CC BY 4.0 (creativecommons.org/licenses/by/4.0). 글자색을 흰색으로 바꿨습니다."),
		]],
		[_t(ko, "Music", "음악"), [
			_t(ko, "All music from FreePD.com — public domain (CC0 1.0). Edited for looping and volume.",
				"모든 곡은 FreePD.com 의 퍼블릭 도메인(CC0 1.0) 음악입니다. 반복 재생과 음량에 맞게 다듬었습니다."),
		] + music],
		[_t(ko, "Sound effects", "효과음"), [
			_t(ko, "Kenney (kenney.nl): Interface Sounds, UI Audio, RPG Audio, Casino Audio, Impact Sounds, Digital Audio, Music Jingles — CC0 1.0.",
				"Kenney (kenney.nl): Interface Sounds, UI Audio, RPG Audio, Casino Audio, Impact Sounds, Digital Audio, Music Jingles — CC0 1.0."),
			_t(ko, "CC0 sound packs from the CC0-Public-Domain-Sounds collection (github.com/lavenderdotpet): creature, bang, water/splash and breaking/hit SFX packs — CC0 1.0.",
				"CC0-Public-Domain-Sounds 모음집(github.com/lavenderdotpet)의 생물 · 폭발 · 물 · 충돌 효과음 팩 — CC0 1.0."),
			_t(ko, "\"Micro Pack: Organic Wooshes\" by Ben Burnes (abstractionmusic.com) — CC0 1.0.",
				"\"Micro Pack: Organic Wooshes\" — Ben Burnes (abstractionmusic.com), CC0 1.0."),
			_t(ko, "Mixed and edited for DEEP PARTY. Wind ambience is synthesized.",
				"DEEP PARTY 에 맞게 섞고 다듬었습니다. 바람 소리는 직접 합성했습니다."),
		]],
		[_t(ko, "Fonts", "글꼴"), [
			_t(ko, "Licensed under the SIL Open Font License 1.1. Full text is at the end of this page.",
				"모두 SIL Open Font License 1.1 이며, 전문은 이 화면 맨 아래에 있습니다."),
		] + fonts],
		[_t(ko, "Art", "그림"), [
			_t(ko, "Textures, icons, 3D models and shaders were made procedurally for this game.",
				"텍스처 · 아이콘 · 3D 모델 · 셰이더는 이 게임을 위해 직접 만들었습니다."),
		]],
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
