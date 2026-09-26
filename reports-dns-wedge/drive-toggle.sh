#!/system/bin/sh
# Toggle wifi once while sampling YT Music playback state every 5s. Args: <tag>
T=$1
i=0
while [ $i -lt 60 ]; do
  ST=$(dumpsys media_session 2>/dev/null | grep -A10 'package=app.morphe.android.apps.youtube.music$' | grep -oE 'state=[A-Z]+\([0-9]\), position=[0-9]+, buffered position=[0-9]+' | head -1)
  echo "$(date +%T) ${ST:-no-session}" >> /data/local/tmp/st$T.log
  i=$((i+1))
  sleep 5
  [ $i -eq 6 ] && svc wifi disable
  [ $i -eq 14 ] && svc wifi enable
done
echo done >> /data/local/tmp/st$T.log
