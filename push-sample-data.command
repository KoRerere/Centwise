#!/bin/zsh -l
# 生成虚拟账本并放进手机 Centwise 的 Import 文件夹；App 重启后显示导入预览，确认后才替换（替换前 App 会自动备份）。
# 推送前先把手机上的 Documents/Centwise 整个取回到 flutter/.dev-logs-iphone/phone-backup-<时间>/。
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
cd "$(dirname "$0")/flutter" || exit 1
if ! command -v flutter >/dev/null 2>&1; then
  for d in /opt/homebrew/bin ~/development/flutter/bin ~/flutter/bin /usr/local/bin; do
    [ -x "$d/flutter" ] && export PATH="$d:$PATH" && break
  done
fi
mkdir -p .dev-logs-iphone
log=.dev-logs-iphone/sample.log
stamp=$(date '+%Y%m%d-%H%M%S')
{
  echo "== $(date '+%F %T') 开始"
  sample=.dev-logs-iphone/虚拟账本-$stamp.centwise
  dart run bin/gen_sample.dart "$sample" || { echo "FAIL gen"; exit 1; }
  xcrun devicectl list devices --json-output /tmp/centwise-devs.json >/dev/null 2>&1
  dev=$(/usr/bin/python3 -c 'import json
d=json.load(open("/tmp/centwise-devs.json"))["result"]["devices"]
d=[x for x in d if x.get("hardwareProperties",{}).get("platform")=="iOS"]
print(d[0]["identifier"] if d else "")')
  [ -z "$dev" ] && { echo "FAIL 没找到 iPhone"; exit 1; }
  common=(--device "$dev" --domain-type appDataContainer --domain-identifier com.koray.centwise)
  backup=.dev-logs-iphone/phone-backup-$stamp
  ok=0
  for n in 1 2 3; do
    xcrun devicectl device copy from "${common[@]}" --source Documents --destination "$backup" && { ok=1; break; }
    sleep 6
  done
  [ $ok = 1 ] || { echo "FAIL backup"; exit 1; }
  echo "手机数据已备份到 flutter/$backup"; find "$backup" -type f | head -30
  ok=0
  for n in 1 2 3; do
    xcrun devicectl device copy to "${common[@]}" --source "$sample" --destination "Documents/Centwise/Import/虚拟账本-$stamp.centwise" && { ok=1; break; }
    sleep 6
  done
  [ $ok = 1 ] || { echo "FAIL push"; exit 1; }
  xcrun devicectl device process launch --device "$dev" --terminate-existing com.koray.centwise || echo "WARN 自动重启失败，请在手机上手动划掉并重新打开 Centwise"
  echo "DONE $(date '+%F %T')"
} 2>&1 | tee "$log"
echo; echo "完成，按回车关闭窗口。"; read
