
#!/bin/bash
LOG_FILE="soak_test_v2_result.log"
echo "=== [Experiment C v2] Deep Soak Test Started ===" > $LOG_FILE

# Generate standard Telegraf configuration with internal monitoring enabled.
cat << 'CONF' > crms_soak.conf
[agent]
  interval = "5s"
  flush_interval = "5s"
[[inputs.internal]]
[[inputs.mem]]
[[inputs.disk]]
  mount_points = ["/"]
[[outputs.file]]
  files = ["output_soak.json"]
  data_format = "json"
CONF

# Clean up previous artifacts.
rm -f output_soak.json telegraf_soak.log

# Launch Telegraf.
telegraf --config crms_soak.conf > telegraf_soak.log 2>&1 &
TEL_PID=$!
echo "Telegraf started (PID: $TEL_PID)" >> $LOG_FILE
printf "%-20s %-10s %-10s %-15s\n" "TIME" "RSS(KB)" "Goroutines" "Heap_Alloc(B)" >> $LOG_FILE

# Monitor the agent every 10 minutes (600 seconds) for a total of 24 hours (144 iterations).
for i in {1..72}; do
    sleep 300
    if ps -p $TEL_PID > /dev/null; then
        # Capture OS-level memory usage.
        RSS=$(ps -p $TEL_PID -o rss | tail -n 1 | tr -d ' ')
        
        # Parse internal Go runtime metrics.
        # WHY Goroutines & Heap? Go applications (like Telegraf) often suffer from leaks 
        # where Goroutines are spawned but never terminated, slowly eating up Heap memory.
        # Tracking these metrics is far more accurate than just watching OS RSS.
        GOROUTINES=$(grep '"name":"internal_agent"' output_soak.json 2>/dev/null | tail -n 1 | grep -o '"go_goroutines":[0-9]*' | cut -d':' -f2 || echo "N/A")
        HEAP=$(grep '"name":"internal_memstats"' output_soak.json 2>/dev/null | tail -n 1 | grep -o '"heap_alloc":[0-9]*' | cut -d':' -f2 || echo "N/A")
        
        # Record the extracted metrics to the log file.
        echo "$(date '+%Y-%m-%d %H:%M:%S')  $RSS       $GOROUTINES         $HEAP" >> $LOG_FILE
        
        # TRUNCATE the JSON file.
        # WHY? Since we run this for 24 hours at a 5s interval, the JSON file will grow massive 
        # and could fill up the disk, causing a false-positive crash. Emptying it prevents this.
        > output_soak.json 
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') Telegraf died!" >> $LOG_FILE
        break
    fi
done

# Cleanup background process.
kill $TEL_PID 2>/dev/null
echo "=== [Experiment C v2] Completed ===" >> $LOG_FILE
