# VisionPlay Relay Server — Production Overview

This document describes the **current production** partner-mode relay used by the VisionPlay iOS app. It is written for future maintainers who may not know the project history.

The relay connects an **iPad display** and an **iPhone coach** over the public internet so Partner Mode training can work without Multipeer / local Wi‑Fi pairing alone.

> Related app config: `Config/RelayRelease.xcconfig` sets `RELAY_HTTP_BASE_URL` to `https://relay.infinite-football.com`.  
> Related server code: repository folder `relay/`.  
> Doc index: [README.md](./README.md).

---

## Current Production Snapshot

**Verified:** August 3, 2026  
**Status:** known-good production state

| Check | Result |
|-------|--------|
| Droplet | `pba-relay` (DigitalOcean, NYC3) |
| Public IP | `104.236.67.75` |
| OS | Ubuntu **22.04.5** |
| Node.js | **v24.14.0** |
| App directory | `/root/relay` |
| SSH user | `root` |
| PM2 process | `relay` — **running / online** |
| Caddy | **running** |
| Internal listen | `127.0.0.1:3000` |
| Health endpoint | `https://relay.infinite-football.com/health` — **verified** (`{"ok":true}`) |
| WebSocket endpoint | `wss://relay.infinite-football.com/ws` |
| Reboot verification | **passed** |
| PM2 resurrection after reboot | **passed** |
| Caddy restart | **passed** |

Use this snapshot as the baseline when investigating regressions. After any major change, re-verify the same checks and update this table.

---

## Production inventory

| Item | Value |
|------|--------|
| **SSH user** | `root` |
| **Droplet name** | `pba-relay` |
| **Cloud provider** | DigitalOcean |
| **OS** | Ubuntu 22.04.5 |
| **Region** | NYC3 |
| **Public IP** | `104.236.67.75` |
| **Domain** | `relay.infinite-football.com` |
| **DNS** | A record → `104.236.67.75` |
| **App directory** | `/root/relay` |
| **Application** | Node.js relay (`relay/` in this repo) |
| **Node.js** | v24.14.0 (production snapshot) |
| **Process manager** | PM2 |
| **PM2 process name** | `relay` |
| **Reverse proxy / TLS** | Caddy |
| **Internal host** | `127.0.0.1` |
| **Internal port** | `3000` |
| **Internal bind** | `127.0.0.1:3000` (Node listens only on localhost) |

---

## Public endpoints

| Purpose | URL |
|---------|-----|
| **Health** | `https://relay.infinite-football.com/health` |
| **Create session** | `POST https://relay.infinite-football.com/v1/sessions` |
| **Join session** | `POST https://relay.infinite-football.com/v1/sessions/join` |
| **WebSocket** | `wss://relay.infinite-football.com/ws` |

### Expected health response

```http
GET /health → HTTP 200
```

```json
{"ok":true}
```

### Expected create-session WebSocket field

`POST /v1/sessions` returns JSON that includes a `wsUrl`. In production it must be:

```text
wss://relay.infinite-football.com/ws
```

That value comes from the server environment variable **`PUBLIC_WS_URL`**. The iOS app does **not** hardcode the WebSocket URL; it uses whatever `wsUrl` the API returns.

---

## Stack roles (what each piece does)

### DigitalOcean droplet (`pba-relay`)

Virtual machine that hosts the entire public relay stack. Region **NYC3**, Ubuntu **22.04.5**.

### Ubuntu

Operating system. Runs Caddy, Node, and PM2. Firewall and packages live here.

### Caddy

Reverse proxy on the public edge:

- Terminates **HTTPS** / **WSS** (TLS certificates, typically Let’s Encrypt).
- Accepts traffic for `relay.infinite-football.com` on port **443**.
- Proxies HTTP and WebSocket upgrade traffic to `http://127.0.0.1:3000`.

Clients never talk to Node’s port directly from the internet.

### Node.js relay

Application process that:

- Creates partner sessions (`POST /v1/sessions`)
- Lets the coach join (`POST /v1/sessions/join`)
- Accepts WebSocket connections on path `/ws`
- Relays opaque messages between **one display** and **one coach** per session (in-memory; no database)

Source of truth for behavior: `relay/src/server.js` and related modules. On the server the app lives at **`/root/relay`**.

### PM2

Keeps the Node process running under the name **`relay`**:

- Restarts on crash
- Resurrects after reboot (verified August 3, 2026)
- Provides `pm2 list` / `pm2 logs relay` for operations

### VisionPlay app

iOS client:

- Uses **HTTPS** base `https://relay.infinite-football.com` (build setting `RELAY_HTTP_BASE_URL`)
- Opens **WSS** using the `wsUrl` from create/join responses

---

## Complete request flow

```text
VisionPlay App  (iPhone coach / iPad display)
        │
        │  HTTPS (REST)  and/or  WSS (WebSocket)
        ▼
relay.infinite-football.com :443
        │
        ▼
Caddy  (TLS termination, reverse proxy)
        │
        │  plain HTTP / WS upgrade to localhost
        ▼
Node Relay  (127.0.0.1:3000)  — /root/relay, PM2 name "relay"
        │
        ▼
PM2  (process supervision)
        │
        ▼
Ubuntu 22.04.5
        │
        ▼
DigitalOcean droplet  pba-relay  (NYC3)
```

### Typical Partner Mode path

1. **Display (iPad)** calls `POST /v1/sessions` over HTTPS.
2. Caddy forwards to Node on `127.0.0.1:3000`.
3. Node returns `joinCode`, tokens, and `wsUrl` (`wss://relay.infinite-football.com/ws`).
4. Display opens a WebSocket to that `wsUrl` (role=`display`).
5. **Coach (iPhone)** calls `POST /v1/sessions/join` with the join code.
6. Coach opens WebSocket (role=`coach`).
7. Relay signals peers and forwards messages for the session.

---

## Environment variables (production intent)

| Variable | Production value |
|----------|------------------|
| `HOST` | `127.0.0.1` |
| `PORT` | `3000` |
| `PUBLIC_WS_URL` | `wss://relay.infinite-football.com/ws` |
| `NODE_ENV` | `production` (recommended) |

Optional: `ROOM_TTL_MS` (24h), `EMPTY_ROOM_GRACE_MS` (default **15 minutes** after both peers disconnect). Same-token display reconnect replaces a zombie display socket immediately (does not wait for the 30s heartbeat).

**TODO:** Confirm whether these are set via a `.env` file in `/root/relay`, PM2 ecosystem file, or shell env on `pm2 start`.

---

## Access cheatsheet

```bash
ssh root@104.236.67.75
# or
ssh root@relay.infinite-football.com

cd /root/relay
pm2 list
pm2 logs relay
```

---

## What this relay is not

- Not a database or long-term analytics store (sessions are **in-memory**).
- Not Multipeer Connectivity (that is a separate local transport path in the app).
- Not Supabase (auth/data live elsewhere; relay is only for partner coach ↔ display messaging).

---

## Quick verification (from any machine)

```bash
dig +short relay.infinite-football.com A
# Expect: 104.236.67.75

curl -fsS https://relay.infinite-football.com/health
# Expect: {"ok":true}

curl -fsS -X POST https://relay.infinite-football.com/v1/sessions
# Expect JSON with wsUrl = wss://relay.infinite-football.com/ws
```

For ongoing ops:

- [README.md](./README.md) — doc map
- [health-check.md](./health-check.md)
- [maintenance.md](./maintenance.md)
- [recovery.md](./recovery.md)
- [deployment.md](./deployment.md)
- [architecture.md](./architecture.md)
- [server-setup.md](./server-setup.md)
