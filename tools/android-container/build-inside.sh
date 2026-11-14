#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/flutter/bin:/opt/pub-cache/bin:/opt/cargo/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/usr/lib/llvm-21/bin:$PATH"
# Linux V8 host compilation intentionally uses Chromium's hermetic Clang.
# The system LLVM 21 installation remains the bindgen/libclang provider.
unset OPERIT_ANDROID_V8_LLVM

python3 -m venv .venv
dart pub global activate fvm 4.3.0 >/dev/null
export FVM_CACHE_PATH="${FVM_CACHE_PATH:-/opt/fvm-cache}"
flutter_version='3.41.10-ohos-0.0.2-beta.operit.9'
flutter_sdk="$FVM_CACHE_PATH/versions/$flutter_version"
if [[ ! -x "$flutter_sdk/bin/flutter" || ! -x "$flutter_sdk/bin/cache/dart-sdk/bin/dart" ]]; then
  (cd apps/flutter/app && fvm install --skip-pub-get)
fi
mkdir -p apps/flutter/app/.fvm
ln -sfn "$flutter_sdk" apps/flutter/app/.fvm/flutter_sdk
export OPERIT_SKIP_FVM_PREPARE=1
npm install --global typescript@5.9.3 >/dev/null
corepack enable
pnpm config set store-dir "${PNPM_STORE_DIR:-/opt/pnpm-store}"

mkdir -p apps/flutter/app/android/app/src/main/jniLibs/arm64-v8a
mkdir -p apps/flutter/app/android/app/src/main/assets/android-runtime/arm64-v8a
if [[ ! -s apps/flutter/app/android/app/src/main/assets/android-runtime/arm64-v8a/rootfs.tar.gz.bin ]]; then
  for attempt in 1 2 3 4 5; do
    if pwsh -NoProfile -File tools/android-runtime/fetch_sources.ps1; then break; fi
    [[ "$attempt" == 5 ]] && exit 1
    sleep $((attempt * 10))
  done
  if [[ ! -d "$HOME/.cache/operit-android-runtime/android-ndk-r29-beta4" ]]; then
    bash tools/android-runtime/fetch_ndk_wsl.sh
  fi
  export ANDROID_NDK_HOME="$HOME/.cache/operit-android-runtime/android-ndk-r29-beta4"
  bash tools/android-runtime/build_android_tools_wsl.sh
  bash tools/android-runtime/build_alpine_rootfs_wsl.sh
fi

cd plugins/packages/buildin/workflow
corepack pnpm install --frozen-lockfile --prefer-offline
cd /work

if [[ ! -f tools/release/work/android-container-debug.keystore ]]; then
  mkdir -p tools/release/work
  keytool -genkeypair -keystore tools/release/work/android-container-debug.keystore \
    -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
    -validity 10000 -dname 'CN=Android Debug,O=Android,C=US'
fi

mkdir -p tools/release/secrets
cat > tools/release/secrets/android-signing.properties <<EOF
RELEASE_STORE_FILE=$(pwd)/tools/release/work/android-container-debug.keystore
RELEASE_STORE_PASSWORD=android
RELEASE_KEY_ALIAS=androiddebugkey
RELEASE_KEY_PASSWORD=android
EOF

python3 tools/build_scripts/build_flutter_android.py --build-name 2.0.0 --build-number 41
