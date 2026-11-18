# DEEP PARTY 중계 서버 (방 코드)

친구끼리 방 코드로 연결해 주고 메시지를 전달만 하는 작은 서버예요. 게임 진행은 방장 PC가 합니다.
라이브러리 설치가 필요 없어요 (Node 18 이상).

## 내 PC에서 테스트
```
node server/relay.js
```
게임은 기본으로 `ws://127.0.0.1:8787` 에 접속해요. 같은 PC에서 게임 창 두 개로 방 만들기 / 방 참가를 해 볼 수 있어요.

## 무료로 인터넷에 올리기 (Render 예시)
1. render.com 가입 → **New → Web Service** → GitHub 저장소 `DEEP-PARTY` 연결
2. **Root Directory**: `server` · **Runtime**: Node · **Build Command**: 비워 둠 · **Start Command**: `node relay.js`
3. 무료(Free) 요금제로 만들기 → 주소가 `https://deep-party-relay.onrender.com` 처럼 나와요
4. 브라우저로 그 주소를 열어 `DEEP PARTY relay OK` 가 보이면 성공
5. 그 주소를 알려 주세요 → 게임의 `scripts/autoload/net.gd` 의 `SERVER_URL` 을 `wss://…` 로 바꿔서 다시 빌드해 드려요

참고: 무료 서버는 한동안 아무도 안 쓰면 잠들어서, 처음 방을 만들 때 30초~1분쯤 걸릴 수 있어요.

## 주소를 빌드 없이 바꾸기 (테스트용)
- 환경변수 `DEEP_PARTY_SERVER=wss://…`
- 또는 `%APPDATA%\Godot\app_userdata\DEEP PARTY\server_url.txt` 에 주소 한 줄
