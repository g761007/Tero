import Foundation

/// 程式鎖定最高；Navigation preview 凍結 Scroll；頁面 policy 不寫入全域鎖。
internal struct TeroTabVisibilityResolver {
    internal func resolve(
        locked: Bool,
        navigation: TeroTabBarPresentationState? = nil,
        policy: TeroTabVisibilityPolicy,
        scroll: TeroTabBarPresentationState
    ) -> TeroTabBarPresentationState {
        if locked { return .hidden }
        if let navigation { return navigation }
        switch policy {
        case .inherit: return scroll
        case .expanded: return .expanded
        case .hidden: return .hidden
        }
    }
}
