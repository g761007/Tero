#!/bin/bash
# 公開 API diff：與 Scripts/api/ 下的基準比對。
# 有意的變更請重新產生基準並在 commit 訊息說明。
set -uo pipefail
cd "$(dirname "$0")/.."

status=0

diff_against() {
  local actual="$1" baseline="$2" label="$3"
  if diff -u "$baseline" "$actual" > /tmp/tero-api-diff.txt; then
    echo "✓ $label 與基準一致"
  else
    echo "✗ $label 與基準不同："
    cat /tmp/tero-api-diff.txt
    status=1
  fi
}

./Scripts/extract-swift-api.sh > /tmp/tero-swift-api.txt
diff_against /tmp/tero-swift-api.txt Scripts/api/swift-api-baseline.txt "Swift 公開 API"

if [ "${TERO_SKIP_OBJC:-0}" != "1" ]; then
  ./Scripts/extract-objc-interface.sh > /tmp/tero-objc-api.txt
  diff_against /tmp/tero-objc-api.txt Scripts/api/objc-interface-baseline.txt "Objective-C 介面"
fi

exit $status
