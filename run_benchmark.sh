#!/bin/bash

echo "=== Starting CRMS Agent Load Test (Waiting for 60s) ==="

# 기존 파일 및 로그 초기화
rm -f output_payload.json telegraf.log

# 백그라운드 실행 (에러 로그를 telegraf.log에 저장)
# 깃허브에서 받으신 crms_test.conf(언더스코어) 파일명으로 맞췄습니다.
telegraf --config crms_test.conf > telegraf.log 2>&1 &
TELEGRAF_PID=$!

echo "Telegraf started successfully (PID: $TELEGRAF_PID)"
echo "Recording CPU and Memory (RSS KB) trends..."

# 5초 간격으로 12번(60초) 측정
printf "%-10s %-10s %-10s\n" "TIME" "CPU(%)" "RSS(KB)"
for i in {1..12}; do
  sleep 5
  # 프로세스가 살아있는지 확인
  if ps -p $TELEGRAF_PID > /dev/null; then
    ps -p $TELEGRAF_PID -o %cpu,rss | tail -n 1 | awk -v d="$(date '+%H:%M:%S')" '{printf "%-10s %-10s %-10s\n", d, $1, $2}'
  else
    echo "Telegraf process died unexpectedly at $i iteration!"
    break
  fi
done

# 프로세스가 살아있을 때만 강제 종료
if ps -p $TELEGRAF_PID > /dev/null; then
  kill $TELEGRAF_PID
fi
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
  echo "output_payload.json file was not generated. Checking Telegraf errors..."
  echo "=== Telegraf Error Log (Last 15 lines) ==="
  tail -n 15 telegraf.log
fi