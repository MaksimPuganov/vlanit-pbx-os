#!/usr/bin/env bash
# scripts/40-staging.sh — формирование payload и обновление release-manifest.
# Выполняется внутри build-контейнера от root.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
STAGING="$BUILD_DIR/iso-staging"
PAYLOAD_SRC="$PROJECT_ROOT/build/payload"
mkdir -p "$STAGING/payload"

log() { printf '[staging] %s\n' "$*"; }

log "копирование payload"
cp -a "$PAYLOAD_SRC/golden.tar.zst" "$PAYLOAD_SRC/golden.tar.zst.sha256" "$STAGING/payload/"
cp -a "$PAYLOAD_SRC/mikopbx-2026.6.99-amd64.tar.zst" "$PAYLOAD_SRC/mikopbx-2026.6.99-amd64.tar.zst.sha256" "$STAGING/payload/"

# версии/defaults для установщика
cp -a "$PROJECT_ROOT/config/build.yaml" "$STAGING/payload/build.yaml"
cp -a "$PROJECT_ROOT/config/defaults.yaml" "$STAGING/payload/defaults.yaml"
cp -a "$PROJECT_ROOT/config/release-manifest.yaml" "$STAGING/payload/release-manifest.yaml"

GOLDEN_SHA="$(awk '{print $1}' "$STAGING/payload/golden.tar.zst.sha256")"
MIKOPBX_SHA="$(awk '{print $1}' "$STAGING/payload/mikopbx-2026.6.99-amd64.tar.zst.sha256")"
FACTS="$BUILD_DIR/facts.json"
DEBIAN_VERSION="$(jq -r .debian_version "$FACTS")"
KERNEL_VERSION="$(jq -r .kernel_version "$FACTS")"
PODMAN_VERSION="$(jq -r .podman_version "$FACTS")"

log "release-manifest.yaml"
python3 - "$STAGING/payload/release-manifest.yaml" <<EOF
import sys, datetime
path = sys.argv[1]
text = open(path).read()
repl = {
    "  build_date: null": f"  build_date: \"{datetime.datetime.now(datetime.timezone.utc).isoformat()}\"",
    "  version: null": f"  version: \"$DEBIAN_VERSION\"",
    "  kernel: null": f"  kernel: \"$KERNEL_VERSION\"",
    "podman: null": f"podman: \"$PODMAN_VERSION\"",
    "  golden_tar: null": f"  golden_tar: \"$GOLDEN_SHA\"",
    "  mikopbx_tar: null": f"  mikopbx_tar: \"$MIKOPBX_SHA\"",
}
for k, v in repl.items():
    assert k in text, f"ключ не найден в манифесте: {k}"
    text = text.replace(k, v, 1)
open(path, "w").write(text)
EOF
cat "$STAGING/payload/release-manifest.yaml" > /dev/stderr || true
log "staging сформирован"
