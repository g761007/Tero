import Foundation

/// 決定哪些 Tab 直接可見、哪些收進 More。Consumer 不應依賴此型別（計畫書 §52）。
internal struct TeroTabOverflowResolver {

    internal struct Resolution: Equatable {
        internal var visibleIndices: [Int]
        internal var overflowIndices: [Int]
        internal var showsMore: Bool

        internal static let empty = Resolution(visibleIndices: [], overflowIndices: [], showsMore: false)
    }

    /// 上限包含 More，不含 Classic 的中央 Action slot（計畫書 §20、§41）。
    ///
    /// 未超過上限時全部顯示；超過時顯示前 (上限 − 1) 個並以最後一格放 More。
    /// 因此多加第 (上限 + 1) 個 Tab 會讓可見數量少一個——這是刻意的行為。
    internal func resolve(tabCount: Int, maximumVisibleItems: Int) -> Resolution {
        guard tabCount > 0 else { return .empty }
        let limit = max(2, maximumVisibleItems)

        if tabCount <= limit {
            return Resolution(
                visibleIndices: Array(0..<tabCount),
                overflowIndices: [],
                showsMore: false
            )
        }

        let visibleCount = limit - 1
        return Resolution(
            visibleIndices: Array(0..<visibleCount),
            overflowIndices: Array(visibleCount..<tabCount),
            showsMore: true
        )
    }
}
