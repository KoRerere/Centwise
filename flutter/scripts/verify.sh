#!/bin/bash
# Static analysis, core tests, and debug builds for iOS (unsigned) and macOS.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
flutter analyze
flutter test
flutter build ios --debug --no-codesign
flutter build macos --debug
echo "分析、核心测试、iOS（未签名）与 macOS 构建均已通过。"
