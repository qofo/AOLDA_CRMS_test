
#!/bin/bash
LOG_FILE="buffer_test_v2_result.log"
echo "=== [Experiment B v2] Network Blackhole & Buffer Test ===" | tee $LOG_FILE

# Simulate a silent network failure (Network Partition / SYN Timeout).
# WHY DROP instead of REJECT? A REJECT returns immediately (Connection Refused), 
# which is easy for an agent to handle. DROP forces the agent to wait for a TCP timeout, 
# which is a much more realistic and dangerous scenario that causes queue saturation.
sudo iptables -A OUTPUT -d 10.255.255.255 -j DROP

# Generate Telegraf configuration for the buffer test.
cat << 'CONF' > crms_blackhole.conf
[agent]
  interval = "1s"
  flush_interval = "1s"
  metric_batch_size = 10
  # We intentionally set an extremely low buffer limit (30) to force rapid saturation.
  # This allows us to observe how Telegraf handles backpressure in a short time frame.
  metric_buffer_limit = 30  
# Enable internal plugin to monitor Telegraf's own health (drops, errors).
[[inputs.internal]] 
[[inputs.mem]]
[[outputs.http]]
  # Route traffic to the blackholed IP address.
  url = "http://10.255.255.255:8080/write"
  timeout = "2s"
[[outputs.file]]
  # Save internal metrics to a file so we can parse dropped metric counts.
  files = ["output_internal.json"]
  data_format = "json"
CONF

# Clean up previous artifacts.
rm -f output_internal.json telegraf_buffer.log

# Launch Telegraf.
telegraf --config crms_blackhole.conf > telegraf_buffer.log 2>&1 &
TEL_PID=$!
echo "Telegraf started with Timeout network config (PID: $TEL_PID)" | tee -a $LOG_FILE

printf "%-10s %-10s %-15s %-15s\n" "TIME" "RSS(KB)" "WRITE_ERRORS" "METRICS_DROPPED" | tee -a $LOG_FILE

# Monitor the agent every 5 seconds for 60 seconds.
for i in {1..12}; do
    sleep 5
    if ps -p $TEL_PID > /dev/null; then
        # Capture memory usage to ensure it plateaus and doesn't cause an OOM crash.
        RSS=$(ps -p $TEL_PID -o rss | tail -n 1 | tr -d ' ')
        
        # Parse the 'internal_write' metrics to extract accumulated errors and drops.
        # This proves whether the agent gracefully discards old metrics when the buffer is full.
        ERRS=$(grep '"name":"internal_write"' output_internal.json 2>/dev/null | tail -n 1 | grep -o '"errors":[0-9]*' | cut -d':' -f2 || echo "0")
        DROPS=$(grep '"name":"internal_write"' output_internal.json 2>/dev/null | tail -n 1 | grep -o '"metrics_dropped":[0-9]*' | cut -d':' -f2 || echo "0")
        
        echo "$(date '+%H:%M:%S')  $RSS       $ERRS            $DROPS" | tee -a $LOG_FILE
    else
        echo "Telegraf died!" | tee -a $LOG_FILE
        break
    fi
done

# Cleanup: Kill the process and remove the iptables drop rule to restore normal networking.
kill $TEL_PID 2>/dev/null
sudo iptables -D OUTPUT -d 10.255.255.255 -j DROP
echo "=== [Experiment B v2] Completed ===" | tee -a $LOG_FILE
