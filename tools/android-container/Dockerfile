FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    CARGO_HOME=/opt/cargo \
    RUSTUP_HOME=/opt/rustup \
    PUB_CACHE=/opt/pub-cache \
    FVM_HOME=/opt/fvm \
    OPERIT_LIBCLANG_DIR=/usr/lib/llvm-21/lib \
    OPERIT_ANDROID_V8_LLVM=/usr/lib/llvm-21 \
    PATH=/opt/flutter/bin:/opt/fvm/bin:/opt/pub-cache/bin:/opt/cargo/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/usr/lib/llvm-21/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash bison build-essential bzip2 ca-certificates clang cmake curl diffutils flex gawk git gnupg gzip \
      openjdk-17-jdk-headless lld ninja-build npm patch pkg-config python3 python3-pip python3-venv \
      software-properties-common tar unzip wget xz-utils zip \
    && wget -q https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && apt-get update && apt-get install -y --no-install-recommends powershell \
    && wget -qO- https://apt.llvm.org/llvm.sh | bash -s -- 21 \
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g typescript@5.9.3 \
    && corepack enable \
    && corepack prepare pnpm@10.7.0 --activate \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.95.0 \
    && /opt/cargo/bin/rustup target add aarch64-linux-android \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/android-sdk/cmdline-tools /tmp/android-tools \
    && curl -fL --retry 5 -o /tmp/android-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip \
    && unzip -q /tmp/android-tools.zip -d /tmp/android-tools \
    && mv /tmp/android-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "cmake;3.22.1" "ndk;28.2.13676358" "ndk;27.0.12077973" \
    && rm -rf /tmp/android-tools /tmp/android-tools.zip

RUN git clone --depth 1 --branch 3.41.10-ohos-0.0.2-beta.operit.9 https://github.com/AAswordman/flutter-ohos.git /opt/flutter \
    && flutter config --no-analytics \
    && flutter precache --android \
    && dart pub global activate fvm 4.3.0

WORKDIR /work
