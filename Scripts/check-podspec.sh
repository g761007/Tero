#!/bin/bash
# 守門：Tero.podspec 要能被真正的 Objective-C App 裝起來並編過，`.h`／`.m`／`.mm` 都要。
#
# **為什麼不只跑 `pod lib lint`**：那只證明 pod 自己編得起來。而這個套件提供 pod 的
# 唯一理由就是 Objective-C 整合——lint 綠燈完全不保證 ObjC 匯入得到產生的介面。
# 這正是這個專案一再被咬的形狀：守門是綠的，它守的那件事根本沒被檢查。
#
# **`.mm` 是重點**。SPM module 在 ObjC++ 匯入不可用（docs/spikes/0001-objc-interop.md），
# 而 pod 可以——但有條件：要 `use_frameworks! :linkage => :static`，而且 `.mm` 裡
# 必須先匯入 UIKit 再匯入產生的標頭。兩個條件任一漏掉就編不過，所以 fixture 兩個都涵蓋。
#
# **刻意不碰 CocoaPods trunk**。Trunk 於 2026-12-02 永久唯讀，之後連既有 pod 的新版本
# 都不再接受。這份 podspec 只供 `:git`／`:path` 取用，不上架。
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$(pwd)

export LANG=${LANG:-en_US.UTF-8}
export LC_ALL=${LC_ALL:-en_US.UTF-8}

command -v pod > /dev/null 2>&1 || {
  echo "✗ 找不到 cocoapods。這道守門驗的是 ObjC 透過 pod 的整合，跳過它等於沒驗。"
  echo "  安裝：gem install cocoapods（或 brew install cocoapods）"
  exit 1
}
command -v xcodegen > /dev/null 2>&1 || {
  echo "✗ 找不到 xcodegen。fixture 的 .xcodeproj 由它產生。"
  echo "  安裝：brew install xcodegen"
  exit 1
}

status=0
logs=$(mktemp -d)

# 一、podspec 本身要 lint 得過（會實際編譯）。
if pod lib lint Tero.podspec --allow-warnings --quick > "$logs/lint.log" 2>&1; then
  echo "✓ podspec lint"
else
  # --quick 跳過建置；真正的建置由下面的整合驗證負責，這裡只驗 podspec 的內容正確。
  echo "✗ podspec lint（完整輸出：$logs/lint.log）"
  grep -E "ERROR|error:" "$logs/lint.log" | head -5
  status=1
fi

# 二、真的裝進一個 Objective-C App 並編譯。
DEST=$(./Scripts/resolve-simulator.sh 2>/dev/null) || { echo "✗ 解析不到模擬器"; exit 1; }

work=$(mktemp -d)
cp -R Scripts/podspec-fixture/. "$work/"
(
  cd "$work" || exit 1
  export TERO_PODSPEC_ROOT="$REPO"
  xcodegen generate > /dev/null 2>&1 || { echo "xcodegen 失敗"; exit 1; }
  pod install > "$logs/install.log" 2>&1 || { echo "pod install 失敗"; exit 1; }
  xcodebuild build -workspace PodConsumer.xcworkspace -scheme PodConsumer \
    -destination "$DEST" -quiet > "$logs/build.log" 2>&1
) 
code=$?
if [ $code -eq 0 ]; then
  echo "✓ Objective-C App 透過 pod 整合並編譯（.h／.m／.mm）"
else
  echo "✗ Objective-C App 整合失敗（完整輸出：${logs}）"
  # 連結失敗的原因不在 `clang++: error:` 那一行，而在它前面的 `ld:` 與 Undefined symbols
  # 區塊。CI 的暫存目錄跑完就消失，這裡沒印出來就再也看不到。
  grep -E "error:|ld: |Undefined symbols|referenced from|symbol\(s\) not found" \
    "$logs/build.log" "$logs/install.log" 2>/dev/null | head -20
  status=1
fi

rm -rf "$work"
exit $status
