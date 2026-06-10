#!/bin/bash
# Build the app and both Quick Look extensions (ad-hoc signed, Debug).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project OmniPreview.xcodeproj \
  -scheme OmniPreview \
  -configuration "${1:-Debug}" \
  -derivedDataPath build \
  build
echo "App: build/Build/Products/${1:-Debug}/OmniPreview.app"
