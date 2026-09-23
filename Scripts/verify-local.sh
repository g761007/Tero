#!/bin/bash
# 本機跑完 CI 的五個 job。
#
# 執行的是與 .github/workflows/ci.yml 相同的指令；合併前先在本機跑過，
# 不必等 CI 才知道結果。
#
# 用法：./Scripts/verify-local.sh [destination]
#   不給就由 Scripts/resolve-simulator.sh 挑一台——它一律解析成 UDID，
#   而且只接受 iOS 26+（理由見那支腳本）。要指定機型用 TERO_DEVICE。
set -uo pipefail
cd "$(dirname "$0")/.."

if [ $# -gt 0 ]; then
  DEST="$1"
elif [ -n "${TERO_DESTINATION:-}" ]; then
  DEST="$TERO_DESTINATION"
else
  DEST=$(./Scripts/resolve-simulator.sh) || exit 1
fi
export TERO_DESTINATION="$DEST"
LOGS=$(mktemp -d)
status=0

step() { printf '\n=== %s ===\n' "$1"; }
report() {
  if [ "$1" -eq 0 ]; then echo "✓ $2"; else echo "✗ $2（完整輸出：$3）"; status=1; fi
}

echo "HEAD:        $(git rev-parse --short HEAD)"
echo "destination: $DEST"

step "1/5 Swift 測試"
xcodebuild test -scheme Tero -destination "$DEST" > "$LOGS/tests.log" 2>&1
code=$?
grep -E "Executed [0-9]+ tests, with" "$LOGS/tests.log" | tail -1
# 跳過數要看得見：71 個測試用 XCTSkipUnless(isFloatingAvailable) 守著 iOS 26，
# 在舊 runtime 上會整批跳過而仍然回報 0 failures。
skipped=$(grep -c "was skipped" "$LOGS/tests.log" 2>/dev/null) || skipped=0
[ "$skipped" -gt 0 ] && echo "  （跳過 $skipped 個；FloatingGlass 的測試需要 iOS 26+）"
[ $code -ne 0 ] && grep -E "error:.*\.swift" "$LOGS/tests.log" | head -10
report $code "Swift 測試" "$LOGS/tests.log"

step "2/5 Swift Demo（SPM）"
( cd Demo/SwiftDemo && xcodegen generate && \
  xcodebuild build -project SwiftDemo.xcodeproj -scheme SwiftDemo -destination "$DEST" ) \
  > "$LOGS/swift-demo.log" 2>&1
report $? "Swift Demo" "$LOGS/swift-demo.log"

step "3/5 Objective-C Demo（source drop）"
( cd Demo/ObjCDemo && xcodegen generate && \
  xcodebuild build -project ObjCDemo.xcodeproj -scheme ObjCDemo -destination "$DEST" ) \
  > "$LOGS/objc-demo.log" 2>&1
report $? "Objective-C Demo" "$LOGS/objc-demo.log"

step "4/5 Demo 啟動"""
./Scripts/check-demos-launch.sh > "$LOGS/launch.log" 2>&1
code=$?
grep -E "^✓|^✗" "$LOGS/launch.log"
report $code "Demo 啟動" "$LOGS/launch.log"

step "5/5 資源、私有 API 與公開 API 守門"
./Scripts/check-no-resources.sh > "$LOGS/guards.log" 2>&1
report $? "資源守門" "$LOGS/guards.log"
./Scripts/check-no-private-api.sh >> "$LOGS/guards.log" 2>&1
report $? "私有 API 守門" "$LOGS/guards.log"
./Scripts/check-appearance-update-pairing.sh >> "$LOGS/guards.log" 2>&1
report $? "外觀更新請求成對守門" "$LOGS/guards.log"
./Scripts/check-drag-gesture-wiring.sh >> "$LOGS/guards.log" 2>&1
report $? "拖曳手勢接線守門" "$LOGS/guards.log"
./Scripts/check-shell-locale-safety.sh >> "$LOGS/guards.log" 2>&1
report $? "shell 變數展開的 locale 安全" "$LOGS/guards.log"
./Scripts/check-podspec.sh >> "$LOGS/guards.log" 2>&1
report $? "podspec 與 Objective-C 整合" "$LOGS/guards.log"
./Scripts/check-public-api.sh > "$LOGS/api.log" 2>&1
code=$?
grep -E "^✓|^✗" "$LOGS/api.log"
[ $code -ne 0 ] && sed -n '/^✗/,/^$/p' "$LOGS/api.log" | head -30
report $code "公開 API 守門" "$LOGS/api.log"

printf '\n'
if [ $status -eq 0 ]; then echo "全部通過。"; else echo "有項目未通過，log 在 $LOGS"; fi
exit $status
