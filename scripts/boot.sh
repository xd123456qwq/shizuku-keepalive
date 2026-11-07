#!/data/data/com.termux/files/usr/bin/sh
# 由 Termux:Boot 在开机时调用：耐心等 adbd 起来，然后切到 5555 并保活
export PATH=/data/data/com.termux/files/usr/bin:$PATH

mkdir -p "$HOME/.android"
if [ -r /sdcard/dsh/adbkey ]; then
  cp /sdcard/dsh/adbkey /sdcard/dsh/adbkey.pub "$HOME/.android/" 2>/dev/null
  chmod 600 "$HOME/.android/adbkey" 2>/dev/null
  export ADB_VENDOR_KEYS=/sdcard/dsh/adbkey
  KEY=ok
else
  KEY=missing
fi

LOG=$HOME/shizuku-boot.log
echo "$(date '+%F %T') boot hook start (key=$KEY)" >>"$LOG"

adb kill-server >/dev/null 2>&1
adb start-server >/dev/null 2>&1

i=0
while [ $i -lt 18 ]; do
  i=$((i+1))
  sleep 20

  adb connect 127.0.0.1:5555 >/dev/null 2>&1
  if adb -s 127.0.0.1:5555 shell true >/dev/null 2>&1; then
    echo "$(date '+%F %T') 5555 ready (try $i)" >>"$LOG"
    break
  fi

  for p in $(nmap -sT -Pn -n --open -T4 --min-rate 3000 -p 30000-50000 127.0.0.1 2>/dev/null \
             | awk '/open/{print $1}' | cut -d/ -f1); do
    adb connect "127.0.0.1:$p" >/dev/null 2>&1
    if adb -s "127.0.0.1:$p" shell true >/dev/null 2>&1; then
      echo "$(date '+%F %T') found adbd on $p (try $i)" >>"$LOG"
      adb -s "127.0.0.1:$p" tcpip 5555 >>"$LOG" 2>&1
      sleep 4
      adb connect 127.0.0.1:5555 >/dev/null 2>&1
      break
    fi
  done
done

if ! adb -s 127.0.0.1:5555 shell true >/dev/null 2>&1; then
  echo "$(date '+%F %T') channel FAILED - 请确认无线调试开着" >>"$LOG"
  exit 1
fi
echo "$(date '+%F %T') channel ok" >>"$LOG"

while true; do
  if ! adb -s 127.0.0.1:5555 shell "ps -A -o NAME | grep -q '^shizuku_server\$'" >/dev/null 2>&1; then
    echo "$(date '+%F %T') shizuku down -> restart" >>"$LOG"
    adb -s 127.0.0.1:5555 shell \
      "sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.sh" >>"$LOG" 2>&1
  fi
  sleep 15
done
