# ReposLite 本地依赖缓存

所有运行时文件（jar、本地 db、缓存包）都放在 **`workspace/`** 下，便于整目录备份或 rsync；仓库里只提交配置，启动脚本等

## 目录说明

| 路径 | 说明 |
|------|------|
| `configuration.shared.json` | 共享配置（代理源等），可提交 |
| `start.sh` | 启动脚本，工作目录固定为 `workspace/` |
| `workspace/reposilite.jar` | 从 Release 下载后放到这里（勿提交） |
| `workspace/reposilite.db` | SQLite 库，自动生成或从旧实例拷贝 |
| `workspace/repositories/` | Maven 缓存，自动生成或从旧实例拷贝 |
| `com.kmp.reposilite.plist` | macOS launchd 配置模板（见下方 macOS 安装） |

## 首次 setup

1. 下载 jar：<https://github.com/dzikoysk/reposilite/releases>
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

1. **创建日志目录**（launchd 启动前需存在）：
   ```bash
   cd infra/reposlite
   mkdir -p workspace/logs
   ```

2. **安装 launchd 用户 agent**（将 `REPOSILITE_DIR` 替换为当前目录的绝对路径）：
   ```bash
   sed "s|REPOSILITE_DIR|$(pwd)|g" com.kmp.reposilite.plist > ~/Library/LaunchAgents/com.kmp.reposilite.plist
   ```

3. **加载并启动服务**：
   ```bash
   launchctl load ~/Library/LaunchAgents/com.kmp.reposilite.plist
   launchctl start com.kmp.reposilite
   ```
   之后每次**用户登录**会自动加载并启动（plist 中 `RunAtLoad` 已开启），无需再手动操作。

常用命令：

```bash
launchctl list com.kmp.reposilite   # 状态
launchctl stop com.kmp.reposilite
launchctl start com.kmp.reposilite
# 卸载：launchctl unload ~/Library/LaunchAgents/com.kmp.reposilite.plist
```

日志位置：`workspace/logs/reposilite-stdout.log`、`workspace/logs/reposilite-stderr.log`。

`start.sh` 默认找 Temurin 21 的 java；也可在 plist 的 `EnvironmentVariables` 中取消注释并设置 `JAVA` 为你的 `java` 可执行路径。

## 检查

```shell
wget http://localhost:8080/releases/org/apache/felix/maven-bundle-plugin/3.5.0/maven-bundle-plugin-3.5.0.pom
```
