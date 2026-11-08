> **给 AI 代理的技能说明。** 用户提到「Shizuku 锁屏掉线」「免 root 保活」「Termux 部署」时加载本技能，按里面的步骤执行，不要凭感觉试。

---
name: shizuku-keepalive
description: 在免 root 的 Android 手机上让 Shizuku 长时间存活：用 adb tcpip 把 adbd 切到固定端口 5555（锁屏不断）、在安卓侧和容器侧各挂一个看门狗自动重启 shizuku_server、用 Termux 的 adb 做外部触发、并记录重启后恢复的方法。用户说「Shizuku 锁屏就停」「后台模式用不了」「不打扰模式掉线」「想让 Shizuku 一直活着」时用它。Keep Shizuku alive on a non-rooted Android phone without a PC.
whenToUse: 用户抱怨 Shizuku 服务停止、锁屏后不可用、dsh-go 不打扰模式掉线，或者要给第二台设备复刻这套保活方案时。不用于内核漏洞提权，也不是 root 方案。
---

# Shizuku 免 root 保活

## 这个技能解决什么

Shizuku 用「无线调试」方式启动时，进程挂在 `adbd` 的 shell 会话下。**锁屏 / 断 Wi-Fi / 连接断开，Shizuku 就一起死**，`dsh-go` 的不打扰模式随即失效。

核心结论（已实测）：

- 用 `adb tcpip 5555` 把 adbd 切成**固定 TCP 端口**后，锁屏 70 秒连接仍在、Shizuku 存活。
- 只用无线调试端口连（不切 tcpip），锁屏 60 秒连接直接 `offline`，Shizuku 死。
- 所以 **tcpip 是必需品**，不是可选项。

## 架构

```
┌─ Termux (u0_aXXX) ──────────┐
│  adb (android-tools)        │
│  借用已配对密钥 → 连 5555    │
│  boot.sh / shizuku CLI      │
└──────────┬──────────────────┘
           │ 127.0.0.1:5555
┌──────────▼──────────────────┐
│  adbd (shell, 系统守护)      │   ← 锁屏不断，重启后消失
│    └─ shizuku_server        │
└──────────▲──────────────────┘
           │ 同一个通道
┌──────────┴──────────────────┐
│  DSH 容器 / 任意 shell 脚本  │
│  keep_shizuku.sh (看门狗)    │
└─────────────────────────────┘
```

两个看门狗互相兜底：每 10~15 秒 `ps | grep shizuku_server`，没了就调 Shizuku 自带的 `start.sh` 拉起来。

## 关键命令

```sh
# 1. 找到 adbd（无线调试端口每次开机随机）
nmap -sT -Pn -n --open -T4 -p 30000-50000 127.0.0.1

# 2. 连上并切到固定端口
adb connect 127.0.0.1:<port>
adb -s 127.0.0.1:<port> tcpip 5555
adb connect 127.0.0.1:5555

# 3. 启动 Shizuku（start.sh 由 Shizuku App 生成）
adb -s 127.0.0.1:5555 shell \
  "sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.sh"

# 4. 检查
adb -s 127.0.0.1:5555 shell "ps -A -o NAME | grep '^shizuku_server$'"
```

## 部署步骤（第二台设备）

见 `docs/DEPLOY.md`，按顺序做，每步都有验收标准。

## 双看门狗的限制

- **安卓侧看门狗**：`shizuku_server` 被杀后约 **15 秒**复活（每 10~15 秒检查一次）。
- **Termux 侧看门狗**：只在 adb 连接正常时有效，**连接断开不会自动重连**，需要手动跑 `nohup sh ~/.termux/boot/01.sh >/dev/null 2>&1 &` 恢复。
- 两者是分工关系：Termux 侧管端口自愈，安卓侧管进程自愈。

## 依赖与限制

- 依赖 Termux 中的 `nmap` 和 `adb`；容器侧为 `android-tools-adb` + `nmap`。
- 部分设备 **SELinux 可能阻止 `adb tcpip`**，需要自行排查（`getenforce`、重新授权密钥、厂商限制）。
- 无线调试开关必须保持开启，否则重启后扫不到端口。
- 密钥配对/授权一次后持久有效，重启不需要重新配对。
- `adb tcpip 5555` 不持久，**重启后必须重做一次**。

## 已知限制 / 排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `tcpip 5555` 报错/无效 | SELinux 或厂商限制 | `getenforce`；重新授权；换连接方式 |
| 扫不到端口 | 无线调试未开 / 扫描目标不对 | 打开无线调试；扫 `127.0.0.1` |
| 端口扫到但 `offline` | 屏幕休眠断开 | 唤醒后重连；必须做 `tcpip 5555` |
| **Termux:Boot 不生效** | 脚本不执行（疑似签名/权限） | 不依赖它，重启后手动跑一条命令 |
| **深度休眠杀进程** | 厂商省电策略 | 关电池优化、允许后台活动、关睡眠待机优化；仍可能被冻结 |

## 排障顺序

1. `adb devices` 有没有 5555
2. 没有 → `nmap` 扫 30000-50000 找无线调试端口
3. 扫不到 → 无线调试开关是不是关了（这是最常见的原因）
4. 连上但 `unauthorized` → 屏幕上点「允许 USB 调试」
5. 连上且 `device` 但 Shizuku 没跑 → 跑 `start.sh`
6. 跑完立刻又死 → 看门狗被系统冻结（电池优化）

详细现象对照见 `docs/TROUBLESHOOTING.md`。
