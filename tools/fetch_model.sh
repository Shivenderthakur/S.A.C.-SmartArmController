#!/usr/bin/env bash
# Downloads the MediaPipe hand landmarker model into the Android assets folder.
#
# The model is a 7.8 MB binary, so it is not committed. Run this once after
# cloning; the build will fail without it.
set -euo pipefail

URL="https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/android/app/src/main/assets/hand_landmarker.task"

if [[ -f "$DEST" ]]; then
  echo "already present: $DEST"
  exit 0
fi

mkdir -p "$(dirname "$DEST")"
echo "fetching hand_landmarker.task…"
curl -fsSL --retry 3 -o "$DEST" "$URL"
echo "wrote $DEST ($(du -h "$DEST" | cut -f1))"
