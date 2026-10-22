#!/bin/zsh -l
# 编译 Centwise 正式版并安装（替换）到已配对的 iPhone。日志：flutter/.dev-logs-iphone/install.log
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
cd "$(dirname "$0")/flutter" || exit 1
if ! command -v flutter >/dev/null 2>&1; then
  for d in /opt/homebrew/bin ~/development/flutter/bin ~/flutter/bin /usr/local/bin; do
    [ -x "$d/flutter" ] && export PATH="$d:$PATH" && break
  done
fi
mkdir -p .dev-logs-iphone
log=.dev-logs-iphone/install.log
{
  echo "== $(date '+%F %T') 开始"
  flutter --version | head -1
  if [ "$1" != "skip-build" ]; then
    flutter pub get || { echo "FAIL pub get"; exit 1; }
    dart analyze --no-fatal-warnings lib || { echo "FAIL analyze"; exit 1; }
    flutter build ios --release || { echo "FAIL build"; exit 1; }
  fi
  xcrun devicectl list devices --json-output /tmp/centwise-devs.json >/dev/null 2>&1
  dev=$(/usr/bin/python3 -c 'import json
d=json.load(open("/tmp/centwise-devs.json"))["result"]["devices"]
d=[x for x in d if x.get("hardwareProperties",{}).get("platform")=="iOS"]
d.sort(key=lambda x: x.get("connectionProperties",{}).get("tunnelState")!="connected")
print(d[0]["identifier"] if d else "")')
  xcrun devicectl list devices
  [ -z "$dev" ] && { echo "FAIL 没找到 iPhone"; exit 1; }
  echo "安装到设备 $dev"
  ok=0
  for n in 1 2 3; do
    echo "第 $n 次安装…"
    if xcrun devicectl device install app --device "$dev" build/ios/iphoneos/Runner.app; then ok=1; break; fi
    sleep 8
  done
  [ $ok = 1 ] || { echo "FAIL install"; exit 1; }
  echo "DONE $(date '+%F %T')"
} 2>&1 | tee "$log"
echo; echo "完成，按回车关闭窗口。"; read
