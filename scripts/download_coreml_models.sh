#!/usr/bin/env bash
# download_coreml_models.sh
#
# Downloads the two Apple CoreML models required for Phase 1 of the
# iCan Eye pipeline and places them ready to be added to the Xcode project.
#
# Usage:
#   chmod +x scripts/download_coreml_models.sh
#   ./scripts/download_coreml_models.sh
#
# After running, open Xcode and do:
#   File → Add Files to "Runner" → select ios/Runner/EyePipeline/Models/
#   Check "Copy items if needed" and "Add to target: Runner"

set -euo pipefail

DEST="ios/Runner/EyePipeline/Models"
mkdir -p "$DEST"

# ── Depth Anything V2 Small F16P6 (~19 MB) ───────────────────────────────────
DEPTH_ZIP="DepthAnythingV2SmallF16P6.mlpackage.zip"
DEPTH_URL="https://ml-assets.apple.com/coreml/models/Image/DepthEstimation/DepthAnything/DepthAnythingV2SmallF16P6.mlpackage.zip"

if [ -d "$DEST/DepthAnythingV2SmallF16P6.mlpackage" ]; then
  echo "[skip] Depth Anything V2 already present"
else
  echo "[download] Depth Anything V2 Small F16P6..."
  curl -L --progress-bar "$DEPTH_URL" -o "$DEST/$DEPTH_ZIP"
  unzip -q "$DEST/$DEPTH_ZIP" -d "$DEST"
  rm "$DEST/$DEPTH_ZIP"
  echo "[done] DepthAnythingV2SmallF16P6.mlpackage"
fi

# ── YOLOv3 Tiny (~35 MB) ─────────────────────────────────────────────────────
YOLO_URL="https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3Tiny.mlmodel"

if [ -f "$DEST/YOLOv3Tiny.mlmodel" ]; then
  echo "[skip] YOLOv3 Tiny already present"
else
  echo "[download] YOLOv3 Tiny..."
  curl -L --progress-bar "$YOLO_URL" -o "$DEST/YOLOv3Tiny.mlmodel"
  echo "[done] YOLOv3Tiny.mlmodel"
fi

echo ""
echo "Models saved to: $DEST"
echo ""
echo "Next step — add to Xcode project:"
echo "  1. Open ios/Runner.xcworkspace in Xcode"
echo "  2. File → Add Files to \"Runner\""
echo "  3. Select ios/Runner/EyePipeline/Models/"
echo "  4. Check 'Copy items if needed' and 'Add to target: Runner'"
echo "  5. Also add the ios/Runner/EyePipeline/*.swift files if not already added"
