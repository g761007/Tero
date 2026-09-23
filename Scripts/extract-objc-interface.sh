#!/bin/bash
# 從 ObjCDemo 的 generated header 抽出對 Objective-C 可見的介面。
# 這同時驗證了 source drop 這條交付路徑真的能產生介面。
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="${1:-$(mktemp -d)}"
DEST="${TERO_DESTINATION:-$("$(dirname "$0")/resolve-simulator.sh")}"

(cd Demo/ObjCDemo && xcodegen generate >/dev/null)
# 輸出必須整個丟掉：-quiet 仍會把編譯警告寫到 stdout，而這支腳本的 stdout
# 就是基準檔本身。少了這個重導向，任何一個新的 deprecation 警告都會被寫進基準。
xcodebuild build \
  -project Demo/ObjCDemo/ObjCDemo.xcodeproj \
  -scheme ObjCDemo \
  -destination "$DEST" \
  -derivedDataPath "$DERIVED" \
  -quiet > /dev/null 2>&1

HEADER=$(find "$DERIVED" -name "ObjCDemo-Swift.h" | head -1)
if [ -z "$HEADER" ]; then
  echo "找不到 generated header——source drop 的交付路徑壞了" >&2
  exit 1
fi

python3 - "$HEADER" <<'PY'
import re, sys, pathlib
header = pathlib.Path(sys.argv[1]).read_text()
lines = []
for m in re.finditer(r'^@interface (Tero\w+)', header, re.M):
    lines.append(f"class {m.group(1)}")
for m in re.finditer(r'^@protocol (Tero\w+)', header, re.M):
    lines.append(f"protocol {m.group(1)}")
for m in re.finditer(r'typedef SWIFT_ENUM\w*\([^,]+,\s*(Tero\w+)', header):
    lines.append(f"enum {m.group(1)}")
# 前向宣告（@protocol Foo;）沒有 @end，若讓它參與比對，非貪婪的 (.*?) 會一路
# 吃到下一個型別的 @end，把那個型別的成員全部掛到前向宣告的名字底下。
for block in re.finditer(r'^@(?:interface|protocol) (Tero\w+)(?![^\n]*;[ \t]*$)[^\n]*\n(.*?)^@end', header, re.M | re.S):
    name, body = block.group(1), block.group(2)
    # 記完整 selector：只記第一段的話，setTabs:selectedIdentifier:animated: 與
    # setTabs: 無從區分，而改簽章正是這個守門要擋的事。
    for member in re.finditer(r'^\s*[-+]\s*\([^)]+\)\s*([^;]+);', body, re.M):
        signature = member.group(1)
        # 標了 SWIFT_UNAVAILABLE 的成員在 Objective-C 是編譯錯誤。留在基準裡，讀基準
        # 的 ObjC 使用者會以為 [TeroTabItem new] 可以用。
        if 'SWIFT_UNAVAILABLE' in signature:
            continue
        labels = re.findall(r'(\w+)\s*:\s*\(', signature)
        if labels:
            selector = ':'.join(labels) + ':'
        else:
            head = re.match(r'(\w+)', signature)
            if not head:
                continue
            selector = head.group(1)
        lines.append(f"  {name}.{selector}")
    for prop in re.finditer(r'^\s*(@property[^;]*?(\w+))\s*;', body, re.M):
        if 'SWIFT_UNAVAILABLE' in prop.group(1):
            continue
        lines.append(f"  {name}.{prop.group(2)}")
print("\n".join(sorted(set(lines))))
PY
