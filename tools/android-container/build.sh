#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
git_common_dir="$(git -C "$repo_dir" rev-parse --git-common-dir)"
host_repo_dir="$(cd "$git_common_dir/.." && pwd)"
image="operit2-android-build:ubuntu24"
# Caches live outside the worktree so every project and every worktree reuses
# the same downloaded toolchains, SDKs and compiled dependencies.
cache_root="${OPERIT_ANDROID_CONTAINER_CACHE:-$HOME/android-dev/caches/android-container}"
mkdir -p "$cache_root"/{cargo-registry,cargo-git,cargo-target,gradle,pub,fvm-cache,pnpm-store,flutter-cache,android-sdk,android-runtime,android-v8,fvp-android,downloads,dist}

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
run_network_args=()
run_proxy_env=()
if [[ "${OPERIT_USE_MBP_PROXY:-0}" == 1 ]]; then
  "$HOME/.local/bin/mbp-proxy" on >/dev/null
  run_network_args=(--network host)
  run_proxy_env=(-e 'ALL_PROXY=socks5h://127.0.0.1:17890' -e 'HTTPS_PROXY=http://127.0.0.1:17891' -e 'HTTP_PROXY=http://127.0.0.1:17891' -e 'NO_PROXY=localhost,127.0.0.1,::1')
fi

container_name="operit2-android-build-$$"
# Stop the container as well as the docker client when this script is cancelled.
cleanup_container() {
  if "$runtime" container inspect "$container_name" >/dev/null 2>&1; then
    "$runtime" stop --timeout 10 "$container_name" >/dev/null 2>&1 || true
  fi
}
trap cleanup_container EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$runtime" run --rm --name "$container_name" --platform linux/amd64 "${run_network_args[@]}" \
  -v "$repo_dir:$source_root:ro" \
  -v "$host_repo_dir:/host-repo:ro" \
  -v "$repo_dir/tools/release/dist:/output-dist" \
  -v "$cache_root/cargo-registry:/opt/cargo/registry" \
  -v "$cache_root/cargo-git:/opt/cargo/git" \
  -v "$cache_root/cargo-target:/cache/cargo-target" \
  -v "$cache_root/gradle:/root/.gradle" \
  -v "$cache_root/pub:/opt/pub-cache" \
  -v "$cache_root/fvm-cache:/opt/fvm-cache" \
  -v "$cache_root/pnpm-store:/opt/pnpm-store" \
  -v "$cache_root/flutter-cache:/opt/flutter-cache" \
  -v "$cache_root/android-sdk:/opt/android-sdk" \
  -v "$cache_root/android-runtime:/root/.cache/operit-android-runtime" \
  -v "$cache_root/android-v8:/cache/android-v8" \
  -v "$cache_root/fvp-android:/cache/fvp-android" \
  -v "$cache_root/downloads:/root/.cache/operit-downloads" \
  -e CI=true \
  -e COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
  "${run_proxy_env[@]}" \
  -e CARGO_HOME=/opt/cargo \
  -e CARGO_TARGET_DIR=/cache/cargo-target \
  -e RUSTUP_HOME=/opt/rustup \
  -e PUB_CACHE=/opt/pub-cache \
  -e FVM_CACHE_PATH=/opt/fvm-cache \
  -e PNPM_HOME=/opt/pnpm-home \
  -e PNPM_STORE_DIR=/opt/pnpm-store \
  -e OPERIT_FLUTTER_CACHE=/opt/flutter-cache \
  -e OPERIT_LIBCLANG_DIR=/usr/lib/llvm-21/lib \
  -w /tmp \
  "$image" bash -lc '
    set -eo pipefail
    # Shared package caches may be mutated by native plugin builds: serialize runs.
    exec 9>/cache/android-v8/container-build.lock
    flock -n 9 || { echo "Another Android build holds the shared cache lock" >&2; exit 75; }
    test "$(realpath -m /work)" = /work && test ! -L /work
    rm -rf /work
    mkdir -p /work
    # tar exits 1 when a source file changes while it is being read (the host
    # repo keeps its build outputs and caches live); only exit 2+ is fatal.
    set +e
    tar -C /tmp/operit2-android-source \
      --exclude=.dart_tool --exclude=build --exclude=node_modules --exclude="*/node_modules" \
      --exclude=.pnpm-store --exclude="*/.pnpm-store" --exclude=.fvm \
      --exclude=.venv --exclude="*/.venv" \
      -cf - . | tar -C /work -xf -
    copy_status=("${PIPESTATUS[@]}")
    set -e
    if (( copy_status[0] > 1 || copy_status[1] > 1 )); then
      echo "Source copy failed: tar producer=${copy_status[0]} consumer=${copy_status[1]}" >&2
      exit 1
    fi
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
    mkdir -p /work/apps/flutter/app/.fvm /opt/fvm-cache /cache/android-v8
    ln -sfn /opt/fvm-cache/versions/3.41.10-ohos-0.0.2-beta.operit.9 /work/apps/flutter/app/.fvm/flutter_sdk
    mkdir -p /work/tools/release/work /work/apps/flutter/native/operit-flutter-bridge
    ln -s /cache/android-v8 /work/tools/release/work/android-v8
    rm -rf /work/apps/flutter/native/operit-flutter-bridge/target
    ln -s /cache/cargo-target /work/apps/flutter/native/operit-flutter-bridge/target
    cd /work
    build_status=0
    bash tools/android-container/build-inside.sh || build_status=$?
    if compgen -G "tools/release/dist/*.apk" >/dev/null; then
      cp -f tools/release/dist/*.apk /output-dist/
    fi
    exit "$build_status"
  '

printf 'APK output:\n'
ls -lh "$repo_dir"/tools/release/dist/*.apk
