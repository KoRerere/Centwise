#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
swift test
xcodebuild -quiet -project QingLedger.xcodeproj -target QingLedger -sdk iphoneos -arch arm64 \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  SYMROOT="$project_root/.build/iOSProducts" OBJROOT="$project_root/.build/iOSObjects" build
printf 'Core tests and unsigned iOS arm64 build passed.\n'
