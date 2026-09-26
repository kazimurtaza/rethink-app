#!/system/bin/sh
# On-device wedge repro: probe DNS, toggle wifi, observe. Writes /data/local/tmp/wedge.log
D=/data/local/tmp
L=$D/wedge.log
probe() {
  for q in $D/q_*.bin; do
    n=$(basename "$q" .bin)
    r=$(timeout 4 nc -u -w 2 10.111.222.3 53 < "$q" 2>/dev/null | od -An -tx1 | tr -d ' \n')
    echo "$(date +%T) $1 $n r=${r:-EMPTY}" >> "$L"
  done
}
echo "== device run start $(date)" >> "$L"
media volume --stream 3 --set 1
am start -a android.intent.action.VIEW -d 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' >/dev/null 2>&1
i=0
while [ $i -lt 14 ]; do
  i=$((i+1))
  probe "c${i}-pre"
  svc wifi disable
  sleep 22
  probe "c${i}-lte"
  svc wifi enable
  sleep 45
  probe "c${i}-wifi"
done
echo "== cycles done $(date), observing 15min no-restart" >> "$L"
j=0
while [ $j -lt 30 ]; do
  j=$((j+1))
  sleep 30
  probe "obs$j"
done
echo "== device run end $(date)" >> "$L"
