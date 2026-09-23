#!/bin/bash
# 守門：兩個 Demo 必須真的啟動得起來。
#
# `xcodebuild build` 只保證編得過。iOS 26 SDK 要求 scene lifecycle，缺了它
# 建置完全不會抱怨，App 卻會在啟動時直接失敗——這個缺口是使用者手動跑才發現的，
# 在那之前每一次驗證都誠實地回報「兩個 Demo 建置成功」。
#
# 因此這裡檢查的是「啟動後仍然活著」，不是「launch 指令有回傳」：
# scene lifecycle 缺失的失敗模式正是啟動後立刻結束。
set -uo pipefail
cd "$(dirname "$0")/.."

# verify-local.sh 會 export TERO_DESTINATION；沿用它，否則兩邊會跑在不同機器上。
# 沒有的話用同一支解析器自己挑。
if [ -n "${TERO_DESTINATION:-}" ] && [ "${TERO_DESTINATION#*id=}" != "$TERO_DESTINATION" ]; then
  UDID="${TERO_DESTINATION##*id=}"
else
  DEST=$(./Scripts/resolve-simulator.sh "${1:-${TERO_DEVICE:-iPhone 17}}") || exit 1
  UDID="${DEST##*id=}"
fi
[ -z "$UDID" ] && { echo "解析不到模擬器"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null
xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1

status=0
check() {
  local name="$1" dir="$2" scheme="$3" bundle="$4"
  local derived; derived=$(mktemp -d)
  ( cd "$dir" && xcodegen generate > /dev/null 2>&1 && \
    xcodebuild build -project "$scheme.xcodeproj" -scheme "$scheme" \
      -destination "id=$UDID" -derivedDataPath "$derived" -quiet > /dev/null 2>&1 )
  local app; app=$(find "$derived" -name "$scheme.app" -maxdepth 6 | head -1)
  [ -z "$app" ] && { echo "✗ ${name}：找不到 .app"; status=1; return; }

  xcrun simctl uninstall "$UDID" "$bundle" > /dev/null 2>&1
  xcrun simctl install "$UDID" "$app" > /dev/null 2>&1 || { echo "✗ ${name}：安裝失敗"; status=1; return; }

  local pid
  pid=$(xcrun simctl launch "$UDID" "$bundle" 2>&1)
  if [[ "$pid" == *"error"* || "$pid" == *"failed"* ]]; then
    echo "✗ ${name}：啟動失敗"
    echo "$pid" | head -3
    status=1
    return
  fi
  # 等狀態，不等秒數。固定 sleep 在忙碌的模擬器上會誤判——同一份程式碼兩次結果不同
  # 的守門，綠燈和紅燈都不能用來判斷任何事。
  #
  # 先等它出現（啟動需要時間），再確認它待得住（scene lifecycle 缺失會啟動後立刻死）。
  # 這裡和底下的存活迴圈用同一套「殘缺取樣不算數」的規則。
  #
  # 先前只有存活那一段做了，出現這一段沒有——於是它把「這次問不到」當成「App 不在」。
  # 症狀正是 2026-09-22 看到的：同一份程式碼單獨跑會過，接在整輪測試後面跑（機器正忙）
  # 就紅。綠燈和紅燈都不能用來判斷任何事的守門，比沒有守門更糟。
  local appeared=0 conclusive=0 snapshot lines
  for _ in $(seq 1 40); do
    snapshot=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null)
    lines=$(printf '%s' "$snapshot" | wc -l | tr -d ' ')
    # 正常清單有數百行；拿到殘缺的就是這次沒問到，不是「不在」的證據。
    if [ "$lines" -ge 20 ]; then
      conclusive=1
      if printf '%s' "$snapshot" | grep -q "$bundle"; then
        appeared=1
        break
      fi
    fi
    sleep 0.25
  done

  if [ "$appeared" -eq 0 ]; then
    # 把兩件事分開講，下次才知道是哪一種。
    if [ "$conclusive" -eq 0 ]; then
      echo "✗ ${name}：十秒內一次都沒問到完整的程序清單，這次檢查沒有結論"
    else
      echo "✗ ${name}：十秒內沒有出現在執行中的程序裡"
    fi
    status=1
    return
  fi

  # 出現之後再觀察一段，確認它不是啟動後隨即結束。
  #
  # 「App 不在了」和「這次檢查沒答出來」是兩件事。先前把兩者混為一談，守門在機器
  # 忙的時候就會紅得毫無道理：load 34 時連跑三次有五次紅，同一份程式碼在 load 25
  # 時六次全綠——那個機制始終沒能重現，所以這裡不賭某個根因，改成對它免疫：
  # 拿不到完整清單的取樣直接跳過，而且要連續兩次確定不在才判死。
  local survived=1 absent=0 snapshot lines
  for _ in $(seq 1 12); do
    sleep 0.25
    snapshot=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null)
    lines=$(printf '%s' "$snapshot" | wc -l | tr -d ' ')
    # 正常清單有數百行；拿到殘缺的就是這次沒問到，不是死亡證明。
    [ "$lines" -lt 20 ] && continue
    if printf '%s' "$snapshot" | grep -q "$bundle"; then
      absent=0
    else
      absent=$((absent + 1))
      if [ "$absent" -ge 2 ]; then
        survived=0
        break
      fi
    fi
  done

  if [ "$survived" -eq 1 ]; then
    echo "✓ $name 啟動後仍在執行"
  else
    echo "✗ ${name}：啟動後隨即結束（scene lifecycle？）"
    status=1
  fi
  xcrun simctl terminate "$UDID" "$bundle" > /dev/null 2>&1
}

check "Swift Demo" Demo/SwiftDemo SwiftDemo com.terotab.SwiftDemo
check "Objective-C Demo" Demo/ObjCDemo ObjCDemo com.terotab.ObjCDemo
exit $status
