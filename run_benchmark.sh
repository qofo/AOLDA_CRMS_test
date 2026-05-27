#!/bin/bash

echo "=== Starting CRMS Agent Load Test (Waiting for 60s) ==="

# 이전 출력 파일 초기화
rm -f output_payload.json

# 백그라운드 실행
telegraf --config crms-test.conf > /dev/null 2>&1 &
TELEGRAF_PID=$!

echo "Telegraf started successfully (PID: $TELEGRAF_PID)"
echo "Recording CPU and Memory (RSS KB) trends..."

# 5초 간격으로 12번(60초) 측정
printf "%-10s %-10s %-10s\n" "TIME" "CPU(%)" "RSS(KB)"
for i in {1..12}; do
  sleep 5
  ps -p $TELEGRAF_PID -o %cpu,rss | tail -n 1 | awk -v d="$(date '+%H:%M:%S')" '{printf "%-10s %-10s %-10s\n", d, $1, $2}'
done

# 프로세스 종료
kill $TELEGRAF_PID
echo "=== Test Completed ==="

# Payload 1회분 예상 크기 측정
if [ -f "output_payload.json" ]; then
  FILE_SIZE=$(stat -c%s "output_payload.json")
  METRIC_COUNT=$(wc -l < output_payload.json)
  
  if [ "$METRIC_COUNT" -gt 0 ]; then
    AVG_SIZE=$(( FILE_SIZE / METRIC_COUNT ))
    echo "Total generated JSON lines: $METRIC_COUNT"
    echo "Estimated Payload size per collection (1 JSON object): approx $AVG_SIZE Bytes"
  else
    echo "No data was measured."
  fi
else
  echo "output_payload.json file was not generated. Please check for Telegraf execution errors."
fi