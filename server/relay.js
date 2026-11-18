// DEEP PARTY 중계 서버 — 방 코드로 친구끼리 연결해 주고, 메시지를 그대로 전달만 함 (게임 진행은 방장 PC)
// 의존성 없음 (Node 18+). 실행:  node server/relay.js      (PORT 환경변수, 기본 8787)
//
// 주고받는 글 (JSON 텍스트):
//   보냄 {t:"host", name}            → 받음 {t:"hosted", code, id:0}
//   보냄 {t:"join", code, name}      → 받음 {t:"joined", code, id, host_name}   (방장에게 {t:"peer_join", id, name})
//                                     실패 {t:"error", code:"no_room"|"full"|"bad"}
//   보냄 {t:"msg", to, d}  (to = 받는 id, -1 = 나 빼고 모두) → 받는 쪽 {t:"msg", from, d}
//   나가면 남은 사람들에게 {t:"peer_left", id}. 방장이 나가면 {t:"room_closed"} 후 방 없어짐
//   보냄 {t:"ping"} → 받음 {t:"pong"}

"use strict";
const http = require("http");
const crypto = require("crypto");

const PORT = parseInt(process.env.PORT || "8787", 10);
const MAX_PEERS = 4;
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 헷갈리는 0/O, 1/I 빼고
const rooms = new Map(); // code → {peers: Map(id → sock), names: Map(id → name)}

function makeCode() {
  for (let tries = 0; tries < 1000; tries++) {
    let c = "";
    for (let i = 0; i < 5; i++) c += CODE_CHARS[crypto.randomInt(CODE_CHARS.length)];
    if (!rooms.has(c)) return c;
  }
  throw new Error("no free code");
}

// ── 아주 작은 WebSocket (RFC 6455) ─────────────────────────────
function sendFrame(sock, opcode, payload) {
  if (sock.destroyed) return;
  const len = payload.length;
  let head;
  if (len < 126) {
    head = Buffer.from([0x80 | opcode, len]);
  } else if (len < 65536) {
    head = Buffer.alloc(4);
    head[0] = 0x80 | opcode; head[1] = 126; head.writeUInt16BE(len, 2);
  } else {
    head = Buffer.alloc(10);
    head[0] = 0x80 | opcode; head[1] = 127; head.writeBigUInt64BE(BigInt(len), 2);
  }
  sock.write(Buffer.concat([head, payload]));
}

function send(sock, obj) {
  sendFrame(sock, 0x1, Buffer.from(JSON.stringify(obj), "utf8"));
}

// 들어온 바이트에서 완성된 프레임을 꺼냄 (조각 프레임도 이어 붙임)
function parseFrames(st, chunk, onMessage, onClose, onPing) {
  st.buf = st.buf.length ? Buffer.concat([st.buf, chunk]) : chunk;
  for (;;) {
    const b = st.buf;
    if (b.length < 2) return;
    const fin = (b[0] & 0x80) !== 0;
    const opcode = b[0] & 0x0f;
    const masked = (b[1] & 0x80) !== 0;
    let len = b[1] & 0x7f;
    let off = 2;
    if (len === 126) { if (b.length < 4) return; len = b.readUInt16BE(2); off = 4; }
    else if (len === 127) { if (b.length < 10) return; len = Number(b.readBigUInt64BE(2)); off = 10; }
    if (len > 4 * 1024 * 1024) { onClose(); return; }
    const need = off + (masked ? 4 : 0) + len;
    if (b.length < need) return;
    let payload = b.subarray(off + (masked ? 4 : 0), need);
    if (masked) {
      const mask = b.subarray(off, off + 4);
      const out = Buffer.alloc(len);
      for (let i = 0; i < len; i++) out[i] = payload[i] ^ mask[i & 3];
      payload = out;
    }
    st.buf = b.subarray(need);
    if (opcode === 0x8) { onClose(); return; }
    if (opcode === 0x9) { onPing(payload); continue; }
    if (opcode === 0xA) continue;
    if (opcode === 0x0 || opcode === 0x1 || opcode === 0x2) {
      if (opcode !== 0x0) st.frag = [];
      st.frag.push(payload);
      if (fin) {
        const whole = Buffer.concat(st.frag);
        st.frag = [];
        onMessage(whole.toString("utf8"));
      }
    }
  }
}

// ── 방 ────────────────────────────────────────────────────────
function leave(sock) {
  const code = sock.room;
  if (!code || !rooms.has(code)) return;
  const room = rooms.get(code);
  room.peers.delete(sock.pid);
  room.names.delete(sock.pid);
  sock.room = null;
  if (sock.pid === 0) {
    for (const s of room.peers.values()) { send(s, { t: "room_closed" }); s.room = null; }
    rooms.delete(code);
    log(`room ${code} closed`);
  } else {
    for (const s of room.peers.values()) send(s, { t: "peer_left", id: sock.pid });
    log(`room ${code}: peer ${sock.pid} left`);
  }
}

function handle(sock, text) {
  let m;
  try { m = JSON.parse(text); } catch { return; }
  if (!m || typeof m.t !== "string") return;
  switch (m.t) {
    case "ping":
      send(sock, { t: "pong" });
      break;
    case "host": {
      leave(sock);
      const code = makeCode();
      const room = { peers: new Map([[0, sock]]), names: new Map([[0, String(m.name || "Host").slice(0, 24)]]) };
      rooms.set(code, room);
      sock.room = code; sock.pid = 0;
      send(sock, { t: "hosted", code, id: 0 });
      log(`room ${code} opened`);
      break;
    }
    case "join": {
      const code = String(m.code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
      const room = rooms.get(code);
      if (!room) { send(sock, { t: "error", code: "no_room" }); return; }
      if (room.peers.size >= MAX_PEERS) { send(sock, { t: "error", code: "full" }); return; }
      leave(sock);
      let id = 1;
      while (room.peers.has(id)) id++;
      const name = String(m.name || "Player").slice(0, 24);
      room.peers.set(id, sock); room.names.set(id, name);
      sock.room = code; sock.pid = id;
      send(sock, { t: "joined", code, id, host_name: room.names.get(0) });
      send(room.peers.get(0), { t: "peer_join", id, name });
      log(`room ${code}: peer ${id} joined`);
      break;
    }
    case "msg": {
      const room = rooms.get(sock.room);
      if (!room) return;
      if (process.env.RELAY_DEBUG) { stats[sock.pid] = (stats[sock.pid] || 0) + 1; }
      const out = { t: "msg", from: sock.pid, d: m.d };
      if (typeof m.to === "number" && m.to >= 0) {
        const s = room.peers.get(m.to);
        if (s) send(s, out);
      } else {
        for (const [id, s] of room.peers) if (id !== sock.pid) send(s, out);
      }
      break;
    }
    case "leave":
      leave(sock);
      break;
  }
}

const stats = {};
if (process.env.RELAY_DEBUG) setInterval(() => { if (Object.keys(stats).length) log("msgs " + JSON.stringify(stats)); }, 5000);

function log(s) { console.log(new Date().toISOString(), s); }

const server = http.createServer((req, res) => {
  // 무료 클라우드의 상태 확인용 (브라우저로 열면 이 글이 보이면 서버가 살아 있는 것)
  res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
  res.end(`DEEP PARTY relay OK — rooms: ${rooms.size}\n`);
});

server.on("upgrade", (req, sock) => {
  const key = req.headers["sec-websocket-key"];
  if (!key || (req.headers.upgrade || "").toLowerCase() !== "websocket") { sock.destroy(); return; }
  const accept = crypto.createHash("sha1").update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
  sock.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
    `Sec-WebSocket-Accept: ${accept}\r\n\r\n`);
  sock.setNoDelay(true);
  sock.room = null; sock.pid = -1;
  const st = { buf: Buffer.alloc(0), frag: [] };
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    leave(sock);
    try { sendFrame(sock, 0x8, Buffer.alloc(0)); } catch {}
    sock.end();
  };
  sock.on("data", (chunk) => parseFrames(st, chunk, (txt) => handle(sock, txt), close, (p) => sendFrame(sock, 0xA, p)));
  sock.on("close", close);
  sock.on("error", close);
});

// 무료 클라우드가 조용한 연결을 끊지 않게 25초마다 ping
setInterval(() => {
  for (const room of rooms.values()) for (const s of room.peers.values()) sendFrame(s, 0x9, Buffer.alloc(0));
}, 25000);

server.listen(PORT, () => log(`DEEP PARTY relay listening on :${PORT}`));
