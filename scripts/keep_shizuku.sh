#!/system/bin/sh
# 安卓侧 Shizuku 保活（跑在 shell 用户下，不依赖 DSH Go）
LOG=/data/local/tmp/keep_shizuku.log
START=/storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.sh

while true; do
  if ! pgrep -f shizuku_server >/dev/null 2>&1; then
    echo "$(date '+%F %T') shizuku down -> restart" >>"$LOG"
    sh "$START" >>"$LOG" 2>&1
  fi
  sleep 15
done
