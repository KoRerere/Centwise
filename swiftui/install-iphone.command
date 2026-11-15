#!/bin/zsh -l
# 编译 Centwise（SwiftUI 版，Release）并安装到已配对的 iPhone。日志：swiftui/.dev/device.log
cd "$(dirname "$0")" || exit 1
zsh .dev/device.sh 2>&1 | tee .dev/device.log
echo; echo "完成，可以关闭这个窗口。"
