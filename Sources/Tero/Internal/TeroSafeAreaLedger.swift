import UIKit

/// 記錄每個 direct child 收到多少來自本容器的 safe area inset。
///
/// **只增減自己的 contribution**，永遠不覆寫整個值——Consumer 自己設的 inset 要原封保留
/// （ADR-0004 的 2.0 修訂）。
///
/// 一個帳本綁一個軸，這是型別層面的軸擁有權：Tab Bar 容器寫 bottom，Navigation Container
/// 寫 top，兩者都不得轉寫它從上層收到的 inset。把 edge 放進 `init` 而不是每次呼叫時傳，
/// 是為了讓「一個容器只寫一向」這條規則無法在呼叫端被繞過。
///
/// entry 綁 containment：View Controller 成為 direct child 時建立、離開 children 時歸還，
/// 與轉場是否提交無關。
internal struct TeroSafeAreaLedger {

    internal enum Edge {
        case top
        case bottom
    }

    private let edge: Edge
    private var contributions: [ObjectIdentifier: CGFloat] = [:]
    /// 本帳本上次實際寫進 child 的那一向總值。
    ///
    /// 只記貢獻不夠：差量記帳假設「child 的現值仍然含著我們上次那一筆」，而 Consumer
    /// 在 `viewDidLoad` 裡**指派**（而不是累加）`additionalSafeAreaInsets` 就會把它抹掉。
    /// 之後同值再套用會在相等短路處被擋掉，貢獻永遠補不回來；歸還則會減掉一筆不存在的
    /// 值。記住寫過什麼，才分得出「沒人動過」和「child 自己改過」。
    private var lastWritten: [ObjectIdentifier: CGFloat] = [:]

    internal init(edge: Edge) {
        self.edge = edge
    }

    /// 這個 child 目前收到多少來自本容器的 inset。
    internal func contribution(for child: UIViewController) -> CGFloat {
        contributions[ObjectIdentifier(child)] ?? 0
    }

    /// 套用新的貢獻值。回傳 true 表示實際改動了 child 的 inset。
    @discardableResult
    internal mutating func apply(_ value: CGFloat, to child: UIViewController) -> Bool {
        let key = ObjectIdentifier(child)
        let previous = contributions[key] ?? 0
        let insets = child.additionalSafeAreaInsets
        let current = edgeValue(of: insets)
        // child 的現值若不是我們上次寫下去的，就是它自己改過——以現值為基準重新推導，
        // 不沿用差量。Consumer 原本的值因此照樣被保留。
        let base = lastWritten[key] == current ? current - previous : current
        let total = base + value

        contributions[key] = value
        guard current != total else {
            lastWritten[key] = total
            return false
        }
        child.additionalSafeAreaInsets = setting(total, in: insets)
        lastWritten[key] = total
        return true
    }

    /// 歸還這個 child 收到的貢獻並移除記錄。
    @discardableResult
    internal mutating func release(_ child: UIViewController) -> Bool {
        let key = ObjectIdentifier(child)
        let written = lastWritten.removeValue(forKey: key)
        guard let contributed = contributions.removeValue(forKey: key),
              contributed != 0 else { return false }

        let insets = child.additionalSafeAreaInsets
        let current = edgeValue(of: insets)
        // child 自己改過就不要再減：那筆貢獻已經不在它身上，減下去只會變成負的。
        guard written == current else { return false }
        child.additionalSafeAreaInsets = setting(max(0, current - contributed), in: insets)
        return true
    }

    private func edgeValue(of insets: UIEdgeInsets) -> CGFloat {
        switch edge {
        case .top: return insets.top
        case .bottom: return insets.bottom
        }
    }

    private func setting(_ value: CGFloat, in insets: UIEdgeInsets) -> UIEdgeInsets {
        var insets = insets
        switch edge {
        case .top: insets.top = value
        case .bottom: insets.bottom = value
        }
        return insets
    }
}
