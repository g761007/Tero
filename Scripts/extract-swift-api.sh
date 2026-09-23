#!/bin/bash
# 抽出 Swift 的公開 API 表面，供 diff 使用。
#
# 三件 grep 做不到、但守門需要的事：
#   1. attribute 寫在宣告的前一行時要併進來。`@objc(setTabs:selectedIdentifier:animated:)`
#      獨立成行的有 16 處；少了它，基準看起來是裸的 public func，改掉 selector 也看不出來。
#   2. attribute 前綴不是只有 @objc。@nonobjc public 一樣是公開表面。
#   3. public protocol 的成員不寫 public（存取層級由協定決定），
#      要知道某一行是不是協定成員只能追蹤大括號深度。
#   5. public enum 的 case 要記下來。case 不寫 public（存取層級由 enum 決定），
#      不記的話新增或移除一個 case 在基準上完全看不見——而 case 就是公開表面。
#   4. 跨行的參數列要接回同一行。只印宣告起始那一行的話，六個 delegate 方法會塌成
#      同一筆、三個 updateContentView 變體也會塌成同一筆——參數型別或 nullability
#      改掉，基準 diff 仍然是乾淨的。而那兩組正是最需要被釘住的。
#
# 排序必須與環境無關：預設 locale 會忽略大小寫，minimizeDuration 與
# minimizedCornerRadius 的先後在本機與 CI 會不一致。
set -uo pipefail
cd "$(dirname "$0")/.."
export LC_ALL=C

python3 - <<'PY' | sed -E 's/[[:space:]]+/ /g; s/ \{$//; s/^ //; s/ $//' | sort -u
import pathlib
import re

# 允許任意 attribute 前綴：@objc public、@nonobjc public 都是公開表面
PUBLIC = re.compile(r'^\s*(@[A-Za-z][^\s]*\s+)*(public|open)\s')
ATTRIBUTE = re.compile(r'^\s*@\w')
# 整行只有 attribute、沒有宣告本體時才暫存等下一行
DECL = re.compile(r'\b(public|open|func|var|let|init|subscript|associatedtype|static|class|enum|struct|protocol)\b')
PROTOCOL = re.compile(r'\bpublic\s+protocol\s+\w+')
MEMBER = re.compile(r'^\s*(@|associatedtype\b|func\b|var\b|init\b|subscript\b|static\b|mutating\b)')
ENUM = re.compile(r'\bpublic\s+enum\s+(\w+)')
CASE = re.compile(r'^\s*case\s+\w')

SIGNATURE = re.compile(r'\b(func|init|subscript)\b')


def logical_lines(text):
    """把跨行的參數列接回一行，其餘原樣保留。"""
    out = []
    buffer = None
    open_parens = 0
    for line in text.splitlines():
        if buffer is None:
            delta = line.count('(') - line.count(')')
            if delta > 0 and SIGNATURE.search(line):
                buffer = [line]
                open_parens = delta
            else:
                out.append(line)
        else:
            buffer.append(line.strip())
            open_parens += line.count('(') - line.count(')')
            if open_parens <= 0:
                out.append(' '.join(buffer))
                buffer = None
    if buffer is not None:
        out.append(' '.join(buffer))
    return out


for path in sorted(pathlib.Path('Sources').rglob('*.swift')):
    pending = []
    depth = 0
    entry = None
    enum_entry = None
    enum_name = None
    for line in logical_lines(path.read_text()):
        stripped = line.strip()

        if stripped.startswith('//'):
            pass
        elif ATTRIBUTE.match(line) and not DECL.search(line):
            # 單獨成行的 attribute：留著接到下一個宣告上
            pending.append(stripped)
            continue
        elif PUBLIC.match(line):
            print(' '.join(pending + [stripped]))
            pending = []
        elif entry is not None and depth == entry + 1 and MEMBER.match(line):
            print(' '.join(pending + [stripped]))
            pending = []
        elif enum_entry is not None and depth == enum_entry + 1 and CASE.match(line):
            # 帶上 enum 名字：不同 enum 的同名 case（例如 none）否則會被 sort -u 併掉
            print(f"{enum_name}.{stripped}")
            pending = []
        else:
            pending = []

        if entry is None:
            if PROTOCOL.search(line):
                entry = depth
        if enum_entry is None:
            match = ENUM.search(line)
            if match:
                enum_entry = depth
                enum_name = match.group(1)
        depth += line.count('{') - line.count('}')
        if entry is not None and depth <= entry:
            entry = None
        if enum_entry is not None and depth <= enum_entry:
            enum_entry = None
            enum_name = None
PY
