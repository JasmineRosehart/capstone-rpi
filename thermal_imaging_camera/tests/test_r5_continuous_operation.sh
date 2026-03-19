#!/bin/bash
# =============================================================
# TEST: R5 — Continuous Operation >= 12 Hours
# Requirement: System runs without crash or degradation for 12h
# Method: Poll process health, CPU temp, and memory every 60s
#         while the main app is running in another terminal
# Usage:  bash tests/test_r5_continuous_operation.sh [minutes]
#         Default: 720 minutes (12 hours)
# Output: tests/results/r5_continuous_operation.txt
# NOTE:   Start ./raspberrypi_video -tl 3 FIRST in another terminal
# =============================================================

RESULTS_DIR="tests/results"
mkdir -p "$RESULTS_DIR"
OUTFILE="$RESULTS_DIR/r5_continuous_operation.txt"

DURATION_MIN=${1:-720}
INTERVAL_SEC=60
ITERATIONS=$(( DURATION_MIN * 60 / INTERVAL_SEC ))
APP_NAME="raspberrypi_video"
CRASH_COUNT=0
MAX_TEMP=0
MIN_TEMP=999
START_EPOCH=$(date +%s)

echo "========================================"     | tee "$OUTFILE"
echo "TEST R5: Continuous Operation"                | tee -a "$OUTFILE"
echo "Requirement: Operate >= 12 hours continuously" | tee -a "$OUTFILE"
echo "Target duration: ${DURATION_MIN} minutes"     | tee -a "$OUTFILE"
echo "Check interval:  ${INTERVAL_SEC} seconds"     | tee -a "$OUTFILE"
echo "Start time: $(date)"                          | tee -a "$OUTFILE"
echo "========================================"     | tee -a "$OUTFILE"
echo ""                                             | tee -a "$OUTFILE"

# Warn if app isn't running yet
if ! pgrep -x "$APP_NAME" > /dev/null; then
    echo "WARNING: $APP_NAME is not running."        | tee -a "$OUTFILE"
    echo "Start it with: sudo nice -n -20 ./raspberrypi_video -tl 3" | tee -a "$OUTFILE"
    echo "Then re-run this script."                  | tee -a "$OUTFILE"
    exit 1
fi

echo "App detected. Beginning monitoring..."        | tee -a "$OUTFILE"
echo ""                                             | tee -a "$OUTFILE"
printf "%-25s %-10s %-15s %-10s %-12s %-10s\n" \
    "Timestamp" "T+min" "App Status" "CPU%" "Mem(MB)" "Temp(C)" \
    | tee -a "$OUTFILE"
printf "%-25s %-10s %-15s %-10s %-12s %-10s\n" \
    "-------------------------" "--------" "---------------" \
    "--------" "----------" "--------" | tee -a "$OUTFILE"

for i in $(seq 1 $ITERATIONS); do
    ELAPSED_MIN=$(( i * INTERVAL_SEC / 60 ))
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    PID=$(pgrep -x "$APP_NAME" 2>/dev/null)

    if [ -n "$PID" ]; then
        STATUS="RUNNING"
        CPU=$(ps -p "$PID" -o %cpu= 2>/dev/null | tr -d ' ')
        MEM=$(ps -p "$PID" -o rss= 2>/dev/null | awk '{printf "%.1f", $1/1024}')
    else
        STATUS="CRASHED"
        CPU="--"
        MEM="--"
        CRASH_COUNT=$((CRASH_COUNT + 1))
    fi

    TEMP_RAW=$(vcgencmd measure_temp 2>/dev/null | grep -oP '\d+\.\d+')
    TEMP_RAW="${TEMP_RAW:-N/A}"

    # Track min/max
    if [[ "$TEMP_RAW" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        INT_TEMP=${TEMP_RAW%.*}
        (( INT_TEMP > MAX_TEMP )) && MAX_TEMP=$INT_TEMP
        (( INT_TEMP < MIN_TEMP )) && MIN_TEMP=$INT_TEMP
        (( INT_TEMP >= 75 )) && WARN=" ⚠ HIGH TEMP" || WARN=""
    else
        WARN=""
    fi

    printf "%-25s %-10s %-15s %-10s %-12s %-10s%s\n" \
        "$TIMESTAMP" "${ELAPSED_MIN}" "$STATUS" \
        "${CPU}" "${MEM}" "${TEMP_RAW}" "$WARN" \
        | tee -a "$OUTFILE"

    sleep "$INTERVAL_SEC"
done

END_EPOCH=$(date +%s)
ACTUAL_MIN=$(( (END_EPOCH - START_EPOCH) / 60 ))

echo ""                                             | tee -a "$OUTFILE"
echo "========================================"     | tee -a "$OUTFILE"
echo "SUMMARY"                                      | tee -a "$OUTFILE"
echo "  End time:        $(date)"                   | tee -a "$OUTFILE"
echo "  Actual runtime:  ${ACTUAL_MIN} minutes"     | tee -a "$OUTFILE"
echo "  Crash events:    $CRASH_COUNT"              | tee -a "$OUTFILE"
echo "  Max CPU temp:    ${MAX_TEMP}°C"             | tee -a "$OUTFILE"
echo "  Min CPU temp:    ${MIN_TEMP}°C"             | tee -a "$OUTFILE"
echo "  Temp threshold:  75°C"                      | tee -a "$OUTFILE"

if [ "$CRASH_COUNT" -eq 0 ] && [ "$ACTUAL_MIN" -ge "$DURATION_MIN" ]; then
    echo "  OVERALL: PASS"  | tee -a "$OUTFILE"
else
    echo "  OVERALL: FAIL"  | tee -a "$OUTFILE"
    [ "$CRASH_COUNT" -gt 0 ] && echo "  Reason: $CRASH_COUNT crash(s) detected" \
        | tee -a "$OUTFILE"
    [ "$ACTUAL_MIN" -lt "$DURATION_MIN" ] && \
        echo "  Reason: Only ran ${ACTUAL_MIN}/${DURATION_MIN} minutes" \
        | tee -a "$OUTFILE"
fi
echo "========================================"     | tee -a "$OUTFILE"
echo "Saved: $OUTFILE"
