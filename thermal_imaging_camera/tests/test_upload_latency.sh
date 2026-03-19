#!/bin/bash
# test_upload_latency.sh
# Tests R3: Measures time from image capture to S3 upload confirmation
# Run: bash test_upload_latency.sh
# Output: test_results/upload_latency.txt

OUTPUT_DIR="test_results"
mkdir -p "$OUTPUT_DIR"
OUTFILE="$OUTPUT_DIR/upload_latency.txt"

echo "======================================" | tee "$OUTFILE"
echo "TEST: Upload Latency (R3)" | tee -a "$OUTFILE"
echo "Requirement: Upload within 30 seconds" | tee -a "$OUTFILE"
echo "Date: $(date)" | tee -a "$OUTFILE"
echo "======================================" | tee -a "$OUTFILE"

PASS=0
FAIL=0
TOTAL=5

echo "" | tee -a "$OUTFILE"
echo "Running $TOTAL capture-and-upload trials..." | tee -a "$OUTFILE"
echo "" | tee -a "$OUTFILE"

for i in $(seq 1 $TOTAL); do
    # Create a test image to simulate a capture
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    TEST_FILE="test_results/test_upload_${TIMESTAMP}.jpg"

    # Use an existing IR image if available, otherwise create dummy
    EXISTING=$(ls ir_images/ir_*.jpg 2>/dev/null | tail -1)
    if [ -n "$EXISTING" ]; then
        cp "$EXISTING" "$TEST_FILE"
    else
        # Create a small dummy file
        dd if=/dev/urandom bs=1024 count=50 2>/dev/null > "$TEST_FILE"
    fi

    echo "Trial $i: Uploading $TEST_FILE..." | tee -a "$OUTFILE"

    START=$(date +%s%N)

    # Upload to S3
    aws s3 cp "$TEST_FILE" \
        "s3://fire-ml-bucket/inputs/test-uploads/$(basename $TEST_FILE)" \
        --region us-east-2 2>&1

    END=$(date +%s%N)
    ELAPSED_MS=$(( (END - START) / 1000000 ))
    ELAPSED_S=$(echo "scale=2; $ELAPSED_MS / 1000" | bc)

    echo "  Time: ${ELAPSED_S}s (${ELAPSED_MS}ms)" | tee -a "$OUTFILE"

    if [ "$ELAPSED_MS" -lt 30000 ]; then
        echo "  Result: PASS (under 30s)" | tee -a "$OUTFILE"
        PASS=$((PASS + 1))
    else
        echo "  Result: FAIL (over 30s)" | tee -a "$OUTFILE"
        FAIL=$((FAIL + 1))
    fi

    echo "" | tee -a "$OUTFILE"
    sleep 2
done

echo "======================================" | tee -a "$OUTFILE"
echo "SUMMARY:" | tee -a "$OUTFILE"
echo "  PASS: $PASS / $TOTAL" | tee -a "$OUTFILE"
echo "  FAIL: $FAIL / $TOTAL" | tee -a "$OUTFILE"
if [ "$FAIL" -eq 0 ]; then
    echo "  OVERALL: PASS" | tee -a "$OUTFILE"
else
    echo "  OVERALL: FAIL" | tee -a "$OUTFILE"
fi
echo "======================================" | tee -a "$OUTFILE"
echo "Results saved to $OUTFILE"
