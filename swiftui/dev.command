#!/bin/zsh -l
# Centwise SwiftUI 版开发助手：双击运行后保持窗口开着即可。
#  - 启动时：用本机 Xcode 编译，装进 iPhone 模拟器并打开 App，截几张图。
#  - 之后：等待 Claude 写入 .dev/request，收到后重新编译、运行、截图，结果写回 .dev/。
#  - 关掉这个窗口就停止。所有日志都在 swiftui/.dev/ 里。
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
cd "$(dirname "$0")" || exit 1
ROOT=$PWD
DEV=$ROOT/.dev
BUNDLE=com.koray.centwise.swift
DD="$HOME/Library/Developer/Xcode/DerivedData/Centwise-SwiftUI"
APP="$DD/Build/Products/Debug-iphonesimulator/Centwise.app"
SEED="$ROOT/../Money Pro 数据备份 2026-10-28/Centwise-个人账本-20261028-0153.centwise"
mkdir -p "$DEV/shots"
rm -f "$DEV/request"

say() { echo "[$(date '+%H:%M:%S')] $*"; }
status() { echo "$*" > "$DEV/status.tmp" && mv "$DEV/status.tmp" "$DEV/status"; }

{
  echo "== $(date)"
  sw_vers
  xcode-select -p
  xcodebuild -version
  xcrun simctl list runtimes
} > "$DEV/env.txt" 2>&1
say "Xcode: $(xcodebuild -version | head -1)"

# Pick a simulator: an already booted iPhone, else iPhone 16 Pro / 17 Pro on the newest iOS, else any iPhone.
SIM=$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json,sys,re
d=json.load(sys.stdin)["devices"]
def ver(k):
    m=re.search(r"iOS-(\d+)-(\d+)",k); return (int(m.group(1)),int(m.group(2))) if m else (0,0)
rts=sorted([k for k in d if "iOS" in k],key=ver,reverse=True)
devs=[(rt,x) for rt in rts for x in d[rt] if x["name"].startswith("iPhone")]
for rt,x in devs:
    if x["state"]=="Booted": print(x["udid"]); sys.exit()
for want in ["iPhone 16 Pro","iPhone 17 Pro","iPhone 17","iPhone 16"]:
    for rt,x in devs:
        if x["name"]==want: print(x["udid"]); sys.exit()
print(devs[0][1]["udid"] if devs else "")')
if [ -z "$SIM" ]; then
  say "没有找到 iPhone 模拟器。请打开 Xcode → Settings → Components 安装 iOS 模拟器后重试。"
  status "error no-simulator"; read; exit 1
fi
echo "simulator $SIM" >> "$DEV/env.txt"
xcrun simctl list devices | grep "$SIM" >> "$DEV/env.txt"
say "模拟器: $(xcrun simctl list devices | grep "$SIM" | sed 's/^ *//')"
xcrun simctl boot "$SIM" >/dev/null 2>&1
open -a Simulator --args -CurrentDeviceUDID "$SIM"
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 >/dev/null 2>&1

build() {
  say "编译中…"
  local t0=$SECONDS
  xcodebuild -project Centwise.xcodeproj -scheme Centwise -configuration Debug \
    -destination "id=$SIM" -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build > "$DEV/build.log" 2>&1
  local rc=$?
  grep -E "(error|warning): " "$DEV/build.log" | grep -v "^ld: warning" | sed "s|$ROOT/||" | sort -u > "$DEV/errors.txt"
  say "编译结束（$((SECONDS-t0)) 秒），退出码 $rc，$(grep -c ' error: ' "$DEV/errors.txt") 个错误"
  return $rc
}

install_app() {
  xcrun simctl install "$SIM" "$APP" || return 1
  local data
  data=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data 2>/dev/null)
  if [ -n "$data" ] && [ ! -f "$data/Documents/Centwise/ledger.centwise" ] && [ -f "$SEED" ]; then
    mkdir -p "$data/Documents/Centwise"
    cp "$SEED" "$data/Documents/Centwise/ledger.centwise"
    say "已放入你的账本数据（Money Pro 迁移备份）"
  fi
  return 0
}

# launch [args...]
launch() {
  xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl launch --terminate-running-process --stdout="$DEV/app.log" --stderr="$DEV/app.log" "$SIM" "$BUNDLE" "$@" >/dev/null
}

# shot NAME APPEARANCE WAIT [args...]
shot() {
  local name=$1 look=$2 wait=$3; shift 3
  xcrun simctl ui "$SIM" appearance "$look" >/dev/null 2>&1
  launch "$@"
  sleep "$wait"
  xcrun simctl io "$SIM" screenshot --type=png "$DEV/shots/$name.png" >/dev/null 2>&1
  say "截图 $name"
}

run_request() {
  local req=$1 id ok=1
  id=$(grep -m1 '^id ' "$req" | cut -d' ' -f2)
  status "busy $id"
  rm -f "$DEV"/shots/*.png
  if build; then
    if install_app; then
      while read -r kind rest; do
        case $kind in
          shot) eval "shot $rest" ;;
          reset)  # remove the app's data so the seed is copied again
            xcrun simctl uninstall "$SIM" "$BUNDLE"; install_app ;;
        esac
      done < "$req"
      xcrun simctl ui "$SIM" appearance light >/dev/null 2>&1
      launch
      status "done $id ok $(date '+%H:%M:%S')"
    else
      status "done $id installfail $(date '+%H:%M:%S')"
    fi
  else
    status "done $id buildfail $(date '+%H:%M:%S')"
  fi
}

# First run: build, launch and a few screenshots.
cat > "$DEV/first.request" <<'REQ'
id 0
shot dashboard light 4
shot settings light 4 -CWSheet settings
REQ
run_request "$DEV/first.request"
rm -f "$DEV/first.request"

say "待命中：Claude 改完代码会自动重新编译。关闭此窗口即停止。"
while true; do
  if [ -f "$DEV/request" ]; then
    mv "$DEV/request" "$DEV/current.request"
    say "收到新请求"
    run_request "$DEV/current.request"
  fi
  sleep 1
done
