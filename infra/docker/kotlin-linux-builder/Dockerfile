# Linux image for Kotlin OH builds (scripts/ci/kotlin-build.sh, Kotlin repo scripts/build-ohos.sh).
# JDKs match .github/workflows/build-kotlin.yml on Linux runners:
#   - Java 8:  Zulu (setup-java distribution zulu)
#   - Java 17: Eclipse Temurin
#   - Java 21: Eclipse Temurin (last setup-java on GHA Linux → default java for Gradle)
#
# kotlin-build.sh looks for /usr/lib/jvm/temurin-21-amd64 and /usr/lib/jvm/zulu-8; Apt uses
# different directory names, so we symlink those canonical paths after install.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg wget \
    git openssh-client patch \
    build-essential unzip zip file \
 && rm -rf /var/lib/apt/lists/*

# Azul Zulu 8 (same distribution as GitHub Actions setup-java for java-version 8)
RUN curl -fsSL https://repos.azul.com/azul-repo.key \
    | gpg --dearmor -o /usr/share/keyrings/azul.gpg \
 && chmod 644 /usr/share/keyrings/azul.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/azul.gpg] https://repos.azul.com/zulu/deb stable main" \
    > /etc/apt/sources.list.d/zulu.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends zulu8-jdk \
 && rm -rf /var/lib/apt/lists/*

# Eclipse Temurin 17 + 21 (same distribution as GitHub Actions for those versions on Linux)
RUN wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg \
 && chmod 644 /usr/share/keyrings/adoptium.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" \
    > /etc/apt/sources.list.d/adoptium.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends temurin-17-jdk temurin-21-jdk \
 && rm -rf /var/lib/apt/lists/*

# Canonical paths for kotlin-build.sh + default java = Temurin 21 (GHA order)
RUN set -eux; \
    J21="$(find /usr/lib/jvm -maxdepth 1 -type d -name 'temurin-21-*' | sort | head -1)"; \
    J17="$(find /usr/lib/jvm -maxdepth 1 -type d -name 'temurin-17-*' | sort | head -1)"; \
    Z8="$(find /usr/lib/jvm -maxdepth 1 -type d \( -name 'zulu8-*' -o -name 'zulu-8*' \) | sort | head -1)"; \
    test -n "$J21" && test -x "$J21/bin/java"; \
    test -n "$J17" && test -x "$J17/bin/java"; \
    test -n "$Z8" && test -x "$Z8/bin/java"; \
    ln -sfn "$J21" /usr/lib/jvm/temurin-21-amd64; \
    ln -sfn "$Z8" /usr/lib/jvm/zulu-8

ENV JAVA_HOME=/usr/lib/jvm/temurin-21-amd64
ENV JDK_18=/usr/lib/jvm/zulu-8
ENV PATH="${JAVA_HOME}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

WORKDIR /workspace
CMD ["/bin/bash"]
