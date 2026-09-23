#!/bin/bash
# 守門：套件內不得觸碰私有 API。
# 計畫書的 Private API Policy 原本只是文件約定，這裡把它變成 CI 擋得住的規則。
#
# 這是純文字比對，因此註解或字串裡提到這些名字一樣會被擋下——
# 要說明「為什麼不使用某個私有型別」，請寫在 docs/adr/ 而不是原始碼註解。
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

check '\b_(UI|CA|NS)[A-Z][A-Za-z]*' '底線前綴的私有系統型別（例如 _UILiquidLensView）'
check '\bCAFilter\b' 'CAFilter'
check '\b(NSClassFromString|NSSelectorFromString)\b' '以字串動態查找型別或 selector'
check '\bperformSelector\b' 'performSelector'

exit $status
