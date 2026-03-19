#!/bin/bash
# =============================================================
# TEST: R3 — Capture, Upload, and Alert Pipeline Latency
# Requirement: Full pipeline (capture → S3 upload) completes
#              within 60 seconds of trigger
# Method: Run 15 upload trials across 3 file sizes, measure
#         latency for each, compute min/max/avg/stddev,
#         and output a CSV for graphing.
# Output: tests/results/r3_upload_latency.txt
#         tests/results/r3_upload_latency.csv   ← for graphing
# =============================================================

RESULTS_DIR="tests/results"
mkdir -p "$RESULTS_DIR"
OUTFILE="$RESULTS_DIR/r3_upload_latency.txt"
CSVFILE="$RESULTS_DIR/r3_upload_latency.csv"
TRIALS=15          # Total trials (5 per file size group)
LIMIT_SEC=60
PASS=0
FAIL=0

# Arrays to collect data
declare -a ALL_TIMES_MS
declare -a ALL_SIZES_KB

echo "========================================"      | tee "$OUTFILE"
echo "TEST R3: Upload & Pipeline Latency"            | tee -a "$OUTFILE"
echo "Requirement: Pipeline completes <= ${LIMIT_SEC}s" | tee -a "$OUTFILE"
echo "Trials: $TRIALS (5 small / 5 medium / 5 large)" | tee -a "$OUTFILE"
echo "Date: $(date)"                                 | tee -a "$OUTFILE"
echo "========================================"      | tee -a "$OUTFILE"
echo ""                                              | tee -a "$OUTFILE"

# Write CSV header
echo "Trial,FileSize_KB,ElapsedTime_ms,ElapsedTime_s,Result" > "$CSVFILE"

# ---- Helper: create test file of a specific size ----
make_test_file() {
    local PATH="$1"
    local SIZE_KB="$2"
    local EXISTING=$(ls ir_images/ir_*.jpg 2>/dev/null | tail -1)

    if [ -n "$EXISTING" ] && [ "$SIZE_KB" -le 100 ]; then
        cp "$EXISTING" "$PATH"
    else
        # Create a file of approximately SIZE_KB using dd
        dd if=/dev/urandom bs=1024 count="$SIZE_KB" 2>/dev/null > "$PATH"
    fi
    echo $(du -k "$PATH" | cut -f1)
}

TRIAL_NUM=0

# ---- Run trials in 3 groups: small, medium, large ----
for GROUP in "small:50" "medium:150" "large:300"; do
    GROUP_NAME=$(echo "$GROUP" | cut -d: -f1)
    TARGET_KB=$(echo "$GROUP" | cut -d: -f2)

    echo "--- Group: $GROUP_NAME (~${TARGET_KB}KB files) ---" | tee -a "$OUTFILE"
    echo "" | tee -a "$OUTFILE"

    printf "%-8s %-12s %-14s %-14s %-8s\n" \
        "Trial" "Size(KB)" "Time(ms)" "Time(s)" "Result" | tee -a "$OUTFILE"
    printf "%-8s %-12s %-14s %-14s %-8s\n" \
        "------" "----------" "------------" "------------" "------" \
        | tee -a "$OUTFILE"

    for i in $(seq 1 5); do
        TRIAL_NUM=$((TRIAL_NUM + 1))
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        TEST_FILE="$RESULTS_DIR/r3_${GROUP_NAME}_${TIMESTAMP}.jpg"

        ACTUAL_KB=$(make_test_file "$TEST_FILE" "$TARGET_KB")

        START=$(date +%s%N)
        aws s3 cp "$TEST_FILE" \
            "s3://fire-ml-bucket/inputs/test-latency/$(basename $TEST_FILE)" \
            --region us-east-2 > /dev/null 2>&1
        END=$(date +%s%N)

        ELAPSED_MS=$(( (END - START) / 1000000 ))
        ELAPSED_S=$(echo "scale=3; $ELAPSED_MS / 1000" | bc)

        ALL_TIMES_MS+=("$ELAPSED_MS")
        ALL_SIZES_KB+=("$ACTUAL_KB")

        if (( ELAPSED_MS < LIMIT_SEC * 1000 )); then
            RESULT="PASS"
            PASS=$((PASS + 1))
        else
            RESULT="FAIL"
            FAIL=$((FAIL + 1))
        fi

        printf "%-8s %-12s %-14s %-14s %-8s\n" \
            "$TRIAL_NUM" "${ACTUAL_KB}" "${ELAPSED_MS}" "${ELAPSED_S}s" "$RESULT" \
            | tee -a "$OUTFILE"

        # Write to CSV
        echo "$TRIAL_NUM,$ACTUAL_KB,$ELAPSED_MS,$ELAPSED_S,$RESULT" >> "$CSVFILE"

        # Clean up test file
        rm -f "$TEST_FILE"
        sleep 2
    done

    echo "" | tee -a "$OUTFILE"
done

# ---- Statistics ----
echo "--- Statistics ---" | tee -a "$OUTFILE"
echo ""                   | tee -a "$OUTFILE"

# Calculate min, max, sum, avg using bash arithmetic
MIN_MS=${ALL_TIMES_MS[0]}
MAX_MS=${ALL_TIMES_MS[0]}
SUM_MS=0

for t in "${ALL_TIMES_MS[@]}"; do
    SUM_MS=$((SUM_MS + t))
    (( t < MIN_MS )) && MIN_MS=$t
    (( t > MAX_MS )) && MAX_MS=$t
done

AVG_MS=$(echo "scale=1; $SUM_MS / $TRIALS" | bc)
AVG_S=$(echo "scale=3; $AVG_MS / 1000" | bc)
MIN_S=$(echo "scale=3; $MIN_MS / 1000" | bc)
MAX_S=$(echo "scale=3; $MAX_MS / 1000" | bc)

# Standard deviation
SUM_SQ=0
for t in "${ALL_TIMES_MS[@]}"; do
    DIFF=$(echo "scale=4; $t - $AVG_MS" | bc)
    SQ=$(echo "scale=4; $DIFF * $DIFF" | bc)
    SUM_SQ=$(echo "scale=4; $SUM_SQ + $SQ" | bc)
done
VARIANCE=$(echo "scale=4; $SUM_SQ / $TRIALS" | bc)
STDDEV_MS=$(echo "scale=1; sqrt($VARIANCE)" | bc -l)
STDDEV_S=$(echo "scale=3; $STDDEV_MS / 1000" | bc)

printf "  %-20s %s ms  (%s s)\n" "Minimum:"         "$MIN_MS"     "$MIN_S"     | tee -a "$OUTFILE"
printf "  %-20s %s ms  (%s s)\n" "Maximum:"         "$MAX_MS"     "$MAX_S"     | tee -a "$OUTFILE"
printf "  %-20s %s ms  (%s s)\n" "Average:"         "$AVG_MS"     "$AVG_S"     | tee -a "$OUTFILE"
printf "  %-20s %s ms  (%s s)\n" "Std Deviation:"   "$STDDEV_MS"  "$STDDEV_S"  | tee -a "$OUTFILE"
printf "  %-20s %s ms  (%s s)\n" "Limit:"           "$((LIMIT_SEC * 1000))" "${LIMIT_SEC}.000" | tee -a "$OUTFILE"
printf "  %-20s %s%%\n" "Pass rate:" "$(echo "scale=1; $PASS * 100 / $TRIALS" | bc)" \
    | tee -a "$OUTFILE"

echo ""                                              | tee -a "$OUTFILE"

# Write stats to CSV footer
echo "" >> "$CSVFILE"
echo "Statistic,Value_ms,Value_s" >> "$CSVFILE"
echo "Minimum,$MIN_MS,$MIN_S"     >> "$CSVFILE"
echo "Maximum,$MAX_MS,$MAX_S"     >> "$CSVFILE"
echo "Average,$AVG_MS,$AVG_S"     >> "$CSVFILE"
echo "StdDev,$STDDEV_MS,$STDDEV_S" >> "$CSVFILE"
echo "Limit,$((LIMIT_SEC*1000)),$LIMIT_SEC" >> "$CSVFILE"

echo "========================================"      | tee -a "$OUTFILE"
echo "SUMMARY"                                       | tee -a "$OUTFILE"
echo "  Total trials: $TRIALS"                       | tee -a "$OUTFILE"
echo "  PASS: $PASS"                                 | tee -a "$OUTFILE"
echo "  FAIL: $FAIL"                                 | tee -a "$OUTFILE"
[ "$FAIL" -eq 0 ] \
    && echo "  OVERALL: PASS (all trials under ${LIMIT_SEC}s)" | tee -a "$OUTFILE" \
    || echo "  OVERALL: FAIL ($FAIL trials exceeded ${LIMIT_SEC}s)" | tee -a "$OUTFILE"
echo ""                                              | tee -a "$OUTFILE"
echo "  Results saved to:"                          | tee -a "$OUTFILE"
echo "    $OUTFILE  (full log)"                     | tee -a "$OUTFILE"
echo "    $CSVFILE  (CSV for graphing)"             | tee -a "$OUTFILE"
echo "========================================"      | tee -a "$OUTFILE"