#!/bin/bash
LOG_FILE="soak_test_v3_result.log"
echo "=== [Experiment C v3] Deep Soak Test Started ===" > $LOG_FILE

# -----------------------------------------------------------------------------
# [Recommendation 1] Go Runtime Memory Tuning
# To achieve the target RSS footprint of under 50MB, we enforce aggressive 
# Garbage Collection (GC) for the Go runtime used by Telegraf.
# GOMEMLIMIT sets a soft memory limit, and GOGC=50 runs GC twice as often as default.
# -----------------------------------------------------------------------------
export GOMEMLIMIT=40MiB
export GOGC=50
echo "Applied Go Runtime Memory Tuning: GOMEMLIMIT=$GOMEMLIMIT, GOGC=$GOGC" >> $LOG_FILE

# -----------------------------------------------------------------------------
# [Recommendation 3] Collection Interval Review
# Generate standard Telegraf configuration. 
# Changed interval from "5s" to "5m" to match the CRMS production policy 
# for internal monitoring (Memory, Disk). This reduces unnecessary overhead.
# -----------------------------------------------------------------------------
cat << 'CONF' > crms_soak.conf
[agent]
  interval = "5m"
  flush_interval = "5m"
[[inputs.internal]]
[[inputs.mem]]
[[inputs.disk]]
  mount_points = ["/"]
[[outputs.file]]
  files = ["output_soak.json"]
  data_format = "json"
CONF

# Clean up previous artifacts to ensure a fresh start.
rm -f output_soak_v3.json telegraf_soak_v3.log

# Launch Telegraf in the background and redirect output to a log file.
telegraf --config crms_soak_v3.conf > telegraf_soak_v3.log 2>&1 &
TEL_PID=$!
echo "Telegraf started (PID: $TEL_PID)" >> $LOG_FILE

# Update the log header to reflect the actual metrics we are extracting.
# We track 'Heap_Objects' instead of 'go_goroutines', and 'Heap_Alloc(B)' for precise internal memory.
printf "%-20s %-15s %-15s %-15s\n" "TIME" "RSS(KB)" "Heap_Objects" "Heap_Alloc(B)" >> $LOG_FILE

# Monitor the agent every 5 minutes (300 seconds) for a total of 24 hours (288 iterations).
for i in {1..288}; do
    sleep 300
    
    # Check if the Telegraf process is still running.
    if ps -p $TEL_PID > /dev/null; then
        
        # 1. Capture OS-level memory usage (RSS).
        # We extract the last line of the 'ps' output and remove any whitespace.
        RSS=$(ps -p $TEL_PID -o rss | tail -n 1 | tr -d ' ')
        
        # -------------------------------------------------------------------------
        # [Recommendation 2] Parse internal Go runtime metrics using ONLY grep.
        # We target the actual JSON keys: "heap_objects" and "heap_alloc_bytes" 
        # located inside the 'internal_memstats' JSON object.
        # -------------------------------------------------------------------------
        
        # Extract the number of allocated heap objects.
        HEAP_OBJS=$(grep '"name":"internal_memstats"' output_soak_v3.json 2>/dev/null | tail -n 1 | grep -o '"heap_objects":[0-9]*' | cut -d':' -f2 || echo "N/A")
        
        # Extract the exact allocated heap bytes.
        HEAP_ALLOC=$(grep '"name":"internal_memstats"' output_soak_v3.json 2>/dev/null | tail -n 1 | grep -o '"heap_alloc_bytes":[0-9]*' | cut -d':' -f2 || echo "N/A")
        
        # Record the extracted metrics to the log file with proper column alignment.
        printf "%-20s %-15s %-15s %-15s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$RSS" "$HEAP_OBJS" "$HEAP_ALLOC" >> $LOG_FILE
        
        # TRUNCATE the JSON file.
        # This prevents the disk from filling up over the 24-hour test period.
        > output_soak.json 
    else
        # If the process ID is no longer found, log the crash and exit the loop.
        echo "$(date '+%Y-%m-%d %H:%M:%S') Telegraf died!" >> $LOG_FILE
        break
    fi
done

# Cleanup the background process gracefully after the test finishes.
kill $TEL_PID 2>/dev/null
echo "=== [Experiment C v3] Completed ===" >> $LOG_FILE