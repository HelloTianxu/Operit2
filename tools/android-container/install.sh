#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
adb="${ADB:-$repo_dir/../../../../default-workspace/tools/platform-tools/adb}"
apk="$(ls -t "$repo_dir"/tools/release/dist/operit2-app-android-arm64-v8a-*.apk | head -1)"
"$adb" devices -l
"$adb" install -r "$apk"
package="app.operit"
"$adb" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 || {
  package="$($adb shell pm list packages | tr -d '\r' | sed -n 's/^package:\(.*operit.*\)$/\1/p' | head -1)"
  "$adb" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1
}
echo "Installed and launched $package from $apk"
