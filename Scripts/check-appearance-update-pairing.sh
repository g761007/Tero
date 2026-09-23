#!/bin/bash
# 守門：外觀更新請求必須三個一起發。
#
# 轉發鏈接對了，系統也不會自己回頭問——容器要在轉發目標改變之後主動請它重問。
# 三項（status bar／home indicator／螢幕邊緣手勢延後）共用同一個時機，漏掉一項
# 的症狀是「只有那一項不更新」，而那正是最難從畫面上看出來的一種。
#
# 為什麼是腳本而不是測試：TeroTabBarController 與 TeroNavigationContainer 都是
# final，測試無法用子類別攔截這些呼叫；「有沒有被呼叫」也不落在套件的兩個測試
# 接縫（controller 公開 API、純值型別）上。這裡守的是**成對出現**，不是時機正確
# ——時機由 ForwardingTests 的鏈路測試與真機驗收負責。
set -uo pipefail
cd "$(dirname "$0")/.."

status=0

for file in $(grep -rl "setNeedsStatusBarAppearanceUpdate" Sources || true); do
  a=$(grep -c "setNeedsStatusBarAppearanceUpdate" "$file")
  b=$(grep -c "setNeedsUpdateOfHomeIndicatorAutoHidden" "$file")
  c=$(grep -c "setNeedsUpdateOfScreenEdgesDeferringSystemGestures" "$file")
  if [ "$a" -eq "$b" ] && [ "$b" -eq "$c" ]; then
    echo "✓ ${file}：$a 處外觀更新請求三項齊全"
  else
    echo "✗ ${file}：三項數量不一致（status bar ${a}、home indicator ${b}、screen edges ${c}）"
    grep -n "setNeedsStatusBarAppearanceUpdate\|setNeedsUpdateOfHomeIndicatorAutoHidden\|setNeedsUpdateOfScreenEdgesDeferringSystemGestures" "$file"
    status=1
  fi
done

exit $status
