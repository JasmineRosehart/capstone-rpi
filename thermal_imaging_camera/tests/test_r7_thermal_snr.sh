#!/bin/bash
# =============================================================
# TEST: R7 — Thermal Camera SNR
# Requirement: Thermal camera produces images with measurable SNR
#              sufficient for downstream ML model consumption
# Method: Use ImageMagick to extract mean and std deviation from
#         saved IR images. SNR = mean / stddev.
#         Also measures dynamic range (max - min pixel value).
# Output: tests/results/r7_thermal_snr.txt
# Prereq: sudo apt install imagemagick
#         At least one IR image must exist in ir_images/
# How to get good results:
#   - Capture images of a clear heat source (hand, warm cup)
#   - Capture images in a cool background (outdoors, cold room)
#   - The more contrast between signal and background, the higher SNR
# =============================================================

RESULTS_DIR="tests/results"
mkdir -p "$RESULTS_DIR"
OUTFILE="$RESULTS_DIR/r7_thermal_snr.txt"
SNR_THRESHOLD=5
PASS=0
FAIL=0
TOTAL=0

# Install ImageMagick if needed
if ! command -v convert &>/dev/null; then
    echo "Installing ImageMagick..."
    sudo apt install -y imagemagick 2>&1
fi

echo "========================================"  | tee "$OUTFILE"
echo "TEST R7: Thermal Camera SNR"               | tee -a "$OUTFILE"
echo "Requirement: SNR >= $SNR_THRESHOLD"        | tee -a "$OUTFILE"
echo "Date: $(date)"                             | tee -a "$OUTFILE"
echo "========================================"  | tee -a "$OUTFILE"
echo ""                                          | tee -a "$OUTFILE"
echo "SNR = mean pixel value / std deviation"   | tee -a "$OUTFILE"
echo "Dynamic range = (max - min) pixel value"  | tee -a "$OUTFILE"
echo ""                                          | tee -a "$OUTFILE"

printf "%-35s %-8s %-8s %-8s %-8s %-8s %-8s\n" \
    "File" "Mean" "StdDev" "Max" "Min" "SNR" "Result" \
    | tee -a "$OUTFILE"
printf "%-35s %-8s %-8s %-8s %-8s %-8s %-8s\n" \
    "-----------------------------------" "------" "------" \
    "------" "------" "------" "------" | tee -a "$OUTFILE"

for img in ir_images/ir_*.jpg; do
    [ -f "$img" ] || { echo "No IR images found. Capture some first." \
        | tee -a "$OUTFILE"; break; }

    TOTAL=$((TOTAL + 1))

    # Get statistics from ImageMagick (values are 0.0-1.0 scale)
    MEAN=$(convert "$img" -colorspace Gray \
        -format "%[fx:mean]" info: 2>/dev/null)
    STDDEV=$(convert "$img" -colorspace Gray \
        -format "%[fx:standard_deviation]" info: 2>/dev/null)
    MAXVAL=$(convert "$img" -colorspace Gray \
        -format "%[fx:maxima]" info: 2>/dev/null)
    MINVAL=$(convert "$img" -colorspace Gray \
        -format "%[fx:minima]" info: 2>/dev/null)

    # Convert to 0-255 scale
    MEAN_255=$(echo "scale=1; $MEAN * 255" | bc 2>/dev/null)
    STDDEV_255=$(echo "scale=1; $STDDEV * 255" | bc 2>/dev/null)
    MAX_255=$(echo "scale=1; $MAXVAL * 255" | bc 2>/dev/null)
    MIN_255=$(echo "scale=1; $MINVAL * 255" | bc 2>/dev/null)

    # Calculate SNR
    if (( $(echo "$STDDEV > 0" | bc -l) )); then
        SNR=$(echo "scale=2; $MEAN / $STDDEV" | bc 2>/dev/null)
    else
        SNR="inf"
    fi

    # Determine pass/fail
    if [ "$SNR" = "inf" ] || (( $(echo "$SNR >= $SNR_THRESHOLD" | bc -l) )); then
        RESULT="PASS"
        PASS=$((PASS + 1))
    else
        RESULT="FAIL"
        FAIL=$((FAIL + 1))
    fi

    FNAME=$(basename "$img")
    printf "%-35s %-8s %-8s %-8s %-8s %-8s %-8s\n" \
        "$FNAME" "$MEAN_255" "$STDDEV_255" \
        "$MAX_255" "$MIN_255" "$SNR" "$RESULT" \
        | tee -a "$OUTFILE"
done

echo ""                                          | tee -a "$OUTFILE"
echo "========================================"  | tee -a "$OUTFILE"
echo "SUMMARY"                                  | tee -a "$OUTFILE"
echo "  Images analyzed: $TOTAL"               | tee -a "$OUTFILE"
echo "  SNR threshold:   >= $SNR_THRESHOLD"     | tee -a "$OUTFILE"
echo "  PASS: $PASS"                            | tee -a "$OUTFILE"
echo "  FAIL: $FAIL"                            | tee -a "$OUTFILE"
[ "$FAIL" -eq 0 ] && [ "$TOTAL" -gt 0 ] \
    && echo "  OVERALL: PASS" | tee -a "$OUTFILE" \
    || echo "  OVERALL: FAIL or INSUFFICIENT DATA" | tee -a "$OUTFILE"
echo "========================================"  | tee -a "$OUTFILE"
echo "Saved: $OUTFILE"
