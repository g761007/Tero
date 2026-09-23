#!/bin/bash
# 守門：`$var` 後面不可以直接接非 ASCII 字元。
#
# 在 UTF-8 locale 下 bash 會把後面那個多位元組字元當成變數名的一部分，於是
# `echo "已選用模擬器：$name（$os）"` 變成讀取一個叫 `name（` 的變數，配上 `set -u`
# 就是 `unbound variable`，整支腳本當場失敗。
#
# **這個 bug 只在 UTF-8 locale 下出現**，而這台開發機的預設 locale 是 C，所以本機
# 全綠、CI runner（一律 UTF-8）會炸。2026-09-22 一次掃出 16 處，全部是潛在的
# ——因為 CI 當時只在尚未建立的公開 repo 上執行，這些腳本從沒在 UTF-8 環境跑過。
#
# 寫法：`${name}（${os}）`，把變數名用大括號界定清楚。
set -uo pipefail
cd "$(dirname "$0")/.."

hits=$(python3 - <<'PY'
import pathlib, re
pattern = re.compile(r'\$([A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7f])')
found = []
for path in sorted(pathlib.Path("Scripts").glob("*.sh")):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        # 註解不會執行——這支守門自己的說明裡就寫著壞的那種寫法當範例。
        if line.lstrip().startswith("#"):
            continue
        for match in pattern.finditer(line):
            found.append(f"{path}:{number}  ${match.group(1)}  →  改成 ${{{match.group(1)}}}")
print("\n".join(found))
PY
)

if [ -z "$hits" ]; then
  echo "✓ shell 變數展開在 UTF-8 locale 下安全"
  exit 0
fi

echo "✗ 有 \$var 直接接非 ASCII 字元，UTF-8 locale 下會變成未定義變數："
echo "${hits}"
exit 1
