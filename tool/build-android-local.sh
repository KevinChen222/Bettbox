#!/usr/bin/env bash
# Local arm64-v8a test build; does not commit, push or publish.
set -euo pipefail

require_signing=false
case "${1:-}" in
  '') ;;
  --require-signing) require_signing=true ;;
  *) echo "Usage: bash tool/build-android-local.sh [--require-signing]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
  echo "Unexpected arguments" >&2
  exit 2
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source tool/linux-env.sh android

# NTFS mounts may silently ignore chmod. Check before downloading/building.
mkdir -p .test
probe="$(mktemp .test/exec-check.XXXXXX)"
trap 'rm -f "$probe"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$probe"
chmod u+x "$probe"
if ! "$probe" 2>/dev/null; then
  echo "This workspace cannot execute build tools. Use a Linux filesystem (e.g. ~/project/bettbox_smart), not the NTFS backup." >&2
  exit 1
fi
rm -f "$probe"
trap - EXIT

has_signing=true
[[ -f android/app/keystore.jks && -f android/local.properties ]] || has_signing=false
for key in keyAlias storePassword keyPassword; do
  if ! grep -Eq "^[[:space:]]*$key[[:space:]]*=[[:space:]]*[^[:space:]]" android/local.properties 2>/dev/null; then
    has_signing=false
  fi
done
if ! "$has_signing"; then
  if "$require_signing"; then
    echo "Restore the original keystore and local signing properties first." >&2
    exit 1
  fi
  echo "WARNING: using a debug signature for this local test APK." >&2
fi

if ! rustup target list --installed | grep -qx aarch64-linux-android; then
  echo "Run: rustup target add aarch64-linux-android" >&2
  exit 1
fi
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang"
export SENTRY_BACKEND=none
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.vfs.watch=false"

flutter pub get
dart run build_runner build
dart setup.dart android --arch arm64 --out core --standard
[[ ! -f android/gradlew ]] || chmod u+x android/gradlew
flutter build apk --no-pub --release --split-per-abi --target-platform android-arm64 --dart-define=APP_ENV=pre --dart-define=APP_STANDARD=true

apk=build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
bash tool/build-android-verify.sh "$apk"
printf '\nAPK: %s/%s\n' "$PWD" "$apk"
sha256sum "$apk"
