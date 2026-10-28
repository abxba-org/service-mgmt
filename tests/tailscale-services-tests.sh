#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/tailscale-services"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS_COUNT=0

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "ok - $1"
}

make_mock_bin() {
  local dir="$1"
  mkdir -p "$dir"

  cat >"$dir/tailscale" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "status" && "${2:-}" == "--json" ]]; then
  echo '{"BackendState":"Running"}'
  exit 0
fi

if [[ "${1:-}" == "serve" && "${2:-}" == "--help" ]]; then
  cat <<H
usage: tailscale serve [reset]
options:
  --bg
  --https
  --http
  --hostname
H
  exit 0
fi

if [[ "${1:-}" == "funnel" && "${2:-}" == "--help" ]]; then
  cat <<H
usage: tailscale funnel [reset]
H
  exit 0
fi

echo "MOCK tailscale $*" >&2
exit 0
EOF
  chmod +x "$dir/tailscale"

  cat >"$dir/ss" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<H
LISTEN 0 128 127.0.0.1:8080 0.0.0.0:*
LISTEN 0 128 127.0.0.1:9090 0.0.0.0:*
LISTEN 0 128 127.0.0.1:7000 0.0.0.0:*
H
EOF
  chmod +x "$dir/ss"
}

run_cmd() {
  local out_file="$1"
  shift
  if "$@" >"$out_file" 2>&1; then
    return 0
  fi
  return 1
}

test_apply_dry_run_multiple_services() {
  local td="$TMP_ROOT/t1" out cfg
  mkdir -p "$td"
  make_mock_bin "$td/bin"
  out="$td/out.txt"
  cfg="$td/services.conf"

  cat >"$cfg" <<'EOF'
web 127.0.0.1:8080 / tailnet https tailnet
api 127.0.0.1:9090 /api tailnet https tailnet
EOF

  run_cmd "$out" env PATH="$td/bin:$PATH" TAILSCALE_BIN=tailscale "$SCRIPT" apply -c "$cfg" --dry-run || fail "apply dry-run failed"
  grep -q "serve --bg --https=443 / http://127.0.0.1:8080" "$out" || fail "missing root route command"
  grep -q "serve --bg --https=443 /api http://127.0.0.1:9090" "$out" || fail "missing api route command"
  pass "apply dry-run prints deterministic serve commands"
}

test_overlapping_paths_rejected() {
  local td="$TMP_ROOT/t2" out cfg
  mkdir -p "$td"
  make_mock_bin "$td/bin"
  out="$td/out.txt"
  cfg="$td/services.conf"

  cat >"$cfg" <<'EOF'
web 127.0.0.1:8080 /app tailnet https tailnet
api 127.0.0.1:9090 /app/v1 tailnet https tailnet
EOF

  if run_cmd "$out" env PATH="$td/bin:$PATH" TAILSCALE_BIN=tailscale "$SCRIPT" validate -c "$cfg"; then
    fail "overlapping route config unexpectedly validated"
  fi
  grep -q "overlaps existing route" "$out" || fail "expected overlap error"
  pass "overlapping paths are rejected"
}

test_funnel_requires_explicit_flags() {
  local td="$TMP_ROOT/t3" out cfg
  mkdir -p "$td"
  make_mock_bin "$td/bin"
  out="$td/out.txt"
  cfg="$td/services.conf"

  cat >"$cfg" <<'EOF'
pub 127.0.0.1:7000 /public funnel https none
EOF

  if run_cmd "$out" env PATH="$td/bin:$PATH" TAILSCALE_BIN=tailscale "$SCRIPT" validate -c "$cfg"; then
    fail "funnel validation unexpectedly passed without --allow-funnel"
  fi
  grep -q "Re-run with --allow-funnel" "$out" || fail "expected allow-funnel guidance"

  run_cmd "$out" env PATH="$td/bin:$PATH" TAILSCALE_BIN=tailscale "$SCRIPT" validate -c "$cfg" --allow-funnel --yes || fail "funnel validation with explicit flags failed"
  pass "funnel requires explicit confirmation flags"
}

test_invalid_target_is_rejected() {
  local td="$TMP_ROOT/t4" out cfg
  mkdir -p "$td"
  make_mock_bin "$td/bin"
  out="$td/out.txt"
  cfg="$td/services.conf"

  cat >"$cfg" <<'EOF'
bad 10.0.0.2:8080 /bad tailnet https tailnet
EOF

  if run_cmd "$out" env PATH="$td/bin:$PATH" TAILSCALE_BIN=tailscale "$SCRIPT" validate -c "$cfg"; then
    fail "non-localhost target unexpectedly validated"
  fi
  grep -q "localhost-only" "$out" || fail "expected localhost-only error"
  pass "non-localhost target is rejected"
}

test_hostname_requires_cli_support() {
  local td="$TMP_ROOT/t5" out cfg
  mkdir -p "$td/bin"
  out="$td/out.txt"
  cfg="$td/services.conf"

  cat >"$td/bin/tailscale" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "status" && "${2:-}" == "--json" ]]; then
  echo '{"BackendState":"Running"}'
  exit 0
fi
if [[ "${1:-}" == "serve" && "${2:-}" == "--help" ]]; then
  cat <<H
usage: tailscale serve [reset]
options:
  --bg
  --https
H
  exit 0
fi
if [[ "${1:-}" == "funnel" && "${2:-}" == "--help" ]]; then
  echo "usage: tailscale funnel"
  exit 0
fi
exit 0
EOF
  chmod +x "$td/bin/tailscale"

  cat >"$td/bin/ss" <<'EOF'
#!/usr/bin/env bash
echo "LISTEN 0 128 127.0.0.1:8080 0.0.0.0:*"
EOF
  chmod +x "$td/bin/ss"

  cat >"$cfg" <<'EOF'
hosted 127.0.0.1:8080 app.example.ts.net tailnet https tailnet
EOF

  if run_cmd "$out" env PATH="$td/bin:$PATH" TAILSCALE_BIN=tailscale "$SCRIPT" validate -c "$cfg"; then
    fail "hostname route unexpectedly validated without --hostname support"
  fi
  grep -q "requires a tailscale version with --hostname support" "$out" || fail "expected hostname support error"
  pass "hostname route support is runtime-validated"
}

main() {
  test_apply_dry_run_multiple_services
  test_overlapping_paths_rejected
  test_funnel_requires_explicit_flags
  test_invalid_target_is_rejected
  test_hostname_requires_cli_support
  echo "All tests passed ($PASS_COUNT)."
}

main "$@"
