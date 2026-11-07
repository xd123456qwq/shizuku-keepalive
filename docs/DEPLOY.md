# 在第二台设备上部署

面向一台全新的 Android 手机。全程不需要 root，不需要电脑（有电脑更省事）。

## 0. 前提

| 项目 | 要求 |
|---|---|
| Android | 11 及以上（无线调试需要） |
| 开发者选项 | 已开启 |
| 无线调试 | 可用（「设置 → 系统与更新 → 开发者选项 → 无线调试」） |
| Shizuku | 已安装，**至少成功用无线调试启动过一次** |
| Termux | 已安装（F-Droid 或 GitHub 版；Play 商店版已停更） |
| 网络 | 手机与执行 adb 的一端在**同一台机器**（本方案走 127.0.0.1 回环） |

> 说明：本方案默认 adb 客户端就跑在手机自己的 Linux 环境里（Termux / proot 容器），所以用 `127.0.0.1`。如果你的 adb 在电脑上，请换成手机在局域网里的 IP，并先确认手机和电脑同网段。

## 1. 装工具

**Termux 里：**

```sh
pkg update -y && pkg install -y android-tools nmap
adb version      # 必须能打印版本号
```

> 如果报 `CANNOT LINK EXECUTABLE ... cannot locate symbol ...absl...`，说明 `android-tools` 与 `libabsl` 版本不匹配，跑 `pkg upgrade -y`，再跑 `pkg install -y --reinstall android-tools`。

**Linux 容器里（若也在容器侧操作）：**

```sh
apt-get update && apt-get install -y android-tools-adb nmap
```

## 2. 开无线调试，拿到端口

设置 → 系统与更新 → 开发者选项 → **无线调试** → 打开。

页面顶部会显示 `IP 地址和端口`，例如 `192.168.1.167:38981`。

**这个端口每次开机都变**，所以后面一律用扫描，不要写死：

```sh
nmap -sT -Pn -n --open -T4 -p 30000-50000 127.0.0.1
```

## 3. 第一次连接（客户端是新密钥时需要配对）

```sh
# 手机上点「使用配对码配对设备」，会显示 端口 + 6 位码
adb pair 127.0.0.1:<配对端口> <6位配对码>

# 然后连无线调试端口
adb connect 127.0.0.1:<无线调试端口>
adb devices
```

`adb devices` 显示 `device` 即为成功；显示 `unauthorized` 说明手机会弹「允许 USB 调试」，在屏幕上点**允许**（勾「一律允许」）。

> **配对/授权只需一次**，密钥存在手机上，重启后依然有效。

## 4. 切到固定端口 5555（关键一步）

```sh
adb -s 127.0.0.1:<无线调试端口> tcpip 5555
sleep 3
adb connect 127.0.0.1:5555
adb devices | grep 5555       # 应为 device
```

这一步之后，adbd 不再依赖无线调试连接，**锁屏不会断**。

## 5. 手动启动一次 Shizuku

```sh
adb -s 127.0.0.1:5555 shell \
  "sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.sh"
sleep 3
adb -s 127.0.0.1:5555 shell "ps -A -o NAME | grep '^shizuku_server$'"
```

看到 `shizuku_server` 即成功。

## 6. 部署安卓侧看门狗（不依赖 Termux / 任何 App）

```sh
adb -s 127.0.0.1:5555 push scripts/keep_shizuku.sh /data/local/tmp/keep_shizuku.sh
adb -s 127.0.0.1:5555 shell "chmod 755 /data/local/tmp/keep_shizuku.sh"
adb -s 127.0.0.1:5555 shell \
  "setsid sh -c 'nohup sh /data/local/tmp/keep_shizuku.sh >/dev/null 2>&1' </dev/null >/dev/null 2>&1 &"
sleep 2
adb -s 127.0.0.1:5555 shell "ps -A -o PPID,ARGS | grep keep_shizuku | grep -v grep"
```

**验收**：输出的 `PPID` 必须是 `1`。是 `1` 才代表进程已经脱离 adb 会话——这样即使 adb 断开、App 关闭，它依然活着。

## 7. 部署 Termux 侧自愈脚本

```sh
mkdir -p ~/.termux/boot
cp /sdcard/dsh/boot.sh ~/.termux/boot/01.sh     # 或自己用 curl 下载
chmod +x ~/.termux/boot/01.sh
```

`boot.sh` 干三件事：

1. 借用已配对密钥（见第 8 步）
2. 等 adbd 起来：先试 5555，不行就扫 30000-50000，找到后 `tcpip 5555`
3. 进入保活循环，每 15 秒检查一次 `shizuku_server`

日志写在 `~/shizuku-boot.log`。

## 8. 让 Termux 用上已配对的密钥（避开重启后重新配对）

Termux 自己的 adb 密钥默认只是「授权」过，重启后连无线端口会被拒。最省事的办法是**借用已经配对的密钥**：

```sh
# 在容器/已有授权的机器上
cp ~/.android/adbkey ~/.android/adbkey.pub /sdcard/dsh/
chmod 644 /sdcard/dsh/adbkey*

# boot.sh 里已经写了：
#   cp /sdcard/dsh/adbkey ~/.android/
#   export ADB_VENDOR_KEYS=/sdcard/dsh/adbkey
```

如果 Termux 读不到 `/sdcard`，先在 Termux 里跑一次 `termux-setup-storage` 授权存储。

> ⚠️ 这会把你已经配对的密钥复制到手机存储。**别把 `/sdcard/dsh/adbkey` 发给别人**，拿到它等于拿到你手机的 adb 授权。

## 9. 验收：锁屏测试

```sh
adb -s 127.0.0.1:5555 shell "input keyevent 26"   # 熄屏
sleep 70
adb devices | grep 5555                            # 应仍是 device
adb -s 127.0.0.1:5555 shell "ps -A -o NAME | grep '^shizuku_server$'"
adb -s 127.0.0.1:5555 shell "input keyevent 26"   # 唤醒
```

两项都在，即通过。

## 10. 重启之后（当前方案的缺口）

`adb tcpip 5555` **不持久**。重启后：

- `5555` 消失，adbd 回到无线调试的随机端口
- 看门狗进程也全部消失

**恢复方法：在 Termux 里跑一条命令**

```sh
nohup sh ~/.termux/boot/01.sh >/dev/null 2>&1 &
```

它会自己扫端口、切 5555、拉起 Shizuku、挂上看门狗。等 20~40 秒即可。

> 关于为什么没能做成全自动，见 `TROUBLESHOOTING.md` 的「Termux:Boot 不生效」一节。

## 11.（可选）接到 dsh-go 的不打扰模式

在 dsh-go：**设置 → 手机操控 → 进阶 → 不打扰模式 → 用 Shizuku**，授权并开启。

通道正常时，AI 就能在后台屏操作，不打断你使用手机。
