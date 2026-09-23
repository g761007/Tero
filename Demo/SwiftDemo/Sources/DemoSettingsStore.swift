import Foundation

/// Demo 的設定保存。
///
/// **只存在 Demo 端**：套件本身不碰 `UserDefaults`，設定的生命週期是 App 的事，
/// 不是 Tab 容器的事（這也是 `TeroTabBarConfiguration` 做深拷貝快照、
/// 而不是自己記住狀態的原因）。
struct DemoSettings: Equatable {

    // 主畫面
    /// Style 不支援 runtime 切換（ADR-0003），因此它只能「存起來、下次啟動生效」。
    var styleIsFloatingGlass = false
    var swipeMode = 0

    // Interaction Lab
    var labStyle = 2            // .fluid
    var labTabCount = 5
    var labSwipeMode = 0
    var duration = 0.4
    var damping = 0.84
    var response = 0.4
    var selectionWidth = 0.0
    var selectionHeight = 0.0
    var cornerRadius = 0.0
    var iconScale = 0.92
}


extension DemoSettings: Codable {

    /// 逐欄以 `decodeIfPresent` 讀取，缺的欄位退回預設值。
    ///
    /// 這不是可有可無的講究：這份結構會隨著旋鈕增加而長大，用預設的 `Codable`
    /// 合成實作時，只要多一個欄位，舊的存檔就整份解不開、使用者調好的參數全部消失。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DemoSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        styleIsFloatingGlass = value(.styleIsFloatingGlass, fallback.styleIsFloatingGlass)
        swipeMode = value(.swipeMode, fallback.swipeMode)
        labStyle = value(.labStyle, fallback.labStyle)
        labTabCount = value(.labTabCount, fallback.labTabCount)
        labSwipeMode = value(.labSwipeMode, fallback.labSwipeMode)
        duration = value(.duration, fallback.duration)
        damping = value(.damping, fallback.damping)
        response = value(.response, fallback.response)
        selectionWidth = value(.selectionWidth, fallback.selectionWidth)
        selectionHeight = value(.selectionHeight, fallback.selectionHeight)
        cornerRadius = value(.cornerRadius, fallback.cornerRadius)
        iconScale = value(.iconScale, fallback.iconScale)
    }
}


enum DemoSettingsStore {

    private static let key = "tero.demo.settings"

    /// 讀取已存的設定。
    ///
    /// 帶 `--reset-settings` 啟動時直接清掉：自動化截圖不該受到上一次手動調參的影響。
    static func load() -> DemoSettings {
        if DemoLaunchOptions.resetsSettings {
            reset()
            return DemoSettings()
        }
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(DemoSettings.self, from: data) else {
            return DemoSettings()
        }
        return settings
    }

    static func save(_ settings: DemoSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
