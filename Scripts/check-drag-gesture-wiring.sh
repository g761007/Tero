#!/bin/bash
# 守門：.drag 的辨識器必須真的接到派送點。
#
# 為什麼是腳本而不是測試：測試接得到 `handleDragGesture`（`simulateDrag` 就是它），
# 但接不到「辨識器建構時那一行 `#selector` 指到誰」——UIKit 沒有公開 API 讀得出
# 一個 UIGestureRecognizer 的 target/action。
#
# 為什麼需要它：把 `handleDragGesture` 的內容掏空之後，19 個 drag 測試一條都沒紅
# （2026-09-18 的變異測試）。同一個形狀在 PR #79 已經讓一次修正整個沒落地：編譯過、
# 測試綠、守門綠，而使用者看到的行為完全沒變。這裡守的是**接線存在**，不是行為正確
# ——行為由 DragCallSiteTests 負責。
set -uo pipefail
cd "$(dirname "$0")/.."

file=Sources/Tero/TeroTabBar.swift
status=0

# 1. 辨識器的 action 必須是 handleDragGesture
if grep -q 'UILongPressGestureRecognizer(target: self, action: #selector(handleDragGesture(_:)))' "$file"; then
  echo "✓ dragRecognizer 的 action 指向 handleDragGesture"
else
  echo "✗ dragRecognizer 沒有接到 handleDragGesture（或寫法變了，請一併更新本守門）"
  grep -n "UILongPressGestureRecognizer(" "$file"
  status=1
fi

# 2. 辨識器必須真的掛到 view 上
if grep -q 'addGestureRecognizer(dragRecognizer)' "$file"; then
  echo "✓ dragRecognizer 有掛到 view 上"
else
  echo "✗ dragRecognizer 沒有被 addGestureRecognizer"
  status=1
fi

# 3. 派送點必須真的往下呼叫
if grep -A3 'func handleDragGesture' "$file" | grep -q 'handleDrag(recognizer)'; then
  echo "✓ handleDragGesture 有呼叫 handleDrag"
else
  echo "✗ handleDragGesture 沒有呼叫 handleDrag"
  sed -n '/func handleDragGesture/,/^    }/p' "$file"
  status=1
fi

# 長按（issue #96）是同一個形狀：測試從 simulateLongPress 進，接不到建構時那一行 #selector。
if grep -q 'UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressGesture(_:)))' "$file"; then
  echo "✓ longPressRecognizer 的 action 指向 handleLongPressGesture"
else
  echo "✗ longPressRecognizer 沒有接到 handleLongPressGesture（或寫法變了，請一併更新本守門）"
  status=1
fi

if grep -q 'addGestureRecognizer(longPressRecognizer)' "$file"; then
  echo "✓ longPressRecognizer 有掛到 view 上"
else
  echo "✗ longPressRecognizer 沒有被 addGestureRecognizer"
  status=1
fi

if grep -A3 'func handleLongPressGesture' "$file" | grep -q 'handleLongPress(recognizer)'; then
  echo "✓ handleLongPressGesture 有呼叫 handleLongPress"
else
  echo "✗ handleLongPressGesture 沒有呼叫 handleLongPress"
  status=1
fi

exit $status
