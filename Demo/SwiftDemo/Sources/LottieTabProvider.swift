import UIKit
import Lottie
import Tero

/// 用 Lottie 當 Tab 內容的轉接層。
///
/// 這一層**寫在 Demo 端**：套件本身不依賴 Lottie 或 SVGAPlayer（計畫書 §8）。
/// 換成 SVGA 或任何其他動畫框架時，要改的只有這個檔案。
final class LottieTabProvider: NSObject, TeroTabInteractiveContentProvider {

    private let animationName: String
    private(set) var loadFailed = false

    init(animationName: String) {
        self.animationName = animationName
        super.init()
    }

    func makeContentView() -> UIView {
        let view = LottieAnimationView(name: animationName)
        view.contentMode = .scaleAspectFit
        view.loopMode = .loop
        if view.animation == nil {
            loadFailed = true
        }
        return view
    }

    func updateContentView(
        _ contentView: UIView,
        selected: Bool,
        presentationState: TeroTabBarPresentationState,
        animated: Bool
    ) {
        guard let view = contentView as? LottieAnimationView else { return }

        // `animated == false` 可能代表使用者開啟了「減少動態效果」，此時應停止播放。
        guard animated else {
            view.stop()
            view.currentProgress = selected ? 1 : 0
            return
        }

        switch (selected, presentationState) {
        case (true, .minimized):
            // 最小化時只播一小段，避免在窄版面裡過度晃動
            view.loopMode = .playOnce
            view.play()
        case (true, _):
            view.loopMode = .loop
            view.play()
        case (false, _):
            view.stop()
            view.currentProgress = 0
        }
    }

    /// 進階協定：轉場途中把 Lottie 的播放進度綁在選取進度上。
    ///
    /// 這正是只有 Bool 做不到的事——膠囊滑到一半，動畫也就播到一半。
    /// 兩端落定之後才交還給上面那個「選取就循環、未選取就停」的行為。
    func updateContentView(_ contentView: UIView, selectionProgress: CGFloat, animated: Bool) {
        guard let view = contentView as? LottieAnimationView else { return }

        if selectionProgress >= 1 {
            guard animated else {
                view.stop()
                view.currentProgress = 1
                return
            }
            view.loopMode = .loop
            view.play()
            return
        }
        if selectionProgress <= 0 {
            view.stop()
            view.currentProgress = 0
            return
        }
        view.stop()
        view.currentProgress = selectionProgress
    }

    func updateContentView(_ contentView: UIView, presentationProgress: CGFloat, animated: Bool) {
        // Selection 控制播放進度；可見度控制可讀性，兩者不搶同一個播放游標。
        contentView.alpha = 1 - presentationProgress * 0.15
        if !animated { (contentView as? LottieAnimationView)?.pause() }
    }

}
