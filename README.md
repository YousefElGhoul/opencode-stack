# OpenCode Headless Server

A minimal Docker Compose environment for one authenticated OpenCode headless
server. OpenCode can read and modify repositories under `/workspace`; the
repositories themselves remain outside this repository.

## Security model

- The server is published only as `127.0.0.1:4096` on the host.
- HTTP Basic authentication is enabled by `OPENCODE_SERVER_PASSWORD`; the
  default username is `opencode`.
- `./opencode` is mounted read-only at `/root/.config/opencode`, which is also
  selected through `OPENCODE_CONFIG_DIR`.
- The external workspace is the only read/write host bind mount.
- Database, provider credentials, and session state persist in the
  Compose-managed `opencode-data` volume at `/root/.local`.
- The stack has no Docker socket mount, privileged mode, host networking, or
  Tailscale container.

OpenCode's official image currently runs as root. Files it creates in the
workspace can therefore be root-owned on the host. Correct ownership with
`sudo chown` if needed, or create files in the repository on the host first.

## Install

Requirements:

- Linux with Docker Engine and the Docker Compose plugin
- An absolute path to a directory containing development repositories
- Tailscale on the host only if remote tailnet access is wanted

Initialize the stack with the external workspace path:

```sh
./scripts/setup.sh /absolute/path/to/development-repositories
```

The setup script creates a mode-`0600` `.env`, generates a random 256-bit
server password, validates Docker, and pulls the official image pinned by both
version and multi-platform manifest digest. It never overwrites an existing
`.env`. It also adds a local `opencode-stack/opencode:<version>` alias so image
management tools such as lazydocker show a useful name; Compose still runs the
official digest-pinned image.

Start, inspect, and stop the server:

```sh
./scripts/start.sh
./scripts/doctor.sh
./scripts/stop.sh
```

Normal shutdown retains persistent state. To inspect logs, run:

```sh
docker compose logs -f opencode
```

## Connect

The local endpoint is `http://127.0.0.1:4096`. Requests use HTTP Basic auth
with username `opencode` and the password stored in `.env`:

```sh
curl --user opencode http://127.0.0.1:4096/global/health
```

`curl` prompts for the password. The OpenAPI document is available at
`http://127.0.0.1:4096/doc` after authentication.

## Configure

Edit `opencode/opencode.json` for non-secret global OpenCode settings. Keep
provider keys and other credentials out of this directory and out of Git.
OpenCode configuration is loaded at startup, so restart after changes:

```sh
./scripts/stop.sh
./scripts/start.sh
```

Project-specific `opencode.json` files may remain inside the mounted
repositories and override global settings. The checked-in global config pins
automatic updates off because the container version is explicitly selected by
`OPENCODE_VERSION` in `.env`.

To upgrade, choose a published tag from the official
`ghcr.io/anomalyco/opencode` image and obtain its multi-platform digest:

```sh
docker buildx imagetools inspect ghcr.io/anomalyco/opencode:VERSION
```

Change both `OPENCODE_VERSION` and `OPENCODE_IMAGE_DIGEST` in `.env`, then run:

```sh
docker compose pull
./scripts/start.sh
```

Do not use `latest` if reproducibility matters.

## Remote access

Tailscale is intentionally installed and authenticated on the host, outside
this stack. Because Docker publishes only on loopback, proxy the local endpoint
to the tailnet with Tailscale Serve:

```sh
sudo tailscale serve --bg http://127.0.0.1:4096
tailscale serve status
```

Use the HTTPS tailnet URL printed by Tailscale and authenticate with the same
OpenCode Basic-auth credentials. This does not expose port 4096 on the host's
LAN address. Remove the host-side proxy with:

```sh
sudo tailscale serve reset
```

Do not use Tailscale Funnel for this service; Funnel makes a service publicly
reachable from the internet.

## Backup

The named volume contains the OpenCode database, provider credentials, and
session state. Treat backups as secrets. Stop the server first for a consistent
database snapshot, then stream the volume into a restricted backup file:

```sh
./scripts/stop.sh
umask 077
mkdir -p backups
docker compose run --rm --no-deps -T --entrypoint tar opencode \
  -C /root/.local -czf - . > backups/opencode-$(date +%Y%m%d).backup.tar.gz
```

The `backups/` directory and `*.backup.tar.gz` are ignored by Git. Move backups
to encrypted storage; a local ignored file is not sufficient protection.

## Recovery

Recovery replaces the current contents of the persistent volume. Keep the
server stopped, verify the backup path, then run:

```sh
./scripts/stop.sh
docker compose run --rm --no-deps -T --entrypoint sh opencode -c \
  'rm -rf /root/.local/* /root/.local/.[!.]* /root/.local/..?*; tar -C /root/.local -xzf -' \
  < backups/opencode-YYYYMMDD.backup.tar.gz
./scripts/start.sh
```

Removing the stack with `docker compose down` preserves the volume. Running
`docker compose down --volumes` permanently deletes it and should only be done
after confirming a usable backup.

## Documentation basis

This stack follows the current official OpenCode documentation and source:

- [Docker installation](https://opencode.ai/docs/#install-with-docker)
- [Server and authentication](https://opencode.ai/docs/server/)
- [Configuration paths](https://opencode.ai/docs/config/)
- [Configuration schema](https://opencode.ai/config.json)

OpenCode documents `GET /global/health` as the health endpoint. Its Linux data
paths are `~/.local/share/opencode` for the database/auth data and
`~/.local/state/opencode` for session state; mounting `/root/.local` preserves
both.
