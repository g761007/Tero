import CoreGraphics
import Foundation

/// 啟動參數，讓自動化截圖能在不點擊 UI 的情況下進入特定狀態。
/// 僅供 Demo 使用，與套件本身無關。
enum DemoLaunchOptions {

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var showsBadgesOnLaunch: Bool { arguments.contains("--badges") }

    static var manyTabs: Bool { arguments.contains("--many-tabs") }

    /// `--style=classic` / `--style=floatingGlass`
    static var requestedStyleName: String? {
        arguments.first { $0.hasPrefix("--style=") }?.replacingOccurrences(of: "--style=", with: "")
    }

    /// `--scrolled=240`：啟動後直接把長清單捲到該位移，供自動化截圖使用。
    static var scrolledOffset: CGFloat? {
        guard let raw = arguments.first(where: { $0.hasPrefix("--scrolled=") }) else { return nil }
        guard let value = Double(raw.replacingOccurrences(of: "--scrolled=", with: "")) else { return nil }
        return CGFloat(value)
    }

    /// `--swipe=drag` / `--swipe=swipe`
    static var swipeModeName: String? {
        arguments.first { $0.hasPrefix("--swipe=") }?.replacingOccurrences(of: "--swipe=", with: "")
    }

    /// `--reset-settings`：清掉已存的設定後再啟動。自動化截圖用它保證起點乾淨。
    static var resetsSettings: Bool { arguments.contains("--reset-settings") }

    /// `--lab`：直接進入 Interaction Lab。
    static var opensInteractionLab: Bool { arguments.contains("--lab") }

    /// `--instagram`：直接進入 Instagram 參考案例（issue #98），供自動化截圖使用。
    static var opensInstagramDemo: Bool { arguments.contains("--instagram") }

    /// `--case=a` / `--case=b` / `--case=c` / `--case=d`：直接進入參考案例，供自動化截圖使用。
    static var referenceCaseName: String? {
        arguments.first { $0.hasPrefix("--case=") }?.replacingOccurrences(of: "--case=", with: "")
    }

    /// `--state=expanded` / `--state=minimized` / `--state=hidden`
    static var presentationStateName: String? {
        arguments.first { $0.hasPrefix("--state=") }?.replacingOccurrences(of: "--state=", with: "")
    }
}
