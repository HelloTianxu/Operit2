#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
git_common_dir="$(git -C "$repo_dir" rev-parse --git-common-dir)"
host_repo_dir="$(cd "$git_common_dir/.." && pwd)"
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

source_root="/tmp/operit2-android-source"
"$runtime" run --rm --platform linux/amd64 \
  -v "$repo_dir:$source_root:ro" \
  -v "$host_repo_dir:/host-repo:ro" \
  -v "$repo_dir/tools/release/dist:/output-dist" \
  -v "$cache_root/cargo-registry:/opt/cargo/registry" \
  -v "$cache_root/cargo-git:/opt/cargo/git" \
  -v "$cache_root/cargo-target:/cache/cargo-target" \
  -v "$cache_root/gradle:/root/.gradle" \
  -v "$cache_root/pub:/opt/pub-cache" \
  -v "$cache_root/android-runtime:/root/.cache/operit-android-runtime" \
  -v "$cache_root/android-v8:/cache/android-v8" \
  -v "$cache_root/flutter:/cache/fvm" \
  -e CARGO_HOME=/opt/cargo \
  -e CARGO_TARGET_DIR=/cache/cargo-target \
  -e RUSTUP_HOME=/opt/rustup \
  -e PUB_CACHE=/opt/pub-cache \
  -e OPERIT_LIBCLANG_DIR=/usr/lib/llvm-21/lib \
  -e OPERIT_ANDROID_V8_LLVM=/usr/lib/llvm-21 \
  -w /tmp \
  "$image" bash -lc '
    rm -rf /work
    cp -a /tmp/operit2-android-source /work
    host_git_dir=$(sed -n "s/^gitdir: //p" /work/.git)
    git_common=/host-repo/.git
    worktree_name=$(basename "$host_git_dir")
    mkdir -p /work/.git-container/worktrees
    cp -a "$git_common"/objects /work/.git-container/
    cp -a "$git_common"/refs /work/.git-container/
    cp -a "$git_common"/HEAD "$git_common"/config "$git_common"/packed-refs /work/.git-container/ 2>/dev/null || true
    cp -a "$git_common"/worktrees/"$worktree_name" /work/.git-container/worktrees/
    printf "gitdir: /work/.git-container/worktrees/%s\n" "$worktree_name" > /work/.git
    printf "/work/.git-container\n" > /work/.git-container/worktrees/"$worktree_name"/commondir
    printf "/work/.git\n" > /work/.git-container/worktrees/"$worktree_name"/gitdir
    rm -rf /work/apps/flutter/app/.fvm /work/tools/release/work/android-v8
    ln -s /cache/fvm /work/apps/flutter/app/.fvm
    mkdir -p /work/tools/release/work
    ln -s /cache/android-v8 /work/tools/release/work/android-v8
    cd /work
    bash tools/android-container/build-inside.sh
    cp -f tools/release/dist/*.apk /output-dist/
  '

printf 'APK output:\n'
ls -lh "$repo_dir"/tools/release/dist/*.apk
