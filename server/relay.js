// Apex Circuit online relay. Phones can't reach each other directly on
// mobile networks, so everyone connects here and the relay forwards game
// messages within a room. It never looks inside the game data.
//
// Control (text frames, JSON):
//   client -> relay  {"op":"host","name":...}            create a room
//                    {"op":"join","room":"ABCD"}          join a room
//   relay -> client  {"op":"welcome","id":N,"room":"ABCD"}   host is id 1
//                    {"op":"error","msg":...}
//                    {"op":"peer_joined","id":N} / {"op":"peer_left","id":N}  (to the host)
//                    {"op":"host_left"}                    (to everyone else)
// Data (binary frames): [target id][payload] in, [sender id][payload] out.
//   target 0 = everyone else in the room.

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8080;
const MAX_PLAYERS = 20;
const CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // no I/L/O/0/1
const rooms = new Map(); // code -> { peers: Map<id, ws>, nextId }

// Testing only: SIM_LAG_MS / SIM_JITTER_MS delay every game message like a
// mobile network would (kept in order per receiver, as TCP does).
const LAG = Number(process.env.SIM_LAG_MS || 0);
const JITTER = Number(process.env.SIM_JITTER_MS || 0);
function deliver(peer, data) {
  if (!LAG && !JITTER) return peer.send(data);
  const at = Math.max(peer.nextAt || 0, Date.now() + LAG + Math.random() * JITTER);
  peer.nextAt = at;
  setTimeout(() => { if (peer.readyState === peer.OPEN) peer.send(data); }, at - Date.now());
}

function newCode() {
  for (;;) {
    let c = "";
    for (let i = 0; i < 4; i++) c += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    if (!rooms.has(c)) return c;
  }
}

function sendJson(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

const server = http.createServer((req, res) => {
  res.writeHead(200, { "content-type": "text/plain" });
  res.end(`apex-circuit relay ok, ${rooms.size} room(s)\n`);
});
const wss = new WebSocketServer({ server, maxPayload: 1 << 20 });

wss.on("connection", (ws) => {
  ws.isAlive = true;
  ws.on("pong", () => (ws.isAlive = true));

  ws.on("message", (data, isBinary) => {
    if (!isBinary) {
      let c;
      try { c = JSON.parse(data.toString()); } catch { return; }
      if (ws.room) return; // already in a room
      if (c.op === "host") {
        const code = newCode();
        const room = { peers: new Map([[1, ws]]), nextId: 2 };
        rooms.set(code, room);
        ws.room = code; ws.id = 1;
        sendJson(ws, { op: "welcome", id: 1, room: code });
      } else if (c.op === "join") {
        const code = String(c.room || "").toUpperCase();
        const room = rooms.get(code);
        if (!room) return sendJson(ws, { op: "error", msg: `No game with code ${code}. Check the code with the host.` });
        if (room.peers.size >= MAX_PLAYERS) return sendJson(ws, { op: "error", msg: "That game is full." });
        const id = room.nextId++;
        if (id > 255) return sendJson(ws, { op: "error", msg: "That game is full." });
        room.peers.set(id, ws);
        ws.room = code; ws.id = id;
        sendJson(ws, { op: "welcome", id, room: code });
        sendJson(room.peers.get(1), { op: "peer_joined", id });
      }
      return;
    }
    // Game data.
    const room = rooms.get(ws.room);
    if (!room || data.length < 2) return;
    const target = data[0];
    const out = Buffer.from(data);
    out[0] = ws.id;
    if (target === 0) {
      for (const [id, peer] of room.peers) if (id !== ws.id && peer.readyState === peer.OPEN) deliver(peer, out);
    } else {
      const peer = room.peers.get(target);
      if (peer && peer.readyState === peer.OPEN) deliver(peer, out);
    }
  });

  ws.on("close", () => {
    const room = rooms.get(ws.room);
    if (!room) return;
    room.peers.delete(ws.id);
    if (ws.id === 1) {
      for (const peer of room.peers.values()) { sendJson(peer, { op: "host_left" }); peer.close(); }
      rooms.delete(ws.room);
    } else {
      sendJson(room.peers.get(1), { op: "peer_left", id: ws.id });
    }
  });
});

// Drop dead connections (phones that lost signal) every 20 s.
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, 20000);

server.listen(PORT, () => console.log(`relay listening on ${PORT}`));
