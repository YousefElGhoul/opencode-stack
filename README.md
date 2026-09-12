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

# OpenCode Remote Development Workstation

A Docker Compose development workstation with an authenticated OpenCode server,
a Debian/glibc toolchain, persistent non-root home, and a Chromium MCP sidecar.
Repositories stay bind-mounted at their original absolute paths. JavaScript
dependencies are isolated from the host in per-package Docker volumes.

## Security model

- The server is published only as `127.0.0.1:4096` on the host.
- HTTP Basic authentication is enabled by `OPENCODE_SERVER_PASSWORD`; the
  default username is `opencode`.
- `./opencode` is mounted read-only at `/etc/opencode-stack`. Its
  `opencode.json` is selected through `OPENCODE_CONFIG`; skills are loaded from
  `/etc/opencode-stack/skills`. Applications can write their own `~/.config`.
- The external workspace is the only read/write host bind mount.
- Database, provider credentials, and session state persist in the
  Compose-managed `opencode-data` volume at `/home/opencode/.local`.
- OpenCode runs as the invoking host user's numeric `HOST_UID:HOST_GID`.
- `/home/opencode` is a user-owned `opencode-home` volume for application config,
  caches, package-manager stores, and other home files. The existing data volume
  is mounted inside it at `.local` and retains its original contents.
- `/tmp/opencode` is private user-owned tmpfs, recreated on each start.
- Playwright MCP and Chromium run in the official sidecar, sharing **OpenCode's
  container network namespace**. The MCP endpoint binds only to shared loopback
  at `127.0.0.1:8931`; it is not published on the host.
- Exa, Context7, GitHub, and Postman use their official hosted HTTPS MCP
  endpoints; no redundant local proxies are created.
- The stack has no Docker socket mount, privileged mode, host networking, or
  Tailscale container.

The official OpenCode runtime image is Alpine/musl and lacks a development
toolchain. `Dockerfile` instead uses a digest-pinned official Node 22 image on
Debian Trixie and installs the same pinned official `opencode-ai` npm release.
The image has a real passwd entry matching `HOST_UID:HOST_GID`. Startup runs
without root and only verifies writable directories; it never installs tools
or recursively changes ownership of a host directory.

## Development toolchain

The image includes Git, GitHub CLI, curl, wget, jq, Bash, OpenSSH client,
ripgrep, fd (`fdfind` alias), unzip/zip/tar/xz, make, GCC/G++, build-essential,
pkg-config, Node 22 with npm/npx, pnpm, Python 3 with venv support, uv/uvx,
OpenJDK 21, Maven, and basic process/network inspection utilities.

Chromium stays in the Playwright sidecar rather than duplicating a browser in
the development image. Astro, Vite, Angular CLI, and other frameworks are
**project-local dependencies**, never globally installed. GitHub CLI uses
`GH_TOKEN`, populated from the existing optional GitHub MCP token. Git identity
and SSH keys are configured by the user in the persistent home when needed.

Node/Debian and uv images are digest-pinned in `Dockerfile`; pnpm and OpenCode
have explicit versions. Debian packages use the signed Trixie repositories so
uncached rebuilds pick up security fixes. Their installed versions are recorded
at `/usr/local/share/opencode-stack/debian-packages.tsv`. This is a reproducible
build procedure, not a byte-identical frozen Debian package snapshot.
The official uv image supplies a self-contained static executable (its version
may say musl); Node and the workstation OS use glibc.

## Install

Requirements:

- Linux with Docker Engine, the Docker Compose plugin, and host Python 3
- An absolute path to a directory containing development repositories
- Tailscale on the host only if remote tailnet access is wanted

Initialize the stack with the external workspace path:

```sh
./scripts/setup.sh /absolute/path/to/development-repositories
```

The setup script creates a mode-`0600` `.env`, generates a random 256-bit
server password, prompts without echo for MCP API keys, validates Docker, and
builds the development image and pulls the digest-pinned Playwright image.
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

The built development image is tagged `opencode-stack/workstation:<version>`;
Playwright also receives a readable local alias. `.dockerignore` allowlists only
the Dockerfile and container helper scripts: secrets, backups, config, and
application repositories are excluded from the build context.

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

### Rebuild and restart

```sh
sudo docker compose -f compose.yaml build --pull opencode
sudo ./scripts/start.sh
sudo ./scripts/doctor.sh
```

`start.sh` uses the cached build where possible, refreshes dependency overlays,
and brings up **both** OpenCode and Playwright. Compose recreates the sidecar
when its network-namespace owner is replaced. Do not replace just OpenCode
with `up --no-deps` and leave a sidecar attached to its previous namespace.
Recreate containers after config changes; existing clients may need to reconnect.
To refresh Debian security packages even when Docker's build cache is valid,
add `--no-cache` to the build command. No host packages are installed by setup.

### JavaScript dependencies

`scripts/dependencies.py`, called by setup/start, scans `WORKSPACE_DIR` for
`package.json` files, excluding dependency trees, VCS directories, and common
build/cache directories. It generates the ignored `compose.override.yaml`
automatically loaded by Compose. Each package's `node_modules` gets a separate
named volume with `nocopy: true`, keyed by its relative path, Node major,
glibc strategy, and CPU architecture. Nested workspace packages are covered.

Existing host `node_modules` are hidden inside the container, not copied,
deleted, or chowned. If a mountpoint directory is absent, the generator creates
only that empty directory with the host user's ownership. It initializes only
empty dependency-volume roots, verifies project labels on existing volumes,
and never removes old volumes. A user-managed `compose.override.yaml` is not
overwritten; merge overlays explicitly in that case.

After adding a package/project, run `sudo ./scripts/start.sh` before installing
dependencies. Doctor detects a stale inventory or missing/wrong running mounts.
Symlinked directory trees and generated output directories are not scanned.
Do not install through an unregistered/symlink alias to a host dependency tree.

Run installation **inside OpenCode**, as its non-root user:

```sh
docker compose exec -w /absolute/path/to/project opencode npm ci
docker compose exec -w /absolute/path/to/project opencode npm run build
# For a pnpm project, use its committed lockfile:
docker compose exec -w /absolute/path/to/project opencode pnpm install --frozen-lockfile
```

Host and container installs are independent. Repeat the container install when
the lockfile changes on the host. A malformed lockfile still needs deliberate
project-level repair; do not delete it, copy host native modules, or download a
temporary Node runtime to work around it. Projects requiring another Node or
package-manager major need an explicit image/version decision.

### Development servers and browser verification

Start a project-local server normally, for example `npm run dev`. Its
`http://localhost:4321` means the same thing to OpenCode and Playwright. No host
port publication or `--host 0.0.0.0` is needed. Use the actual URL printed by the
server: an IPv6-only `localhost` listener is not reachable via `127.0.0.1`.
Development processes stop when OpenCode is recreated; start them again afterward.

The enabled Playwright MCP offers normal navigation, snapshots, and evaluation
to the agent. For a repeatable end-to-end check:

```sh
sudo ./scripts/workstation-test.sh
```

This uses the stack-owned `tests/workstation` Vite/Tailwind project, its committed
lockfile and isolated dependencies. It runs all tool checks, `npm ci`, a native
Tailwind build, starts a loopback-only server on port 4321, and invokes actual
Playwright MCP navigation, accessibility snapshots and DOM evaluation from
OpenCode. It stops its own server and removes temporary control files afterward.
Port 4321 must be free in the shared namespace. It does not modify your app repos.

For an already-running page:

```sh
docker compose exec opencode browser-check http://localhost:4321
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
| `playwright` | Shared-loopback sidecar at `http://127.0.0.1:8931/mcp` | None |
| `github` | `https://api.githubcopilot.com/mcp/` | `GITHUB_PERSONAL_ACCESS_TOKEN` |
| `postman` | `https://mcp.postman.com/minimal` | `POSTMAN_API_KEY` |

Exa and Context7 remain enabled and allow anonymous access with lower limits.
Playwright is enabled. GitHub and Postman retain their existing disabled state;
enable them in the checked-in config when wanted. Their hosted URLs and secret
headers do not depend on the base image or Docker namespace. All MCP credential
prompts remain optional. Run setup again to configure or rotate them:

```sh
sudo ./scripts/setup.sh
```

Secrets remain in `.env`, which is ignored by Git and restricted to mode
`0600`. They are passed to the OpenCode container as environment variables and
are therefore visible to host users with Docker daemon or root access. Docker
does not provide a security boundary against its own administrators.

To upgrade OpenCode, choose an official `opencode-ai` npm release, change
`OPENCODE_VERSION` in `.env`, then rebuild. `OPENCODE_IMAGE_DIGEST` from the old
runtime-only setup is no longer used. Upgrade Node/Debian, uv, and pnpm pins in
`Dockerfile` deliberately and run the workstation integration check:

```sh
docker compose -f compose.yaml build --pull opencode
./scripts/start.sh
./scripts/workstation-test.sh
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
docker compose run --rm --no-deps -T --entrypoint tar opencode \
  --exclude=./.local -C /home/opencode -czf - . > backups/opencode-home-$(date +%Y%m%d).backup.tar.gz
```

The `backups/` directory and `*.backup.tar.gz` are ignored by Git. Move backups
to encrypted storage; a local ignored file is not sufficient protection.
Back up both volumes: `.local` contains the original OpenCode sessions/auth;
the home backup contains other application configuration, credentials and caches.
Dependency volumes are rebuildable from project lockfiles and are not included.

### Upgrade from the previous Alpine stack

Back up before recreating the service. The Debian image keeps the exact existing
`opencode-data` volume and `.local/share`/`.local/state` paths; no ownership
migration is needed if they already match `HOST_UID:HOST_GID`. The new home
volume is initialized from user-owned image directories. Nothing is copied from
host `node_modules` or temporary runtimes in the old container. The old tmpfs
home and `/tmp` were ephemeral; save any manually placed files there separately.

Installing Git lets OpenCode recognize repositories that previously fell back
to its `global` project. OpenCode may update existing sessions' project IDs and
timestamps during that discovery; verify their session IDs and messages rather
than mistaking this reassociation for deletion.

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
   volume=$(docker inspect --format '{{range .Mounts}}{{if or (eq .Destination "/root/.local") (eq .Destination "/home/opencode/.local")}}{{.Name}}{{end}}{{end}}' "$container")
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
   docker compose up --detach --wait
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
If changing the host identity on an existing workstation, rebuild the passwd
entry and separately back up/review ownership of the `opencode-home` and
dependency volumes too. Existing non-empty volumes are never recursively
chowned automatically by setup/start.

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
| Cache and downloaded tools | `/home/opencode/.cache/opencode` | Persistent home volume |
| Writable application config | `/home/opencode/.config` | Persistent home volume |
| Managed OpenCode config and skills | `/etc/opencode-stack` | Read-only `./opencode` bind |
| Temporary OpenCode files | `/tmp/opencode` | User-owned tmpfs |

These paths are verified with `opencode debug paths` and the pinned release's
[global path implementation](https://github.com/anomalyco/opencode/blob/v1.18.29/packages/core/src/global.ts).
No XDG overrides are required. The image provides a matching passwd entry;
database/session data, provider logins, application config and caches persist.
