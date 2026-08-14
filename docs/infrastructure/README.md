# VisionPlay Infrastructure Docs

Operational documentation for the **VisionPlay partner relay** hosted on DigitalOcean droplet **`pba-relay`**.

These docs are for future maintainers. They describe production reality as verified during the infrastructure audit and the August 3, 2026 known-good snapshot. They do **not** replace application code docs under `relay/README.md`.

---

## Start here

| If you need to… | Open |
|-----------------|------|
| Learn what is running in production | [relay-server.md](./relay-server.md) |
| Run a quick “is it up?” check | [health-check.md](./health-check.md) |
| Deploy a relay code update | [deployment.md](./deployment.md) |
| Recover from an outage | [recovery.md](./recovery.md) |
| Rebuild a server from scratch | [server-setup.md](./server-setup.md) |
| Understand why the stack looks like this | [architecture.md](./architecture.md) |
| Do monthly / quarterly upkeep | [maintenance.md](./maintenance.md) |

**New maintainer path:** read **relay-server.md** → **architecture.md** → **health-check.md**, then keep **deployment.md** / **recovery.md** handy.

---

## Document map

### [relay-server.md](./relay-server.md)

Production inventory for the live relay: droplet, domain, endpoints, PM2/Caddy/Node roles, request flow, and the **Current Production Snapshot** (known-good state verified August 3, 2026).

### [architecture.md](./architecture.md)

ASCII diagrams and design rationale: why Node binds to localhost, why Caddy terminates TLS, why PM2 supervises the process, and why Node is not exposed directly.

### [deployment.md](./deployment.md)

How to ship relay updates to `/root/relay` on `pba-relay`: SSH, pull/install, `pm2 restart relay`, health/WebSocket/app verification.

### [server-setup.md](./server-setup.md)

End-to-end rebuild guide for a **new** Ubuntu droplet: Node, PM2, code at `/root/relay`, env vars, Caddy, PM2 save, health and WebSocket verification. Unconfirmed steps are marked **TODO**.

### [health-check.md](./health-check.md)

One-page ops checklist with the exact commands (`pm2 list`, Caddy status, health curl, disk/memory, PM2 systemd unit) and expected healthy output.

### [maintenance.md](./maintenance.md)

Monthly and quarterly recurring checklist (health, PM2, Caddy, resources, SSL, updates, snapshots, reboot survival).

### [recovery.md](./recovery.md)

Disaster recovery and troubleshooting: reboot, PM2 resurrection, Caddy, DNS, HTTPS, WebSocket failures, and droplet-level restore pointers.

---

## Confirmed production facts (quick reference)

| Item | Value |
|------|--------|
| SSH | `ssh root@104.236.67.75` |
| Droplet | `pba-relay` (NYC3) |
| App directory | `/root/relay` |
| PM2 process | `relay` |
| Internal | `127.0.0.1:3000` |
| Health | `https://relay.infinite-football.com/health` |
| WebSocket | `wss://relay.infinite-football.com/ws` |

iOS Release/Debug builds currently use HTTPS base `https://relay.infinite-football.com` via `Config/RelayRelease.xcconfig` and `Config/RelayDebug.xcconfig`.

---

## Related in-repo docs (outside this folder)

- `relay/README.md` — application behavior, env vars, local/dev run
- `relay/DEPLOYMENT_CHECKLIST.md` — earlier deploy checklist (keep in sync mentally with these ops docs)
- `Config/README.md` — how the iOS app injects `RELAY_HTTP_BASE_URL`
