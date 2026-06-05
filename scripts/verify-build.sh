#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

require_arch() {
  local archs="$1"
  local required="$2"
  case " $archs " in
    *" $required "*) ;;
    *) echo "Missing required architecture $required (got: $archs)" >&2; exit 1 ;;
  esac
}

echo "==> swift test ChatCore"
swift test --package-path Shared/ChatCore

echo "==> swift build ChatUI"
swift build --package-path Shared/ChatUI

echo "==> xcodebuild ClaudeMac"
xcodebuild -project ClaudeMac.xcodeproj -scheme ClaudeMac -configuration Debug \
  -destination 'platform=macOS' build -quiet

echo "==> xcodebuild test ClaudeMac"
xcodebuild test -project ClaudeMac.xcodeproj -scheme ClaudeMac \
  -destination 'platform=macOS' -quiet

echo "==> xcodebuild ClaudeMac Release universal"
MAC_VERIFY_DERIVED_DATA="$ROOT/build/VerifyMacUniversal"
xcodebuild -project ClaudeMac.xcodeproj -scheme ClaudeMac -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$MAC_VERIFY_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  ENABLE_CODE_COVERAGE=NO \
  CLANG_COVERAGE_MAPPING=NO \
  build -quiet

MAC_APP="$MAC_VERIFY_DERIVED_DATA/Build/Products/Release/AnnaCode.app"
MAC_BINARY="$MAC_APP/Contents/MacOS/AnnaCode"
MAC_ARCHS="$(lipo -archs "$MAC_BINARY")"
echo "==> AnnaCode architectures: $MAC_ARCHS"
require_arch "$MAC_ARCHS" arm64
require_arch "$MAC_ARCHS" x86_64

while IFS= read -r -d '' executable; do
  if file "$executable" | grep -Fq "Mach-O"; then
    archs="$(lipo -archs "$executable")"
    echo "==> ${executable#$MAC_APP/}: $archs"
    require_arch "$archs" arm64
    require_arch "$archs" x86_64
  fi
done < <(find "$MAC_APP/Contents/Frameworks" -type f -perm -111 -print0 2>/dev/null || true)

echo "==> xcodebuild Acode"
xcodebuild -project AcodeIOS/Acode.xcodeproj -scheme Acode -configuration Debug \
  -destination 'generic/platform=iOS' build -quiet

echo "all green"
