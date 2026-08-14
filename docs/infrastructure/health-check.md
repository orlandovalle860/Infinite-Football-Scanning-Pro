# Relay Health Check — One-Page Ops Checklist

Use this page for a fast “is production relay OK?” check on droplet **`pba-relay`**.

| Item | Value |
|------|--------|
| SSH | `ssh root@104.236.67.75` |
| App directory | `/root/relay` |
| PM2 name | `relay` |
| Health | `https://relay.infinite-football.com/health` |
| WebSocket | `wss://relay.infinite-football.com/ws` |
| Internal | `127.0.0.1:3000` |

---

## Commands to run

SSH for local commands (`pm2`, `systemctl`, `df`, `free`):

```bash
ssh root@104.236.67.75
```

`curl` to the public HTTPS URL can be run from the droplet **or** your laptop.

### 1. PM2 process list

```bash
pm2 list
```

**Healthy expectation**

- Process named **`relay`** exists
- Status: **`online`**
- Restarts not rapidly increasing while you watch

---

### 2. Caddy service

```bash
systemctl status caddy
```

**Healthy expectation**

- `Active: active (running)`
- Recent log lines without repeated certificate or crash errors

---

### 3. Public health endpoint

```bash
curl https://relay.infinite-football.com/health
```

Prefer fail-fast form during automation:

```bash
curl -fsS https://relay.infinite-football.com/health
```

**Healthy expectation**

```json
{"ok":true}
```

HTTP status **200**. `curl -fsS` exits **0**.

---

### 4. Disk usage

```bash
df -h
```

**Healthy expectation**

- Root (`/`) has meaningful free space
- Investigate if usage is consistently high (e.g. ≥ ~80–85%)

---

### 5. Memory usage

```bash
free -h
```

**Healthy expectation**

- Available memory is not exhausted
- Temporary spikes under load can be normal; sustained near-zero free + heavy swap is a warning

---

### 6. PM2 startup service

```bash
systemctl status pm2-root
```

**Healthy expectation**

- Service enabled and **active (running)**
- After reboot, `pm2 list` still shows **`relay`** without manual start

---

## Extra one-liners (recommended)

### Confirm DNS

```bash
dig +short relay.infinite-football.com A
```

**Healthy expectation:** `104.236.67.75`

### Confirm WebSocket URL contract

```bash
curl -fsS -X POST https://relay.infinite-football.com/v1/sessions
```

**Healthy expectation:** JSON includes

```text
"wsUrl":"wss://relay.infinite-football.com/ws"
```

### Confirm Node on localhost

```bash
curl -fsS http://127.0.0.1:3000/health
```

**Healthy expectation:** `{"ok":true}`

---

## Pass / fail summary

| Check | Pass criteria |
|-------|----------------|
| `pm2 list` | **`relay`** **online** |
| `systemctl status caddy` | **active (running)** |
| `curl …/health` | `{"ok":true}` |
| `df -h` | Comfortable free disk |
| `free -h` | Memory not exhausted |
| `systemctl status pm2-root` | PM2 service healthy / enabled |
| DNS | Points to `104.236.67.75` |
| `POST /v1/sessions` | `wsUrl` is `wss://relay.infinite-football.com/ws` |

If any critical check fails, go to [recovery.md](./recovery.md).

---

## Copy-paste block

```bash
pm2 list
systemctl status caddy --no-pager
curl -fsS https://relay.infinite-football.com/health; echo
df -h
free -h
systemctl status pm2-root --no-pager
dig +short relay.infinite-football.com A
curl -fsS -X POST https://relay.infinite-football.com/v1/sessions; echo
curl -fsS http://127.0.0.1:3000/health; echo
```
