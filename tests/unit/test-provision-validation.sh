#!/usr/bin/env bash
# tests/unit/test-provision-validation.sh — unit-тесты валидатора схемы VLANit.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROVISION="$ROOT/provisioning/vlanit-provision"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
expect_ok() {
    local name="$1" file="$2"
    if python3 "$PROVISION" --validate-only "$file" >/dev/null 2>&1; then
        echo "PASS $name"
    else
        echo "FAIL $name (ожидался успех)"; fail=1
    fi
}
expect_err() {
    local name="$1" file="$2"
    if python3 "$PROVISION" --validate-only "$file" >/dev/null 2>&1; then
        echo "FAIL $name (ожидалась ошибка)"; fail=1
    else
        echo "PASS $name"
    fi
}

cat > "$WORK/valid.yaml" <<'EOF'
schema_version: 1
system:
  hostname: vlanit-pbx-001
  network:
    mode: static
    address: 192.168.1.10/24
    gateway: 192.168.1.1
storage:
  filesystem: btrfs
  snapshots: true
container:
  runtime: podman
  network_mode: host
mikopbx:
  name: VLANit-PBX-001
  provisioning:
    enabled: true
    profile: basic
  env:
    SIP_PORT: "5060"
EOF
expect_ok "valid full config" "$WORK/valid.yaml"

cat > "$WORK/minimal.yaml" <<'EOF'
schema_version: 1
EOF
expect_ok "minimal config" "$WORK/minimal.yaml"

sed 's/schema_version: 1/schema_version: 2/' "$WORK/valid.yaml" > "$WORK/badver.yaml"
expect_err "wrong schema_version" "$WORK/badver.yaml"

sed 's/vlanit-pbx-001/Bad_Name!/' "$WORK/valid.yaml" > "$WORK/badhost.yaml"
expect_err "invalid hostname" "$WORK/badhost.yaml"

sed 's|192.168.1.10/24|10.0.0.999/24|' "$WORK/valid.yaml" > "$WORK/badip.yaml"
expect_err "invalid static address" "$WORK/badip.yaml"

sed 's/mode: static/mode: pppoe/' "$WORK/valid.yaml" > "$WORK/badmode.yaml"
expect_err "unknown network mode" "$WORK/badmode.yaml"

sed 's/SIP_PORT/UNCONFIRMED_FAKE_PARAM/' "$WORK/valid.yaml" > "$WORK/badenv.yaml"
expect_err "unconfirmed mikopbx env param" "$WORK/badenv.yaml"

cat > "$WORK/badnetmode.yaml" <<'EOF'
schema_version: 1
container:
  network_mode: bridge
EOF
expect_err "container network_mode != host" "$WORK/badnetmode.yaml"

if [ "$fail" -ne 0 ]; then echo "UNIT TESTS FAILED"; exit 1; fi
echo "UNIT TESTS OK"
