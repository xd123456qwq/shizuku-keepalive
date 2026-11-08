# Shizuku Keep-Alive

> Keep **Shizuku** running after screen lock on a **non-rooted** Android phone — no PC, no root, no re-pairing.

[![Platform](https://img.shields.io/badge/platform-Android%2011%2B-3ddc84?logo=android&logoColor=white)](#requirements)
[![Root](https://img.shields.io/badge/root-not%20required-blue)](#how-it-works)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-中文-orange)](README.md)
[![Language](https://img.shields.io/badge/lang-English-blue)](README.en.md)

---

## The problem

Shizuku started over **Wireless debugging** lives inside `adbd`'s shell session. Lock the screen, let the phone sleep, or drop Wi-Fi — and it dies:

```
不打扰模式（后台屏）用不了（Shizuku 未运行）
```

Every "keep Shizuku alive" guide tells you to disable battery optimization. That is not enough, because the process is killed by the **debugging connection dropping**, not by the battery manager.

## The fix

Two moving parts:

1. **`adb tcpip 5555`** — restart `adbd` in fixed TCP mode. `adbd` is a system daemon, so it survives screen lock and does not depend on Wireless debugging any more.
2. **Two watchdogs** — one in Android's shell, one inside a Linux container (Termux/proot). Each polls `shizuku_server` every 10–15 s and restarts it with Shizuku's own `start.sh` if it is gone.

```
Termux adb ──┐
             ├── 127.0.0.1:5555 ── adbd ── shizuku_server
container  ──┘
             ↑ both watchdogs revive shizuku_server through this channel
```

## Measured results

Tested on OnePlus Ace 3 · ColorOS 16 (Android 15) · kernel 5.15.149.

| Setup | 60–70 s after screen lock |
|---|---|
| Wireless-debugging port only | ❌ `adb devices` → `offline`, Shizuku dead |
| **`adb tcpip 5555` + watchdogs** | ✅ connection alive, Shizuku alive |

Also verified:

- `kill -9 shizuku_server` → revived within 15 s
- `adb disconnect` → the Android-side watchdog **survives** (`PPID=1`)
- adb keys paired once stay valid across reboots

## Requirements

| Item | Detail |
|---|---|
| Android | 11+ (Wireless debugging) |
| Root | **not required** |
| Developer options | enabled |
| Wireless debugging | enabled (must stay enabled) |
| Shizuku | installed, started over Wireless debugging at least once |
| Client | Termux, a proot container, or a PC on the same host/network |

## Quick start

```sh
# 1. find adbd (the wireless-debugging port changes every boot)
nmap -sT -Pn -n --open -T4 -p 30000-50000 127.0.0.1

# 2. pair once (only for a brand-new adb key)
adb pair 127.0.0.1:<pair-port> <6-digit-code>
adb connect 127.0.0.1:<wireless-port>

# 3. switch to the fixed port — this is the step that fixes screen lock
adb -s 127.0.0.1:<wireless-port> tcpip 5555
sleep 3 && adb connect 127.0.0.1:5555

# 4. start Shizuku
adb -s 127.0.0.1:5555 shell \
  "sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.sh"

# 5. keep it alive
adb -s 127.0.0.1:5555 push scripts/keep_shizuku.sh /data/local/tmp/
adb -s 127.0.0.1:5555 shell \
  "setsid sh -c 'nohup sh /data/local/tmp/keep_shizuku.sh >/dev/null 2>&1' </dev/null >/dev/null 2>&1 &"
```

Full step-by-step, including verification for every stage: **[docs/DEPLOY.md](docs/DEPLOY.md)** (Chinese).

## Watchdog limitations

- **Android-side watchdog**: revives `shizuku_server` in about **15 s** (checks every 10–15 s).
- **Termux-side watchdog**: only works while the adb connection is alive. When the connection drops it does **not** reconnect by itself — run `nohup sh ~/.termux/boot/01.sh >/dev/null 2>&1 &` to recover.
- The two cover different failures: Termux side heals the port, Android side heals the process.

## Dependencies

- Requires `nmap` and `adb` in Termux (`pkg install android-tools nmap`), or `android-tools-adb` + `nmap` in a Linux container.
- On some devices **SELinux may block `adb tcpip`** — check `getenforce`, re-authorize the adb key, or accept that the port cannot be changed.

## Known issues / troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `tcpip 5555` errors out or does nothing | SELinux / vendor restriction | check `getenforce`, re-authorize, try another path |
| No port found in 30000–50000 | Wireless debugging off, or scanning the wrong host | enable it, scan `127.0.0.1` |
| Port found but `offline` | Screen sleep dropped the connection | wake the screen, reconnect; always run `tcpip 5555` |
| **Termux:Boot does not run scripts** | script never executes (likely signing/permission) | do not rely on it; run one command after reboot |
| **Deep sleep kills processes** | vendor battery policy | disable battery optimization, allow background activity |

## Repo layout

| Path | Purpose |
|---|---|
| `scripts/boot.sh` | Termux side: borrow the paired key → wait for `adbd` → `tcpip 5555` → watchdog loop |
| `scripts/keep_shizuku.sh` | Android shell watchdog, independent of Termux/DSH |
| `scripts/shizuku` | CLI: `start` / `restart` / `stop` / `status` / `watch` / `killwatch` / `log` / `adb` |
| `docs/DEPLOY.md` | Full deployment guide with acceptance criteria per step |
| `docs/TROUBLESHOOTING.md` | Symptom → cause table, plus approaches that were tested and failed |
| `SKILL.md` | Ready-to-use skill file for AI agents (DSH format) |

## Who this is for

Anyone using Shizuku for ADB-level app features on a phone without root — for example, **non-disruptive (hidden-screen) automation** in [dsh-go](https://github.com/) or similar agent apps, where the background screen stops working the moment Shizuku dies.

## Disclaimer

Switching `adbd` to a fixed TCP port weakens the default security posture: the debugging port stays open on `127.0.0.1:5555` and any already-authorized adb client can connect. Use it on a device you control, keep the key private, and turn it off if you no longer need it.

## License

[MIT](LICENSE)
