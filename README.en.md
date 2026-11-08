# Shizuku Keep-Alive

> Keep **Shizuku** running after screen lock on a **non-rooted** Android phone — no PC, no root, no re-pairing.

**English** · [简体中文](README.md)

[![Platform](https://img.shields.io/badge/platform-Android%2011%2B-3ddc84?logo=android&logoColor=white)](#requirements)
[![Root](https://img.shields.io/badge/root-not%20required-blue)](#how-it-works)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Language](https://img.shields.io/badge/lang-English-blue)](README.en.md)

---

## The problem

Shizuku started over **Wireless debugging** lives inside `adbd`'s shell session. Lock the screen, let the phone sleep, or drop Wi-Fi — the connection is cut and Shizuku exits at once:

```
不打扰模式（后台屏）用不了（Shizuku 未运行）
```

Most guides only tell you to disable battery optimization. That does not help — **the process is not killed by the battery manager, it is killed by the debugging connection dropping**.

## How it works

Two things:

1. **`adb tcpip 5555`** — restarts `adbd` in fixed TCP mode. `adbd` is a system daemon, so it survives screen lock and no longer depends on the Wireless debugging session.
2. **Two watchdogs** — one on the Android shell side, one inside Termux (or a Linux container). Each polls `shizuku_server` every 10–15 s and revives it with Shizuku's own `start.sh` if it is gone.

```
Termux adb ──┐
             ├── 127.0.0.1:5555 ── adbd ── shizuku_server
container  ──┘
             ↑ both watchdogs revive shizuku_server through this channel
```

## Measured results

OnePlus Ace 3 · ColorOS 16 (Android 15) · kernel 5.15.149

| Setup | 60–70 s after screen lock |
|---|---|
| Wireless-debugging port only | ❌ `adb devices` turns `offline`, Shizuku dies |
| **`tcpip 5555` + watchdogs** | ✅ connection alive, Shizuku alive |

Also verified:

- `kill -9 shizuku_server` → revived within 15 s
- `adb disconnect` → the Android-side watchdog **keeps running** (`PPID=1`)
- adb keys paired once stay valid across reboots, no re-pairing needed

## Requirements

| Item | Detail |
|---|---|
| Android | 11+ |
| Root | **not required** |
| Developer options | enabled |
| Wireless debugging | enabled (and must stay enabled) |
| Shizuku | installed, and started over Wireless debugging at least once |
| Client | Termux / proot container / a PC on the same network |

## Quick start

```sh
# 1. find adbd (the wireless-debugging port changes every boot)
nmap -sT -Pn -n --open -T4 -p 30000-50000 127.0.0.1

# 2. pair once for a new adb key
adb pair 127.0.0.1:<pair-port> <6-digit-code>
adb connect 127.0.0.1:<wireless-port>

# 3. switch to the fixed port — this is what fixes screen lock
adb -s 127.0.0.1:<wireless-port> tcpip 5555
sleep 3 && adb connect 127.0.0.1:5555

# 4. start Shizuku
adb -s 127.0.0.1:5555 shell \
  "sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.sh"

# 5. install the watchdog
adb -s 127.0.0.1:5555 push scripts/keep_shizuku.sh /data/local/tmp/
adb -s 127.0.0.1:5555 shell \
  "setsid sh -c 'nohup sh /data/local/tmp/keep_shizuku.sh >/dev/null 2>&1' </dev/null >/dev/null 2>&1 &"
```

Acceptance criteria for every step: **[docs/DEPLOY.md](docs/DEPLOY.md)** (Chinese).

### Already deployed? Just restart the service

Prerequisite: `android-tools` and `nmap` are installed in Termux, and the repo is at `~/shizuku-keepalive`.

```sh
nohup sh ~/shizuku-keepalive/scripts/boot.sh >/dev/null 2>&1 &
```

It does three things in order: scans the wireless-debugging port → `tcpip 5555` → starts Shizuku and keeps it alive.
Watch progress with `tail -f ~/shizuku-boot.log` (`channel ok` means it worked).

## Watchdog limitations

- **Android-side watchdog**: revives `shizuku_server` in about **15 s** after it is killed (checks every 10–15 s).
- **Termux-side watchdog**: only works while the adb connection is alive. **When the connection drops (screen lock, sleep, adb killed) it does not reconnect by itself** — recover manually:

  ```sh
  nohup sh ~/.termux/boot/01.sh >/dev/null 2>&1 &
  ```

  In other words: the Termux side heals the port, the Android side heals the process. Neither replaces the other.

## Dependencies and limitations

- Requires **`nmap` and `adb` in Termux** (`pkg install android-tools nmap`); same for a Linux container (`apt-get install android-tools-adb nmap`).
- On some devices **SELinux may block `adb tcpip`** (`inaccessible or not found`, or it just fails). Check it yourself: confirm USB debugging is authorized, check `getenforce`, and whether the vendor restricts changing the adb port.
- This project does not modify system partitions and does not persist any root privilege; the channel has to be re-established after a reboot.

## Known issues / troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `adb tcpip 5555` errors out or does nothing | SELinux / vendor restriction | check `getenforce`; re-authorize with a new key; some devices do not allow changing the port |
| No port found in 30000–50000 | Wireless debugging off, or scanning the wrong host | enable Wireless debugging; make sure you scan `127.0.0.1` |
| Port found but connection is `offline` | screen sleep dropped the connection | wake the screen, reconnect; for long-term stability always run `tcpip 5555` |
| **Termux:Boot does not run scripts** | Termux starts but the script never executes (likely signing/permission mismatch) | do not rely on it; run the command above after each reboot |
| **Deep sleep kills processes** | vendor battery policy freezes adb / Termux | disable battery optimization, allow background activity, turn off sleep standby optimization; it can still be frozen |
| `5555` disappears after reboot | `tcpip` is not persistent | see "Watchdog limitations" above |

## Repo layout

| Path | Purpose |
|---|---|
| `scripts/boot.sh` | Termux side: borrow the paired key → wait for adbd → switch to 5555 → keep-alive loop |
| `scripts/keep_shizuku.sh` | Android shell side watchdog, independent of Termux |
| `scripts/shizuku` | CLI: `start` / `restart` / `stop` / `status` / `watch` / `killwatch` / `log` / `adb` |
| `docs/DEPLOY.md` | Full deployment guide for a second device |
| `docs/TROUBLESHOOTING.md` | Symptom table + approaches that were tested and failed |
| `SKILL.md` | Skill file for AI agents (DSH format) |

## Who this is for

Situations where Shizuku is used for ADB-level access to do background / hidden-screen automation — for example the **non-disruptive mode** in dsh-go, which stops working the moment Shizuku dies.

## Disclaimer

Switching `adbd` to a fixed TCP port weakens the default security posture: `127.0.0.1:5555` stays open and any already-authorized adb client can connect. Only use it on a device you control, keep the key private, and close it when you no longer need it.

## License

[MIT](LICENSE)
