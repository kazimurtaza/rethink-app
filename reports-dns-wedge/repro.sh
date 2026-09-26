#!/bin/bash
# Repro Rethink DNS wedge: cycle Wi-Fi (WiFi<->LTE) while probing googlevideo vs control.
# On wedge: stop cycling, observe without restart (self-heal test), capture state.
cd "$(dirname "$0")"
LOG="repro-run-$(date +%H%M%S).log"
IP=10.3.0.213

disc() { adb mdns services 2>/dev/null | grep -oE "${IP}:[0-9]+" | head -1; }
ensure() { local d; d=$(adb devices | grep -oE "${IP}:[0-9]+"); [ -n "$d" ] && { echo "$d"; return; }
  for i in 1 2 3 4 5 6; do sleep 5; d=$(disc); [ -n "$d" ] && { adb connect "$d" >/dev/null 2>&1; sleep 1; d=$(adb devices | grep -oE "${IP}:[0-9]+"); [ -n "$d" ] && { echo "$d"; return; }; }; done; echo ""; }
probe() { local d="$1" tag="$2"; for h in rr1---sn-a5mekn6k.googlevideo.com r4---sn-hxa7zn7s.googlevideo.com www.youtube.com; do
  echo "[$(date +%T)] $tag $(python3 dnsq.py "$d" "$h" 2>/dev/null || echo 'PROBE-ERR')" | tee -a "$LOG"; done; }

D=$(ensure); [ -z "$D" ] && { echo "no device" | tee -a "$LOG"; exit 1; }
echo "== repro start $(date) serial=$D" | tee -a "$LOG"
adb -s "$D" shell "logcat -c; setsid sh -c 'logcat -f /data/local/tmp/repro-dns.log -r 4096 -n 4 -v time *:I' >/dev/null 2>&1 &" 2>/dev/null
# playback load (muted-ish) so CDN churn is real
adb -s "$D" shell "media volume --stream 3 --set 1; am start -a android.intent.action.VIEW -d 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'" >/dev/null 2>&1

WEDGE=0; NOSVC=0
for cycle in $(seq 1 14); do
  D=$(ensure); [ -z "$D" ] && { echo "[$(date +%T)] LOST-DEVICE" | tee -a "$LOG"; continue; }
  probe "$D" "c${cycle}-pre"
  adb -s "$D" shell "svc wifi disable" >/dev/null 2>&1
  sleep 22
  D=$(ensure); [ -n "$D" ] && probe "$D" "c${cycle}-lte"
  [ -z "$D" ] && adb connect "${IP}:$(true)" >/dev/null 2>&1
  D=$(ensure); [ -n "$D" ] && adb -s "$D" shell "svc wifi enable" >/dev/null 2>&1
  sleep 40
  D=$(ensure); [ -n "$D" ] && probe "$D" "c${cycle}-wifi"
  # wedge detect: googlevideo failing while control resolves
  tail -3 "$LOG" >/dev/null
  GV=$(grep "c${cycle}-" "$LOG" | grep googlevideo | grep -cE "rcode=3|NO-RESPONSE|PROBE-ERR")
  GV3=$(grep "c${cycle}-" "$LOG" | grep googlevideo | grep -cE "rcode=3")
  CTL=$(grep "c${cycle}-" "$LOG" | grep www.youtube | grep -cE "rcode=0")
  if [ "$GV3" -ge 2 ] 2>/dev/null && [ "$CTL" -ge 1 ] 2>/dev/null; then WEDGE=1; break; fi
  if [ "$GV" -ge 4 ] 2>/dev/null; then NOSVC=1; break; fi
done

if [ $WEDGE -eq 1 ] || [ $NOSVC -eq 1 ]; then
  echo "== WEDGE DETECTED (mode:$([ $WEDGE -eq 1 ] && echo rcode3 || echo no-resp)) $(date) — observation, NO restart" | tee -a "$LOG"
  D=$(ensure)
  adb -s "$D" shell "dumpsys connectivity | grep -A4 'VPN CONNECTED'" > "wedge-connectivity-$(date +%H%M%S).txt" 2>/dev/null
  adb -s "$D" shell "dumpsys netpolicy | grep -E '10588|10600'" >> "wedge-connectivity-$(date +%H%M%S).txt" 2>/dev/null
  for i in $(seq 1 30); do  # 30 x 30s = 15 min self-heal watch
    sleep 30; D=$(ensure); [ -z "$D" ] && continue
    probe "$D" "obs$i"
    H=$(grep "obs$i" "$LOG" | grep googlevideo | grep -c "rcode=0")
    [ "$H" -ge 1 ] 2>/dev/null && { echo "== SELF-HEALED after ~$((i*30))s without restart" | tee -a "$LOG"; break; }
  done
else
  echo "== no wedge after 14 cycles" | tee -a "$LOG"
fi
D=$(ensure); [ -n "$D" ] && adb -s "$D" pull /data/local/tmp/repro-dns.log "repro-device-logcat-$(date +%H%M%S).log" >/dev/null 2>&1
echo "== repro end $(date)" | tee -a "$LOG"
