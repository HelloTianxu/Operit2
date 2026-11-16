# Android 容器构建

本文是本地 Android APK 容器构建的**唯一权威来源**。CI 侧由
`.github/workflows/android-flutter-build.yml` 直接在 Ubuntu/Windows runner 上调用
`build_flutter_android.py`，不经过容器封装；两者共用同一套构建脚本，差异在签名材料、
rootfs 产物来源与缓存位置。

## 适用范围

- 目标平台：macOS 上的 OrbStack / Docker（`linux/amd64` 镜像，在 Apple Silicon 上经模拟运行）。
- 产物：`tools/release/dist/operit2-app-android-arm64-v8a-<release-version>.apk`。
- 不适用：iOS、OpenHarmony、CLI、Android 模块 ZIP；见 [BUILDING](../BUILDING.md) 对应章节。

## 入口

```bash
cd <Operit2 worktree>
tools/android-container/build.sh      # 构建 APK 并复制到 tools/release/dist/
tools/android-container/install.sh    # 安装最新产物并启动 app.operit
```

`build.sh` 会：

1. 校验或构建 `operit2-android-build:ubuntu24` 镜像（设置 `REBUILD_IMAGE=1` 强制重建）。
2. 以 `--platform linux/amd64` 启动一次性容器，挂载下文的缓存目录。
3. 把工作树打包进容器 `/work`（排除 `build`、`node_modules`、`.fvm`、`.venv` 等）。
4. 在容器内执行 `build-inside.sh`，完成插件打包、Rust 交叉编译与 Gradle `assembleRelease`。
5. 把 `tools/release/dist/*.apk` 复制回宿主。

`install.sh` 从 `tools/release/dist/` 取最新的 `operit2-app-android-arm64-v8a-*.apk`，
用 `adb install -r` 安装并启动；`ADB` 环境变量可覆盖 adb 路径。

## 缓存

缓存根目录默认为 `$HOME/android-dev/caches/android-container`，可用
`OPERIT_ANDROID_CONTAINER_CACHE` 指向别处。目录内容：

| 目录 | 内容 |
| --- | --- |
| `gradle` | Gradle 依赖与构建缓存 |
| `android-sdk` | Android SDK 与 NDK（版本由 Flutter 的 `flutter.ndkVersion` 决定） |
| `cargo-target` | Rust 桥接的编译产物 |
| `cargo-registry`、`cargo-git` | Cargo 下载缓存 |
| `android-v8` | 源码构建的 V8 归档与 GN 参数 |
| `android-runtime` | Android rootfs 与 NDK 构建工具 |
| `pub`、`fvm-cache`、`pnpm-store`、`flutter-cache` | Flutter/Dart/Node 工具链 |
| `downloads` | 其他一次性下载 |
| `fvp-android` | Android 虚拟机镜像 |
| `debug-keystore` | 其他项目（如 Shizuku 构建）复用的调试签名；本仓库不使用 |

产物不写进缓存：`build.sh` 把宿主工作树的 `tools/release/dist` 挂载为容器的
`/output-dist`，构建完成后直接复制回该目录。

这些目录位于工作树之外，因此**多个 worktree 和多个项目共享同一份缓存**。
删除它们只会导致重新下载，不会损坏工作树。

### 缓存链接

容器内通过符号链接把工作树里的路径接到缓存：

```text
/work/tools/release/work/android-v8            -> /cache/android-v8
/work/apps/flutter/native/operit-flutter-bridge/target -> /cache/cargo-target
/work/apps/flutter/app/.fvm/flutter_sdk        -> /opt/fvm-cache/versions/<pinned>
```

**手工复现容器构建时必须自己建立这三条链接。** 缺少 V8 链接会让
`prepare_android_v8.py` 认为缓存缺失，从而每次全量重编 V8（在模拟环境下可达一小时）；
缺少 `.fvm` 链接会让 Gradle 找不到 Flutter SDK。

### V8 缓存身份

`prepare_android_v8.py` 用配置清单和 SHA-256 校验缓存，身份包含 V8 版本、GN 参数与
`android_ndk_version`。NDK 由 Gradle 通过 `OPERIT_ANDROID_V8_NDK` 传入，取值为
`android.ndkDirectory`，因此**换 NDK 会让 V8 缓存失效并触发重编**。缓存命中时日志为
`Using verified V8 cache`；未命中为 `Building V8 <version> ... (first build takes time)`。

## 签名

容器构建使用**调试签名**：`build-inside.sh` 每次运行都会生成
`tools/release/work/android-container-debug.keystore`（如不存在）并**覆盖写入**
`tools/release/secrets/android-signing.properties`。

这意味着：

- 该文件在容器构建后指向调试 keystore，而不是正式发布 keystore；它已被
  `tools/release/.gitignore` 忽略。
- 调试签名密钥库保存在工作树的 `tools/release/work/android-container-debug.keystore`
  （已被 `tools/release/.gitignore` 忽略）。**删除 `tools/release/work/` 会导致签名变化**，
  届时必须先 `adb uninstall app.operit` 再安装，否则 `install -r` 会因签名不一致失败。
- 正式发布签名（`operit2-release.keystore`）只在 CI 或显式执行
  `build_flutter_android.py` 且未经过 `build-inside.sh` 时使用；见
  [BUILDING](../BUILDING.md) 的签名章节。

## 可调试构建

Android 的 release 构建类型设置了 `isDebuggable = true`，因此产物**可以**用
`adb run-as app.operit` 读取应用私有目录（`/data/user/0/app.operit`），无需 root。

**Dart 必须保持 AOT，这一点不是自动成立的。** Flutter 的 Gradle 插件用 Android 构建类型
推导 Dart 构建模式（`FlutterPluginUtils.buildModeFor`：构建类型可调试时返回 `debug`）。
只设置 `isDebuggable = true` 会让 Dart 编成 JIT 快照（`assets/flutter_assets/kernel_blob.bin`）
且不产出 `lib/<abi>/libapp.so`，而本 fork 只发布 release 引擎制品，于是 debug 字节码与
release 引擎不匹配，**应用一启动就崩溃**。

`app/build.gradle.kts` 因此在 release 任务上把 Flutter 构建模式钉回 `release`，用
`doFirst` 执行：配置期的赋值会被插件自己的赋值覆盖，而 `doFirst` 在所有配置动作之后、
任务读取该值之前运行。产物据此同时具备 AOT 与可调试。

由此产生三个必须知道的后果：

1. **APK 命名**：AGP 会把产物命名为 `app-arm64-v8a-debug.apk`（在
   `build/app/outputs/flutter-apk/`），而 Flutter 工具按 `--release` 查找
   `app-arm64-v8a-release.apk`，因此 `flutter build apk` 会以非零码退出。
   `build_flutter_android.py` 把该退出码视为提示，改为从
   `build/app/outputs/apk/release/app-arm64-v8a-release.apk` 取产物。
2. **AOT 校验**：`build_flutter_android.py` 在发布前要求 `lib/<abi>/libapp.so` 存在。
   缺失即失败，并提示是否携带了 JIT 的 `kernel_blob.bin`。此前只校验 rootfs 资产，
   因此 JIT 模式的包能通过验证、到设备上才崩溃。
3. **引擎制品**：`flutter-ohos-engine-maven` 只发布 release 引擎制品，而 debuggable 会让
   Flutter 的 Gradle 插件请求 `*_debug` 模块。`app/build.gradle.kts` 用依赖替换把这些模块
   指向对应的 `*_release`。**依赖替换只解决依赖解析，不决定 Dart 编译模式**；
   决定模式的是上文钉住的 `buildMode`。

**会话数据不需要 debuggable**：Operit2 的运行时状态位于共享存储
`/storage/emulated/0/Agent_run`，adb 可直接读取。debuggable 只用于访问
`/data/user/0/app.operit` 下的私有数据。

## Correction log

| 旧说法 | 出现位置 | 实际情况 |
| --- | --- | --- |
| "Dart 代码仍以 AOT 编译并做 tree-shaking" | 本文件"可调试构建" | 只设 `isDebuggable = true` 时 Flutter 按 `debug` 模式编译 Dart，产出 `kernel_blob.bin` 且无 `libapp.so`，与 release 引擎不匹配导致启动崩溃。AOT 依赖构建脚本钉住 `buildMode`，并非默认结果 |
| "Flutter 在 debuggable 下跳过图标字体子集化，`--tree-shake-icons` 不生效" | 本文件"可调试构建"第 2 条 | 钉住 `buildMode=release` 后字体子集化照常执行，日志出现 `Font asset ... was tree-shaken` |
| 发布前只校验 Android rootfs 资产 | 本文件"可调试构建" | JIT 模式的 APK 因此能通过验证；现已校验 `lib/<abi>/libapp.so` |

## 文件监视

`apps/flutter/app/android/gradle.properties` 设置了 `org.gradle.vfs.watch=false`。
构建过程会在 Gradle 运行期间把 Rust 产物与插件包写入源码树，文件监视会因此报
`File modified during build. Build must be rerun.` 并中断。关闭监视不影响增量构建，
增量状态仍由 Gradle 自己的缓存提供。

## 网络

构建期间会下载 models.dev 目录、V8 工具链（gn/ninja）与 ICU 数据。这些下载已带退避重试与
长度校验；网络不稳定时构建会重试而不是直接失败。

需要特定出口时：

```bash
OPERIT_USE_MBP_PROXY=1 tools/android-container/build.sh
```

该开关会以 `--network host` 启动容器并注入 SOCKS/HTTP 代理环境变量。代理本身由
`~/.local/bin/mbp-proxy` 管理。

## 排障

| 现象 | 原因与处理 |
| --- | --- |
| `run_network_args[@]: unbound variable` | 旧版脚本在 `set -u` 下展开空数组失败；已修复 |
| `IncompleteRead` 后构建失败 | 下载被截断；已加重试，仍失败则检查网络 |
| `Building V8 ... (first build takes time)` 反复出现 | V8 缓存未命中：检查 `android-v8` 链接与 NDK 版本 |
| `Gradle build failed to produce an .apk file` | debuggable 导致的命名差异；检查脚本是否为最新 |
| `File modified during build. Build must be rerun.` | 文件监视未关闭；检查 `gradle.properties` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 签名变化；先 `adb uninstall app.operit` |
| 构建卡在 `pnpm install` | 源码里带了宿主的 `node_modules`；确认打包时已排除 |

## 手工复现

需要保留容器检查产物时，按 `build.sh` 的挂载与链接方式启动容器，再执行
`build-inside.sh`。注意必须同时提供 `/host-repo`（宿主 `.git` 所在目录）挂载，
否则插件同步会因 `git ls-files` 失败而中止。
