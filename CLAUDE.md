# Activepieces Home Assistant Addon

## Project Goal
Create a Home Assistant addon for [Activepieces](https://www.activepieces.com/) (open-source automation platform) with Ingress support.

## Architecture Decisions
- **Single-container mode**: Uses `AP_DB_TYPE=PGLITE` (embedded PostgreSQL) and `AP_REDIS_TYPE=MEMORY` — no external databases needed
- **Debian Bullseye base**: Must use `ghcr.io/home-assistant/{arch}-base-debian:bullseye` because the Activepieces official image (`ghcr.io/activepieces/activepieces:0.79.3`) is built on Debian 11 (Bullseye). Native bindings (sqlite3, bun) are incompatible with Alpine or Bookworm
- **Multi-stage Dockerfile**: Copies Node.js, Bun, app code, and frontend static files from the official Activepieces image into the HA base image
- **Ingress via nginx**: nginx reverse proxy on the HA-assigned ingress port, serves frontend static files and proxies `/api/` to the Node.js backend on port 3000
- **s6-overlay**: Uses s6 service management (init-activepieces oneshot → activepieces + nginx longrun services)
- **Env var passing**: Uses a sourced env file (`/var/run/activepieces.env`) rather than s6 container_environment files, as the latter was unreliable across base image versions

## Current Status (2026-03-14)
**The addon is working on HAOS with Ingress.** All core functionality verified: s6 init, backend API, frontend UI, ingress proxying.

### Ingress architecture
Activepieces has **no native subpath support** ([GitHub issue #5844](https://github.com/activepieces/activepieces/issues/5844) closed as NOT_PLANNED). The frontend hardcodes `window.location.origin + "/api"` as the API base URL. To make it work behind HA ingress:

1. **nginx `sub_filter`** rewrites `<base href>`, `src`, and `href` paths in HTML to include the ingress prefix
2. **Injected JS interceptor** patches `window.fetch` and `XMLHttpRequest.prototype.open` to rewrite both absolute paths (`/api/...`) and full URLs (`https://origin/api/...`) through the ingress path
3. **`proxy_pass` with trailing slash** (`http://127.0.0.1:3000/;`) strips the `/api/` prefix before forwarding to the backend (which expects routes at `/v1/...`)
4. **Separate `/socket.io` location** block for WebSocket support

### Previously resolved issues
- **HAOS `/init` permission denied**: `init: true` in config.yaml injected tini as PID 1, conflicting with s6-overlay v3. Fix: `init: false`. Ref: https://developers.home-assistant.io/blog/2022/05/12/s6-overlay-base-images/
- Activepieces image version: `0.36.5` doesn't exist, current is `0.79.3`
- `xxd` not available on Debian base → switched to `openssl rand -hex`
- Secret values with hex characters being interpreted as bash commands → added quoting
- Node.js entry point changed: now `packages/server/api/dist/src/bootstrap.js` (not `dist/packages/server/api/main.js`)
- Native sqlite3 bindings built with Bun are incompatible with Alpine (glibc vs musl)
- Activepieces requires `bun` binary at runtime (calls `bun --version`)
- Activepieces requires `ps` command → added `procps` package
- Copied Node.js binary from Bullseye image can't run on Bookworm (linker mismatch)
- s6 container_environment path varies between base images → switched to sourced env file

## Key Files
- `config.yaml` — addon metadata, ingress config, user options
- `build.yaml` — maps architectures to base images (currently Bullseye Debian)
- `Dockerfile` — multi-stage build copying from activepieces:0.79.3
- `rootfs/etc/s6-overlay/s6-rc.d/init-activepieces/run` — generates secrets, writes env file
- `rootfs/etc/s6-overlay/s6-rc.d/activepieces/run` — sources env, starts Node.js server
- `rootfs/etc/s6-overlay/s6-rc.d/nginx/run` — configures ingress port, starts nginx
- `rootfs/etc/nginx/servers/ingress.conf` — reverse proxy config (static files + API proxy)

## Development Workflow
- **Local testing**: `docker build --platform linux/amd64 --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bullseye -t activepieces-test . && docker run --platform linux/amd64 --rm --name ap-test activepieces-test`
- **HAOS testing**: Copy addon folder to `\\homeassistant\addons\activepieces` via Samba share, then Settings → Add-ons → Add-on Store → three dots → Check for updates → install from Local add-ons
- **IMPORTANT**: Bump `version` in `config.yaml` every time build files change, otherwise HA won't pick up updates
- Supervisor API errors in local testing are expected (no `supervisor` host) — these are handled gracefully with fallbacks

## Next Steps
1. Fix missing font files (inter-v20-latin-regular woff2) — may need to copy from a different path in the Activepieces image
2. Add back a refined AppArmor profile
3. Test webhook support (requires exposing port 80 externally)
4. Clean up debug logging in nginx once stable
