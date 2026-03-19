#!/bin/bash
# =============================================================
# TEST: C4 — Temperature Range Operation (-10°C to 40°C)
# Requirement: System operates stably in -10°C to 40°C
# Method: Monitor Pi CPU temperature and system stability
#         while the app is running. Log temperature over time.
#         For full compliance, run outdoors in cold conditions.
# Output: tests/results/c4_temperature.txt
# Usage:  bash tests/test_c4_temperature.sh [minutes]
#         Default: 30 minutes. Run longer for full testing.
# NOTE:   For cold testing (-10°C), take the Pi outside in winter
#         and run this script via SSH.
# =============================================================

RESULTS_DIR="tests/results"
mkdir -p "$RESULTS_DIR"
OUTFILE="$RESULTS_DIR/c4_temperature.txt"

DURATION_MIN=${1:-30}
INTERVAL_SEC=30
ITERATIONS=$(( DURATION_MIN * 60 / INTERVAL_SEC ))
MAX_SAFE=80   # Pi throttles at 80°C
AMBIENT="unknown"

echo "========================================"    | tee "$OUTFILE"
echo "TEST C4: Temperature Range Operation"        | tee -a "$OUTFILE"
echo "Requirement: Operate in -10°C to 40°C"      | tee -a "$OUTFILE"
echo "Duration: ${DURATION_MIN} minutes"           | tee -a "$OUTFILE"
echo "Date: $(date)"                               | tee -a "$OUTFILE"
echo "========================================"    | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"

# Prompt for ambient temperature annotation
echo "Enter current ambient temperature (°C), then press Enter:"
read -t 10 AMBIENT_INPUT
AMBIENT="${AMBIENT_INPUT:-not recorded}"
echo "Ambient temperature recorded: ${AMBIENT}°C"  | tee -a "$OUTFILE"
echo "Test condition: (WARM/COLD/ROOM TEMP - annotate manually)" \
    | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"

APP_NAME="raspberrypi_video"
MAX_OBSERVED=0
MIN_OBSERVED=999
THROTTLE_COUNT=0
CRASH_COUNT=0

echo "Monitoring system for ${DURATION_MIN} minutes..." | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"
printf "%-25s %-12s %-12s %-10s\n" \
    "Timestamp" "Pi Temp(°C)" "App Status" "Notes" | tee -a "$OUTFILE"
printf "%-25s %-12s %-12s %-10s\n" \
    "---" "---" "---" "---"                        | tee -a "$OUTFILE"

for i in $(seq 1 $ITERATIONS); do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oP '\d+\.\d+')
    TEMP="${TEMP:-N/A}"

    PID=$(pgrep -x "$APP_NAME" 2>/dev/null)
    [ -n "$PID" ] && STATUS="RUNNING" || { STATUS="CRASHED"; CRASH_COUNT=$((CRASH_COUNT+1)); }

    NOTES=""
    if [[ "$TEMP" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        INT_T=${TEMP%.*}
        (( INT_T > MAX_OBSERVED )) && MAX_OBSERVED=$INT_T
        (( INT_T < MIN_OBSERVED )) && MIN_OBSERVED=$INT_T
        (( INT_T >= MAX_SAFE ))    && { NOTES="⚠ THERMAL THROTTLE RISK"; THROTTLE_COUNT=$((THROTTLE_COUNT+1)); }
    fi

    printf "%-25s %-12s %-12s %-10s\n" \
        "$TIMESTAMP" "${TEMP}" "$STATUS" "$NOTES"  | tee -a "$OUTFILE"
    sleep "$INTERVAL_SEC"
done

echo ""                                            | tee -a "$OUTFILE"
echo "========================================"    | tee -a "$OUTFILE"
echo "SUMMARY"                                    | tee -a "$OUTFILE"
echo "  Ambient temp at test start: ${AMBIENT}°C" | tee -a "$OUTFILE"
echo "  Max Pi CPU temp observed:  ${MAX_OBSERVED}°C" | tee -a "$OUTFILE"
echo "  Min Pi CPU temp observed:  ${MIN_OBSERVED}°C" | tee -a "$OUTFILE"
echo "  Throttle warnings (>=${MAX_SAFE}°C): $THROTTLE_COUNT" | tee -a "$OUTFILE"
echo "  Crash count: $CRASH_COUNT"                | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"
echo "  Full compliance requires testing at:"     | tee -a "$OUTFILE"
echo "    Cold: ambient <= -10°C (run outdoors in winter)" | tee -a "$OUTFILE"
echo "    Warm: ambient >= 35°C (warm room or summer outdoor)" | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"

if [ "$CRASH_COUNT" -eq 0 ] && [ "$THROTTLE_COUNT" -eq 0 ]; then
    echo "  OVERALL: PASS (at current ambient temperature)" | tee -a "$OUTFILE"
elif [ "$CRASH_COUNT" -eq 0 ]; then
    echo "  OVERALL: PARTIAL — no crashes but thermal warnings observed" \
        | tee -a "$OUTFILE"
else
    echo "  OVERALL: FAIL — system crashed during test" | tee -a "$OUTFILE"
fi
echo "========================================"    | tee -a "$OUTFILE"
echo "Saved: $OUTFILE"
