import CoreGraphics

/// 方向鎖：只回答「現在算往哪個方向捲」與「從錨點走了多遠」。
///
/// 頂部 chrome 與底部 Tab Bar 讀同一份捲動樣本，但**各自決定怎麼反應**（§26）。
/// 共用的只有這一層算術——把它抽出來，兩邊才不會各自維護一份會漂移的方向判定。
///
/// 純值型別，不依賴 UIKit：輸入 offset 與 delta，輸出方向。可直接以 seam 2 測試。
internal struct TeroScrollDirectionLock: Equatable {

    internal enum Direction: Equatable {
        case none
        case down
        case up
    }

    internal private(set) var direction: Direction = .none
    private var anchorOffset: CGFloat = 0
    private var turningOffset: CGFloat = 0

    internal init(anchorOffset: CGFloat = 0) {
        self.anchorOffset = anchorOffset
        self.turningOffset = anchorOffset
    }

    /// 從錨點算起走了多遠。正值代表往內容底部。
    internal func translation(at offset: CGFloat) -> CGFloat {
        offset - anchorOffset
    }

    internal mutating func reset(to offset: CGFloat) {
        direction = .none
        anchorOffset = offset
        turningOffset = offset
    }

    /// 餵一筆位移。
    ///
    /// 小幅反向不立刻清掉既有方向：累積到鎖距才換向，並以轉向極值當新錨點——
    /// 否則抖動會讓門檻永遠重算，慢速長距離捲動就收不起來。
    internal mutating func consume(offset: CGFloat, delta: CGFloat, lockDistance: CGFloat) {
        let lock = lockDistance.isFinite && lockDistance > 0 ? lockDistance : 8

        switch direction {
        case .none:
            let distance = offset - anchorOffset
            guard abs(distance) >= lock else { return }
            direction = distance > 0 ? .down : .up
            turningOffset = offset
        case .down:
            turningOffset = max(turningOffset, offset)
            if turningOffset - offset >= lock, delta < 0 {
                anchorOffset = turningOffset
                direction = .up
                turningOffset = offset
            }
        case .up:
            turningOffset = min(turningOffset, offset)
            if offset - turningOffset >= lock, delta > 0 {
                anchorOffset = turningOffset
                direction = .down
                turningOffset = offset
            }
        }
    }
}
