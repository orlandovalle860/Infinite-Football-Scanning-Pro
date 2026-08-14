# Rebuild Relay Server From a New Ubuntu Host

Complete guide to recreate the VisionPlay production relay on a **brand-new** Ubuntu server, matching the known-good layout used on droplet **`pba-relay`**.

Target end state:

| Item | Value |
|------|--------|
| SSH user | `root` |
| App directory | `/root/relay` |
| PM2 process name | `relay` |
| Internal listen | `127.0.0.1:3000` |
| Domain | `relay.infinite-football.com` |
| Health | `https://relay.infinite-football.com/health` |
| WebSocket | `wss://relay.infinite-football.com/ws` |

Production reference snapshot (August 3, 2026): Ubuntu **22.04.5**, Node **v24.14.0**, PM2 + Caddy running — see [relay-server.md](./relay-server.md).

> Marked **TODO** items must be confirmed on the new host rather than guessed.

---

## 1. Create the DigitalOcean droplet

1. In DigitalOcean, create a droplet.
2. Recommended baseline to match production:
   - **Image:** Ubuntu **22.04** LTS
   - **Region:** NYC3 (or update DNS/docs if you choose another region)
   - **Name:** e.g. `pba-relay` (or a new name — update docs if renamed)
3. Enable SSH key auth for **`root`** (or your admin user; production ops docs assume `root`).
4. Note the new **public IPv4**.

**TODO:** Confirm droplet size / plan used in production (CPU/RAM) and match it for capacity.

---

## 2. Point DNS at the new droplet

Create or update an **A** record:

```text
relay.infinite-football.com  →  <NEW_DROPLET_IP>
```

Wait for DNS to propagate:

```bash
dig +short relay.infinite-football.com A
# Expect: <NEW_DROPLET_IP>
```

If this is a replacement for the existing host, the previous IP was `104.236.67.75`. Update [relay-server.md](./relay-server.md) after cutover.

---

## 3. SSH into the new server

```bash
ssh root@<NEW_DROPLET_IP>
```

Update packages:

```bash
apt update
apt upgrade -y
```

---

## 4. Install Node.js

Production snapshot used **Node v24.14.0**. Install a current Node **18+** (prefer matching v24.x if possible).

**TODO:** Confirm the exact install method used on `pba-relay` (NodeSource, `nvm`, snap, official tarball, etc.). Example using NodeSource-style setup is common but must be verified:

```bash
# TODO: replace with the confirmed Node install commands for this project
node -v
# Expect something like v24.14.0 when matched to production snapshot
npm -v
```

---

## 5. Install PM2

```bash
npm install -g pm2
pm2 -v
```

---

## 6. Obtain the relay application at `/root/relay`

Production runs from **`/root/relay`**.

Monorepo (contains `relay/`):

```text
https://github.com/orlandovalle860/Infinite-Football-Scanning-Pro.git
```

Recommended approach:

```bash
cd /root
git clone https://github.com/orlandovalle860/Infinite-Football-Scanning-Pro.git
mkdir -p /root/relay
cp -a /root/Infinite-Football-Scanning-Pro/relay/. /root/relay/
cd /root/relay
ls
# Expect: package.json, src/server.js, etc.
```

**TODO:** Confirm whether production `/root/relay` is maintained as:

- a copy of `relay/` only (as above), or
- a git repo itself, or
- a different deploy artifact path

Use the same method for ongoing deploys ([deployment.md](./deployment.md)).

---

## 7. Install dependencies

```bash
cd /root/relay
npm install --production
```

---

## 8. Configure environment variables

Required production values:

```bash
export HOST=127.0.0.1
export PORT=3000
export PUBLIC_WS_URL=wss://relay.infinite-football.com/ws
# optional but recommended:
export NODE_ENV=production
```

Persist them for PM2 using one of:

```bash
# Option A: .env file loaded by your start method
# TODO: confirm whether the relay process loads .env automatically on this host
# cp /root/relay/.env.production.example /root/relay/.env
# then edit PUBLIC_WS_URL / HOST / PORT

# Option B: pass env on pm2 start (shown in next section)
```

| Variable | Value |
|----------|--------|
| `HOST` | `127.0.0.1` |
| `PORT` | `3000` |
| `PUBLIC_WS_URL` | `wss://relay.infinite-football.com/ws` |

**Do not** bind Node to `0.0.0.0` in production when Caddy is on the same host.

---

## 9. Install and configure Caddy

Install Caddy for Ubuntu.

**TODO:** Confirm the exact Caddy install commands/repo used on `pba-relay` (official Caddy apt repo vs distro package).

After install:

```bash
systemctl enable caddy
systemctl status caddy
```

Configure reverse proxy for `relay.infinite-football.com` → `127.0.0.1:3000` with WebSocket support.

Illustrative Caddyfile site block (adjust to the real file on disk):

```caddyfile
relay.infinite-football.com {
        reverse_proxy 127.0.0.1:3000
}
```

**TODO:** Confirm production Caddyfile path (often `/etc/caddy/Caddyfile`) and the exact site block in use (timeouts, logging, headers).

Validate and reload:

```bash
# TODO: confirm config path
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
# or: systemctl restart caddy
```

Open firewall / DigitalOcean cloud firewall for **80** and **443** (required for HTTPS + Let’s Encrypt).

**TODO:** Document any DigitalOcean firewall rules currently applied to `pba-relay`.

---

## 10. Start the relay with PM2

```bash
cd /root/relay
HOST=127.0.0.1 PORT=3000 PUBLIC_WS_URL=wss://relay.infinite-football.com/ws \
  pm2 start src/server.js --name relay

pm2 list
# Expect: relay | online
```

Local smoke test (before or after Caddy):

```bash
curl -fsS http://127.0.0.1:3000/health
# Expect: {"ok":true}
```

---

## 11. Save PM2 state (survive reboot)

```bash
pm2 startup
# Run the command PM2 prints (systemd unit for root)
pm2 save
systemctl status pm2-root
```

Reboot test (recommended before declaring production ready):

```bash
reboot
# reconnect
ssh root@<NEW_DROPLET_IP>
pm2 list
# Expect: relay online without manual start
systemctl status caddy
curl -fsS https://relay.infinite-football.com/health
```

---

## 12. Verify health endpoint

```bash
curl -fsS https://relay.infinite-football.com/health
# Expect: {"ok":true}
```

If this fails:

- DNS not pointing at this droplet yet
- Caddy not running / cert issuance failed (check `journalctl -u caddy`)
- Node not listening (`pm2 logs relay`, `curl http://127.0.0.1:3000/health`)

---

## 13. Verify WebSocket connectivity

### API contract

```bash
curl -fsS -X POST https://relay.infinite-football.com/v1/sessions
```

Confirm:

- HTTP 200 JSON body
- `wsUrl` is exactly **`wss://relay.infinite-football.com/ws`**

### Optional WebSocket client test

**TODO:** Prefer documenting the exact websocat (or equivalent) commands used by the team once confirmed on a rebuild. Pattern:

1. Create session → capture `sessionId`, `displayToken`, `wsUrl`
2. Connect display role over WSS with query params
3. Join as coach via `POST /v1/sessions/join`
4. Connect coach role over WSS
5. Confirm peer join / message relay

See also `relay/README.md` for local `ws://` examples; production must use **`wss://`**.

### App verification

- iPad Partner Mode shows join code
- iPhone coach joins and pairs
- One rep command flows end-to-end

---

## 14. Post-build checklist

- [ ] Droplet created (Ubuntu 22.04)
- [ ] DNS A record → new IP
- [ ] Node installed (`node -v`)
- [ ] PM2 installed
- [ ] Code present at `/root/relay`
- [ ] `npm install --production`
- [ ] Env: `HOST`, `PORT`, `PUBLIC_WS_URL`
- [ ] Caddy installed, proxying to `127.0.0.1:3000`
- [ ] `pm2 start … --name relay`
- [ ] `pm2 startup` + `pm2 save`
- [ ] `https://relay.infinite-football.com/health` → `{"ok":true}`
- [ ] `POST /v1/sessions` → `wsUrl` = `wss://relay.infinite-football.com/ws`
- [ ] Reboot survival verified
- [ ] Update [relay-server.md](./relay-server.md) Current Production Snapshot

---

## Related docs

- [README.md](./README.md)
- [relay-server.md](./relay-server.md)
- [deployment.md](./deployment.md)
- [recovery.md](./recovery.md)
- [architecture.md](./architecture.md)
- Repo: `relay/README.md`, `relay/.env.production.example`
