#!/usr/bin/env bash
set -euo pipefail

# Deploy a notarized macOS DMG to acode.anna.vin and publish the online-update
# metadata consumed by GET /remote/app-updates/check.
#
# Common overrides:
#   RELEASE_NOTES="..." FORCE_UPDATE=1 scripts/deploy-macos-update.sh
#   DMG_PATH=/path/to/annacode-macos.dmg APP_PATH=/path/to/AnnaCode.app scripts/deploy-macos-update.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DMG_PATH="${DMG_PATH:-$ROOT_DIR/build/releases/annacode-macos.dmg}"
APP_PATH="${APP_PATH:-/Users/oreo/Desktop/AnnaCode.app}"

SSH_KEY="${SSH_KEY:-/Users/oreo/Desktop/ssh-root-8.156.64.76-ed25519}"
REMOTE_HOST="${REMOTE_HOST:-8.156.64.76}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_PORT="${REMOTE_PORT:-22}"
REMOTE_ROOT="${REMOTE_ROOT:-/www/wwwroot/acode.anna.vin}"
REMOTE_DOWNLOAD_DIR="${REMOTE_DOWNLOAD_DIR:-$REMOTE_ROOT/downloads}"
REMOTE_RELEASE_DIR="${REMOTE_RELEASE_DIR:-$REMOTE_DOWNLOAD_DIR/releases}"
REMOTE_DMG_NAME="${REMOTE_DMG_NAME:-annacode-macos.dmg}"
DOWNLOAD_BASE_URL="${DOWNLOAD_BASE_URL:-https://acode.anna.vin/downloads}"
DOWNLOAD_URL="${DOWNLOAD_URL:-$DOWNLOAD_BASE_URL/$REMOTE_DMG_NAME}"

PLATFORM="${PLATFORM:-macos}"
CHANNEL="${CHANNEL:-stable}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
PACKAGE_ARCH="${PACKAGE_ARCH:-universal}"
MINIMUM_VERSION="${MINIMUM_VERSION:-}"
RELEASE_NOTES="${RELEASE_NOTES:-修复远程连接稳定性、macOS 同步显示和在线更新流程。}"
FORCE_UPDATE="${FORCE_UPDATE:-0}"
PUBLISHED="${PUBLISHED:-1}"

VERIFY_NOTARIZATION="${VERIFY_NOTARIZATION:-1}"
SKIP_UPLOAD="${SKIP_UPLOAD:-0}"
SKIP_DB="${SKIP_DB:-0}"
SKIP_PUBLIC_VERIFY="${SKIP_PUBLIC_VERIFY:-0}"

SSH_TARGET="$REMOTE_USER@$REMOTE_HOST"
SSH_ARGS=(-i "$SSH_KEY" -p "$REMOTE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
SCP_ARGS=(-i "$SSH_KEY" -P "$REMOTE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

TMP_DIR="$(mktemp -d)"
SQL_FILE="$TMP_DIR/annacode-macos-update.sql"
REMOTE_TMP_DMG="$REMOTE_DOWNLOAD_DIR/.${REMOTE_DMG_NAME}.tmp-$(date +%Y%m%d%H%M%S)-$$"
REMOTE_TMP_SQL="/tmp/annacode-macos-update-$(date +%Y%m%d%H%M%S)-$$.sql"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

log() {
  printf '[deploy-macos-update] %s\n' "$*"
}

die() {
  printf '[deploy-macos-update] ERROR: %s\n' "$*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || die "missing file: $path"
}

sql_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

bool_to_int() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|y|on) printf '1' ;;
    0|false|no|n|off|'') printf '0' ;;
    *) die "invalid boolean value: $1" ;;
  esac
}

extract_version_from_app() {
  [[ -d "$APP_PATH" ]] || die "APP_PATH does not exist: $APP_PATH"
  local info_plist="$APP_PATH/Contents/Info.plist"
  require_file "$info_plist"
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
  BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
}

verify_local_package() {
  require_file "$DMG_PATH"
  [[ -n "$VERSION" ]] || extract_version_from_app
  [[ -n "$BUILD_NUMBER" ]] || extract_version_from_app

  log "local package: $DMG_PATH"
  log "release: platform=$PLATFORM channel=$CHANNEL arch=$PACKAGE_ARCH version=$VERSION build=$BUILD_NUMBER"

  if [[ "$VERIFY_NOTARIZATION" == "1" ]]; then
    hdiutil verify "$DMG_PATH" >/dev/null
    spctl -a -vv -t open --context context:primary-signature "$DMG_PATH" >/dev/null 2>&1
    log "local verification: hdiutil + Gatekeeper passed"
  fi
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

file_size() {
  stat -f '%z' "$1"
}

remote_exec() {
  ssh "${SSH_ARGS[@]}" "$SSH_TARGET" "$@"
}

remote_prepare() {
  remote_exec "mkdir -p '$(printf "%q" "$REMOTE_DOWNLOAD_DIR")' '$(printf "%q" "$REMOTE_RELEASE_DIR")'"
}

upload_package() {
  local digest="$1"
  local size="$2"
  if [[ "$SKIP_UPLOAD" == "1" ]]; then
    log "upload skipped"
    return
  fi

  remote_prepare
  log "uploading DMG to $SSH_TARGET:$REMOTE_TMP_DMG"
  scp "${SCP_ARGS[@]}" "$DMG_PATH" "$SSH_TARGET:$REMOTE_TMP_DMG" >/dev/null

  remote_exec "set -e
remote_sha=\$(sha256sum '$(printf "%q" "$REMOTE_TMP_DMG")' | awk '{print \$1}')
remote_size=\$(stat -c '%s' '$(printf "%q" "$REMOTE_TMP_DMG")')
test \"\$remote_sha\" = '$(printf "%q" "$digest")'
test \"\$remote_size\" = '$(printf "%q" "$size")'
if [ -f '$(printf "%q" "$REMOTE_DOWNLOAD_DIR/$REMOTE_DMG_NAME")' ]; then
  cp -f '$(printf "%q" "$REMOTE_DOWNLOAD_DIR/$REMOTE_DMG_NAME")' '$(printf "%q" "$REMOTE_RELEASE_DIR/annacode-macos-$VERSION-$BUILD_NUMBER-$(date +%Y%m%d%H%M%S).dmg")'
fi
mv -f '$(printf "%q" "$REMOTE_TMP_DMG")' '$(printf "%q" "$REMOTE_DOWNLOAD_DIR/$REMOTE_DMG_NAME")'
chmod 0644 '$(printf "%q" "$REMOTE_DOWNLOAD_DIR/$REMOTE_DMG_NAME")'"
  log "upload complete: $DOWNLOAD_URL"
}

write_sql_file() {
  local digest="$1"
  local size="$2"
  local force_update_int
  local published_int
  force_update_int="$(bool_to_int "$FORCE_UPDATE")"
  published_int="$(bool_to_int "$PUBLISHED")"

  cat >"$SQL_FILE" <<SQL
START TRANSACTION;

SET @existing_id := (
  SELECT id FROM (
    SELECT id
    FROM remote_app_updates
    WHERE deleted_at IS NULL
      AND platform = $(sql_quote "$PLATFORM")
      AND channel = $(sql_quote "$CHANNEL")
      AND package_arch = $(sql_quote "$PACKAGE_ARCH")
      AND version = $(sql_quote "$VERSION")
      AND build_number = $(sql_quote "$BUILD_NUMBER")
    ORDER BY released_at DESC, id DESC
    LIMIT 1
  ) AS existing_update
);

INSERT INTO remote_app_updates (
  created_at,
  updated_at,
  platform,
  channel,
  version,
  build_number,
  package_arch,
  minimum_version,
  release_notes,
  update_type,
  download_url,
  app_store_url,
  package_file_name,
  package_file_size,
  package_sha256,
  force_update,
  published,
  released_at
)
SELECT
  NOW(3),
  NOW(3),
  $(sql_quote "$PLATFORM"),
  $(sql_quote "$CHANNEL"),
  $(sql_quote "$VERSION"),
  $(sql_quote "$BUILD_NUMBER"),
  $(sql_quote "$PACKAGE_ARCH"),
  $(sql_quote "$MINIMUM_VERSION"),
  $(sql_quote "$RELEASE_NOTES"),
  'file',
  $(sql_quote "$DOWNLOAD_URL"),
  '',
  $(sql_quote "$REMOTE_DMG_NAME"),
  $size,
  $(sql_quote "$digest"),
  $force_update_int,
  0,
  NOW(3)
WHERE @existing_id IS NULL;

SET @published_id := IF(@existing_id IS NULL, LAST_INSERT_ID(), @existing_id);

UPDATE remote_app_updates
SET published = 0, updated_at = NOW(3)
WHERE deleted_at IS NULL
  AND platform = $(sql_quote "$PLATFORM")
  AND channel = $(sql_quote "$CHANNEL")
  AND package_arch = $(sql_quote "$PACKAGE_ARCH")
  AND published = 1
  AND id <> @published_id;

UPDATE remote_app_updates
SET updated_at = NOW(3),
    platform = $(sql_quote "$PLATFORM"),
    channel = $(sql_quote "$CHANNEL"),
    version = $(sql_quote "$VERSION"),
    build_number = $(sql_quote "$BUILD_NUMBER"),
    package_arch = $(sql_quote "$PACKAGE_ARCH"),
    minimum_version = $(sql_quote "$MINIMUM_VERSION"),
    release_notes = $(sql_quote "$RELEASE_NOTES"),
    update_type = 'file',
    download_url = $(sql_quote "$DOWNLOAD_URL"),
    app_store_url = '',
    package_file_name = $(sql_quote "$REMOTE_DMG_NAME"),
    package_file_size = $size,
    package_sha256 = $(sql_quote "$digest"),
    force_update = $force_update_int,
    published = $published_int,
    released_at = NOW(3)
WHERE id = @published_id;
COMMIT;

SELECT id, platform, channel, package_arch, version, build_number, package_file_size, package_sha256, published, released_at
FROM remote_app_updates
WHERE deleted_at IS NULL
  AND platform = $(sql_quote "$PLATFORM")
  AND channel = $(sql_quote "$CHANNEL")
  AND package_arch = $(sql_quote "$PACKAGE_ARCH")
ORDER BY released_at DESC, id DESC
LIMIT 3;
SQL
}

publish_update_record() {
  if [[ "$SKIP_DB" == "1" ]]; then
    log "database update skipped"
    return
  fi

  log "publishing update metadata to remote_app_updates"
  scp "${SCP_ARGS[@]}" "$SQL_FILE" "$SSH_TARGET:$REMOTE_TMP_SQL" >/dev/null
  remote_exec "set -e
cnf=\$(mktemp /tmp/acode-mysql.XXXXXX.cnf)
cleanup_remote() {
  rm -f \"\$cnf\" '$(printf "%q" "$REMOTE_TMP_SQL")'
}
trap cleanup_remote EXIT
python3 - '$(printf "%q" "$REMOTE_ROOT/backend/config.yaml")' \"\$cnf\" <<'PY'
import pathlib
import re
import sys

config_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
text = config_path.read_text()
match = re.search(r'^mysql:\\n(?P<body>(?:[ \\t]+[^\\n]+\\n)+)', text, re.M)
if not match:
    raise SystemExit('mysql config block not found')

values = {}
for line in match.group('body').splitlines():
    stripped = line.strip()
    if ':' not in stripped:
        continue
    key, value = stripped.split(':', 1)
    value = value.strip().strip('\"').strip(\"'\")
    values[key.strip()] = value

db = values.get('db-name') or values.get('dbname') or values.get('database')
user = values.get('username') or values.get('user')
password = values.get('password') or ''
host_port = values.get('path') or values.get('host') or '127.0.0.1:3306'
if ':' in host_port:
    host, port = host_port.rsplit(':', 1)
else:
    host, port = host_port, '3306'
if not db or not user:
    raise SystemExit('mysql db-name or username missing')

out_path.write_text(
    '[client]\\n'
    f'host={host}\\n'
    f'port={port}\\n'
    f'user={user}\\n'
    f'password={password}\\n'
    f'database={db}\\n',
)
out_path.chmod(0o600)
PY
mysql --defaults-extra-file=\"\$cnf\" < '$(printf "%q" "$REMOTE_TMP_SQL")'"
}

verify_public_update() {
  if [[ "$SKIP_PUBLIC_VERIFY" == "1" ]]; then
    log "public verification skipped"
    return
  fi

  log "verifying public download URL"
  curl -fsSI "$DOWNLOAD_URL" | awk '{line=tolower($0); if (index(line,"http/")==1 || index(line,"content-length:")==1 || index(line,"content-type:")==1) print}'

  log "verifying public update API for older build"
  curl -fsS "https://acode.anna.vin/remote/app-updates/check?platform=$PLATFORM&channel=$CHANNEL&arch=$PACKAGE_ARCH&version=1.0&buildNumber=1"
  printf '\n'

  log "verifying public update API for current build"
  curl -fsS "https://acode.anna.vin/remote/app-updates/check?platform=$PLATFORM&channel=$CHANNEL&arch=$PACKAGE_ARCH&version=$VERSION&buildNumber=$BUILD_NUMBER"
  printf '\n'
}

main() {
  verify_local_package
  local digest
  local size
  digest="$(sha256_file "$DMG_PATH")"
  size="$(file_size "$DMG_PATH")"
  log "sha256=$digest size=$size"
  upload_package "$digest" "$size"
  write_sql_file "$digest" "$size"
  publish_update_record
  verify_public_update
  log "done"
}

main "$@"
