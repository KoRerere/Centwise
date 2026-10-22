#!/bin/bash
# One-time setup: generates the iOS / macOS host projects (ios/, macos/) around the Dart code,
# then applies Centwise's bundle settings. Safe to run again; existing files are not overwritten.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "需要先安装 Flutter：https://docs.flutter.dev/get-started/install/macos" >&2
  exit 1
fi

if [ ! -d ios ] || [ ! -d macos ]; then
  flutter create --platforms=ios,macos --org com.koray --project-name centwise .
  # flutter create adds a counter-app widget test that does not apply to this project.
  if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then
    mv test/widget_test.dart test/widget_test.dart.generated-unused
  fi
fi

plist=/usr/libexec/PlistBuddy
set_plist() { # file key type value
  "$plist" -c "Set :$2 $4" "$1" 2>/dev/null || "$plist" -c "Add :$2 $3 $4" "$1"
}

# iOS: name, Files app access to the ledger folder.
ios_plist=ios/Runner/Info.plist
set_plist "$ios_plist" CFBundleDisplayName string Centwise
set_plist "$ios_plist" CFBundleName string Centwise
set_plist "$ios_plist" CFBundleDevelopmentRegion string zh_CN
set_plist "$ios_plist" UIFileSharingEnabled bool true
set_plist "$ios_plist" LSSupportsOpeningDocumentsInPlace bool true

# macOS: name, user-selected file access for import/export, phone-sized preview window.
sed -i '' 's/^PRODUCT_NAME = .*/PRODUCT_NAME = Centwise/' macos/Runner/Configs/AppInfo.xcconfig
for entitlements in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  set_plist "$entitlements" com.apple.security.files.user-selected.read-write bool true
done
cat > macos/Runner/MainFlutterWindow.swift <<'SWIFT'
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 430, height: 900)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 380, height: 700)
    self.title = "Centwise"
    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }
}
SWIFT

flutter pub get
echo "完成。Mac 预览（演示数据）：flutter run -d macos --dart-define=CENTWISE_DEMO=true"
