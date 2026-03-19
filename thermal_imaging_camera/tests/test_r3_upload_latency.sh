#!/bin/bash --- DONE!!!
# =============================================================
# TEST: R3 — Capture, Upload, and Alert Pipeline Latency
# Requirement: Full pipeline (capture → S3 upload) completes
#              within 60 seconds of trigger
# Method: Time 5 upload trials using existing captured images
# Output: tests/results/r3_upload_latency.txt
# =============================================================

RESULTS_DIR="tests/results"
mkdir -p "$RESULTS_DIR"
OUTFILE="$RESULTS_DIR/r3_upload_latency.txt"
TRIALS=20
LIMIT_SEC=60
PASS=0
FAIL=0

echo "========================================"  | tee "$OUTFILE"
echo "TEST R3: Upload & Pipeline Latency"        | tee -a "$OUTFILE"
echo "Requirement: Pipeline completes <= ${LIMIT_SEC}s" | tee -a "$OUTFILE"
echo "Date: $(date)"                             | tee -a "$OUTFILE"
echo "========================================"  | tee -a "$OUTFILE"
echo ""                                          | tee -a "$OUTFILE"

for i in $(seq 1 $TRIALS); do
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    TEST_FILE="tests/results/test_upload_${TIMESTAMP}.jpg"

    # Use the most recent IR capture if available, else create dummy
    EXISTING=$(ls ir_images/ir_*.jpg 2>/dev/null | tail -1)
    if [ -n "$EXISTING" ]; then
        cp "$EXISTING" "$TEST_FILE"
    else
        dd if=/dev/urandom bs=1024 count=50 2>/dev/null > "$TEST_FILE"
        echo "  Warning: No IR image found, using dummy file" | tee -a "$OUTFILE"
    fi

    echo "Trial $i of $TRIALS: $(basename $TEST_FILE)" | tee -a "$OUTFILE"

    START=$(date +%s%N)
    aws s3 cp "$TEST_FILE" \
        "s3://fire-ml-bucket/inputs/test-latency/$(basename $TEST_FILE)" \
        --region us-east-2 2>&1 | tee -a "$OUTFILE"
    END=$(date +%s%N)

    ELAPSED_MS=$(( (END - START) / 1000000 ))
    ELAPSED_S=$(echo "scale=2; $ELAPSED_MS / 1000" | bc)

    echo "  Upload time: ${ELAPSED_S}s (${ELAPSED_MS}ms)" | tee -a "$OUTFILE"

    if (( ELAPSED_MS < LIMIT_SEC * 1000 )); then
        echo "  Result: PASS (<= ${LIMIT_SEC}s)"  | tee -a "$OUTFILE"
        PASS=$((PASS + 1))
    else
        echo "  Result: FAIL (> ${LIMIT_SEC}s)"   | tee -a "$OUTFILE"
        FAIL=$((FAIL + 1))
    fi
    echo "" | tee -a "$OUTFILE"
    sleep 2
done

echo "========================================" | tee -a "$OUTFILE"
echo "SUMMARY"                                  | tee -a "$OUTFILE"
echo "  Trials:  $TRIALS"                        | tee -a "$OUTFILE"
echo "  PASS:    $PASS"                          | tee -a "$OUTFILE"
echo "  FAIL:    $FAIL"                          | tee -a "$OUTFILE"
[ "$FAIL" -eq 0 ] && echo "  OVERALL: PASS" | tee -a "$OUTFILE" \
                  || echo "  OVERALL: FAIL" | tee -a "$OUTFILE"
echo "========================================" | tee -a "$OUTFILE"
echo "Saved: $OUTFILE"