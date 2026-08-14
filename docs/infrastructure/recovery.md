# Relay Disaster Recovery & Troubleshooting

Procedures when VisionPlay Partner Mode relay (`relay.infinite-football.com`) is degraded or offline.

| Item | Value |
|------|--------|
| Droplet | `pba-relay` |
| SSH | `ssh root@104.236.67.75` |
| App directory | `/root/relay` |
| PM2 name | `relay` |
| Internal | `127.0.0.1:3000` |
| Health | `https://relay.infinite-football.com/health` |
| WebSocket | `wss://relay.infinite-football.com/ws` |

---

## Recovery goals (in order)

1. Droplet is reachable over SSH as `root`.
2. Caddy is serving HTTPS for `relay.infinite-football.com`.
3. Node relay is listening on `127.0.0.1:3000` under PM2 process `relay`.
4. Public `/health` returns `{"ok":true}`.
5. `POST /v1/sessions` returns `wsUrl: wss://relay.infinite-football.com/ws`.
6. App can create/join and exchange Partner Mode messages.

---

## A. Reboot verification

After a planned or unexpected reboot:

```bash
ssh root@104.236.67.75

uptime
hostname
systemctl is-system-running || true
```

- [ ] SSH works
- [ ] System finished booting

Then continue with Caddy → PM2 → health checks below.

*(Reboot verification passed on August 3, 2026 — see [relay-server.md](./relay-server.md) snapshot.)*

---

## B. PM2 resurrection

```bash
pm2 list
```

**Healthy:** process **`relay`** shows **online**.

If empty / stopped:

```bash
pm2 resurrect
# or
pm2 restart relay
```

If completely missing:

```bash
cd /root/relay
HOST=127.0.0.1 PORT=3000 PUBLIC_WS_URL=wss://relay.infinite-football.com/ws \
  pm2 start src/server.js --name relay
pm2 save
```

Ensure startup on boot is configured (one-time / if broken):

```bash
pm2 startup
pm2 save
```

Also confirm:

```bash
systemctl status pm2-root
```

*(PM2 resurrection after reboot passed on August 3, 2026.)*

---

## C. Caddy startup

```bash
systemctl status caddy
systemctl start caddy
systemctl enable caddy
```

Validate config if Caddy fails to start:

```bash
# TODO: confirm Caddyfile path on this host (commonly /etc/caddy/Caddyfile on Ubuntu packages)
caddy validate --config /etc/caddy/Caddyfile
systemctl restart caddy
journalctl -u caddy -n 100 --no-pager
```

*(Caddy restart passed on August 3, 2026.)*

---

## D. Health endpoint verification

```bash
curl -fsS https://relay.infinite-football.com/health
# Expect: {"ok":true}

curl -fsS http://127.0.0.1:3000/health
# Expect: {"ok":true}
```

Interpretation:

| Public HTTPS | Localhost :3000 | Likely layer |
|--------------|-----------------|--------------|
| OK | OK | Healthy |
| Fail | OK | Caddy / TLS / DNS / firewall |
| Fail | Fail | Node / PM2 / app crash |
| OK | Fail | Unusual — investigate bind address / `HOST` env |

---

## E. DNS verification

```bash
dig +short relay.infinite-football.com A
# Expect: 104.236.67.75
```

Also verify from another network if possible (phone LTE vs home Wi‑Fi).

If DNS is wrong, fix the domain A record before chasing Node logs.

---

## F. App connectivity verification

1. Confirm API:

```bash
curl -fsS -X POST https://relay.infinite-football.com/v1/sessions
```

`wsUrl` must be `wss://relay.infinite-football.com/ws`.

2. On devices:

- iPad display: Partner Mode → join code appears
- iPhone coach: enter code → connects
- Advance a rep end-to-end

If API is healthy but app fails, check app build config (`RELAY_HTTP_BASE_URL`) and client network — not only the droplet.

---

## Troubleshooting playbooks

### 1. Relay offline (Node / PM2)

**Symptoms:** `/health` fails; Partner Mode cannot create sessions; `pm2 list` shows `relay` stopped/errored.

**Checks:**

```bash
pm2 list
pm2 logs relay --lines 200
curl -v http://127.0.0.1:3000/health
```

**Actions:**

1. `pm2 restart relay`
2. Confirm env: `HOST=127.0.0.1`, `PORT=3000`, `PUBLIC_WS_URL=wss://relay.infinite-football.com/ws`
3. If crash-looping after a deploy, roll back code in `/root/relay` (see [deployment.md](./deployment.md))
4. Confirm port not conflicting: `ss -ltnp | grep 3000`

---

### 2. Caddy offline

**Symptoms:** Localhost `:3000` health OK; public HTTPS fails; browsers show connection errors.

**Checks:**

```bash
systemctl status caddy
journalctl -u caddy -n 100 --no-pager
ss -ltnp | grep -E ':443|:80'
```

**Actions:**

1. `systemctl restart caddy`
2. Validate site block for `relay.infinite-football.com`
3. Confirm reverse_proxy target is `127.0.0.1:3000`
4. Confirm firewall allows 80/443 (DigitalOcean cloud firewall + `ufw` if used)

---

### 3. DNS issues

**Symptoms:** Wrong IP, NXDOMAIN, intermittent resolution; health works for some networks only.

**Checks:**

```bash
dig +short relay.infinite-football.com A
dig +short relay.infinite-football.com AAAA
ping -c 2 104.236.67.75
```

**Actions:**

1. Fix A record → `104.236.67.75`
2. Wait for TTL / flush local DNS caches
3. Avoid pointing clients at the raw IP in production app config (hostname + TLS is required)

---

### 4. HTTPS failures

**Symptoms:** Certificate errors, TLS handshake failures, HTTP-only redirects broken.

**Checks:**

```bash
curl -vI https://relay.infinite-football.com/health
echo | openssl s_client -servername relay.infinite-football.com -connect relay.infinite-football.com:443 2>/dev/null | openssl x509 -noout -issuer -dates -subject
```

**Actions:**

1. Restart Caddy (often renews/reloads certs)
2. Ensure ports **80** and **443** are reachable (Let’s Encrypt HTTP-01 needs 80)
3. Confirm system clock is correct (`timedatectl`) — bad time breaks TLS
4. Review Caddy logs for ACME errors

---

### 5. WebSocket failures

**Symptoms:** `/health` OK; session create OK; app shows join code but never pairs; coach join may succeed while WS stalls.

**Checks:**

```bash
curl -fsS -X POST https://relay.infinite-football.com/v1/sessions
# Confirm wsUrl == wss://relay.infinite-football.com/ws

pm2 logs relay --lines 200
journalctl -u caddy -n 100 --no-pager
```

**Actions:**

1. Fix `PUBLIC_WS_URL` if `wsUrl` is `ws://`, localhost, or wrong host
2. Confirm Caddy proxies `/ws` with WebSocket upgrade support
3. Confirm long-lived connections are not killed by an aggressive idle timeout
4. Reproduce with a WS client using the returned token URL
5. Verify client network path (corporate Wi‑Fi sometimes breaks WSS)

---

## Droplet-level disaster

If the VM is gone or unrecoverable:

1. Prefer restore from a **DigitalOcean snapshot** of `pba-relay`.
2. Or rebuild from scratch using [server-setup.md](./server-setup.md).
3. Point DNS A record for `relay.infinite-football.com` to the droplet IP (currently `104.236.67.75`; update if the new droplet has a new IP).
4. Run full verification (health, session create, device smoke test).
5. Update [relay-server.md](./relay-server.md) snapshot if IP / versions change.

**TODO:** Document the team’s preferred golden-image / snapshot restore click-path in DigitalOcean.

---

## Related docs

- [health-check.md](./health-check.md)
- [maintenance.md](./maintenance.md)
- [deployment.md](./deployment.md)
- [server-setup.md](./server-setup.md)
- [relay-server.md](./relay-server.md)
- [architecture.md](./architecture.md)
