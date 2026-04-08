# ReposLite 本地依赖缓存

所有运行时文件（jar、本地 db、缓存包）都放在 `**workspace/**` 下，便于整目录备份或 rsync；仓库里只提交配置，启动脚本等

## 目录说明


| 路径                          | 说明                                                         |
| --------------------------- | ---------------------------------------------------------- |
| `configuration.shared.json` | 共享配置（`releases` Maven 聚合 + `distributions` Gradle zip 独立仓） |
| `start.sh`                  | 启动脚本，工作目录固定为 `workspace/`                                  |
| `workspace/reposilite.jar`  | 从 Release 下载后放到这里（勿提交）                                     |
| `workspace/reposilite.db`   | SQLite 库，自动生成或从旧实例拷贝                                       |
| `workspace/repositories/`   | Maven 缓存，自动生成或从旧实例拷贝                                       |
| `com.kmp.reposilite.plist`  | macOS launchd 配置模板（见下方 macOS 安装）                           |


## 首次 setup

1. 下载 jar：[https://github.com/dzikoysk/reposilite/releases](https://github.com/dzikoysk/reposilite/releases)
2. 创建目录并放入 jar：
  ```bash
   mkdir -p workspace
   mv reposilite-*.jar workspace/reposilite.jar
  ```
3. 启动：
  ```bash
   chmod +x start.sh
   ./start.sh
  ```

## 环境变量

- `JAVA`：覆盖 Java 路径。默认：Linux `/usr/lib/jvm/java-21-openjdk/bin/java`；若不存在则尝试 macOS Temurin `/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java`。

## 以 systemd user 服务安装（Linux）

```bash
# 1. 进入本目录
cd infra/reposlite   # 或你 clone 下来的 infra/reposlite 绝对路径

# 2. 安装 user 服务（把 REPOSILITE_DIR 替换成当前路径）
mkdir -p ~/.config/systemd/user
sed "s|REPOSILITE_DIR|$(pwd)|g" reposilite.service > ~/.config/systemd/user/reposilite.service

# 3. 重载并启用、启动
systemctl --user daemon-reload
systemctl --user enable reposilite
systemctl --user start reposilite
```

常用命令：

```bash
systemctl --user status reposilite   # 状态
systemctl --user stop reposilite
systemctl --user start reposilite
journalctl --user -u reposilite -f   # 看日志
```

## 以 launchd 服务安装（macOS）

以下命令请在**仓库根目录**下执行，且步骤 1 和 2 在同一终端中顺序执行（这样 `$(pwd)` 才是 reposlite 目录）。

1. **创建日志目录**（launchd 启动前需存在）：
  ```bash
   cd infra/reposlite
   mkdir -p workspace/logs
  ```
2. **安装 launchd 用户 agent**（将 `REPOSILITE_DIR` 替换为当前目录的绝对路径）：
  ```bash
   sed "s|REPOSILITE_DIR|$(pwd)|g" com.kmp.reposilite.plist > ~/Library/LaunchAgents/com.kmp.reposilite.plist
  ```
3. **加载并启动服务**（macOS 较新系统上请用 `bootstrap`，不要再用无 domain 的 `load`）：
  ```bash
   UIDN="$(id -u)"
   launchctl bootstrap "gui/$UIDN" ~/Library/LaunchAgents/com.kmp.reposilite.plist
  ```
   之后每次**用户登录**会自动加载并启动（plist 中 `RunAtLoad` 已开启），无需再手动操作。

常用命令（**务必带 `gui/$(id -u)/` 前缀**）：

```bash
UIDN="$(id -u)"
launchctl print "gui/$UIDN/com.kmp.reposilite"   # 是否在跑、路径、环境
launchctl kickstart -k "gui/$UIDN/com.kmp.reposilite"   # 强制重启进程（改配置后常用）
launchctl bootout "gui/$UIDN/com.kmp.reposilite"       # 停止并卸载该 job
launchctl bootstrap "gui/$UIDN" ~/Library/LaunchAgents/com.kmp.reposilite.plist  # 重新注册并启动
```

若 `launchctl unload ~/Library/LaunchAgents/...` / `load` 无效，多半是未在 `**gui/<你的 UID>**` 域下操作；按上面 `bootout` / `bootstrap` 即可。

**临时用 `./start.sh` 测试时**：先 `launchctl bootout "gui/$(id -u)/com.kmp.reposilite"` 释放 8080，再 `./start.sh`；结束后再 `bootstrap` 装回服务。

日志位置：`workspace/logs/reposilite-stdout.log`、`workspace/logs/reposilite-stderr.log`。

`start.sh` 默认找 Temurin 21 的 java；也可在 plist 的 `EnvironmentVariables` 中取消注释并设置 `JAVA` 为你的 `java` 可执行路径。

## 检查

```shell
wget http://localhost:8080/releases/org/apache/felix/maven-bundle-plugin/3.5.0/maven-bundle-plugin-3.5.0.pom
# Kotlin bootstrap（proxied `reference` 必须以 `/` 结尾，否则拼接会变成 …/maven/org/jetbrains/… 而 404）
wget -S -O /dev/null "http://localhost:8080/releases/org/jetbrains/kotlin/kotlin-stdlib-js/2.2.20-Beta2-71/kotlin-stdlib-js-2.2.20-Beta2-71.klib"
# Gradle distribution（路径必须是「文件名」这一层，不要再加 `distributions/`，否则会和 `downloads.gradle.org/distributions/` 拼成双重路径 404）
wget -S -O /dev/null "http://localhost:8080/distributions/gradle-8.5-bin.zip"
wget -S -O /dev/null "http://localhost:8080/distributions/gradle-8.14-bin.zip"
wget -S -O /dev/null "http://localhost:8080/distributions/gradle-8.5-bin.zip.sha256"
```

### `releases` 与 `distributions`（Gradle zip）

- `**releases**`：聚合 Maven 上游，供 `maven-proxy.init.gradle` 等使用（`/releases/...`）。
- `**distributions**`：Reposilite 仓库 id 与 URL 路径均为 `distributions`，与 `services.gradle.org/distributions/…` 一致，便于 CI 用 `sed` 只换主机。上游顺序为 `https://downloads.gradle.org/distributions/` 再 `https://mirrors.cloud.tencent.com/gradle/`。本地 URL：`/distributions/gradle-8.14-bin.zip`。不要拼成 `…/distributions/distributions/…`（双重路径 404）。不用 `services.gradle.org` 拉 zip（307 到 GitHub release，Reposilite 常失败）。
- **Reposilite 3.5.x**：对 proxied 仓库默认会拒绝 `.zip` / `.xml`（如 `maven-metadata.xml`），日志里为 `illegal EXTENSION`，对 zip 会表现为 **404**。因此 `configuration.shared.json` 里 `distributions` 的两条 proxied 都配置了 `**allowedExtensions`**（含 `.zip`、`.sha256`、`.xml` 等）。改完后必须**重启** Reposilite。某个版本**第一次**经代理拉取时，会边从上游下载边写入 `workspace/repositories/distributions/`，大 zip 可能要几分钟，`wget`/`curl` 会像卡住一样，属正常；缓存完成后再次请求会很快。

启动成功后日志中应出现 `+ releases (public)` 与 `+ distributions (public)`。若只有默认的 `snapshots` / `private`，说明未读到 `configuration.shared.json`（例如旧版 `start.sh` 在 `cd workspace` 后把相对路径指错；当前 `start.sh` 已用绝对路径传 `--shared-configuration`）。

**wget 仍 404 时**：先看 `workspace/logs` 里是否有 `illegal EXTENSION`（有则检查是否已更新配置并重启）；再确认启动段列出 `distributions`；最后在跑 Reposilite 的机器上执行 `curl -sSIL https://downloads.gradle.org/distributions/gradle-8.14-bin.zip | head` 与 `curl -sSIL https://mirrors.cloud.tencent.com/gradle/gradle-8.14-bin.zip | head`，确认 JVM/网络能访问至少一条上游。改完 `configuration.shared.json` 后需重启 Reposilite（例如 `launchctl kickstart -k "gui/$(id -u)/com.kmp.reposilite"`）。

**从 `gradle-distributions` 迁移**：将配置中的仓库 id 改为 `distributions` 并重启后，URL 由 `/gradle-distributions/…` 变为 `/distributions/…`；磁盘缓存目录由 `workspace/repositories/gradle-distributions` 变为 `workspace/repositories/distributions`（可迁移数据或重新预热）。

### Proxied 源 URL 必须以 `/` 结尾

Reposilite 把 artifact 路径拼到 `reference` 后面；若写成 `…/maven/bootstrap`（无末尾 `/`），按 RFC 3986 会**丢掉**最后一段 `bootstrap`，实际请求变成 `…/maven/org/jetbrains/…`，上游 404，而直接 `wget https://redirector.kotlinlang.org/maven/bootstrap/org/jetbrains/…` 仍正常。

- [https://maven.pkg.jetbrains.space/kotlin/p/kotlin/bootstrap/](https://maven.pkg.jetbrains.space/kotlin/p/kotlin/bootstrap/) : kotlin默认bootstrap版本
- [https://maven.eazytec-cloud.com/nexus/repository/maven-public/](https://maven.eazytec-cloud.com/nexus/repository/maven-public/) : cpf版本

