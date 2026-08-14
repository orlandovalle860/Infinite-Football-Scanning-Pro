# VisionPlay Relay — Architecture Overview

High-level design of the production partner relay for VisionPlay.

This document explains **how the pieces fit together** and **why** the stack is shaped this way. For inventory, endpoints, and the August 3, 2026 snapshot, see [relay-server.md](./relay-server.md). Doc index: [README.md](./README.md).

Production process facts: app at `/root/relay`, PM2 name `relay`, internal `127.0.0.1:3000`, public `https://relay.infinite-football.com` / `wss://relay.infinite-football.com/ws`.

---

## System diagram

```text
VisionPlay iPhone (coach)
        │
        │  HTTPS + WSS
        ▼
relay.infinite-football.com
        │
        ▼
      Caddy          ← public edge: TLS + reverse proxy
        │
        │  HTTP / WS to localhost only
        ▼
  127.0.0.1:3000
        │
        ▼
   Node Relay        ← /root/relay
        │
        ▼
   PM2 (relay)       ← keep Node alive / restart on failure
        │
        ▼
     Ubuntu          ← OS on the VM
        │
        ▼
  DigitalOcean       ← droplet pba-relay (NYC3)
```

The **iPad display** uses the same public hostname and paths; both roles meet inside an in-memory relay session.

---

## End-to-end Partner Mode flow

```text
┌──────────────┐   POST /v1/sessions (HTTPS)   ┌─────────┐
│ iPad Display │ ─────────────────────────────▶│  Caddy  │──▶ Node
│              │◀──── joinCode + wsUrl ────────│         │
│              │   WSS /ws?role=display…       │         │──▶ Node WS
└──────────────┘                               └─────────┘

┌──────────────┐   POST /v1/sessions/join      ┌─────────┐
│ iPhone Coach │ ─────────────────────────────▶│  Caddy  │──▶ Node
│              │◀──── coachToken + wsUrl ──────│         │
│              │   WSS /ws?role=coach…         │         │──▶ Node WS
└──────────────┘                               └─────────┘

                 opaque training messages ◀──▶ relay room
```

Important design detail:

- The app’s configured base URL is only the **HTTPS API** host (`https://relay.infinite-football.com`).
- The **WebSocket URL** is supplied by the server (`PUBLIC_WS_URL` → JSON field `wsUrl`).

---

## Why the relay only listens on localhost

Production Node binds to **`127.0.0.1:3000`** (`HOST=127.0.0.1`).

Reasons:

1. **Attack surface** — The Node process is not reachable from the public internet. Only Caddy on the same machine can talk to it.
2. **Single entry point** — All auth-at-the-edge concerns (TLS, HTTP headers, rate limits later) can live at the proxy.
3. **Clear trust boundary** — Port 3000 is internal plumbing, not a product endpoint.
4. **Fewer mistakes** — Operators are less likely to accidentally expose an unencrypted Node server on `:3000`.

If Node were bound to `0.0.0.0:3000` without a firewall, anyone could bypass Caddy and hit plain HTTP/WS.

---

## Why Caddy terminates HTTPS

Caddy sits on **443** and presents certificates for `relay.infinite-football.com`.

Reasons:

1. **TLS is hard to get wrong with a dedicated proxy** — Certificate obtain/renew (Let’s Encrypt) is a solved operational path for Caddy.
2. **Node stays simple** — The relay speaks plain HTTP locally; no certificate files inside the Node app.
3. **WebSocket upgrade at the edge** — Caddy proxies HTTP and WSS upgrade to localhost; clients use `https://` and `wss://`.
4. **Operational separation** — TLS outages vs app crashes can be diagnosed separately (`systemctl status caddy` vs `pm2 list`).

---

## Why PM2 manages the Node process

PM2 supervises the relay process.

Reasons:

1. **Auto-restart** on crash.
2. **Visibility** — `pm2 list`, `pm2 logs` for operators.
3. **Boot persistence** — with `pm2 startup` + `pm2 save`, the relay returns after reboot.
4. **Low ceremony** — suitable for a single small Node service on one droplet.

(Alternatives like systemd are also valid; this production host uses **PM2**.)

---

## Why not expose Node directly on the internet?

Exposing Node on `:443` or public `:3000` would mean:

- Implementing TLS inside Node or terminating TLS elsewhere anyway
- Handling certificate renewal in-app or with a sidecar
- Widening the attack surface of the application process
- Mixing process supervision concerns with edge concerns

The preferred architecture:

```text
Internet clients
      │
      ▼
Caddy (public, TLS, proxy)     ← hardened edge
      │
      ▼
Node on localhost              ← minimal app surface
```

This matches common production practice for small Node services and matches the guidance in `relay/README.md` (*Production (VPS + TLS)*).

---

## Data & durability characteristics

| Topic | Behavior |
|-------|----------|
| Session storage | **In-memory** (lost on process restart) |
| Database | **None** |
| Auth for rooms | Opaque display/coach tokens + join codes |
| Persistence of training history | **Not** the relay’s job (app / Supabase elsewhere) |

Implication: a relay restart drops active partner sessions. Clients must create/join again. That is expected for this design.

---

## Relationship to the iOS app

| Layer | Location |
|-------|----------|
| Production HTTPS base | `Config/RelayRelease.xcconfig` → `RELAY_HTTP_BASE_URL` |
| Info.plist injection | `Info.plist` key `RELAY_HTTP_BASE_URL` |
| Runtime HTTP client | `WebSocketSessionAPI.swift` |
| Runtime WS transport | `WebSocketRemoteTransport.swift` + partner session coordinators |

Debug builds currently use the **same** production hostname (see `Config/RelayDebug.xcconfig`). Treat production deploys as live for both TestFlight/App Store and typical local Debug partner testing.

---

## Related docs

- [relay-server.md](./relay-server.md)
- [deployment.md](./deployment.md)
- [maintenance.md](./maintenance.md)
- [recovery.md](./recovery.md)
- [health-check.md](./health-check.md)
