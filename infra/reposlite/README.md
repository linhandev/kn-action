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

- `JAVA`：覆盖 Java 路径，默认 `/usr/lib/jvm/java-21-openjdk/bin/java`

## 以 systemd user 服务安装

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
