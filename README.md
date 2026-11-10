# DEEP PARTY — 메인화면

Godot 4.3 이상에서 `project.godot`를 열고 F5로 실행하세요.

## 실행 파일(.exe) 만들기 — Godot 설치 없이 실행
1. 이 폴더의 `build_windows.bat`을 더블클릭합니다.
2. 처음 한 번은 Godot 4.3(약 60MB)과 내보내기 템플릿(약 1GB)을 자동으로 받습니다. 인터넷 속도에 따라 몇 분 걸려요. 받은 Godot은 `.build_tools` 폴더에만 들어가고 설치되지 않습니다.
3. 끝나면 `build` 폴더가 열리고 `DeepParty.exe`가 생깁니다. 이 파일 하나만 있으면 Godot 없이 실행되고, 다른 PC로 복사해도 됩니다.
4. 게임을 고친 뒤 다시 실행하면 이번엔 다운로드 없이 몇 초 만에 새 exe가 나옵니다.

Windows가 "PC 보호" 창을 띄우면 "추가 정보 → 실행"을 누르세요. (서명 안 된 새 exe라서 뜨는 경고예요. 스팀으로 배포하면 뜨지 않습니다.)

GitHub로 자동 빌드: 이 폴더를 GitHub 저장소(main 브랜치)에 올리면 `.github/workflows/build-windows.yml`이 GitHub 서버에서 exe를 만들어 저장소의 **Releases**에 올려 줍니다. 내 PC에는 아무것도 받을 필요가 없어요.

Godot 에디터로 직접 만들 때: 프로젝트 → 내보내기 → "Windows Desktop" 선택 → (템플릿이 없으면 "내보내기 템플릿 관리 → 다운로드") → 프로젝트 내보내기.

## 시작 로고 화면
`scenes/splash.tscn` (`scripts/splash.gd`) — 검은 화면에 Godot 로고 → MS 로고 → JS BROS 로고 → 메인화면.
- Godot 기본 부트 스플래시는 끄고(project.godot), 창이 다 뜬 뒤에 로고를 시작해서 로딩 중에 놓치지 않게 했습니다.
- 로고가 나오는 동안 메인화면을 뒤에서 미리 불러 둡니다. 클릭하면 지금 로고를 건너뜁니다.
- 시간 조절: `FADE_IN`, `HOLD`, `FADE_OUT`, `GAP` 상수.
- Godot 로고: Andrea Calabró, CC BY 4.0 (`textures/splash/GODOT_LOGO_LICENSE.txt`). 검은 배경에 맞게 글자색만 흰색으로 바꿨습니다.

## 소리
`scripts/autoload/audio.gd` (자동 로드 `Audio`)
- 배경음악 `audio/music/menu_theme.ogg` — 116 BPM 마림바 곡, 약 66초 끊김 없이 반복. 메인화면에서 서서히 시작.
- 효과음 `audio/sfx/*.wav` — `Audio.play("click")`. 모든 버튼은 자동으로 마우스 올림/누름 소리가 나고, 버튼마다 `set_meta("sfx", "back")`로 바꿀 수 있어요.
- 음악은 Music 버스, 효과음은 SFX 버스라 설정의 음량 슬라이더가 그대로 적용돼요.
- 다시 만들기: `cd tools && python make_audio.py` (numpy, scipy, ffmpeg 필요)

## 화면 구성 (뒤에서 앞 순서)
1. 물 (셰이더) — 에메랄드빛 물 색, 수면 쪽 빛무늬
2. 바다 밑 장면 — `textures/seabed_scene.png` (미리 렌더링한 실사풍 그림) + 표면을 따라 움직이는 빛무늬 셰이더
3. 해초·물고기 떼 — `scripts/background/sea_life.gd` (KELP / SCHOOLS 표에서 위치 조절)
4. 물방울·부유물·보드판 밑 공기방울 — `scripts/background/bubbles.gd`
5. 빛줄기, 가장자리 어둡게
6. 메뉴 UI — `scripts/main_menu.gd` (진주빛/아쿠아/청록 유리 느낌으로 통일)

## 바다 밑 장면 다시 만들기 (선택)
보드판 인쇄 그림이나 배치를 바꾸고 싶으면 `tools/` 폴더의 파이썬 스크립트로 다시 렌더링합니다.
```
pip install numpy pillow
cd tools
python make_board_print.py        # 보드판 윗면 인쇄 그림 (out/board_print.png)
python render_seabed.py 1920 2    # 장면 렌더링 → ../textures/ 에 PNG 3장 (약 5~6분)
python make_icon.py               # 게임 아이콘 → ../icon.png, ../icon.ico (약 3초)
python render_pawn.py             # 실사풍 말 그림 → ../textures/pawn_diffuse.png, pawn_spec.png (약 20초)
```
- 카메라, 보드판 위치·기울기, 말·주사위·카드·바위·산호 위치는 `render_seabed.py` 맨 위 "장면 설정"에서 바꿉니다.
- 렌더링 후 `textures/seabed_marks.json`에 보드판 모서리 등의 화면 좌표가 나오니, 공기방울 위치(`underwater_background.gd`의 VENTS)를 맞출 때 쓰세요.

## 폰트
`fonts/Poppins-Bold.ttf` (SIL OFL, 상업용 무료). 라이선스 안내는 fonts/FONT_LICENSE.txt

## 조작
마우스, 키보드(방향키 / Enter / Esc), 게임패드(십자키 / A / B) 모두 지원

## 다음 단계
`scenes/lobby.tscn`을 만들면 모드 선택 후 자동으로 그 화면으로 넘어갑니다.
