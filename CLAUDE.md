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

## Current Status (2026-03-13)
**The addon builds and runs successfully in local Docker testing** (verified with `docker run --platform linux/amd64`), but **still fails to start on actual HAOS** with the error:
```
/bin/sh: can't open '/init': Permission denied
```

### What works locally
- s6-overlay init completes
- Secrets are generated and persisted
- Activepieces Node.js server starts, runs DB migrations, and listens on port 3000
- The ASCII banner prints and the job queue worker starts
- nginx starts for ingress proxying

### The unresolved HAOS `/init` permission denied issue
This error occurs even with a **minimal Dockerfile** (just base image + `apk add nginx nodejs npm`, no Activepieces at all), so it is NOT related to our app code. Things we tried:
1. `init: false` → `init: true` in config.yaml
2. Removing custom `apparmor.txt` (deleted entirely, using HA default profile)
3. Adding `chmod +x /init` to Dockerfile
4. Switching from community base (`ghcr.io/hassio-addons/base:20.0.1`) to official HA base images
5. Trying both Alpine (`ghcr.io/home-assistant/amd64-base:3.23`) and Debian bases
6. `docker image prune -a` on the HA box
7. Full uninstall/reinstall of the addon

**Hypothesis**: This may be a HAOS-specific issue with how the Supervisor launches containers, possibly related to protection mode, Docker security options, or the specific HAOS version. It works perfectly when run with plain `docker run`. The next step should be investigating how HA Supervisor actually launches addon containers (security opts, capabilities, user namespaces, etc.) and comparing that to our local `docker run`.

### Other issues found and fixed along the way
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
1. **Debug the `/init` permission issue on HAOS** — this is the blocker. Try:
   - Check HAOS version and Docker version on the box
   - Look at Supervisor logs (not just addon logs) for more detail
   - Try `ha addons rebuild local_activepieces` via SSH
   - Check if other local addons work (to rule out a system-wide issue)
   - Try adding `privileged: true` temporarily to config.yaml to test if it's a security restriction
   - Inspect how the Supervisor launches the container: `docker inspect <container_id>` to see SecurityOpt, CapAdd, etc.
2. Once running on HAOS, verify Ingress works end-to-end
3. Add back a refined AppArmor profile
4. Test webhook support (requires exposing port 80 externally)
