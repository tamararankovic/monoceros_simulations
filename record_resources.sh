#!/bin/sh

PORT=5001
OUTPUT_FILE="/var/log/monoceros/results/usage.csv"
SLEEP_BEFORE_START=5

sleep $SLEEP_BEFORE_START

PID=$(netstat -tulpn | grep :$PORT | awk '{split($7,a,"/"); print a[1]}' | head -n 1)

if [ -z "$PID" ]; then
  echo "No process found listening on port $PORT"
  exit 1
fi

echo "timestamp_s,cpu_percent,rss_kb" > "$OUTPUT_FILE"

CLK_TCK=$(getconf CLK_TCK)

# Get initial CPU and time
read UTIME STIME < <(awk '{print $14, $15}' /proc/$PID/stat)
CPU_PREV=$((UTIME + STIME))
TIME_PREV=$(date +%s)

while kill -0 "$PID" 2>/dev/null; do
  sleep 1

  # Current CPU times
  read UTIME STIME RSS_PAGES < <(awk '{print $14, $15, $24}' /proc/$PID/stat)
  CPU_CUR=$((UTIME + STIME))
  RSS_KB=$((RSS_PAGES * 4))

  TIME_NOW=$(date +%s)

  DELTA_CPU=$((CPU_CUR - CPU_PREV))
  DELTA_TIME=$((TIME_NOW - TIME_PREV))

  if [ $DELTA_TIME -gt 0 ]; then
    CPU_PERCENT=$(awk "BEGIN {printf \"%.2f\", 100 * $DELTA_CPU / ($DELTA_TIME * $CLK_TCK)}")
  else
    CPU_PERCENT=0
  fi

  echo "$TIME_NOW,$CPU_PERCENT,$RSS_KB" >> "$OUTPUT_FILE"

  CPU_PREV=$CPU_CUR
  TIME_PREV=$TIME_NOW
done
