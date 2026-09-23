import Foundation

/// 共用的事件紀錄，讓 Demo 畫面能顯示事件的順序。
final class DemoJournal {

    private(set) var lines: [String] = []
    var onChange: (() -> Void)?

    func record(_ line: String) {
        lines.append(line)
        if lines.count > 40 { lines.removeFirst(lines.count - 40) }
        onChange?()
    }

    func clear() {
        lines.removeAll()
        onChange?()
    }

    var text: String {
        lines.suffix(14).joined(separator: "\n")
    }
}
