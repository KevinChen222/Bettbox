#!/usr/bin/env bash
# Source this file before developing Bettbox on Linux.
# SDKs and download caches live on the user's Linux filesystem.
export BETTBOX_TOOLCHAIN_DIR="${BETTBOX_TOOLCHAIN_DIR:-$HOME/development/bettbox-toolchains}"
export FLUTTER_ROOT="$BETTBOX_TOOLCHAIN_DIR/flutter"
export ANDROID_HOME="$BETTBOX_TOOLCHAIN_DIR/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK="$ANDROID_HOME/ndk/28.2.13676358"
export JAVA_HOME="${BETTBOX_JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
export PUB_CACHE="$HOME/.cache/bettbox/pub"
export GOPATH="$HOME/.cache/bettbox/go"
export GOMODCACHE="$HOME/.cache/bettbox/go-mod"
export GOCACHE="$HOME/.cache/bettbox/go-build"
export GRADLE_USER_HOME="$HOME/.cache/bettbox/gradle"

for bettbox_bin_dir in \
  "$HOME/.cargo/bin" \
  "$BETTBOX_TOOLCHAIN_DIR/go/bin" \
  "$FLUTTER_ROOT/bin" \
  "$ANDROID_HOME/cmdline-tools/latest/bin" \
  "$ANDROID_HOME/platform-tools" \
  "$JAVA_HOME/bin"; do
  case ":$PATH:" in
    *":$bettbox_bin_dir:"*) ;;
    *) PATH="$bettbox_bin_dir:$PATH" ;;
  esac
done
export PATH
unset bettbox_bin_dir
