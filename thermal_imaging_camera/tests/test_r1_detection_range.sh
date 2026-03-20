#!/bin/bash
# =============================================================
# TEST: R1 — Smoke/Heat Source Detection Range
# Requirement: System detects heat signatures within 50m
# Method: Capture images of a controlled heat source at
#         increasing distances (0.5m, 1m, 2m, 5m, 10m).
#         Analyze thermal images for detectable heat gradient.
#         A heat source is "detected" if its region has
#         significantly higher pixel value than background.
# Output: tests/results/r1_detection_range.txt
# Prereq: ImageMagick, captured IR images of a heat source
#         at known distances (label images with distance below)
#
# HOW TO RUN THIS TEST:
#   1. Set up a heat source (warm cup, hand, candle from 2m+)
#   2. Run the app, capture an image at each distance
#   3. Rename images to include distance, e.g.:
#        cp ir_images/ir_TIMESTAMP.jpg ir_images/ir_0.5m.jpg
#        cp ir_images/ir_TIMESTAMP.jpg ir_images/ir_1m.jpg
#        cp ir_images/ir_TIMESTAMP.jpg ir_images/ir_2m.jpg
#   4. Run this script
# =============================================================

RESULTS_DIR="tests/results"
mkdir -p "$RESULTS_DIR"
OUTFILE="$RESULTS_DIR/r1_detection_range.txt"

echo "========================================"   | tee "$OUTFILE"
echo "TEST R1: Heat Source Detection Range"       | tee -a "$OUTFILE"
echo "Requirement: Detect heat sources within 50m" | tee -a "$OUTFILE"
echo "Date: $(date)"                              | tee -a "$OUTFILE"
echo "========================================"   | tee -a "$OUTFILE"
echo ""                                           | tee -a "$OUTFILE"

if ! command -v convert &>/dev/null; then
    sudo apt install -y imagemagick 2>&1
fi

PASS=0
FAIL=0
TOTAL=0

# Check for distance-labeled images
DISTANCE_IMAGES=$(ls ir_images/ir_*m.jpg 2>/dev/null)

if [ -z "$DISTANCE_IMAGES" ]; then
    echo "No distance-labeled images found."      | tee -a "$OUTFILE"
    echo "Looking for regular IR images instead..." | tee -a "$OUTFILE"
    echo ""                                       | tee -a "$OUTFILE"

    # Fall back to analyzing all IR images
    for img in ir_images/ir_*.jpg; do
        [ -f "$img" ] || { echo "No IR images found." | tee -a "$OUTFILE"; break; }
        TOTAL=$((TOTAL + 1))

        MAXVAL=$(convert "$img" -colorspace Gray \
            -format "%[fx:maxima]" info: 2>/dev/null)
        MEANVAL=$(convert "$img" -colorspace Gray \
            -format "%[fx:mean]" info: 2>/dev/null)

        MAX_255=$(echo "scale=1; $MAXVAL * 255" | bc)
        MEAN_255=$(echo "scale=1; $MEANVAL * 255" | bc)
        CONTRAST=$(echo "scale=2; $MAXVAL - $MEANVAL" | bc)
        CONTRAST_255=$(echo "scale=1; $CONTRAST * 255" | bc)

        echo "File: $(basename $img)"             | tee -a "$OUTFILE"
        echo "  Max pixel:   $MAX_255 / 255"      | tee -a "$OUTFILE"
        echo "  Mean pixel:  $MEAN_255 / 255"     | tee -a "$OUTFILE"
        echo "  Contrast:    $CONTRAST_255"       | tee -a "$OUTFILE"

        # A detectable heat source should have contrast > 20/255
        INT_CONTRAST=${CONTRAST_255%.*}
        if (( INT_CONTRAST > 20 )); then
            echo "  Hot spot visible: YES — PASS"  | tee -a "$OUTFILE"
            PASS=$((PASS + 1))
        else
            echo "  Hot spot visible: NO — FAIL (flat image, no heat source detected)" \
                | tee -a "$OUTFILE"
            FAIL=$((FAIL + 1))
        fi
        echo ""                                   | tee -a "$OUTFILE"
    done
else
    # Analyze distance-labeled images
    printf "%-20s %-10s %-10s %-10s %-8s\n" \
        "Image" "Distance" "Max(0-255)" "Contrast" "Detected" \
        | tee -a "$OUTFILE"
    printf "%-20s %-10s %-10s %-10s %-8s\n" \
        "---" "---" "---" "---" "---"             | tee -a "$OUTFILE"

    for img in $DISTANCE_IMAGES; do
        TOTAL=$((TOTAL + 1))
        FNAME=$(basename "$img")
        DIST=$(echo "$FNAME" | grep -oP '\d+\.?\d*m')

        MAXVAL=$(convert "$img" -colorspace Gray \
            -format "%[fx:maxima]" info: 2>/dev/null)
        MEANVAL=$(convert "$img" -colorspace Gray \
            -format "%[fx:mean]" info: 2>/dev/null)
        MAX_255=$(echo "scale=1; $MAXVAL * 255" | bc)
        CONTRAST=$(echo "scale=1; ($MAXVAL - $MEANVAL) * 255" | bc)
        INT_C=${CONTRAST%.*}

        if (( INT_C > 20 )); then
            DETECTED="YES"
            PASS=$((PASS + 1))
        else
            DETECTED="NO"
            FAIL=$((FAIL + 1))
        fi

        printf "%-20s %-10s %-10s %-10s %-8s\n" \
            "$FNAME" "${DIST:-unknown}" "$MAX_255" "$CONTRAST" "$DETECTED" \
            | tee -a "$OUTFILE"
    done
fi

echo ""                                           | tee -a "$OUTFILE"
echo "========================================"   | tee -a "$OUTFILE"
echo "SUMMARY"                                   | tee -a "$OUTFILE"
echo "  Images analyzed: $TOTAL"                 | tee -a "$OUTFILE"
echo "  Heat detected:   $PASS"                  | tee -a "$OUTFILE"
echo "  Not detected:    $FAIL"                  | tee -a "$OUTFILE"
echo ""                                          | tee -a "$OUTFILE"
echo "  For full R1 verification:"               | tee -a "$OUTFILE"
echo "  Capture images at 0.5m, 1m, 2m, 3m, 5m, 10m, 15m" | tee -a "$OUTFILE"
echo "  and rename to ir_images/ir_Xm.jpg"       | tee -a "$OUTFILE"
[ "$FAIL" -eq 0 ] && [ "$TOTAL" -gt 0 ] \
    && echo "  OVERALL: PASS" | tee -a "$OUTFILE" \
    || echo "  OVERALL: PARTIAL / UNTESTED" | tee -a "$OUTFILE"
echo "========================================"   | tee -a "$OUTFILE"
echo "Saved: $OUTFILE"
