<!--
---
portfolio:
  title: "OpenCode Stack"
  subtitle: "Containerized Remote AI Development Environment"
  type: 
    - Infrastructure
    - DevOps
  status: "Maintained"
  time: "2026"

  description: "A reproducible Docker Compose environment for running an authenticated OpenCode headless development server with persistent state, isolated tooling, MCP integrations, secure remote access through Tailscale, and documented backup and recovery procedures."

  skills:
    - Docker
    - Docker Compose
    - Linux
    - OpenCode
    - Tailscale
    - Shell Scripting
    - MCP
    - Infrastructure
    - Security

  live: null
  slug: "opencode-stack"
---
-->

# OpenCode Headless Server

A minimal Docker Compose environment for one authenticated OpenCode headless
server. OpenCode can read and modify repositories under the configured absolute
workspace path; the repositories themselves remain outside this repository.

## Security model

- The server is published only as `127.0.0.1:4096` on the host.
- HTTP Basic authentication is enabled by `OPENCODE_SERVER_PASSWORD`; the
  default username is `opencode`.
- `./opencode` is mounted read-only at `/home/opencode/.config/opencode`, which is also
  selected through `OPENCODE_CONFIG_DIR`.
- The external workspace is the only read/write host bind mount.
- Database, provider credentials, and session state persist in the
  Compose-managed `opencode-data` volume at `/home/opencode/.local`.
- OpenCode runs as the invoking host user's numeric `HOST_UID:HOST_GID`.
- `/home/opencode` is a user-owned tmpfs home. Cache and other non-persistent
  home files are ephemeral; the data volume and read-only config mount overlay it.
- Playwright MCP runs in its official container and is reachable only on the
  internal Compose network.
- Exa, Context7, GitHub, and Postman use their official hosted HTTPS MCP
  endpoints; no redundant local proxies are created.
- The stack has no Docker socket mount, privileged mode, host networking, or
  Tailscale container.

The official image is used directly. Its `/root` is mode `0700`, and a numeric
user without `HOME` resolves its default data path to `/.local`. An explicit,
writable home avoids both failures without a root startup wrapper or a custom
image. Files created in the workspace use the configured host UID/GID.

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
server password, prompts without echo for MCP API keys, validates Docker, and
pulls official images pinned by version and multi-platform manifest digest.
When `.env` already exists, rerun `sudo ./scripts/setup.sh` without a workspace
argument to add or rotate MCP keys while preserving existing values when a
prompt is left blank.

Setup derives `HOST_UID` and `HOST_GID` using `id` for the invoking user, or
`SUDO_USER` when run through sudo. It also leaves `.env` owned by that user and
their primary group. No `1000:1000` default is assumed. Direct root invocation
without a non-root `SUDO_USER` is rejected. Normal invocation requires access to
Docker and write access to this repository.

For a new installation, setup initializes ownership of an **empty** data
volume using a one-shot root helper. It never recursively changes an existing
volume. Existing root-owned installations must complete the migration below;
setup reports an error if the configured user cannot write existing data.

The workspace is mounted at the same absolute path inside the container. Setup
also installs `~/.local/bin/opencode` and mode-`0600` client credential files
under `~/.config/opencode-stack`. This lets the local TUI attach to the server
using its dedicated client credential file.

The host client requires `mise` with OpenCode installed. For Bash login users,
setup adds an `opencode` function to `~/.bashrc` that invokes the wrapper by
absolute path. Open a new shell after setup. A PATH prepend alone is insufficient:
mise can put its own OpenCode binary first again on an environment refresh.
For other shells and scripts, invoke `~/.local/bin/opencode` explicitly.

The script also adds local `opencode-stack/*:<version>` aliases so image
management tools such as lazydocker show useful names. Compose still runs the
official digest-pinned images.

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

Run `opencode` from any directory under the configured workspace. A path can be
provided explicitly, and launches outside the mounted tree default to the
workspace root:

```sh
opencode
opencode /home/ghoul/Projects/some-project
```

The wrapper preserves management subcommands such as `opencode upgrade` and
`opencode auth` as local CLI operations. Use `opencode local ...` as an explicit
escape hatch for any other local invocation. Omarchy's `opencode --auto` alias
attaches normally; `attach` has no `--auto` option, so permission handling
remains controlled by the remote server configuration.

Only the default interactive launch is redirected. Commands including `run`,
`session`, `stats`, `export`, and `import` still use the host CLI and local data
unless the command itself is explicitly configured to attach. Their output does
not establish what sessions exist on the server. Existing local TUI processes
also stay local; installing the wrapper does not reconnect them.

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

### Provider login

Provider credentials are stored in the persistent Docker volume, not in the
checked-in config. For interactive provider login, use:

```sh
sudo ./scripts/auth-login.sh
```

The helper stops the main server, starts a temporary one-shot container with
OAuth callback port `127.0.0.1:1455` published, and restarts the normal stack
after login. The temporary container and port publication are removed
automatically. The normal Compose service continues to publish only
`127.0.0.1:4096`.

Project-specific `opencode.json` files may remain inside the mounted
repositories and override global settings. The checked-in global config pins
automatic updates off because the container version is explicitly selected by
`OPENCODE_VERSION` in `.env`.

### MCP servers

The checked-in config contains no MCP credentials. It references values passed
from `.env` using OpenCode's `{env:VARIABLE}` syntax:

| Name | Deployment | Credential |
| --- | --- | --- |
| `websearch` | `https://mcp.exa.ai/mcp` | `EXA_API_KEY` |
| `context7` | `https://mcp.context7.com/mcp` | `CONTEXT7_API_KEY` |
| `playwright` | Internal container at `http://playwright:8931/mcp` | None |
| `github` | `https://api.githubcopilot.com/mcp/` | `GITHUB_PERSONAL_ACCESS_TOKEN` |
| `postman` | `https://mcp.postman.com/minimal` | `POSTMAN_API_KEY` |

Exa and Context7 allow anonymous access with lower limits. GitHub and Postman
credentials are required by setup because API keys are the most predictable
option for this unattended server stack. Run setup again to configure or rotate
them:

```sh
sudo ./scripts/setup.sh
```

Secrets remain in `.env`, which is ignored by Git and restricted to mode
`0600`. They are passed to the OpenCode container as environment variables and
are therefore visible to host users with Docker daemon or root access. Docker
does not provide a security boundary against its own administrators.

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
to the tailnet with the setup script:

```sh
./scripts/tailscale-setup.sh
```

The script enables the host `tailscaled` system service, signs the host into a
tailnet if needed, and configures an HTTPS Serve proxy to
`http://127.0.0.1:4096`. Install Tailscale on the phone, sign in to the same
tailnet, open the printed `https://*.ts.net` URL in the phone browser, and
authenticate with the OpenCode username `opencode` and server password.

This does not expose port 4096 on the host's LAN address. Inspect or remove the
host-side proxy with:

```sh
sudo tailscale serve status
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
  -C /home/opencode/.local -czf - . > backups/opencode-$(date +%Y%m%d).backup.tar.gz
```

The `backups/` directory and `*.backup.tar.gz` are ignored by Git. Move backups
to encrypted storage; a local ignored file is not sufficient protection.

## Migrate an existing root-owned data volume

Use this procedure before starting the updated service. It retains the same
named volume and the same internal `share/` and `state/` tree. Only ownership
and the container mount destination change. Do not run `down --volumes`, remove
the volume, or recursively change ownership of the host workspace.

1. Set `HOST_UID` and `HOST_GID` in `.env` to `id -u USER` and `id -g USER` for
   the intended normal host user. Running setup through sudo does this too;
   its existing-data check may stop with the migration message. Keep `.env`
   mode `0600` and owned by that user and primary group.
2. Stop **only OpenCode**. Discover and inspect the actual project volume and
   pinned image from its existing container. These commands also work with the
   old `/root/.local` mount. Run them from this repository in a shell with Docker
   access; substitute the intended account for `YOUR_NORMAL_USER`:

   ```sh
   host_user=YOUR_NORMAL_USER
   uid=$(id -u "$host_user")
   gid=$(id -g "$host_user")
   test "$uid" -ne 0 && test "$gid" -ne 0
   docker compose stop opencode
   container=$(docker compose ps -aq opencode)
   volume=$(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' "$container")
   image=$(docker inspect --format '{{.Image}}' "$container")
   project=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$container")
   docker volume inspect "$volume"
   test "$(docker volume inspect --format '{{index .Labels "com.docker.compose.project"}}' "$volume")" = "$project"
   test "$(docker volume inspect --format '{{index .Labels "com.docker.compose.volume"}}' "$volume")" = opencode-data
   ```

3. Back up while stopped. The helper has **only this volume** mounted,
   read-only, and no network. The second complete read must have the same hash
   as the stored archive; do not continue on any error or mismatch. The tar
   archive preserves original numeric ownership and permissions for recovery.

   ```sh
   umask 077
   mkdir -p backups
   backup="backups/opencode-$(date +%Y%m%dT%H%M%S).backup.tar"
   docker run --rm --network none --security-opt no-new-privileges:true \
     --label "com.docker.compose.project=$project" --user 0:0 \
     --mount "type=volume,src=$volume,dst=/data,readonly" \
     --entrypoint tar "$image" -C /data -cf - . > "$backup"
   sha256sum "$backup"
   docker run --rm --network none --security-opt no-new-privileges:true \
     --label "com.docker.compose.project=$project" --user 0:0 \
     --mount "type=volume,src=$volume,dst=/data,readonly" \
     --entrypoint tar "$image" -C /data -cf - . | sha256sum
   ```

4. After verifying the backup, change ownership **only inside this volume**.
   `find -xdev` does not cross filesystems; `chown -h` does not follow symlinks.
   No file contents or permission modes are changed:

   ```sh
   docker run --rm --network none --security-opt no-new-privileges:true \
     --label "com.docker.compose.project=$project" --user 0:0 \
     --mount "type=volume,src=$volume,dst=/data" \
     --entrypoint sh "$image" -eu -c \
     'find /data -xdev -exec chown -h "$1:$2" {} +' sh "$uid" "$gid"
   docker compose up --detach --no-deps --wait opencode
   ./scripts/doctor.sh
   docker compose exec -T opencode opencode auth list
   docker compose exec -T opencode opencode db 'PRAGMA integrity_check'
   docker compose exec -T opencode opencode db 'SELECT count(*) AS sessions FROM session'
   ```

   Compare session IDs/counts and provider listings before and after migration.
   `auth list` confirms credential discovery; a successful provider request is
   needed to verify live authentication. Keep the backup until satisfied.

Run doctor as the intended user, or through sudo so `SUDO_USER` identifies them.
It checks configured and actual process IDs, `.env` ownership, mount properties,
data writability, a temporary container-created workspace file and its cleanup,
authenticated health, Playwright health, and IPv4-loopback-only publication.
The ownership probe removes its temporary file on failure or interruption too.

The host workspace must already allow this user to write. Previously root-owned
workspace files are not repaired automatically; review individual affected
files separately. This configuration assumes ordinary Linux Docker UID mapping;
rootless Docker or user-namespace remapping may need additional mapping work,
and doctor will expose a mismatch.

## Recovery

Recovery replaces persistent contents and requires a deliberate decision and a
verified backup. Keep the server stopped. The example below is for routine gzip
backups; a migration `.backup.tar` is uncompressed (use `tar -xf`, not `-xzf`).
For a pre-migration archive, restore as root to preserve its metadata, then
repeat the verified ownership migration before starting the non-root service:

```sh
./scripts/stop.sh
docker compose run --rm --no-deps -T --user 0:0 --entrypoint sh opencode -eu -c \
  'rm -rf /home/opencode/.local/* /home/opencode/.local/.[!.]* /home/opencode/.local/..?*; tar -C /home/opencode/.local -xzf -' \
   < backups/opencode-YYYYMMDD.backup.tar.gz
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
`~/.local/state/opencode` for state. With `HOME=/home/opencode`, the layout is:

| Purpose | Container path | Lifetime |
| --- | --- | --- |
| Database, sessions, logs, provider `auth.json` | `/home/opencode/.local/share/opencode` | Existing named volume |
| State and locks | `/home/opencode/.local/state/opencode` | Existing named volume |
| Cache and downloaded tools | `/home/opencode/.cache/opencode` | Ephemeral home tmpfs |
| Config | `/home/opencode/.config/opencode` | Read-only `./opencode` bind |

These paths were verified with `opencode debug paths` in the pinned official
image and its [global path implementation](https://github.com/anomalyco/opencode/blob/v1.18.29/packages/core/src/global.ts).
No XDG overrides or passwd entry are required. Cache is regenerated after
container recreation; database/session data and provider logins persist.
