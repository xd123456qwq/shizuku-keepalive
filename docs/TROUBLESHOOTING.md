# 排障与踩坑记录

这份文档记录**实际试过的现象**，包括失败的路子，方便下次少走弯路。

## 现象对照表

| 现象 | 原因 | 处理 |
|---|---|---|
| `adb devices` 里什么都没有 | adbd 没监听（常见：无线调试开关关了 / 重启后未恢复） | 开无线调试；`nmap` 扫 30000-50000 |
| `127.0.0.1:xxxx unauthorized` | 客户端密钥没被授权 | 看手机屏幕，点「允许 USB 调试」，勾「一律允许」 |
| `failed to authenticate` | 连的是无线调试 TLS 端口，但密钥没配对过 | `adb pair` 走一次配对，或借用已配对密钥 |
| `protocol fault (couldn't read status message)` | 配对码过期 / 配对弹窗被切到后台关闭 | 重新点开配对弹窗，**别切窗口**，尽快在 6 位码有效期内执行 |
| 锁屏后 `offline`，Shizuku 死 | 没做 `adb tcpip 5555` | 见 DEPLOY.md 第 4 步 |
| 5555 通了但 Shizuku 立刻又没了 | 看门狗没起 / 被电池优化冻结 | 检查 `ps -A -o NAME \| grep shizuku_server`；关电池优化 |
| 重启后 5555 连不上 | `tcpip` 不持久 | Termux 跑 `nohup sh ~/.termux/boot/01.sh &` |
| `ps` 里 `keep_shizuku` 的 PPID 不是 1 | 启动方式没脱离 adb 会话 | 用 `setsid ... &`，确认 PPID=1 |

## 已验证失败 / 不可行的路

### 1. Termux:Boot 不生效

- 现象：重启后 Termux 进程被拉起（`ps -A | grep com.termux` 有结果），但 `~/shizuku-boot.log` 没有新的 `boot hook start` 记录，脚本没执行。
- 试过：Termux:Boot（GitHub 版 `termux-boot-app_v0.8.1+github.debug.apk`，adb 安装成功）、脚本放 `~/.termux/boot/01.sh`、`chmod +x`。
- 怀疑：Termux 与 Termux:Boot 签名不一致（F-Droid 版 vs GitHub debug 版），`com.termux.permission.RUN_COMMAND` 被拒。
- 结论：**暂不可靠，按「重启后手动一条命令」使用**。若要继续攻，方向是从同源（都从 F-Droid 或都从 GitHub）安装 Termux 与 Termux:Boot。

### 2. 只连无线调试端口（不切 tcpip）

- 实测：锁屏 60 秒后 `adb devices` 变 `offline`，`shizuku_server` 消失。
- 结论：无线调试连接会随屏幕休眠断掉，**必须切 tcpip**。

### 3. 用 adb `input text` / `input tap` 往 Termux 里打字

- 现象：无任何效果，命令没执行。
- 原因：Termux 终端是自绘 View，不是输入框；且手机前台可能被其他悬浮窗覆盖，输入事件打不到。
- 结论：**需要用户手动粘贴命令**，或用 `expore ADB_VENDOR_KEYS` 之类无需交互的方案。

### 4. aShell You 之类的终端 App 读输出

- 现象：能执行，但终端内容不进无障碍树，AI 读不到结果。
- 结论：要拿输出就让命令写文件到 `/sdcard`，再读文件。

### 5. `pkill -f 'termux/boot/01.sh'`

- 现象：终端"卡住"很久。
- 原因：`pkill -f` 匹配到了**正在执行这条命令的 shell 自己**，把自己杀了。
- 结论：别用 `pkill -f <自己命令行里出现的字符串>`；改用精确 PID 或换命令。

### 6. 幽灵锁（GhostLock，CVE-2026-43499）临时提权

与本方案无关，但同期试过，记录在此避免重复投入：

- 5 次尝试全部死在同一步：`[route] route_done success=1` → `native exited code=1` → `Write 1 failed`。
- 前面的 heap spray、futex 碰撞、`selinux_state` 页定位、PI 路由都过了，**卡在最后写内核那一下**。
- 本机内核串与工具 profile 完全一致（`5.15.149-android13-8-o-01126-ge3f5c81edd77`），所以不是版本对不上。
- 仓库 `YuKongA/ghostlock-app` 主分支没有该机型/内核的 profile，新提交基本是加别的机型。
- 结论：这台机器上此路不通，放弃。

## 日志位置

| 日志 | 路径 |
|---|---|
| Termux 侧启动 / 保活 | `~/shizuku-boot.log` |
| 安卓侧看门狗 | `/data/local/tmp/keep_shizuku.log` |
| 容器侧看门狗 | `~/.dsh/shizuku-watchdog.log`（默认路径） |
