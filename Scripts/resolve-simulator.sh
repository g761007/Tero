#!/bin/bash
# 印出一個可用的 xcodebuild destination，一律解析成 `id=<UDID>`。
#
# **為什麼一定要 UDID**：在某些機器上 `-destination "platform=iOS Simulator,name=iPhone 17"`
# 解析不到，即使那台裝置存在、可用、而且已經開機——xcodebuild 自己印出的 available
# 清單裡明明就列著 `name:iPhone 17`。換成 `id=` 立刻正常。成因未查明，但「名稱解析不可靠」
# 是可重現的事實，所以這裡不賭它。（`check-demos-launch.sh` 一直沒事，正是因為它本來就
# 自己用 simctl 解析成 UDID。）
#
# **為什麼一定要 iOS 26+**：FloatingGlass 只在 26 以上存在，測試套件用
# `XCTSkipUnless(isFloatingAvailable)` 守著它——目前 71 處。在 18.x 的模擬器上跑，
# 那 71 個會整批跳過而**仍然回報 0 failures**。那是最糟的失敗模式：看起來驗過了，
# 其實沒驗。所以挑不到 26+ 時寧可失敗，不要降級。
#
# **挑選規則**（依序）：
#   1. 參數或 `TERO_DEVICE` 指定的名稱，限 iOS 26+
#   2. 預設機型 `iPhone 17`——與 CI 一致，本機與 CI 跑在同一種機器上比較好比對
#   3. 都沒有時退回 iOS 最新、名稱字母序最前的一台，並在 stderr 說明換了哪一台
#
# 用法：
#   Scripts/resolve-simulator.sh              # 用預設機型
#   Scripts/resolve-simulator.sh "iPhone 18 Pro"
#   TERO_DEVICE="iPhone 18 Pro" Scripts/resolve-simulator.sh
set -uo pipefail

# 與 .github/workflows/ci.yml 的 TERO_DEVICE 保持一致。
want="${1:-${TERO_DEVICE:-iPhone 17}}"

result=$(xcrun simctl list devices available -j 2>/dev/null | WANT="$want" python3 -c '
import json, os, sys

want = os.environ.get("WANT", "")
try:
    devices = json.load(sys.stdin)["devices"]
except Exception:
    sys.exit("無法讀取 simctl 的裝置清單")

candidates = []          # (major, minor, name, udid)
for runtime, items in devices.items():
    key = runtime.rsplit(".", 1)[-1]          # com.apple.CoreSimulator.SimRuntime.iOS-26-5
    if not key.startswith("iOS-"):
        continue
    parts = key.split("-")[1:]
    try:
        major, minor = int(parts[0]), int(parts[1]) if len(parts) > 1 else 0
    except ValueError:
        continue
    for item in items:
        if not item.get("isAvailable"):
            continue
        if not item["name"].startswith("iPhone"):
            continue
        candidates.append((major, minor, item["name"], item["udid"]))

modern = [c for c in candidates if c[0] >= 26]
if not modern:
    listing = ", ".join(sorted({f"{n} (iOS {a}.{b})" for a, b, n, _ in candidates})) or "（一台 iPhone 模擬器都沒有）"
    sys.exit(
        "找不到 iOS 26 以上的 iPhone 模擬器。\n"
        "FloatingGlass 只在 26 以上存在，71 個測試會整批跳過而仍然回報 0 failures，\n"
        "所以這裡不降級。請在 Xcode > Settings > Components 安裝 iOS 26+ 的 runtime。\n"
        f"目前可用：{listing}"
    )

chosen = None
if want:
    exact = [c for c in modern if c[2] == want]
    if exact:
        chosen = max(exact)                       # 同名多個 runtime 時取最新的
    else:
        print(f"注意：指定的「{want}」不在 iOS 26+ 的可用清單裡，改挑一台替代。", file=sys.stderr)
if chosen is None:
    # iOS 由新到舊，同版本取名稱字母序最前的一台——只是要一個確定的結果，
    # 不要每次跑在不同機型上。
    chosen = sorted(modern, key=lambda c: (-c[0], -c[1], c[2]))[0]

major, minor, name, udid = chosen
print(f"{name}|iOS {major}.{minor}|{udid}")
') || exit 1

name="${result%%|*}"
rest="${result#*|}"
os="${rest%%|*}"
udid="${rest##*|}"

echo "已選用模擬器：${name}（${os}）" >&2
echo "platform=iOS Simulator,id=$udid"
