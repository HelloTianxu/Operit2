#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
image="operit2-android-build:ubuntu24"
cache_root="${OPERIT_ANDROID_CONTAINER_CACHE:-$repo_dir/tools/release/work/android-container}"
mkdir -p "$cache_root"/{cargo-registry,cargo-git,cargo-target,gradle,pub,android-runtime,android-v8,flutter,dist}

runtime="${CONTAINER_RUNTIME:-docker}"
if ! command -v "$runtime" >/dev/null 2>&1; then
  if [[ -x /Applications/OrbStack.app/Contents/MacOS/xbin/docker ]]; then
    runtime=/Applications/OrbStack.app/Contents/MacOS/xbin/docker
  else
    echo "Docker runtime not found. Start OrbStack first." >&2
    exit 1
  fi
fi

if ! "$runtime" image inspect "$image" >/dev/null 2>&1 || [[ "${REBUILD_IMAGE:-0}" == 1 ]]; then
  "$runtime" build --platform linux/amd64 -t "$image" -f "$repo_dir/tools/android-container/Dockerfile" "$repo_dir"
fi

"$runtime" run --rm --platform linux/amd64 \
  -v "$repo_dir:/work" \
  -v "$cache_root/cargo-registry:/opt/cargo/registry" \
  -v "$cache_root/cargo-git:/opt/cargo/git" \
  -v "$cache_root/cargo-target:/work/tools/release/work/android-container/cargo-target" \
  -v "$cache_root/gradle:/root/.gradle" \
  -v "$cache_root/pub:/opt/pub-cache" \
  -v "$cache_root/android-runtime:/root/.cache/operit-android-runtime" \
  -v "$cache_root/android-v8:/work/tools/release/work/android-v8" \
  -v "$cache_root/flutter:/work/apps/flutter/app/.fvm" \
  -e CARGO_HOME=/opt/cargo \
  -e CARGO_TARGET_DIR=/work/tools/release/work/android-container/cargo-target \
  -e RUSTUP_HOME=/opt/rustup \
  -e PUB_CACHE=/opt/pub-cache \
  -e OPERIT_LIBCLANG_DIR=/usr/lib/llvm-21/lib \
  -e OPERIT_ANDROID_V8_LLVM=/usr/lib/llvm-21 \
  -w /work \
  "$image" bash tools/android-container/build-inside.sh

cp -f "$repo_dir"/tools/release/dist/*.apk "$cache_root/dist/"
printf 'APK output:\n'
ls -lh "$repo_dir"/tools/release/dist/*.apk
