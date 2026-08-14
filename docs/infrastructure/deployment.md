# Relay Deployment Guide

How to deploy updates to the **production** VisionPlay relay on DigitalOcean droplet **`pba-relay`**.

Audience: maintainers with moderate Linux experience.

> Do not change iOS app Relay URLs as part of a normal relay deploy. App config is separate (`Config/RelayRelease.xcconfig`).

---

## Production facts (confirmed)

| Item | Value |
|------|--------|
| SSH | `ssh root@104.236.67.75` or `ssh root@relay.infinite-football.com` |
| Droplet | `pba-relay` |
| App directory | `/root/relay` |
| PM2 process name | `relay` |
| Internal listen | `127.0.0.1:3000` |
| Health | `https://relay.infinite-football.com/health` |
| WebSocket | `wss://relay.infinite-football.com/ws` |

---

## Prerequisites

- SSH access as **`root`** to `pba-relay`
- Node.js on the server (production snapshot: **v24.14.0**)
- PM2 managing process **`relay`**
- Caddy terminating TLS for `relay.infinite-football.com`
- Ability to update code under `/root/relay`

### Confirm before you start

```bash
curl -fsS https://relay.infinite-football.com/health
```

Expect: `{"ok":true}`

If production is already down, prefer [recovery.md](./recovery.md) before deploying new code.

---

## 1. SSH into the server

```bash
ssh root@104.236.67.75
# or
ssh root@relay.infinite-football.com
```

Confirm host:

```bash
hostname
# Expect: related to pba-relay / this droplet
uname -a
```

---

## 2. Go to the relay application directory

```bash
cd /root/relay
ls
# Expect package.json and src/server.js (or equivalent relay layout)
```

---

## 3. Pull latest code

If `/root/relay` is a Git checkout:

```bash
git status
git fetch origin
git pull origin main
```

**TODO:** Confirm whether `/root/relay` is a full monorepo checkout, a git checkout of only the `relay/` tree, or a plain directory updated by copy/rsync. Adjust the pull/copy step to match.

If deploys are done by copying from the monorepo:

```bash
# Example shape — only use if this matches your workflow
# git -C /root/Infinite-Football-Scanning-Pro pull origin main
# cp -a /root/Infinite-Football-Scanning-Pro/relay/. /root/relay/
```

Monorepo remote (app repo):

```text
https://github.com/orlandovalle860/Infinite-Football-Scanning-Pro.git
```

---

## 4. Install dependencies (if needed)

After dependency changes in `package.json` / lockfile:

```bash
cd /root/relay
npm install --production
```

If only application source changed and dependencies are unchanged, you may skip this step — still preferred after any lockfile change.

---

## 5. Confirm production environment

Before restart, verify the process will keep production settings:

| Variable | Required production value |
|----------|---------------------------|
| `HOST` | `127.0.0.1` |
| `PORT` | `3000` |
| `PUBLIC_WS_URL` | `wss://relay.infinite-football.com/ws` |

```bash
pm2 env relay
# and/or:
# cat /root/relay/.env
```

**TODO:** Document the exact place env vars are defined on this host (PM2 ecosystem, `.env`, or inline `pm2 start` env).

**Critical:** If `PUBLIC_WS_URL` is wrong, the app will receive a bad `wsUrl` and Partner Mode WebSockets will fail even if `/health` looks fine.

---

## 6. Restart the relay with PM2

```bash
pm2 list
pm2 restart relay
```

Prefer `restart` over delete/start unless you need a full recreate.

If the process is missing (unusual for a routine deploy):

```bash
cd /root/relay
# Recommended start shape (confirm env injection method on this host):
HOST=127.0.0.1 PORT=3000 PUBLIC_WS_URL=wss://relay.infinite-football.com/ws \
  pm2 start src/server.js --name relay
pm2 save
```

Check status:

```bash
pm2 list
pm2 logs relay --lines 50
```

Expect process **`relay`** to be **online**, not errored/restart-looping.

---

## 7. Verify health endpoint

```bash
curl -fsS https://relay.infinite-football.com/health
# Expect: {"ok":true}

curl -fsS http://127.0.0.1:3000/health
# Expect: {"ok":true}
```

If public HTTPS fails but localhost works, the problem is likely **Caddy / TLS / firewall**, not Node. See [recovery.md](./recovery.md).

---

## 8. Verify WebSocket endpoint (API contract)

```bash
curl -fsS -X POST https://relay.infinite-football.com/v1/sessions
```

Confirm the JSON includes:

- `sessionId`
- `joinCode`
- `displayToken`
- `wsUrl` exactly: **`wss://relay.infinite-football.com/ws`**

Optional deeper check with a WebSocket client (e.g. websocat) using the returned tokens — see `relay/README.md` for local examples; use `wss://` URLs in production.

---

## 9. Verify Caddy still serving TLS

```bash
systemctl status caddy
# Expect: active (running)
```

Quick TLS sanity:

```bash
curl -vI https://relay.infinite-football.com/health 2>&1 | grep -E 'HTTP/|SSL|subject:|expire'
```

---

## 10. Verify app connectivity

With a VisionPlay build pointed at production:

| Step | Action | Pass? |
|------|--------|------|
| A | iPad: start a Partner Mode activity; join code appears | [ ] |
| B | iPhone coach: enter join code and connect | [ ] |
| C | Both sides show connected / paired | [ ] |
| D | Coach advances a rep; display receives it | [ ] |

If API health is green but the app fails, check:

- App `RELAY_HTTP_BASE_URL` is still `https://relay.infinite-football.com`
- Returned `wsUrl` is `wss://relay.infinite-football.com/ws`
- Device network / captive portals
- Server logs during join (`pm2 logs relay`)

---

## Deployment checklist (copy/paste)

- [ ] Pre-check: `curl https://relay.infinite-football.com/health` → `{"ok":true}`
- [ ] `ssh root@104.236.67.75`
- [ ] `cd /root/relay`
- [ ] Pull / deliver new code
- [ ] `npm install --production` if dependencies changed
- [ ] Confirm `PUBLIC_WS_URL=wss://relay.infinite-football.com/ws`
- [ ] `pm2 restart relay`
- [ ] `pm2 list` shows `relay` online
- [ ] Public `/health` OK
- [ ] `POST /v1/sessions` returns correct `wsUrl`
- [ ] Caddy active
- [ ] Partner Mode smoke test on devices

---

## Rollback (high level)

If a deploy breaks Partner Mode:

1. Note the failing symptom (health vs WSS vs app-only).
2. Restore previous known-good code in `/root/relay`.
   - **TODO:** Document the exact rollback command used here (`git checkout <sha>`, previous artifact, etc.).
3. `pm2 restart relay`
4. Re-run health + session create + device smoke test.

If the droplet itself is unhealthy, use [recovery.md](./recovery.md) and DigitalOcean snapshots (see [maintenance.md](./maintenance.md)).

---

## Related docs

- [relay-server.md](./relay-server.md) — production topology + August 3, 2026 snapshot
- [server-setup.md](./server-setup.md) — rebuild from a blank Ubuntu server
- [architecture.md](./architecture.md)
- [health-check.md](./health-check.md)
- Repo: `relay/README.md`, `relay/DEPLOYMENT_CHECKLIST.md`
