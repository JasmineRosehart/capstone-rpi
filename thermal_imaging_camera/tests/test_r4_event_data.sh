#!/bin/bash
# =============================================================
# TEST: R4 — Event Data Recording
# Requirement: Each capture records time, GPS location, and image
# Method: Verify saved images have matching timestamps across IR
#         and RGB, and that GPS EXIF fields are present
# Output: tests/results/r4_event_data.txt
# Prereq: At least one capture must exist in ir_images/ and rgb_images/
# =============================================================

RESULTS_DIR="tests/results"
mkdir -p "$RESULTS_DIR"
OUTFILE="$RESULTS_DIR/r4_event_data.txt"
PASS=0
FAIL=0
TOTAL=0

echo "========================================"  | tee "$OUTFILE"
echo "TEST R4: Event Data Recording"             | tee -a "$OUTFILE"
echo "Requirement: Each capture records time,"   | tee -a "$OUTFILE"
echo "             GPS location, and image data" | tee -a "$OUTFILE"
echo "Date: $(date)"                             | tee -a "$OUTFILE"
echo "========================================"  | tee -a "$OUTFILE"
echo ""                                          | tee -a "$OUTFILE"

# ---- 1. Check timestamp synchronization ----
echo "--- 1. Timestamp Synchronization ---"      | tee -a "$OUTFILE"
echo "Verifying IR and RGB images share timestamps..." | tee -a "$OUTFILE"
echo "" | tee -a "$OUTFILE"

IR_TIMESTAMPS=$(ls ir_images/ir_*.jpg 2>/dev/null \
    | sed 's|ir_images/ir_||' | sed 's|\.jpg||')

if [ -z "$IR_TIMESTAMPS" ]; then
    echo "  No IR images found. Run the app and capture at least one image first." \
        | tee -a "$OUTFILE"
else
    for ts in $IR_TIMESTAMPS; do
        TOTAL=$((TOTAL + 1))
        IR_FILE="ir_images/ir_${ts}.jpg"
        RGB_FILE="rgb_images/rgb_${ts}.jpg"

        if [ -f "$RGB_FILE" ]; then
            echo "  Timestamp $ts: IR ✓  RGB ✓  — PASS" | tee -a "$OUTFILE"
            PASS=$((PASS + 1))
        else
            echo "  Timestamp $ts: IR ✓  RGB ✗  — FAIL (no matching RGB)" \
                | tee -a "$OUTFILE"
            FAIL=$((FAIL + 1))
        fi
    done
fi

echo "" | tee -a "$OUTFILE"

# ---- 2. Check GPS EXIF in IR images ----
echo "--- 2. GPS EXIF in IR Images ---"          | tee -a "$OUTFILE"
echo "" | tee -a "$OUTFILE"

for img in ir_images/ir_*.jpg; do
    [ -f "$img" ] || { echo "  No IR images found." | tee -a "$OUTFILE"; break; }
    TOTAL=$((TOTAL + 1))
    GPS=$(exiftool "$img" 2>/dev/null | grep -i "GPS Position")
    if [ -n "$GPS" ]; then
        echo "  $(basename $img): $GPS — PASS" | tee -a "$OUTFILE"
        PASS=$((PASS + 1))
    else
        echo "  $(basename $img): No GPS data — FAIL" | tee -a "$OUTFILE"
        FAIL=$((FAIL + 1))
    fi
done

echo "" | tee -a "$OUTFILE"

# ---- 3. Check GPS EXIF in RGB images ----
echo "--- 3. GPS EXIF in RGB Images ---"         | tee -a "$OUTFILE"
echo "" | tee -a "$OUTFILE"

for img in rgb_images/rgb_*.jpg; do
    [ -f "$img" ] || { echo "  No RGB images found." | tee -a "$OUTFILE"; break; }
    TOTAL=$((TOTAL + 1))
    GPS=$(exiftool "$img" 2>/dev/null | grep -i "GPS Position")
    if [ -n "$GPS" ]; then
        echo "  $(basename $img): $GPS — PASS" | tee -a "$OUTFILE"
        PASS=$((PASS + 1))
    else
        echo "  $(basename $img): No GPS data — FAIL" | tee -a "$OUTFILE"
        FAIL=$((FAIL + 1))
    fi
done

echo "" | tee -a "$OUTFILE"

# ---- 4. Check S3 presence ----
echo "--- 4. S3 Cloud Storage Verification ---"  | tee -a "$OUTFILE"
echo "" | tee -a "$OUTFILE"

IR_S3=$(aws s3 ls s3://fire-ml-bucket/inputs/ir-images/ \
    --region us-east-2 2>/dev/null | wc -l)
RGB_S3=$(aws s3 ls s3://fire-ml-bucket/inputs/rgb-images/ \
    --region us-east-2 2>/dev/null | wc -l)

echo "  IR images in S3:  $IR_S3" | tee -a "$OUTFILE"
echo "  RGB images in S3: $RGB_S3" | tee -a "$OUTFILE"

if [ "$IR_S3" -gt 0 ] && [ "$RGB_S3" -gt 0 ]; then
    echo "  S3 upload verified — PASS" | tee -a "$OUTFILE"
    PASS=$((PASS + 1))
else
    echo "  S3 missing images — FAIL" | tee -a "$OUTFILE"
    FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

echo ""                                          | tee -a "$OUTFILE"
echo "========================================"  | tee -a "$OUTFILE"
echo "SUMMARY"                                  | tee -a "$OUTFILE"
echo "  Checks: $TOTAL"                         | tee -a "$OUTFILE"
echo "  PASS:   $PASS"                          | tee -a "$OUTFILE"
echo "  FAIL:   $FAIL"                          | tee -a "$OUTFILE"
[ "$FAIL" -eq 0 ] && echo "  OVERALL: PASS" | tee -a "$OUTFILE" \
                  || echo "  OVERALL: FAIL" | tee -a "$OUTFILE"
echo "========================================"  | tee -a "$OUTFILE"
echo "Saved: $OUTFILE"
