#!/usr/bin/env python3
"""Generate node_modules volume overlays for workspace JS projects; never delete data."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
GENERATED = ROOT / "compose.override.yaml"
MARKER = "opencode-stack node_modules overlays v1"
SKIP = {"node_modules", ".git", ".hg", ".svn", ".venv", "venv", "dist", "build",
        "target", ".astro", ".next", ".nuxt", ".angular", ".svelte-kit", ".turbo",
        ".output", "coverage", ".cache", "backups"}


def output(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def discover(workspace):
    projects = []
    def scan_error(error):
        raise error  # Never silently omit a project whose host modules need masking.
    for directory, dirs, files in os.walk(workspace, followlinks=False, onerror=scan_error):
        dirs[:] = sorted(name for name in dirs if name not in SKIP and not Path(directory, name).is_symlink())
        if "package.json" in files:
            target = Path(directory) / "node_modules"
            if target.is_symlink() or (target.exists() and not target.is_dir()):
                raise RuntimeError(f"Refusing to overlay a symlink/non-directory: {target}")
            projects.append(target)
    return sorted(projects)


def configuration():
    return json.loads(output("docker", "compose", "-f", "compose.yaml", "config", "--format", "json"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify generated and running mounts without changing anything")
    args = parser.parse_args()
    config = configuration()
    service = config["services"]["opencode"]
    workspace = Path(service["working_dir"])
    uid, gid = map(int, service["user"].split(":"))
    if uid <= 0 or gid <= 0 or not workspace.is_absolute() or not workspace.is_dir():
        raise RuntimeError("A valid workspace and non-root HOST_UID/HOST_GID are required")
    arch = output("docker", "image", "inspect", service["image"], "--format", "{{.Architecture}}")
    targets = discover(workspace)
    volumes = {}
    mounts = []
    for target in targets:
        relative = str(target.relative_to(workspace))
        key = f"js22-glibc-{arch}-" + hashlib.sha256(relative.encode()).hexdigest()[:16]
        name = f"{config['name']}_{key}"
        volumes[key] = {"external": True, "name": name}
        mounts.append({"type": "volume", "source": key, "target": str(target).replace("$", "$$"),
                       "volume": {"nocopy": True}})
    generated = {"x-generated-by": MARKER, "services": {"opencode": {"volumes": mounts}}, "volumes": volumes}
    if GENERATED.is_symlink():
        raise RuntimeError(f"Refusing to overwrite symlink: {GENERATED}")
    if GENERATED.exists():
        previous = json.loads(GENERATED.read_text())
        if previous.get("x-generated-by") != MARKER:
            raise RuntimeError("compose.override.yaml is user-managed; merge the dependency overlays explicitly")
    elif args.check:
        raise RuntimeError("Missing dependency overlays; run scripts/start.sh")
    if args.check:
        if previous != generated:
            raise RuntimeError("JS project inventory changed; run scripts/start.sh before installing dependencies")
        container = output("docker", "compose", "ps", "-q", "opencode")
        inspect = json.loads(output("docker", "inspect", container))[0]
        actual = {item["Destination"]: item for item in inspect["Mounts"]}
        for target, mount in zip(targets, mounts):
            item = actual.get(str(target), {})
            if item.get("Type") != "volume" or item.get("Name") != volumes[mount["source"]]["name"] or not item.get("RW"):
                raise RuntimeError(f"Host node_modules is not isolated: {target}")
            subprocess.run(["docker", "exec", container, "test", "-w", str(target)], check=True)
        print(f"ok: {len(targets)} JS package directories use writable, container-only node_modules volumes")
        return
    for target, mount in zip(targets, mounts):
        # Docker must not create a root-owned directory inside the host bind.
        # Existing host modules are neither read, copied, removed nor chowned.
        if not target.exists():
            target.mkdir(mode=0o755)
            if os.getuid() == 0:
                os.chown(target, uid, gid)
        name = volumes[mount["source"]]["name"]
        exists = subprocess.run(["docker", "volume", "inspect", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        if not exists:
            output("docker", "volume", "create", "--label", f"com.docker.compose.project={config['name']}",
                   "--label", "io.opencode-stack.dependencies=node22-glibc", name)
        info = json.loads(output("docker", "volume", "inspect", name))[0]
        labels = info.get("Labels") or {}
        if labels.get("com.docker.compose.project") != config["name"] or labels.get("io.opencode-stack.dependencies") != "node22-glibc":
            raise RuntimeError(f"Refusing to modify a volume not managed by this generator: {name}")
        subprocess.run(["docker", "run", "--rm", "--network", "none", "--security-opt", "no-new-privileges:true",
            "--label", f"com.docker.compose.project={config['name']}", "--user", "0:0",
            "--mount", f"type=volume,source={name},target=/dependencies,volume-nocopy",
            "--entrypoint", "sh", service["image"], "-eu", "-c",
            'if [ -z "$(ls -A /dependencies)" ]; then chown "$1:$2" /dependencies; fi; '
            'test "$(stat -c %u:%g /dependencies)" = "$1:$2"', "sh", str(uid), str(gid)], check=True)
        print(f"Isolated dependencies: {target.relative_to(workspace)} -> {name}")
    descriptor, temporary = tempfile.mkstemp(prefix=".env.dependencies-", dir=ROOT)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(generated, stream, indent=2)
            stream.write("\n")
        os.chmod(temporary, 0o644)
        if os.getuid() == 0:
            os.chown(temporary, uid, gid)
        os.replace(temporary, GENERATED)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f"Generated {GENERATED.name} for {len(targets)} package directories; existing volumes are never deleted")


if __name__ == "__main__":
    main()
