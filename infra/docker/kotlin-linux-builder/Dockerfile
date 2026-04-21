# Linux image for Kotlin OH builds (scripts/ci/kotlin-build.sh, Kotlin repo scripts/build-ohos.sh).
# JDKs: Zulu 8, Temurin 17 + 21. Only JAVA_HOME + JDK_18 in ENV; kotlin-build.sh prepends JAVA_HOME/bin to PATH. Symlinks: stable paths for auto-detect.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Single layer: base tools + both APT repos + all JDKs (faster rebuild cache when only later steps change).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg wget \
    git git-lfs openssh-client patch \
    build-essential unzip zip file \
 && curl -fsSL https://repos.azul.com/azul-repo.key \
    | gpg --dearmor -o /usr/share/keyrings/azul.gpg \
 && chmod 644 /usr/share/keyrings/azul.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/azul.gpg] https://repos.azul.com/zulu/deb stable main" \
    > /etc/apt/sources.list.d/zulu.list \
 && wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg \
 && chmod 644 /usr/share/keyrings/adoptium.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" \
    > /etc/apt/sources.list.d/adoptium.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends zulu8-jdk temurin-17-jdk temurin-21-jdk \
 && git lfs install \
 && rm -rf /var/lib/apt/lists/*

# APT uses names like temurin-21-jdk-amd64; kotlin-build.sh looks for temurin-21-amd64 / zulu-8. Symlinks bridge that (same idea on arm64).
RUN set -eux; \
    J21="$(find /usr/lib/jvm -maxdepth 1 -type d -name 'temurin-21-*' | sort | head -1)"; \
    J17="$(find /usr/lib/jvm -maxdepth 1 -type d -name 'temurin-17-*' | sort | head -1)"; \
    Z8="$(find /usr/lib/jvm -maxdepth 1 -type d \( -name 'zulu8-*' -o -name 'zulu-8*' \) | sort | head -1)"; \
    test -n "$J21" && test -x "$J21/bin/java"; \
    test -n "$J17" && test -x "$J17/bin/java"; \
    test -n "$Z8" && test -x "$Z8/bin/java"; \
    ln -sfn "$J21" /usr/lib/jvm/temurin-21-amd64; \
    ln -sfn "$J17" /usr/lib/jvm/temurin-17-amd64; \
    ln -sfn "$Z8" /usr/lib/jvm/zulu-8

ENV JAVA_HOME=/usr/lib/jvm/temurin-21-amd64 \
    JDK_18=/usr/lib/jvm/zulu-8

WORKDIR /workspace
CMD ["/bin/bash"]
