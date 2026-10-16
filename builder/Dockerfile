# syntax=docker/dockerfile:1
# Toolchain for building the T3 Code Android APK from upstream source.
# Pinned SDK packages match what upstream's Expo/React Native versions ask for; when
# upstream bumps them, AGP downloads the missing package at build time (slower, still
# green) and the build log names it — bump the list below then.
FROM eclipse-temurin:17-jdk-noble

ARG NODE_MAJOR=24
ARG CMDLINE_TOOLS=13114758
ARG ANDROID_PACKAGES="platform-tools platforms;android-36 build-tools;36.0.0 ndk;27.1.12297006 cmake;3.22.1"

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0
ENV PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils python3 build-essential \
    && curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip" \
    && unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager --install $ANDROID_PACKAGES >/dev/null \
    && chmod -R a+rwX "$ANDROID_HOME"
