#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="$project_root/../CentwisePreview.app"
cd "$project_root"
swift build --product LedgerPreview
binary_path="$(swift build --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_path/LedgerPreview" "$app_path/Contents/MacOS/LedgerPreview"
cp "$project_root/PreviewInfo.plist" "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
printf 'Mac preview: %s\n' "$app_path"
