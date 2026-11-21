#!/usr/bin/env bash
# Source this file before developing Bettbox on Linux.
# SDKs and download caches live on the user's Linux filesystem.
export BETTBOX_TOOLCHAIN_DIR="${BETTBOX_TOOLCHAIN_DIR:-$HOME/development/bettbox-toolchains}"
export FLUTTER_ROOT="$BETTBOX_TOOLCHAIN_DIR/flutter"
export ANDROID_HOME="$BETTBOX_TOOLCHAIN_DIR/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK="$ANDROID_HOME/ndk/28.2.13676358"
# Linux bundles use the system JDK 17 for JNI. Android uses JDK 21.
if [[ ${1:-} == android ]]; then
  bettbox_default_java=/usr/lib/jvm/java-21-openjdk-amd64
  bettbox_local_java="$BETTBOX_TOOLCHAIN_DIR/jdk-21-local/usr/lib/jvm/java-21-openjdk-amd64"
  if [[ ! -x "$bettbox_default_java/bin/javac" && -x "$bettbox_local_java/bin/javac" ]]; then
    bettbox_default_java="$bettbox_local_java"
  fi
  unset bettbox_local_java
else
  bettbox_default_java=/usr/lib/jvm/java-17-openjdk-amd64
fi
export JAVA_HOME="${BETTBOX_JAVA_HOME:-$bettbox_default_java}"
unset bettbox_default_java
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
