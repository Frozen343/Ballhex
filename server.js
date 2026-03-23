const crypto = require("crypto");
const http = require("http");
const path = require("path");

const express = require("express");
const { WebSocketServer } = require("ws");

const PORT = Number(process.env.PORT || 3000);
const WEB_DIR = path.join(__dirname, "web");
const EMPTY_CLOSE_CODE = 1011;
const HOST_GONE_CLOSE_CODE = 4000;
const GUEST_BUSY_CLOSE_CODE = 4001;
const LOBBY_NOT_FOUND_CLOSE_CODE = 4004;
const LOBBY_STALE_TIMEOUT_MS = 2 * 60 * 1000;

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });
const lobbies = new Map();

app.use(express.json());
app.use((req, res, next) => {
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
  next();
});

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, lobbies: listJoinableLobbies().length });
});

app.get("/api/lobbies", (_req, res) => {
  pruneStaleLobbies();
  res.json({ lobbies: listJoinableLobbies() });
});

app.post("/api/lobbies", (req, res) => {
  pruneStaleLobbies();

  const id = crypto.randomUUID();
  const lobby = {
    id,
    name: sanitizeLobbyName(req.body?.name),
    createdAt: new Date().toISOString(),
    createdAtMs: Date.now(),
    hostSocket: null,
    guestSocket: null,
    guestPeerId: null
  };

  lobbies.set(id, lobby);
  res.status(201).json(serializeLobby(lobby));
});

app.delete("/api/lobbies/:id", (req, res) => {
  const lobby = lobbies.get(req.params.id);
  if (!lobby) {
    res.status(404).json({ error: "Lobby not found" });
    return;
  }

  safelyCloseSocket(lobby.hostSocket, 1000, "Lobby closed");
  safelyCloseSocket(lobby.guestSocket, 1000, "Lobby closed");
  lobbies.delete(lobby.id);
  res.status(204).end();
});

app.use(express.static(WEB_DIR));
app.get("/", (_req, res) => {
  res.sendFile(path.join(WEB_DIR, "index.html"));
});

server.on("upgrade", (request, socket, head) => {
  const requestUrl = new URL(request.url, `http://${request.headers.host}`);
  if (requestUrl.pathname !== "/ws") {
    socket.destroy();
    return;
  }

  wss.handleUpgrade(request, socket, head, (ws) => {
    wss.emit("connection", ws, request, requestUrl);
  });
});

wss.on("connection", (ws, _request, requestUrl) => {
  pruneStaleLobbies();

  const lobbyId = requestUrl.searchParams.get("lobbyId") || "";
  const role = requestUrl.searchParams.get("role") || "";
  const peerId = Number(requestUrl.searchParams.get("peerId") || "0");
  const lobby = lobbies.get(lobbyId);

  if (!lobby) {
    sendJson(ws, { type: "error", message: "Lobby not found." });
    ws.close(LOBBY_NOT_FOUND_CLOSE_CODE, "Lobby not found");
    return;
  }

  if (role === "host") {
    if (lobby.hostSocket) {
      sendJson(ws, { type: "error", message: "Lobby host already connected." });
      ws.close(GUEST_BUSY_CLOSE_CODE, "Host already connected");
      return;
    }

    lobby.hostSocket = ws;
    lobby.createdAtMs = Date.now();
    sendJson(ws, {
      type: "host_ready",
      lobby: serializeLobby(lobby)
    });
  } else if (role === "guest") {
    if (!lobby.hostSocket) {
      sendJson(ws, { type: "error", message: "Lobby host is offline." });
      ws.close(HOST_GONE_CLOSE_CODE, "Host offline");
      return;
    }

    if (lobby.guestSocket) {
      sendJson(ws, { type: "error", message: "Lobby already full." });
      ws.close(GUEST_BUSY_CLOSE_CODE, "Lobby already full");
      return;
    }

    if (!Number.isInteger(peerId) || peerId < 2) {
      sendJson(ws, { type: "error", message: "Invalid peer id." });
      ws.close(EMPTY_CLOSE_CODE, "Invalid peer id");
      return;
    }

    lobby.guestSocket = ws;
    lobby.guestPeerId = peerId;
    sendJson(ws, {
      type: "guest_ready",
      lobby: serializeLobby(lobby),
      peerId
    });
    sendJson(lobby.hostSocket, {
      type: "guest_joined",
      peerId
    });
  } else {
    sendJson(ws, { type: "error", message: "Invalid socket role." });
    ws.close(EMPTY_CLOSE_CODE, "Invalid socket role");
    return;
  }

  ws.on("message", (rawBuffer) => {
    let message;
    try {
      message = JSON.parse(rawBuffer.toString("utf8"));
    } catch (_error) {
      sendJson(ws, { type: "error", message: "Invalid JSON payload." });
      return;
    }

    if (!message || message.type !== "signal") {
      return;
    }

    if (role === "host") {
      if (!lobby.guestSocket) {
        return;
      }

      sendJson(lobby.guestSocket, {
        type: "signal",
        kind: message.kind,
        peerId: lobby.guestPeerId,
        sdpType: message.sdpType,
        sdp: message.sdp,
        mid: message.mid,
        index: message.index
      });
      return;
    }

    if (!lobby.hostSocket) {
      return;
    }

    sendJson(lobby.hostSocket, {
      type: "signal",
      kind: message.kind,
      peerId: lobby.guestPeerId,
      sdpType: message.sdpType,
      sdp: message.sdp,
      mid: message.mid,
      index: message.index
    });
  });

  ws.on("close", () => {
    if (role === "host" && lobby.hostSocket === ws) {
      if (lobby.guestSocket) {
        sendJson(lobby.guestSocket, { type: "lobby_closed" });
        safelyCloseSocket(lobby.guestSocket, 1000, "Host left");
      }
      lobbies.delete(lobby.id);
      return;
    }

    if (role === "guest" && lobby.guestSocket === ws) {
      lobby.guestSocket = null;
      lobby.guestPeerId = null;
      sendJson(lobby.hostSocket, { type: "guest_left" });
    }
  });
});

server.listen(PORT, () => {
  console.log(`Hexball server listening on ${PORT}`);
});

function sanitizeLobbyName(name) {
  const fallback = `Hexball Lobby ${randomTwoDigit()}`;
  const text = typeof name === "string" ? name.trim() : "";
  if (!text) {
    return fallback;
  }
  return text.slice(0, 32);
}

function randomTwoDigit() {
  return Math.floor(Math.random() * 90 + 10);
}

function serializeLobby(lobby) {
  return {
    id: lobby.id,
    name: lobby.name,
    createdAt: lobby.createdAt,
    playerCount: lobby.guestSocket ? 2 : 1
  };
}

function listJoinableLobbies() {
  return Array.from(lobbies.values())
    .filter((lobby) => Boolean(lobby.hostSocket) && !lobby.guestSocket)
    .map(serializeLobby);
}

function pruneStaleLobbies() {
  const now = Date.now();
  for (const lobby of lobbies.values()) {
    if (lobby.hostSocket || lobby.guestSocket) {
      continue;
    }

    if (now - lobby.createdAtMs > LOBBY_STALE_TIMEOUT_MS) {
      lobbies.delete(lobby.id);
    }
  }
}

function sendJson(ws, payload) {
  if (!ws || ws.readyState !== 1) {
    return;
  }
  ws.send(JSON.stringify(payload));
}

function safelyCloseSocket(ws, code, reason) {
  if (!ws || ws.readyState !== 1) {
    return;
  }
  ws.close(code, reason);
}
