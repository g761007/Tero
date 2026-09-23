#!/bin/bash
# 守門：套件內不得依賴任何資源檔（ADR-0007）。
# Objective-C 以 source drop 整合，SPM 的 resource bundle 在該模式下不存在。
set -uo pipefail
cd "$(dirname "$0")/.."

status=0

check() {
  local pattern="$1" label="$2"
  local hits
  hits=$(grep -REn "$pattern" Sources || true)
  if [ -n "$hits" ]; then
    echo "✗ 套件內出現 ${label}："
    echo "$hits"
    status=1
  else
    echo "✓ 無 $label"
  fi
}

check 'Bundle\.module' 'Bundle.module'
check 'NSLocalizedString' 'NSLocalizedString'
check 'UIImage\(named:' 'UIImage(named:)（請改用 systemName 或程式繪製）'
check 'UINib|loadNibNamed' 'nib 載入'

for suffix in strings stringsdict xcassets xib storyboard json plist; do
  hits=$(find Sources -name "*.$suffix" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "✗ 套件內出現 .$suffix 檔案：$hits"
    status=1
  fi
done
[ $status -eq 0 ] && echo "✓ 套件內無資源檔"

exit $status
