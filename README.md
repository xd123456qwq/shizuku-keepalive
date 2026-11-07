# Shizuku 免 root 保活

> 让 Android 手机上的 **Shizuku 锁屏后不再掉线** —— 不需要 root，不需要常连电脑，不用反复配对。

[English](README.en.md) · **简体中文**

[![Platform](https://img.shields.io/badge/platform-Android%2011%2B-3ddc84?logo=android&logoColor=white)](#前提条件)
[![Root](https://img.shields.io/badge/root-不需要-blue)](#怎么解决的)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Language](https://img.shields.io/badge/lang-简体中文-orange)](README.md)

---

## 问题出在哪

用「无线调试」方式启动的 Shizuku，服务进程挂在 `adbd` 的 shell 会话下。**一锁屏、一休眠、一断 Wi-Fi，连接被切，Shizuku 立刻退出**：

```
不打扰模式（后台屏）用不了（Shizuku 未运行）
```

网上绝大多数教程只教你关电池优化，但没用——**杀进程的不是电池管理，是调试连接断开**。

## 怎么解决的

两件事：

1. **`adb tcpip 5555`** —— 让 `adbd` 以固定 TCP 模式重启。`adbd` 是系统守护进程，锁屏不会停，也不再依赖无线调试会话。
2. **两个看门狗** —— 一个跑在安卓 shell 侧，一个跑在 Linux 容器/ Termux 里。每 10~15 秒查一次 `shizuku_server`，没了就用 Shizuku 自带的 `start.sh` 拉回来。

```
Termux adb ──┐
             ├── 127.0.0.1:5555 ── adbd ── shizuku_server
容器 adb   ──┘
             ↑ 两个看门狗都通过这条通道重启 shizuku_server
```

## 实测结果

一加 Ace 3 · ColorOS 16（Android 15）· 内核 5.15.149

| 方案 | 锁屏 60~70 秒后 |
|---|---|
| 只连无线调试端口 | ❌ `adb devices` 变 `offline`，Shizuku 死 |
| **`tcpip 5555` + 看门狗** | ✅ 连接存活，Shizuku 存活 |

另外验证过：

- `kill -9 shizuku_server` → 15 秒内自动复活
- `adb disconnect` → 安卓侧看门狗**照样活着**（`PPID=1`）
- 密钥配对一次后，重启依然有效，无需重新配对

## 前提条件

| 项目 | 要求 |
|---|---|
| Android | 11 及以上 |
| Root | **不需要** |
| 开发者选项 | 开启 |
| 无线调试 | 开启（且必须保持开启） |
| Shizuku | 已安装，并成功用无线调试启动过一次 |
| 客户端 | Termux / proot 容器 / 同网络的电脑 |

## 快速开始

```sh
# 1. 找 adbd（无线调试端口每次开机都变）
nmap -sT -Pn -n --open -T4 -p 30000-50000 127.0.0.1

# 2. 新密钥需要配对一次
adb pair 127.0.0.1:<配对端口> <6位码>
adb connect 127.0.0.1:<无线调试端口>

# 3. 切固定端口 —— 解决锁屏掉线的关键一步
adb -s 127.0.0.1:<无线调试端口> tcpip 5555
sleep 3 && adb connect 127.0.0.1:5555

# 4. 启动 Shizuku
adb -s 127.0.0.1:5555 shell \
  "sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.sh"

# 5. 挂看门狗
adb -s 127.0.0.1:5555 push scripts/keep_shizuku.sh /data/local/tmp/
adb -s 127.0.0.1:5555 shell \
  "setsid sh -c 'nohup sh /data/local/tmp/keep_shizuku.sh >/dev/null 2>&1' </dev/null >/dev/null 2>&1 &"
```

每一步的验收标准见 **[docs/DEPLOY.md](docs/DEPLOY.md)**。

## 已知限制

- **`tcpip` 重启后失效**：开机后 `adbd` 回到无线调试的随机端口。
- **Termux:Boot 开机自启实测未生效**：Termux 会被拉起，但启动脚本不执行，怀疑是 Termux 与 Termux:Boot 签名不一致。目前需要在重启后手动跑一条：

  ```sh
  nohup sh ~/.termux/boot/01.sh >/dev/null 2>&1 &
  ```

- 无线调试必须保持开启，否则重启后连端口都扫不到。
- 任何能读到已配对 adb 密钥的东西都能控制你的手机，密钥请当密码对待。

## 目录

| 路径 | 作用 |
|---|---|
| `scripts/boot.sh` | Termux 侧：借密钥 → 等 adbd → 切 5555 → 保活循环 |
| `scripts/keep_shizuku.sh` | 安卓 shell 侧看门狗，不依赖 Termux |
| `scripts/shizuku` | 命令行工具：`shizuku start / status / watch / log` |
| `docs/DEPLOY.md` | 第二台设备的完整部署步骤 |
| `docs/TROUBLESHOOTING.md` | 现象对照表 + 已验证失败的路子 |
| `SKILL.md` | 给 AI 代理用的技能文件（DSH 格式） |

## 适用场景

在用 Shizuku 拿到 ADB 级权限去做「后台/隐藏屏操作」的场景，例如 dsh-go 的**不打扰模式**——Shizuku 一死，后台屏立刻不可用。

## 免责声明

把 `adbd` 切到固定 TCP 端口会降低默认安全性：`127.0.0.1:5555` 会常开，任何已授权的 adb 客户端都能连。请只在自己的设备上使用，保护好密钥，不需要时关掉。

## License

[MIT](LICENSE)
