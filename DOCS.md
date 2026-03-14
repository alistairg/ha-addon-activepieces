# Home Assistant Add-on: Activepieces

Activepieces is an open-source business automation platform. It provides a visual flow builder to create automations connecting your apps and services.

## How it works

This addon runs Activepieces with an embedded database (PGLite) and in-memory message queue, making it fully self-contained. All data is persisted in `/config/activepieces/`.

Access the Activepieces UI through the Home Assistant sidebar via Ingress - no port forwarding needed.

## Configuration

### Option: `telemetry_enabled`

Enables anonymous usage telemetry sent to the Activepieces team. Default: `false`.

## Webhooks

If you need to receive webhooks from external services, you'll need to expose port 80 in the addon configuration and set up appropriate port forwarding on your network. Ingress URLs are not accessible from outside your Home Assistant instance.

## Backups

Addon data is stored in `/config/activepieces/` and is included in Home Assistant backups. This includes:
- The embedded database
- Encryption keys and secrets
- Flow cache data
