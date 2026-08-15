/**
 * Minimal PBA WebSocket relay: HTTP create/join + WS attach + opaque relay.
 */
import http from 'http';
import os from 'os';
import { URL } from 'url';
import express from 'express';
import { WebSocketServer, WebSocket } from 'ws';

import {
  createSession,
  claimCoachSlot,
  attachSocket,
  detachSocket,
} from './roomStore.js';

const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || '0.0.0.0';

/** Non-loopback IPv4s for startup hints (iPad / LAN clients). */
function getLanIPv4Addresses() {
  const nets = os.networkInterfaces();
  const out = [];
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] || []) {
      if ((net.family === 'IPv4' || net.family === 4) && !net.internal) {
        out.push(net.address);
      }
    }
  }
  return out;
}

/**
 * Canonical `wsUrl` for JSON: exactly one `/ws` path. Single place for PUBLIC_WS_URL handling.
 * - `ws://host:port` → `ws://host:port/ws`
 * - `ws://host:port/ws` → unchanged (no duplicate `/ws`)
 * - Collapses accidental `/ws/ws` → `/ws`
 */
function normalizeRelayWsUrl() {
  const raw =
    process.env.PUBLIC_WS_URL ||
    `ws://${HOST === '0.0.0.0' ? 'localhost' : HOST}:${PORT}`;
  let u;
  try {
    u = new URL(raw);
  } catch {
    return `ws://127.0.0.1:${PORT}/ws`;
  }
  let p = u.pathname || '';
  p = p.replace(/\/+$/, '') || '';
  if (p === '' || p === '/') {
    u.pathname = '/ws';
  } else {
    while (p.endsWith('/ws/ws')) {
      p = p.slice(0, -3);
    }
    if (p === '/ws') {
      u.pathname = '/ws';
    } else if (p.endsWith('/ws')) {
      u.pathname = p;
    } else {
      u.pathname = `${p}/ws`;
    }
  }
  return u.href;
}

const RELAY_WS_URL = normalizeRelayWsUrl();

const app = express();
app.use(express.json());

function sendControl(ws, payload) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(payload));
  }
}

function safeJsonSend(ws, obj) {
  try {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj));
  } catch (_) {
    /* ignore */
  }
}

// --- HTTP ---

app.post('/v1/sessions', (_req, res) => {
  const room = createSession();
  res.status(201).json({
    sessionId: room.sessionId,
    joinCode: room.joinCode,
    displayToken: room.displayToken,
    wsUrl: RELAY_WS_URL,
    expiresAt: new Date(room.expiresAt).toISOString(),
  });
});

app.post('/v1/sessions/join', (req, res) => {
  const joinCode = req.body?.joinCode;
  if (!joinCode || typeof joinCode !== 'string') {
    return res.status(400).json({ error: 'joinCode required' });
  }
  try {
    const { room, coachToken } = claimCoachSlot(joinCode);
    return res.status(200).json({
      sessionId: room.sessionId,
      coachToken,
      wsUrl: RELAY_WS_URL,
      expiresAt: new Date(room.expiresAt).toISOString(),
    });
  } catch (e) {
    const code = e.code || 'ERROR';
    if (code === 'INVALID_JOIN_CODE' || code === 'SESSION_NOT_FOUND') {
      return res.status(404).json({ error: code });
    }
    if (code === 'SESSION_EXPIRED') {
      return res.status(410).json({ error: code });
    }
    if (code === 'COACH_SLOT_TAKEN') {
      return res.status(409).json({ error: code });
    }
    return res.status(500).json({ error: 'INTERNAL' });
  }
});

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

// --- WebSocket ---

const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (request, socket, head) => {
  try {
    const host = request.headers.host || `localhost:${PORT}`;
    const u = new URL(request.url || '', `http://${host}`);
    if (u.pathname !== '/ws') {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request, u);
    });
  } catch {
    socket.destroy();
  }
});

wss.on('connection', (ws, _req, url) => {
  const sessionId = url.searchParams.get('sessionId');
  const role = url.searchParams.get('role');
  const token = url.searchParams.get('token');

  if (!sessionId || !role || !token) {
    safeJsonSend(ws, {
      type: 'control.error',
      code: 'MISSING_PARAMS',
      message: 'sessionId, role, and token query params required',
    });
    ws.close(4400, 'missing params');
    return;
  }

  if (role !== 'display' && role !== 'coach') {
    safeJsonSend(ws, {
      type: 'control.error',
      code: 'INVALID_ROLE',
      message: 'role must be display or coach',
    });
    ws.close(4400, 'invalid role');
    return;
  }

  let room;
  /** @type {import('ws').WebSocket | null} */
  let replacedSocket = null;
  try {
    const attached = attachSocket(sessionId, role, token, ws);
    room = attached.room;
    replacedSocket = attached.replacedSocket;
  } catch (e) {
    const code = e.code || 'ATTACH_FAILED';
    if (code === 'SESSION_NOT_FOUND') {
      const suffix = String(sessionId || '').slice(0, 8) || 'nil';
      console.log(`[pba-relay] RELAY attach_rejected reason=SESSION_NOT_FOUND sessionSuffix=${suffix}`);
    }
    safeJsonSend(ws, {
      type: 'control.error',
      code,
      message: String(e.message || code),
    });
    ws.close(4401, code);
    return;
  }

  if (replacedSocket) {
    const suffix = String(room.sessionId || '').slice(0, 8);
    console.log(`[pba-relay] ${role.toUpperCase()} socket replacement sessionSuffix=${suffix}`);
  }

  ws.isAlive = true;
  ws.on('pong', () => {
    ws.isAlive = true;
  });

  const peer = role === 'display' ? room.coachSocket : room.displaySocket;
  const peerPresent = !!(peer && peer !== ws && peer.readyState === WebSocket.OPEN);

  sendControl(ws, {
    type: 'control.ack',
    sessionId: room.sessionId,
    role,
    peerPresent,
  });

  // Same-token replacement is transport recovery: notify the NEW socket of an existing peer,
  // but do not flap the peer with peer_left/peer_joined (zombie may still look "present").
  if (peer && peer.readyState === WebSocket.OPEN) {
    sendControl(ws, { type: 'control.peer_joined', sessionId: room.sessionId });
    if (!replacedSocket) {
      sendControl(peer, { type: 'control.peer_joined', sessionId: room.sessionId });
    }
  }

  // Only after the new socket owns the role slot, close the stale one.
  if (replacedSocket && replacedSocket !== ws) {
    const closeReason = role === 'display' ? 'display_replaced' : 'coach_replaced';
    try {
      replacedSocket.close(4000, closeReason);
    } catch {
      try {
        replacedSocket.terminate();
      } catch {
        /* ignore */
      }
    }
  }

  const heartbeat = setInterval(() => {
    if (ws.isAlive === false) {
      clearInterval(heartbeat);
      ws.terminate();
      return;
    }
    ws.isAlive = false;
    try {
      ws.ping();
    } catch {
      clearInterval(heartbeat);
    }
  }, 30000);

  let cleanedUp = false;
  function cleanup() {
    if (cleanedUp) return;
    cleanedUp = true;
    clearInterval(heartbeat);
    // Capture peer before detach. Identity-safe: only notify if THIS socket still owns the slot.
    const other = role === 'display' ? room.coachSocket : room.displaySocket;
    const detached = detachSocket(room, role, ws);
    if (!detached) {
      // Replaced (or already cleared by a newer owner) — do not send false peer_left.
      return;
    }
    if (other && other.readyState === WebSocket.OPEN) {
      sendControl(other, {
        type: 'control.peer_left',
        sessionId: room.sessionId,
        role,
      });
    }
  }

  ws.on('message', (data, isBinary) => {
    handleAppMessage(room, role, ws, data, isBinary);
  });

  ws.on('close', cleanup);
  ws.on('error', cleanup);
});

/**
 * Relay opaque payloads. JSON with type control.* from client: only control.ping gets control.pong; not relayed.
 * control.ping must work even when the peer slot is empty (solo-in-room keepalive / recovery).
 */
function handleAppMessage(room, role, _sender, data, isBinary) {
  if (!isBinary) {
    const text = data.toString();
    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = null;
    }
    if (parsed && typeof parsed.type === 'string' && parsed.type.startsWith('control.')) {
      if (parsed.type === 'control.ping') {
        sendControl(_sender, { type: 'control.pong', sessionId: room.sessionId });
      }
      return;
    }
    if (parsed == null) {
      const peer = role === 'display' ? room.coachSocket : room.displaySocket;
      if (!peer || peer.readyState !== WebSocket.OPEN) return;
      peer.send(text);
      return;
    }
  }

  const peer = role === 'display' ? room.coachSocket : room.displaySocket;
  if (!peer || peer.readyState !== WebSocket.OPEN) return;

  if (isBinary) {
    peer.send(data, { binary: true });
    return;
  }

  peer.send(data.toString());
}

server.listen(PORT, HOST, () => {
  console.log(`[pba-relay] Listening on all interfaces: ${HOST}:${PORT}`);
  console.log(`[pba-relay] HTTP (localhost) http://127.0.0.1:${PORT}`);
  console.log(`[pba-relay] WS   (localhost) ws://127.0.0.1:${PORT}/ws`);
  const lans = getLanIPv4Addresses();
  if (lans.length > 0) {
    for (const ip of lans) {
      console.log(`[pba-relay] HTTP (LAN)       http://${ip}:${PORT}`);
      console.log(`[pba-relay] WS   (LAN)       ws://${ip}:${PORT}/ws`);
    }
  } else {
    console.log('[pba-relay] No LAN IPv4 detected for hints; use 127.0.0.1 on this machine or set PUBLIC_WS_URL.');
  }
  console.log(`[pba-relay] JSON wsUrl (normalized): ${RELAY_WS_URL}`);
});
