#!/bin/bash
# =============================================================
# TEST: R4 — Event Data Recording
# Requirement: Each capture records time, GPS location, and image
# Method: Waits for the app to be running, then monitors the
#         ir_images/ and rgb_images/ folders for new captures.
#         You trigger captures manually by clicking "Capture Image"
#         in the app UI. This script watches for them and verifies
#         timestamp sync, GPS EXIF, and S3 upload for each one.
#
# Usage:
#   1. Start the app in another terminal:
#        sudo nice -n -20 ./raspberrypi_video -tl 3
#   2. Run this script:
#        bash tests/test_r4_event_data.sh
#   3. Click "Capture Image" in the app X times when prompted
#
# Output: tests/results/r4_event_data.txt
# =============================================================

RESULTS_DIR="tests/results"
mkdir -p "$RESULTS_DIR"
OUTFILE="$RESULTS_DIR/r4_event_data.txt"
PASS=0
FAIL=0
TOTAL=0
REQUIRED_CAPTURES=5 # Number of captures to test (you can adjust this)

echo "========================================"    | tee "$OUTFILE"
echo "TEST R4: Event Data Recording"               | tee -a "$OUTFILE"
echo "Requirement: Each capture records time,"     | tee -a "$OUTFILE"
echo "             GPS location, and image data"   | tee -a "$OUTFILE"
echo "Date: $(date)"                               | tee -a "$OUTFILE"
echo "========================================"    | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"

# ---- Check app is running ----
if ! pgrep -f "raspberrypi_video" > /dev/null; then
    echo "ERROR: raspberrypi_video is not running." | tee -a "$OUTFILE"
    echo "Start it first with:"                     | tee -a "$OUTFILE"
    echo "  sudo nice -n -20 ./raspberrypi_video -tl 3" | tee -a "$OUTFILE"
    exit 1
fi

echo "App detected. Ready to monitor captures."   | tee -a "$OUTFILE"
echo ""                                            | tee -a "$OUTFILE"

# ---- Record baseline (existing files before test) ----
BEFORE_IR=$(ls ir_images/ir_*.jpg 2>/dev/null | sort)
BEFORE_RGB=$(ls rgb_images/rgb_*.jpg 2>/dev/null | sort)

# ---- Prompt user to trigger captures ----
echo "============================================"
echo "ACTION REQUIRED:"
echo "  Click 'Capture Image' in the app UI"
echo "  ${REQUIRED_CAPTURES} times."
echo "  This script will detect each capture automatically."
echo "============================================"
echo ""

CAPTURED=0
SEEN_TIMESTAMPS=""

while [ "$CAPTURED" -lt "$REQUIRED_CAPTURES" ]; do
    echo "Waiting for capture $((CAPTURED + 1)) of ${REQUIRED_CAPTURES}..." \
        | tee -a "$OUTFILE"

    # Poll for new IR images
    TIMEOUT=60
    ELAPSED=0
    NEW_IR=""
    while [ -z "$NEW_IR" ] && [ "$ELAPSED" -lt "$TIMEOUT" ]; do
        sleep 2
        ELAPSED=$((ELAPSED + 2))
        CURRENT_IR=$(ls ir_images/ir_*.jpg 2>/dev/null | sort)
        # Find files that weren't there before
        for f in $CURRENT_IR; do
            if ! echo "$BEFORE_IR" | grep -qF "$f" && \
               ! echo "$SEEN_TIMESTAMPS" | grep -qF "$(basename $f)"; then
                NEW_IR="$f"
                break
            fi
        done
    done

    if [ -z "$NEW_IR" ]; then
        echo "  Timeout waiting for capture — did you click the button?" \
            | tee -a "$OUTFILE"
        break
    fi

    # Extract timestamp from filename
    TS=$(basename "$NEW_IR" | sed 's/ir_//' | sed 's/\.jpg//')
    SEEN_TIMESTAMPS="$SEEN_TIMESTAMPS $TS"
    CAPTURED=$((CAPTURED + 1))
    BEFORE_IR="$BEFORE_IR $NEW_IR"

    echo ""                                        | tee -a "$OUTFILE"
    echo "--- Capture $CAPTURED detected: $TS ---" | tee -a "$OUTFILE"
    echo ""                                        | tee -a "$OUTFILE"

    IR_FILE="ir_images/ir_${TS}.jpg"
    RGB_FILE="rgb_images/rgb_${TS}.jpg"

    # ---- Check 1: IR image exists ----
    TOTAL=$((TOTAL + 1))
    if [ -f "$IR_FILE" ]; then
        SIZE=$(du -k "$IR_FILE" | cut -f1)
        echo "  [1] IR image:   FOUND (${SIZE}KB) — PASS"  | tee -a "$OUTFILE"
        PASS=$((PASS + 1))
    else
        echo "  [1] IR image:   NOT FOUND — FAIL"           | tee -a "$OUTFILE"
        FAIL=$((FAIL + 1))
    fi

    # ---- Check 2: RGB image exists with matching timestamp ----
    TOTAL=$((TOTAL + 1))
    # Give RGB a moment to save (it runs concurrently)
    sleep 3
    if [ -f "$RGB_FILE" ]; then
        SIZE=$(du -k "$RGB_FILE" | cut -f1)
        echo "  [2] RGB image:  FOUND (${SIZE}KB) — PASS"  | tee -a "$OUTFILE"
        PASS=$((PASS + 1))
    else
        echo "  [2] RGB image:  NOT FOUND (timestamp mismatch?) — FAIL" \
            | tee -a "$OUTFILE"
        FAIL=$((FAIL + 1))
    fi

    # ---- Check 3: GPS EXIF in IR image ----
    TOTAL=$((TOTAL + 1))
    # Give exiftool a moment after save
    sleep 2
    GPS_IR=$(exiftool "$IR_FILE" 2>/dev/null | grep -i "GPS Position")
    if [ -n "$GPS_IR" ]; then
        echo "  [3] IR GPS EXIF: $GPS_IR — PASS"            | tee -a "$OUTFILE"
        PASS=$((PASS + 1))
    else
        echo "  [3] IR GPS EXIF: NOT FOUND — FAIL"          | tee -a "$OUTFILE"
        FAIL=$((FAIL + 1))
    fi

    # ---- Check 4: GPS EXIF in RGB image ----
    TOTAL=$((TOTAL + 1))
    if [ -f "$RGB_FILE" ]; then
        GPS_RGB=$(exiftool "$RGB_FILE" 2>/dev/null | grep -i "GPS Position")
        if [ -n "$GPS_RGB" ]; then
            echo "  [4] RGB GPS EXIF: $GPS_RGB — PASS"      | tee -a "$OUTFILE"
            PASS=$((PASS + 1))
        else
            echo "  [4] RGB GPS EXIF: NOT FOUND — FAIL"     | tee -a "$OUTFILE"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  [4] RGB GPS EXIF: SKIPPED (no RGB file)"    | tee -a "$OUTFILE"
    fi

    # ---- Check 5: File appears in S3 ----
    TOTAL=$((TOTAL + 1))
    sleep 5  # Give S3 upload time to complete
    S3_IR=$(aws s3 ls \
        "s3://fire-ml-bucket/inputs/ir-images/ir_images/ir_${TS}.jpg" \
        --region us-east-2 2>/dev/null)
    if [ -n "$S3_IR" ]; then
        echo "  [5] S3 upload:  CONFIRMED — PASS"            | tee -a "$OUTFILE"
        PASS=$((PASS + 1))
    else
        # Try alternate path
        S3_IR2=$(aws s3 ls \
            "s3://fire-ml-bucket/inputs/ir-images/" \
            --region us-east-2 2>/dev/null | grep "ir_${TS}")
        if [ -n "$S3_IR2" ]; then
            echo "  [5] S3 upload:  CONFIRMED — PASS"        | tee -a "$OUTFILE"
            PASS=$((PASS + 1))
        else
            echo "  [5] S3 upload:  NOT YET VISIBLE (may still be uploading) — CHECK MANUALLY" \
                | tee -a "$OUTFILE"
            FAIL=$((FAIL + 1))
        fi
    fi

    echo ""                                        | tee -a "$OUTFILE"
    echo "  Capture $CAPTURED complete."           | tee -a "$OUTFILE"
    echo ""                                        | tee -a "$OUTFILE"

    if [ "$CAPTURED" -lt "$REQUIRED_CAPTURES" ]; then
        echo "============================================"
        echo "  Click 'Capture Image' again ($((REQUIRED_CAPTURES - CAPTURED)) more needed)"
        echo "============================================"
    fi
done

# ---- Final S3 count ----
echo "--- S3 Bucket Contents ---"                  | tee -a "$OUTFILE"
echo "IR images in S3:"                            | tee -a "$OUTFILE"
aws s3 ls s3://fire-ml-bucket/inputs/ir-images/ \
    --region us-east-2 2>/dev/null | tail -5       | tee -a "$OUTFILE"
echo "RGB images in S3:"                           | tee -a "$OUTFILE"
aws s3 ls s3://fire-ml-bucket/inputs/rgb-images/ \
    --region us-east-2 2>/dev/null | tail -5       | tee -a "$OUTFILE"

echo ""                                            | tee -a "$OUTFILE"
echo "========================================"    | tee -a "$OUTFILE"
echo "SUMMARY"                                    | tee -a "$OUTFILE"
echo "  Captures tested: $CAPTURED"               | tee -a "$OUTFILE"
echo "  Total checks:    $TOTAL"                  | tee -a "$OUTFILE"
echo "  PASS:            $PASS"                   | tee -a "$OUTFILE"
echo "  FAIL:            $FAIL"                   | tee -a "$OUTFILE"
[ "$FAIL" -eq 0 ] && [ "$CAPTURED" -ge "$REQUIRED_CAPTURES" ] \
    && echo "  OVERALL: PASS" | tee -a "$OUTFILE" \
    || echo "  OVERALL: FAIL" | tee -a "$OUTFILE"
echo "========================================"    | tee -a "$OUTFILE"
echo "Saved: $OUTFILE"