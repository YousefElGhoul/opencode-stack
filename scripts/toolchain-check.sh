#!/bin/sh
set -eu
for tool in git gh curl wget jq bash ssh rg fd unzip zip tar make gcc g++ pkg-config \
  node npm npx pnpm python3 uv java javac mvn; do
  command -v "$tool" >/dev/null || { printf 'Missing tool: %s\n' "$tool" >&2; exit 1; }
done
getconf GNU_LIBC_VERSION
git --version
gh --version
node --version
npm --version
npx --version
pnpm --version
python3 --version
uv --version
java --version
mvn --version
curl --version
rg --version
fd --version
test "$(node -p 'process.versions.node.split(".")[0]')" = 22
java -XshowSettings:properties -version 2>&1 | grep -q 'java.specification.version = 21'
