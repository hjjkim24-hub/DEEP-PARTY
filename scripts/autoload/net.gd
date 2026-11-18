extends Node
## 온라인 (방 코드). 중계 서버(server/relay.js)를 거쳐 방장 PC ↔ 친구 PC 가 JSON 메시지를 주고받음.
##   Net.host_room()            방 만들기 → hosted(code)
##   Net.join_room("KRK7Q")     방 참가 → joined(code, my_id) / failed("no_room" | "full" | "connect")
##   Net.send_to(id, d) · Net.broadcast(d)   → 받는 쪽 message(from, d)
##   Net.leave()
## 게임 진행은 방장 PC가 하고, 친구 PC는 조작을 보내고 결과를 받아 보여줘요.
##
## 서버 주소: 아래 SERVER_URL (서버를 올린 뒤 그 주소로 바꿔 주세요, wss://…)
##   테스트용으로 바꾸려면 환경변수 DEEP_PARTY_SERVER 또는 user://server_url.txt 한 줄

signal hosted(code: String)
signal joined(code: String, my_id: int)
signal peer_joined(id: int, pname: String)
signal peer_left(id: int)
signal message(from: int, d: Dictionary)
signal failed(reason: String)
signal room_closed
signal disconnected

const SERVER_URL := "wss://deep-party.onrender.com"
const CONNECT_TIMEOUT := 9.0

var role := ""          ## "" 오프라인, "host" 방장, "guest" 손님
var code := ""
var my_id := -1
var peers := {}          ## 방장 쪽: 손님 id → 이름

var _ws: WebSocketPeer
var _first := {}         ## 연결되자마자 보낼 첫 글 (host / join)
var _open := false
var _connect_t := 0.0
var _ping_t := 0.0


func server_url() -> String:
	var env := OS.get_environment("DEEP_PARTY_SERVER")
	if env != "":
		return env
	if FileAccess.file_exists("user://server_url.txt"):
		var s := FileAccess.get_file_as_string("user://server_url.txt").strip_edges()
		if s != "":
			return s
	return SERVER_URL


func is_online() -> bool:
	return role != ""


func is_host() -> bool:
	return role == "host"


func is_guest() -> bool:
	return role == "guest"


func host_room(pname: String = "Host") -> void:
	_start({"t": "host", "name": pname})
	if _ws:
		role = "host"


func join_room(room_code: String, pname: String = "Player") -> void:
	_start({"t": "join", "code": room_code.strip_edges().to_upper(), "name": pname})
	if _ws:
		role = "guest"


func leave() -> void:
	if _ws and _open:
		_raw({"t": "leave"})
		_ws.close()
	_reset()


func send_to(id: int, d: Dictionary) -> void:
	_raw({"t": "msg", "to": id, "d": d})


func broadcast(d: Dictionary) -> void:
	_raw({"t": "msg", "to": -1, "d": d})


## 손님 → 방장
func to_host(d: Dictionary) -> void:
	send_to(0, d)


func _start(first: Dictionary) -> void:
	_reset()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var err := _ws.connect_to_url(server_url())
	if err != OK:
		_fail("connect")
		return
	_first = first
	_connect_t = 0.0


func _reset() -> void:
	_ws = null
	_open = false
	_first = {}
	role = ""
	code = ""
	my_id = -1
	peers.clear()


func _fail(reason: String) -> void:
	_reset()
	failed.emit(reason)


func _raw(obj: Dictionary) -> void:
	if _ws and _open:
		_ws.send_text(JSON.stringify(obj))


func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_CONNECTING:
		_connect_t += delta
		if _connect_t > CONNECT_TIMEOUT:
			_fail("connect")
		return
	if st == WebSocketPeer.STATE_CLOSED:
		var was := _open
		var had_role := role != ""
		_reset()
		if was and had_role:
			disconnected.emit()
		elif not was:
			failed.emit("connect")
		return
	if st != WebSocketPeer.STATE_OPEN:
		return
	if not _open:
		_open = true
		if not _first.is_empty():
			_raw(_first)
			_first = {}
	_ping_t += delta
	if _ping_t > 20.0:
		_ping_t = 0.0
		_raw({"t": "ping"})
	while _ws and _ws.get_available_packet_count() > 0:
		var txt := _ws.get_packet().get_string_from_utf8()
		var m = JSON.parse_string(txt)
		if typeof(m) != TYPE_DICTIONARY:
			continue
		_handle(m)


func _handle(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"hosted":
			code = String(m["code"])
			my_id = 0
			hosted.emit(code)
		"joined":
			code = String(m["code"])
			my_id = int(m["id"])
			joined.emit(code, my_id)
		"peer_join":
			peers[int(m["id"])] = String(m.get("name", ""))
			peer_joined.emit(int(m["id"]), String(m.get("name", "")))
		"peer_left":
			peers.erase(int(m["id"]))
			peer_left.emit(int(m["id"]))
		"room_closed":
			_reset()
			room_closed.emit()
		"error":
			_fail(String(m.get("code", "connect")))
		"msg":
			var d = m.get("d")
			if typeof(d) == TYPE_DICTIONARY:
				message.emit(int(m.get("from", -1)), d)
