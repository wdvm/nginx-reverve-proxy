# NGINX Reverse Proxy (Docker Compose)

Production-ready Docker Compose stack with **NGINX** as a reverse proxy and subdomain-based routing to backend applications on an internal Docker network.

## Project structure

```
project-root/
├── docker-compose.yml
├── .env.example
├── nginx/
│   ├── conf.d/
│   │   └── aaa.conf          # One file per subdomain/app
│   └── nginx.conf
└── apps/
    └── aaa/
        ├── Dockerfile
        ├── package.json
        └── src/
            └── index.js
```

| Component | Role |
|-----------|------|
| `nginx` | Reverse proxy; exposes ports 80 and 443 |
| `aaa` | Sample Express app; listens on 3000 (internal only) |
| `proxy` network | Isolated bridge; services talk by **service name** |

Routing: **`aaa.localhost`** → NGINX → Docker service **`aaa:3000`**

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/) v2+
- Ability to edit `/etc/hosts` (for local subdomain testing)

## Quick start

```bash
# From the project root
cp .env.example .env

docker compose up --build -d
```

Check status:

```bash
docker compose ps
docker compose logs -f nginx
```

Stop:

```bash
docker compose down
```

## Map `aaa.localhost` locally

Add this line to your hosts file so the subdomain resolves to your machine:

**macOS / Linux**

```bash
sudo sh -c 'echo "127.0.0.1 aaa.localhost" >> /etc/hosts'
```

**Windows** (run as Administrator)

```
127.0.0.1 aaa.localhost
```

Edit: `C:\Windows\System32\drivers\etc\hosts`

Verify:

```bash
ping -c 1 aaa.localhost
```

## Test locally

### HTTP (port 80)

```bash
# Root — JSON service info
curl -s http://aaa.localhost/ | jq

# Health endpoint (app + NGINX proxy path)
curl -s http://aaa.localhost/health | jq

# Verbose headers
curl -sv http://aaa.localhost/
```

Expected root response:

```json
{
  "service": "aaa",
  "status": "running"
}
```

Expected health response:

```json
{
  "status": "ok"
}
```

### Direct container check (bypasses NGINX)

```bash
docker compose exec aaa wget -qO- http://127.0.0.1:3000/health
```

### HTTPS (port 443)

Port **443** is published, but TLS is not configured yet. NGINX uses `ssl reject_handshake` so connections fail until you add certificates (see [SSL with Let's Encrypt](#ssl-with-lets-encrypt-later) below).

## How routing works

1. Browser requests `http://aaa.localhost/` → host resolves to `127.0.0.1`.
2. Request hits NGINX on port 80.
3. NGINX matches `server_name aaa.localhost` in `nginx/conf.d/aaa.conf`.
4. `proxy_pass` sends traffic to upstream **`aaa:3000`** (Docker DNS name, not `localhost`).
5. The `aaa` container responds; NGINX returns the response to the client.

## Add more applications later

Follow this pattern for each new app (e.g. `bbb` at `bbb.localhost`):

### 1. Create the app

```
apps/bbb/
├── Dockerfile
├── package.json
└── src/index.js
```

Listen on `0.0.0.0` and port `3000` (or set `PORT` via environment).

### 2. Register in `docker-compose.yml`

```yaml
  bbb:
    build:
      context: ./apps/bbb
    expose:
      - "3000"
    networks:
      - proxy
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://127.0.0.1:3000/health').then((r) => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s
    restart: unless-stopped
```

Add `bbb` under `nginx.depends_on` if you want NGINX to wait for its health check.

### 3. Add NGINX config

Copy `nginx/conf.d/aaa.conf` → `nginx/conf.d/bbb.conf` and update:

- `server_name bbb.localhost`
- `upstream bbb_backend { server bbb:3000; }`
- All `proxy_pass` targets to `http://bbb_backend`

Reload NGINX after changes:

```bash
docker compose exec nginx nginx -s reload
```

Or recreate the stack:

```bash
docker compose up -d --build
```

### 4. Local DNS

```bash
sudo sh -c 'echo "127.0.0.1 bbb.localhost" >> /etc/hosts'
```

### 5. Test

```bash
curl -s http://bbb.localhost/
```

**Tips for scaling**

- Keep **one `conf.d/<app>.conf` per subdomain** — easy to review and diff.
- Use **upstream** blocks and **keepalive** for each backend.
- Never `proxy_pass` to `localhost` inside NGINX; always use the **Compose service name**.
- Do not publish app ports on the host unless you need direct debugging.

## SSL with Let's Encrypt (later)

For production domains (not `.localhost`), common approaches:

### Option A: Certbot sidecar or host Certbot

1. Point real DNS (e.g. `aaa.example.com`) to your server.
2. Temporarily allow HTTP-01 on port 80, or use DNS-01 for wildcards.
3. Obtain certs:

   ```bash
   certbot certonly --webroot -w /var/www/certbot -d aaa.example.com
   ```

4. Mount certificates into the NGINX container:

   ```yaml
   volumes:
     - ./certbot/conf:/etc/letsencrypt:ro
   ```

5. Uncomment and adapt the SSL `server` block in `nginx/conf.d/aaa.conf`.
6. Remove the `listen 443 ssl reject_handshake on;` placeholder from the HTTP server block.
7. Add an HTTP → HTTPS redirect server block (example included as comments in `aaa.conf`).

### Option B: Traefik or Caddy in front

Let a dedicated edge proxy handle ACME automatically, with NGINX as an internal router — useful when you have many services.

### Option C: Docker Compose + nginx-proxy / acme-companion

Community images automate vhost discovery and certificate renewal from container labels.

**Renewal:** schedule `certbot renew` (cron or systemd timer) and reload NGINX after renewal:

```bash
docker compose exec nginx nginx -s reload
```

## Environment variables

Copy `.env.example` to `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `COMPOSE_PROJECT_NAME` | `nginx-proxy` | Compose project name |
| `HTTP_PORT` | `80` | Host port for HTTP |
| `HTTPS_PORT` | `443` | Host port for HTTPS |

## Troubleshooting

| Issue | Check |
|-------|--------|
| Connection refused | `docker compose ps` — are `nginx` and `aaa` healthy? |
| 502 Bad Gateway | `docker compose logs aaa` — is the app listening on 3000? |
| Wrong host / 404 | `server_name` in `aaa.conf` must match the Host header (`aaa.localhost`) |
| Name not resolving | `/etc/hosts` entry for `aaa.localhost` |
| Port 80 in use | Change `HTTP_PORT` in `.env` (e.g. `8080:80`) |

## License

MIT — use freely in your own projects.
