#!/bin/bash
# =============================================================
# TEST: C3 — Power Consumption <= 50W
# Method: Component-level power analysis from datasheets +
#         live CPU load measurement while app is running.
#         For exact measurement: use a USB power meter at 5V input.
# Output: tests/results/c3_power_consumption.txt
# =============================================================

RESULTS_DIR="tests/results"
mkdir -p "$RESULTS_DIR"
OUTFILE="$RESULTS_DIR/c3_power_consumption.txt"
LIMIT_W=50

echo "========================================"    | tee "$OUTFILE"
echo "TEST C3: Power Consumption"                  | tee -a "$OUTFILE"
echo "Requirement: Total system power <= ${LIMIT_W}W" | tee -a "$OUTFILE"
echo "Date: $(date)"                               | tee -a "$OUTFILE"
echo "========================================"    | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"

echo "--- Component Power (from datasheets) ---"  | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"
printf "%-35s %-10s\n" "Component" "Power (W)"    | tee -a "$OUTFILE"
printf "%-35s %-10s\n" "---" "---"                | tee -a "$OUTFILE"
printf "%-35s %-10s\n" "Raspberry Pi 3B (full load)" "3.7"   | tee -a "$OUTFILE"
printf "%-35s %-10s\n" "FLIR Lepton 3.5"           "0.15"   | tee -a "$OUTFILE"
printf "%-35s %-10s\n" "Pi Camera Module 2"         "0.25"   | tee -a "$OUTFILE"
printf "%-35s %-10s\n" "GY-NEO6MV2 GPS module"      "0.045"  | tee -a "$OUTFILE"
printf "%-35s %-10s\n" "HDMI display (external)"    "2.5"    | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"

PI=3.7; LEPTON=0.15; PICAM=0.25; GPS=0.045; HDMI=2.5
TOTAL_NO_DISPLAY=$(echo "scale=3; $PI + $LEPTON + $PICAM + $GPS" | bc)
TOTAL_WITH_DISPLAY=$(echo "scale=3; $TOTAL_NO_DISPLAY + $HDMI" | bc)

echo "--- Calculated Totals ---"                   | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"
echo "  Without display: ${TOTAL_NO_DISPLAY}W"    | tee -a "$OUTFILE"
echo "  With display:    ${TOTAL_WITH_DISPLAY}W"  | tee -a "$OUTFILE"
echo "  Limit:           ${LIMIT_W}W"             | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"

# Live CPU measurement
echo "--- Live CPU Measurements (5 samples) ---"  | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"

APP_PID=$(pgrep -x "raspberrypi_video")
if [ -n "$APP_PID" ]; then
    echo "  App running (PID $APP_PID)"            | tee -a "$OUTFILE"
    CPU_SUM=0
    for i in $(seq 1 5); do
        CPU=$(ps -p "$APP_PID" -o %cpu= 2>/dev/null | tr -d ' ')
        MEM=$(ps -p "$APP_PID" -o rss= 2>/dev/null \
            | awk '{printf "%.1f", $1/1024}')
        TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oP '\d+\.\d+')
        printf "  Sample %-2s: CPU=%-6s Mem=%-8s Temp=%s°C\n" \
            "$i" "${CPU}%" "${MEM}MB" "$TEMP" | tee -a "$OUTFILE"
        CPU_SUM=$(echo "$CPU_SUM + $CPU" | bc)
        sleep 2
    done
    AVG_CPU=$(echo "scale=1; $CPU_SUM / 5" | bc)
    echo ""                                        | tee -a "$OUTFILE"
    echo "  Average CPU load: ${AVG_CPU}%"         | tee -a "$OUTFILE"
else
    echo "  App not running — start it for live measurements" \
        | tee -a "$OUTFILE"
    echo "  (Static datasheet analysis only)"      | tee -a "$OUTFILE"
fi

echo ""                                            | tee -a "$OUTFILE"
echo "--- Measurement Instructions ---"            | tee -a "$OUTFILE"
echo "  For exact measurement use a USB power meter:" | tee -a "$OUTFILE"
echo "  1. Insert USB power meter between charger and Pi" | tee -a "$OUTFILE"
echo "  2. Run app at full load: sudo nice -n -20 ./raspberrypi_video -tl 3" | tee -a "$OUTFILE"
echo "  3. Record: Voltage (V) x Current (A) = Power (W)" | tee -a "$OUTFILE"
echo "  Expected: ~5V x 0.8-1.2A = 4-6W"         | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"

echo "========================================"    | tee -a "$OUTFILE"
echo "SUMMARY"                                    | tee -a "$OUTFILE"
RESULT=$(echo "$TOTAL_WITH_DISPLAY < $LIMIT_W" | bc)
echo "  Estimated total (with display): ${TOTAL_WITH_DISPLAY}W" \
    | tee -a "$OUTFILE"
echo "  Limit: ${LIMIT_W}W"                        | tee -a "$OUTFILE"
[ "$RESULT" -eq 1 ] \
    && echo "  OVERALL: PASS (${TOTAL_WITH_DISPLAY}W << ${LIMIT_W}W)" \
        | tee -a "$OUTFILE" \
    || echo "  OVERALL: FAIL" | tee -a "$OUTFILE"
echo "========================================"    | tee -a "$OUTFILE"
echo "Saved: $OUTFILE"
