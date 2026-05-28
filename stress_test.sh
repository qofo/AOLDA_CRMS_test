#!/bin/bash
LOG_FILE="stress_test_v2_result.log"
echo "=== [Experiment A v2] Stress & Drift Test Started ===" | tee $LOG_FILE

# Ensure stress-ng is installed to simulate high resource contention.
if ! command -v stress-ng &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y stress-ng
fi

# Generate a standalone Telegraf configuration specifically for this test.
# We configure a standard 5-second interval to observe scheduling consistency.
cat << 'CONF' > crms_stress.conf
[agent]
  interval = "5s"
  flush_interval = "5s"
[[inputs.mem]]
[[inputs.disk]]
  mount_points = ["/"]
[[outputs.file]]
  files = ["output_stress.json"]
  data_format = "json"
CONF

# Clean up previous artifacts to ensure a fresh test environment.
rm -f output_stress.json telegraf_stress.log

# Launch Telegraf in the background and capture its PID for monitoring.
telegraf --config crms_stress.conf > telegraf_stress.log 2>&1 &
TEL_PID=$!
echo "Telegraf started (PID: $TEL_PID)" | tee -a $LOG_FILE

# Inject load using stress-ng.
# WHY 600M? On a 1GB VM, allocating exactly 1GB or 800MB might trigger the Linux OOM Killer 
# unpredictably, killing our agent not because of its own fault, but due to kernel panic. 
# 600M creates heavy pressure while leaving enough room for the OS and Telegraf to operate.
stress-ng --cpu 1 --vm 1 --vm-bytes 600M --timeout 65s > /dev/null 2>&1 &
STRESS_PID=$!
echo "stress-ng started (PID: $STRESS_PID) - Injecting Load..." | tee -a $LOG_FILE

# Print the header for our monitoring output.
printf "%-10s %-10s %-10s %-15s %-20s\n" "TIME" "CPU(%)" "RSS(KB)" "JSON_LINES" "LATEST_TIMESTAMP" | tee -a $LOG_FILE

# Monitor the agent every 5 seconds for roughly 65 seconds (13 iterations).
for i in {1..13}; do
    sleep 5
    if ps -p $TEL_PID > /dev/null; then
        # Count the total lines in the output file to verify data is actively being written.
        LINES=$(wc -l < output_stress.json 2>/dev/null || echo "0")
        
        # Extract the latest timestamp from the JSON output.
        # WHY? If CPU contention is too high, Go's scheduler might starve Telegraf's goroutines.
        # By tracking the timestamp, we can detect "metric drift" (e.g., missing a 5s cycle).
        LATEST_TS=$(tail -n 1 output_stress.json 2>/dev/null | grep -o '"timestamp":[0-9]*' | cut -d':' -f2 || echo "N/A")
        
        # Fetch the current CPU and Memory (RSS) usage of the Telegraf process.
        ps -p $TEL_PID -o %cpu,rss | tail -n 1 | awk -v d="$(date '+%H:%M:%S')" -v l="$LINES" -v ts="$LATEST_TS" '{printf "%-10s %-10s %-10s %-15s %-20s\n", d, $1, $2, l, ts}' | tee -a $LOG_FILE
    else
        echo "Telegraf died unexpectedly!" | tee -a $LOG_FILE
        break
    fi
done

# Graceful cleanup of background processes.
kill $TEL_PID 2>/dev/null
kill $STRESS_PID 2>/dev/null
echo "=== [Experiment A v2] Completed ===" | tee -a $LOG_FILE
