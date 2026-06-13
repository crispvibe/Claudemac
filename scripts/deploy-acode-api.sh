#!/usr/bin/env bash
set -euo pipefail

# Build, upload, switch, restart, and verify acode-api on acode.anna.vin.
#
# Usage:
#   SSH_KEY=/path/to/key scripts/deploy-acode-api.sh
#   SSH_KEY=/path/to/key SKIP_TESTS=1 scripts/deploy-acode-api.sh
#   BUILD_ONLY=1 scripts/deploy-acode-api.sh
#
# Environment overrides:
#   SSH_KEY          SSH private key (required unless BUILD_ONLY=1)
#   REMOTE_HOST      default: 8.156.64.76
#   REMOTE_USER      default: root
#   REMOTE_PORT      default: 22
#   REMOTE_ROOT      default: /www/wwwroot/acode.anna.vin/backend
#   SKIP_TESTS       default: 0
#   SKIP_UPLOAD      default: 0
#   SKIP_VERIFY      default: 0
#   BUILD_ONLY       default: 0  (only compile to /tmp/acode-api)
#   OUTPUT_PATH      default: /tmp/acode-api

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/后端/server"

SSH_KEY="${SSH_KEY:-/Users/oreo/Desktop/ssh-root-8.156.64.76-ed25519}"
REMOTE_HOST="${REMOTE_HOST:-8.156.64.76}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_PORT="${REMOTE_PORT:-22}"
REMOTE_ROOT="${REMOTE_ROOT:-/www/wwwroot/acode.anna.vin/backend}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://acode.anna.vin}"

SKIP_TESTS="${SKIP_TESTS:-0}"
SKIP_UPLOAD="${SKIP_UPLOAD:-0}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
BUILD_ONLY="${BUILD_ONLY:-0}"
OUTPUT_PATH="${OUTPUT_PATH:-/tmp/acode-api}"

RELEASE_ID="$(date +%Y%m%d-%H%M%S)"
REMOTE_RELEASE_PATH="$REMOTE_ROOT/releases/acode-api-$RELEASE_ID"
REMOTE_BIN_PATH="$REMOTE_ROOT/bin/acode-api"

SSH_TARGET="$REMOTE_USER@$REMOTE_HOST"
SSH_ARGS=(-i "$SSH_KEY" -p "$REMOTE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
SCP_ARGS=(-i "$SSH_KEY" -P "$REMOTE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

log() {
  printf '[deploy-acode-api] %s\n' "$*"
}

die() {
  printf '[deploy-acode-api] ERROR: %s\n' "$*" >&2
  exit 1
}

require_go() {
  command -v go >/dev/null 2>&1 || die "go not found; install with: brew install go"
}

require_ssh_key() {
  [[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY (set SSH_KEY=/path/to/key)"
}

run_tests() {
  log "running backend unit tests..."
  (
    cd "$SERVER_DIR"
    go test ./... -count=1
  )
}

build_binary() {
  log "building linux/amd64 binary -> $OUTPUT_PATH"
  (
    cd "$SERVER_DIR"
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o "$OUTPUT_PATH" .
  )
  file "$OUTPUT_PATH"
  ls -lh "$OUTPUT_PATH"
}

upload_and_switch() {
  log "uploading release acode-api-$RELEASE_ID"
  scp "${SCP_ARGS[@]}" "$OUTPUT_PATH" "$SSH_TARGET:$REMOTE_RELEASE_PATH"

  log "switching active binary and restarting service"
  ssh "${SSH_ARGS[@]}" "$SSH_TARGET" bash -s <<EOF
set -euo pipefail
install -m 0755 "$REMOTE_RELEASE_PATH" "$REMOTE_BIN_PATH"
chown www:www "$REMOTE_BIN_PATH"
systemctl restart acode-api.service
systemctl is-active acode-api.service
EOF
}

verify_remote() {
  log "verifying local health on server"
  ssh "${SSH_ARGS[@]}" "$SSH_TARGET" bash -s <<'EOF'
set -euo pipefail
curl -fsS --connect-timeout 3 --max-time 10 http://127.0.0.1:8868/health >/dev/null
systemctl is-active acode-api.service
EOF

  log "verifying public health endpoint"
  curl -fsS --connect-timeout 5 --max-time 15 "$PUBLIC_BASE_URL/health" >/dev/null

  log "verifying lan-token route is registered (expect HTTP 401 without auth, not 404)"
  status="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
    -X POST "$PUBLIC_BASE_URL/remote/devices/1/lan-token" \
    -H 'Content-Type: application/json' \
    -d '{"ip":"192.168.1.20","port":18765,"transient_token":"probe","expires_at":9999999999999}')"
  if [[ "$status" == "404" ]]; then
    die "lan-token endpoint still returns 404; deployment may not have taken effect"
  fi
  log "lan-token probe status: $status (401/403/400 are acceptable; 404 is not)"
}

main() {
  require_go

  if [[ "$SKIP_TESTS" != "1" ]]; then
    run_tests
  else
    log "SKIP_TESTS=1, skipping unit tests"
  fi

  build_binary

  if [[ "$BUILD_ONLY" == "1" ]]; then
    log "BUILD_ONLY=1, done"
    exit 0
  fi

  if [[ "$SKIP_UPLOAD" == "1" ]]; then
    log "SKIP_UPLOAD=1, binary ready at $OUTPUT_PATH"
    exit 0
  fi

  require_ssh_key
  upload_and_switch

  if [[ "$SKIP_VERIFY" != "1" ]]; then
    verify_remote
  else
    log "SKIP_VERIFY=1, skipping post-deploy checks"
  fi

  log "deploy complete: acode-api-$RELEASE_ID"
}

main "$@"
