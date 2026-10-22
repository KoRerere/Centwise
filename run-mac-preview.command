#!/bin/zsh -l
# Centwise 预览。默认在 Mac 上运行你的真实账本（保存在本机）。
#   zsh run-mac-preview.command          Mac 预览
#   zsh run-mac-preview.command iphone   装到用数据线连接的 iPhone（需先在 Xcode 里选好签名 Team）
#   再加 demo 使用演示数据，例如：zsh run-mac-preview.command iphone demo
#   zsh run-mac-preview.command iphone release   正式版：可以直接從手機桌面打開，但不能自動刷新
#
# 自动热重载：lib/ 下的 .dart 文件一变，先跑 dart analyze；没有错误就热重载（SIGUSR1），有错误则不重载。
# 日志在 flutter/.dev-logs/：run.log（flutter run 输出）、analyze.log（最近一次检查）。
# 创建 flutter/.dev-logs/restart 文件会触发一次热重启（SIGUSR2），用于热重载不生效的改动。
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
cd "$(dirname "$0")/flutter" || exit 1
if ! command -v flutter >/dev/null 2>&1; then
  for d in /opt/homebrew/bin ~/development/flutter/bin ~/flutter/bin /usr/local/bin; do
    [ -x "$d/flutter" ] && export PATH="$d:$PATH" && break
  done
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "没找到 flutter 命令，请确认 Flutter 已安装并加入 PATH。"; read; exit 1
fi

target=(-d macos)
logs=.dev-logs
if [ "$1" = "iphone" ]; then
  echo "正在查找已连接的 iPhone…"
  dev=$(flutter devices --machine 2>/dev/null | /usr/bin/python3 -c 'import json,sys
d=[x for x in json.load(sys.stdin) if str(x.get("targetPlatform","")).startswith("ios") and not x.get("emulator")]
print(d[0]["id"] if d else "")')
  if [ -z "$dev" ]; then
    echo "没找到已连接的 iPhone。请确认：数据线已连接、手机已点「信任此电脑」、已打开「设置 → 隐私与安全性 → 开发者模式」。"
    flutter devices
    read; exit 1
  fi
  target=(-d "$dev")
  logs=.dev-logs-iphone
fi
mkdir -p "$logs"
pidfile="$logs/flutter.pid"
rm -f "$pidfile" "$logs/restart"
touch "$logs/.stamp"

watch_and_reload() {
  while true; do
    sleep 1.5
    if [ -f "$logs/restart" ] && [ -f "$pidfile" ]; then
      rm -f "$logs/restart"
      echo "\n[自动] 热重启…"
      kill -USR2 "$(cat "$pidfile")" 2>/dev/null
      touch "$logs/.stamp"
      continue
    fi
    changed=$(find lib -name '*.dart' -newer "$logs/.stamp" 2>/dev/null | head -1)
    [ -z "$changed" ] && continue
    sleep 1   # let a batch of file writes finish
    touch "$logs/.stamp"
    if dart analyze --no-fatal-warnings lib > "$logs/analyze.log" 2>&1; then
      echo "ok $(date '+%H:%M:%S')" >> "$logs/analyze.log"
      if [ -f "$pidfile" ]; then
        echo "\n[自动] 检查通过，热重载…"
        kill -USR1 "$(cat "$pidfile")" 2>/dev/null
      fi
    else
      echo "\n[自动] 代码有错误，没有重载。详情：flutter/$logs/analyze.log"
    fi
  done
}

flutter --version
flutter pub get
watch_and_reload &
watcher=$!
trap 'kill $watcher 2>/dev/null' EXIT INT TERM
demo_flag=()
[[ " $* " == *" demo "* ]] && demo_flag=(--dart-define=CENTWISE_DEMO=true)
mode_flag=()
[[ " $* " == *" release "* ]] && mode_flag=(--release)
flutter run "${target[@]}" "${mode_flag[@]}" --pid-file "$pidfile" "${demo_flag[@]}" 2>&1 | tee "$logs/run.log"
kill $watcher 2>/dev/null
echo; echo "已退出。按回车关闭窗口。"; read
