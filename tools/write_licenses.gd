extends SceneTree
## 설치 폴더에 함께 넣을 LICENSES.txt 를 만듦 (Windows 내보내기 뒤에 실행):
##   godot --headless --path . -s res://tools/write_licenses.gd -- build/LICENSES.txt
func _init() -> void:
	var out := "build/LICENSES.txt"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var Credits := load("res://scripts/credits.gd")
	var f := FileAccess.open(ProjectSettings.globalize_path("res://") + out, FileAccess.WRITE)
	if f == null:
		f = FileAccess.open(out, FileAccess.WRITE)
	f.store_string(Credits.plain_text())
	f.close()
	print("wrote ", out)
	quit()
