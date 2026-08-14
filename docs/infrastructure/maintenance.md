# Relay Maintenance Checklist

Recurring maintenance for DigitalOcean droplet **`pba-relay`** (VisionPlay partner relay).

Goal: keep `https://relay.infinite-football.com` healthy with minimal surprise downtime.

| Item | Value |
|------|--------|
| SSH | `ssh root@104.236.67.75` |
| App directory | `/root/relay` |
| PM2 name | `relay` |
| Health | `https://relay.infinite-football.com/health` |
| WebSocket | `wss://relay.infinite-football.com/ws` |

> Before major OS upgrades or risky changes, create a **DigitalOcean snapshot**. Prefer a quiet maintenance window when Partner Mode is unlikely to be in active use.

---

## Monthly checklist

Run once per month (or after any incident). Check off each item.

### 1. Public health endpoint

```bash
curl -fsS https://relay.infinite-football.com/health
```

- [ ] Response is `{"ok":true}`
- [ ] HTTP status 200

### 2. Session / WebSocket contract

```bash
curl -fsS -X POST https://relay.infinite-football.com/v1/sessions
```

- [ ] JSON includes `joinCode`, `sessionId`, `displayToken`
- [ ] `wsUrl` is exactly `wss://relay.infinite-football.com/ws`

### 3. PM2 status

```bash
ssh root@104.236.67.75
pm2 list
pm2 describe relay
```

- [ ] Process **`relay`** is **online**
- [ ] Restart count is not climbing rapidly (no crash loop)
- [ ] Recent logs look normal: `pm2 logs relay --lines 100`

### 4. Caddy status

```bash
systemctl status caddy
```

- [ ] `active (running)`
- [ ] No repeating certificate / config errors in `journalctl -u caddy -n 50`

### 5. Memory usage

```bash
free -h
```

- [ ] Available memory is healthy (not constantly near zero)
- [ ] No unexplained sustained swap thrashing

### 6. Disk usage

```bash
df -h
```

- [ ] Root filesystem has comfortable free space (investigate if above ~80–85% used)
- [ ] Old logs are not filling the volume unexpectedly

### 7. SSL / HTTPS

```bash
curl -fsSI https://relay.infinite-football.com/health
# Optional:
# echo | openssl s_client -servername relay.infinite-football.com -connect relay.infinite-football.com:443 2>/dev/null | openssl x509 -noout -dates
```

- [ ] HTTPS succeeds without certificate warnings
- [ ] Certificate not near expiry (Caddy usually auto-renews; still verify)

### 8. Ubuntu updates (awareness)

```bash
apt update
apt list --upgradable
```

- [ ] Review pending updates
- [ ] Apply non-risky security updates if appropriate this month **or** schedule them for the quarterly window
- [ ] Do **not** blindly reboot mid-session without a plan (see quarterly)

### 9. Snapshot before major upgrades

If you plan kernel upgrades, Caddy major upgrades, Node major upgrades, or disk changes:

- [ ] Create a **DigitalOcean snapshot** of `pba-relay` first
- [ ] Record snapshot name/date in your ops notes

---

## Quarterly checklist

In addition to the monthly items:

### 1. Update Ubuntu packages

```bash
apt update
apt upgrade
# Follow prompts carefully; reboot if the packages require it.
```

- [ ] Packages updated successfully
- [ ] Snapshot taken **before** upgrade if the change set is large

### 2. Reboot during a maintenance window

```bash
reboot
```

After reboot:

- [ ] SSH comes back (`ssh root@104.236.67.75`)
- [ ] Caddy is running (`systemctl status caddy`)
- [ ] PM2 shows `relay` online (`pm2 list`) — see [recovery.md](./recovery.md)
- [ ] `curl -fsS https://relay.infinite-football.com/health` → `{"ok":true}`
- [ ] `POST /v1/sessions` returns correct `wsUrl`
- [ ] Quick Partner Mode device smoke test (optional but recommended)

### 3. Verify relay survives reboot

- [ ] No manual `pm2 start` was required after reboot  
  - If it was required, fix PM2 startup (`pm2 startup` / `pm2 save`)
- [ ] No manual Caddy start was required (`systemctl enable caddy` if needed)

---

## Suggested monthly log template

```text
Date:
Operator:

Health OK? Y/N
wsUrl correct? Y/N
PM2 relay online? Y/N
Caddy active? Y/N
Memory notes:
Disk notes:
SSL notes:
Updates pending:
Snapshot taken? Y/N (name:)
Follow-ups:
```

---

## Related docs

- [health-check.md](./health-check.md)
- [recovery.md](./recovery.md)
- [deployment.md](./deployment.md)
- [relay-server.md](./relay-server.md)
