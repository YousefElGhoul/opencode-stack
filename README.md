# OpenCode Headless Server

A minimal Docker Compose environment for one authenticated OpenCode headless
server. OpenCode can read and modify repositories under the configured absolute
workspace path; the repositories themselves remain outside this repository.

## Security model

- The server is published only as `127.0.0.1:4096` on the host.
- HTTP Basic authentication is enabled by `OPENCODE_SERVER_PASSWORD`; the
  default username is `opencode`.
- `./opencode` is mounted read-only at `/root/.config/opencode`, which is also
  selected through `OPENCODE_CONFIG_DIR`.
- The external workspace is the only read/write host bind mount.
- Database, provider credentials, and session state persist in the
  Compose-managed `opencode-data` volume at `/root/.local`.
- Playwright MCP runs in its official container and is reachable only on the
  internal Compose network.
- Exa, Context7, GitHub, and Postman use their official hosted HTTPS MCP
  endpoints; no redundant local proxies are created.
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
server password, prompts without echo for MCP API keys, validates Docker, and
pulls official images pinned by version and multi-platform manifest digest.
When `.env` already exists, rerun `sudo ./scripts/setup.sh` without a workspace
argument to add or rotate MCP keys while preserving existing values when a
prompt is left blank.

The workspace is mounted at the same absolute path inside the container. Setup
also installs `~/.local/bin/opencode` and mode-`0600` client credential files
under `~/.config/opencode-stack`. This lets the local TUI attach to the server
without exposing the root-owned stack `.env`.

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

