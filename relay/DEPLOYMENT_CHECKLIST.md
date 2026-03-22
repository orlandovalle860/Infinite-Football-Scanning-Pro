# Relay + app — deployment checklist

Concise steps to deploy the Node relay behind TLS and point the iOS app at it.

---

## 1. Relay deployment

- [ ] VPS has **Node.js 18+** installed.
- [ ] Copy `relay/` to the server (or clone the repo) and run `npm install --production` in `relay/`.
- [ ] Set **environment variables** (see §2) — systemd, pm2, Docker, or `.env` as you prefer.
- [ ] Bind **HTTP** only on localhost (e.g. `127.0.0.1:3000`) if a reverse proxy on the same host fronts TLS.
- [ ] Install and configure a **reverse proxy** (Nginx, Caddy, …) for TLS and WebSocket upgrade (`/ws`). See `README.md` → *Production (VPS + TLS)*.
- [ ] Start the relay: `npm start` (or your process manager).

---

## 2. Required environment variables

| Variable | Production example | Purpose |
|----------|-------------------|---------|
| `PORT` | `3000` | Port Node listens on (behind proxy). |
| `HOST` | `127.0.0.1` | Bind address (`0.0.0.0` only if needed without a local proxy). |
| `PUBLIC_WS_URL` | `wss://relay.yourdomain.com/ws` | Returned in API JSON as `wsUrl` — **must** match public WSS URL. |

Optional: `ROOM_TTL_MS`, `EMPTY_ROOM_GRACE_MS` (defaults usually fine). See `relay/.env.production.example`.

---

## 3. Domain and TLS

- [ ] **DNS:** `relay.yourdomain.com` (or your chosen hostname) **A/AAAA** → VPS IP.
- [ ] **TLS:** Valid certificate on the proxy (e.g. Let’s Encrypt) for **HTTPS** on port **443**.
- [ ] **HTTPS** terminates at the proxy; proxy forwards to `http://127.0.0.1:<PORT>`.
- [ ] **WebSocket:** Path **`/ws`** proxied with **Upgrade** + **Connection** headers (HTTP/1.1, long read timeout). Same host as HTTPS → clients use **`wss://`**.

---

## 4. App config (production)

- [ ] In the Xcode project, set **`RELAY_HTTP_BASE_URL`** for **Release** builds.

**File:** `Config/RelayRelease.xcconfig`  

**Value:** HTTPS base **with no path**, same host as the relay API:

```text
https://relay.yourdomain.com
```

(Use the `SLASH` pattern already in that file — replace `relay.yourdomain.com` with your real hostname.)

- [ ] Archive / ship a **Release** build (not Debug relay URL).

---

## 5. Health check and smoke tests

**Health (from any machine with DNS to your relay):**

```bash
curl -fsS https://relay.yourdomain.com/health
```

Expect: `{"ok":true}` and HTTP **200**.

**API smoke (session creation):**

```bash
curl -fsS -X POST https://relay.yourdomain.com/v1/sessions | jq
```

- [ ] Response includes `joinCode`, `sessionId`, `displayToken`, **`wsUrl`**.
- [ ] **`wsUrl`** is exactly **`wss://relay.yourdomain.com/ws`** (or your host; scheme **`wss`** in production).

---

## 6. Final verification (Two Minute partner, relay mode)

**Prereq:** iOS **Debug** build uses relay transport for Two Minute partner (see app); both devices reach **`https://relay.yourdomain.com`**.

| Step | Action | Pass? |
|------|--------|------|
| A | **iPad (display):** Start Two Minute partner session; confirm join code / relay UI appears. | [ ] |
| B | **iPhone (coach):** Enter join code, connect relay WebSocket. | [ ] |
| C | Both sides show **connected** / relay status; **raw or UI** indicates **`control.peer_joined`** (or equivalent “joined display”). | [ ] |
| D | Coach sends **NEXT REP** (or next rep flow); **display** receives the rep (engine advances). **One** `TwoMinuteMessage` path (e.g. `nextRep`) is delivered end-to-end. | [ ] |

If **A–D** pass, relay + app config are aligned for production.

---

## Quick reference

| Item | Value |
|------|--------|
| Public HTTPS API | `https://relay.yourdomain.com` |
| Public WSS (in JSON) | `wss://relay.yourdomain.com/ws` |
| iOS `RELAY_HTTP_BASE_URL` (Release) | `https://relay.yourdomain.com` |
| Health | `GET /health` |

More detail: **`relay/README.md`** (Production section).
