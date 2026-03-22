# PBA WebSocket relay (scaffold)

Minimal Node relay: **one display** + **one coach** per session. In-memory only; no database.

## Requirements

- Node.js **18+**

## Install

```bash
cd relay
npm install
```

## Run

```bash
npm start
```

With auto-reload on file changes:

```bash
npm run dev
```

Default: **HTTP** `http://127.0.0.1:3000`, **WebSocket** `ws://127.0.0.1:3000/ws`.

### Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3000` | HTTP port the Node process listens on |
| `HOST` | `0.0.0.0` | Bind address (`127.0.0.1` if only the reverse proxy on the same machine connects) |
| `PUBLIC_WS_URL` | `ws://<host>:<port>/ws` (derived) | **Canonical WebSocket base** returned in JSON as `wsUrl` (see `normalizeRelayWsUrl()` in `server.js`). **Must** be set to your public `wss://…` URL in production. |
| `ROOM_TTL_MS` | `86400000` (24h) | Session expiry from creation |
| `EMPTY_ROOM_GRACE_MS` | `300000` (5m) | After both peers disconnect, delete room after this delay |

Template for production: copy `relay/.env.production.example` and adjust values on the server.

## Quick test (curl + websocat)

Install [websocat](https://github.com/vi/websocat) or use any WebSocket client.

1. Create a session:

```bash
curl -s -X POST http://127.0.0.1:3000/v1/sessions | jq
```

Save `sessionId`, `joinCode`, `displayToken`, and `wsUrl`.

2. Display connects (replace values):

```bash
websocat "ws://127.0.0.1:3000/ws?sessionId=SESSION_ID&role=display&token=DISPLAY_TOKEN"
```

3. Coach joins via HTTP:

```bash
curl -s -X POST http://127.0.0.1:3000/v1/sessions/join \
  -H 'Content-Type: application/json' \
  -d '{"joinCode":"JOINCODE"}' | jq
```

4. Coach connects:

```bash
websocat "ws://127.0.0.1:3000/ws?sessionId=SESSION_ID&role=coach&token=COACH_TOKEN"
```

You should see `control.ack` on each side; when both are up, `control.peer_joined`. JSON text messages from one side appear on the other (opaque relay).

Health check:

```bash
curl -s http://127.0.0.1:3000/health
```

## Project layout

- `src/server.js` — Express + WebSocket upgrade, relay, control messages, heartbeat
- `src/roomStore.js` — In-memory rooms, join codes, attach/detach, TTL + empty-room cleanup
- `src/token.js` — Opaque tokens (base64url)
- `src/codegen.js` — 6-character join codes

---

## Production (VPS + TLS)

Run the relay as a **plain HTTP** Node process on the host (e.g. `127.0.0.1:3000`). Terminate **TLS** at a **reverse proxy** (Nginx, Caddy, Traefik, etc.) in front of it. Clients and the iOS app use **HTTPS** / **WSS** to your public hostname.

### Assumptions

| Public endpoint | Example |
|-----------------|--------|
| HTTPS API base (create/join sessions) | `https://relay.yourdomain.com` |
| WebSocket URL (returned in JSON as `wsUrl` after normalization) | `wss://relay.yourdomain.com/ws` |

The iOS app’s **`RELAY_HTTP_BASE_URL`** (see `Config/RelayRelease.xcconfig`) must be the **HTTPS base with no path**, e.g. `https://relay.yourdomain.com` — same host the relay serves HTTP on.

### Environment variables (production)

Set these on the server (systemd `Environment=`, Docker `env`, hosting panel, or `.env` loaded by your process manager):

| Variable | Example value | Notes |
|----------|----------------|--------|
| `PORT` | `3000` | Port Node listens on **behind** the proxy. |
| `HOST` | `127.0.0.1` | Bind only to localhost if the proxy is on the same machine; use `0.0.0.0` only if you need direct access without a proxy. |
| `PUBLIC_WS_URL` | `wss://relay.yourdomain.com/ws` | **Required** for production. This is embedded in API responses so clients open the correct secure WebSocket. Scheme must be `wss` when the site is served over HTTPS. |

Optional (same as local dev):

| Variable | Default |
|----------|---------|
| `ROOM_TTL_MS` | `86400000` |
| `EMPTY_ROOM_GRACE_MS` | `300000` |

### How to run the relay

- **Install:** `cd relay && npm install --production`
- **Start:** `npm start` (or `node src/server.js`)
- **Process manager:** use **systemd**, **pm2**, or Docker so the process restarts on failure and reboot. Example systemd unit:

```ini
[Service]
WorkingDirectory=/opt/pba-relay/relay
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=HOST=127.0.0.1
Environment=PUBLIC_WS_URL=wss://relay.yourdomain.com/ws
ExecStart=/usr/bin/node src/server.js
Restart=always
```

Adjust paths and add `User=` as appropriate.

### Reverse proxy: expected behavior

1. **TLS:** Terminate HTTPS on `443` with a valid certificate (e.g. Let’s Encrypt).
2. **HTTP:** Forward `https://relay.yourdomain.com/*` to `http://127.0.0.1:3000` (or whatever `HOST:PORT` the relay uses).
3. **Routes the relay uses:**
   - `POST /v1/sessions` — create session
   - `POST /v1/sessions/join` — coach join
   - `GET /health` — health check
   - **WebSocket:** path **`/ws`** only (upgrade handler rejects other paths).

4. **WebSocket upgrade (required):** The proxy must pass through the upgrade handshake:

   - `Upgrade: websocket`
   - `Connection: Upgrade`
   - Forward `Host`, and optionally `X-Forwarded-For` / `X-Forwarded-Proto` if your stack needs them.

   **Nginx** (illustrative — adjust `upstream`/`proxy_pass`):

   ```nginx
   map $http_upgrade $connection_upgrade {
       default upgrade;
       ''      close;
   }

   server {
       listen 443 ssl;
       server_name relay.yourdomain.com;
       # ssl_certificate / ssl_certificate_key ...

       location /ws {
           proxy_pass http://127.0.0.1:3000;
           proxy_http_version 1.1;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection $connection_upgrade;
           proxy_set_header Host $host;
           proxy_read_timeout 86400s;
       }

       location / {
           proxy_pass http://127.0.0.1:3000;
           proxy_http_version 1.1;
           proxy_set_header Host $host;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```

   **Caddy** (TLS automatic): a minimal `Caddyfile` often forwards HTTP and WebSocket correctly when using `reverse_proxy 127.0.0.1:3000` for the whole site; ensure long timeouts for long-lived WS connections.

**Why `PUBLIC_WS_URL` matters:** The relay does not see the public hostname from the client when building JSON. It uses `PUBLIC_WS_URL` so `POST /v1/sessions` (and join) return a `wsUrl` that matches what clients must dial (`wss://…/ws` in production).

### Health check

Use **`GET /health`** for load balancers and uptime checks:

```bash
curl -fsS https://relay.yourdomain.com/health
```

Expect JSON: `{"ok":true}` (HTTP 200).

### Quick production smoke test

```bash
curl -fsS https://relay.yourdomain.com/health
curl -fsS -X POST https://relay.yourdomain.com/v1/sessions | jq
```

Confirm `wsUrl` in the JSON is `wss://relay.yourdomain.com/ws` (or your chosen host).
