import UIKit

/// Bar 上一格的視圖。Consumer 不應依賴此型別（計畫書 §52）。
///
/// 繼承 `UIButton` 而非 `UIControl`，是為了取得原生的 `menu` 與
/// `showsMenuAsPrimaryAction`（More 的選單需要）。按鈕自身的 title/image
/// 一律不設定，內容全部由下面自訂的 subview 繪製。
internal final class TeroTabItemView: UIButton {

    /// 這一格在目前這段轉場裡扮演的角色。決定縮放曲線的形狀。
    internal enum SelectionPhase {
        /// 接手選取。
        case incoming
        /// 交出選取。
        case outgoing
        /// 沒有參與這段轉場。
        case idle
    }

    /// 正常狀態的圖示。
    private let iconView = UIImageView()
    /// 選取狀態的圖示，疊在 `iconView` 之上。
    ///
    /// 兩張圖不同時才啟用：交叉淡入同時帶來 tint 的插補，
    /// 不必再逐幀去算顏色。兩張圖相同時只留一層，直接插補 tint。
    private let selectedIconView = UIImageView()
    private let captionLabel = UILabel()
    private let badgeView = TeroTabBadgeView(frame: .zero)

    private var minimizationProgress: CGFloat = 0
    private var minimizedIconSide: CGFloat = 24
    private var fadesTitle = true

    internal func applyPresentation(progress: CGFloat, iconSide: CGFloat, hidesTitle: Bool) {
        minimizationProgress = progress
        minimizedIconSide = iconSide
        fadesTitle = hidesTitle
        captionLabel.alpha = hidesTitle ? 1 - progress : 1
        captionLabel.isHidden = (captionLabel.text?.isEmpty ?? true) || (hidesTitle && progress >= 1)
        setNeedsLayout()
        layoutIfNeeded()
    }

    private var appearance = TeroTabItemAppearance()
    private var badgeAppearance = TeroTabBadgeAppearance()
    private var normalImage: UIImage?
    private var selectedImage: UIImage?
    private var usesIconCrossfade = false

    /// 這一格目前的選取程度。
    ///
    /// 公開行為的單一事實來源仍然是 `isSelected`（無障礙 trait、`didReselect` 的判準
    /// 都看它）；連續進度是內部細節，不對外開放（補充規格 §6）。
    internal private(set) var selectionProgress: CGFloat = 0

    /// 目前這段轉場的整體進度。只用來決定縮放曲線走到哪。
    private var transitionProgress: CGFloat = 1
    private var selectionPhase: SelectionPhase = .idle

    internal override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        selectedIconView.contentMode = .scaleAspectFit
        selectedIconView.isUserInteractionEnabled = false
        selectedIconView.alpha = 0
        captionLabel.textAlignment = .center
        captionLabel.isUserInteractionEnabled = false
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.7
        // 自訂內容可以畫出 Item 邊界（跳起、放大、飛出）——真正需要裁切的是
        // 外層的玻璃膠囊，不是這裡（補充規格 §11）。
        clipsToBounds = false
        addSubview(iconView)
        addSubview(selectedIconView)
        addSubview(captionLabel)
        addSubview(badgeView)
        badgeView.isHidden = true
    }

    internal required init?(coder: NSCoder) { fatalError() }

    /// 目前承載的自訂內容。由 Bar 提供並持有快取，Item 視圖只負責擺放。
    private weak var hostedContentView: UIView?

    /// 版面方向由 Bar 決定並傳下來。
    ///
    /// 不自己讀 `effectiveUserInterfaceLayoutDirection`：那只反映本視圖自身的
    /// `semanticContentAttribute`，父視圖上的設定不會傳遞過來。
    internal var layoutDirection: UIUserInterfaceLayoutDirection = .leftToRight {
        didSet {
            guard layoutDirection != oldValue else { return }
            setNeedsLayout()
        }
    }

    internal func configure(
        with presentation: TeroTabItemPresentation,
        appearance: TeroTabItemAppearance,
        badgeAppearance: TeroTabBadgeAppearance,
        contentView: UIView?
    ) {
        setHostedContentView(contentView)
        self.appearance = appearance
        self.badgeAppearance = badgeAppearance
        self.normalImage = presentation.image
        self.selectedImage = presentation.selectedImage
        // 以識別而非相等比較：consumer 沒設 selectedImage 時，兩者本來就是同一個實例。
        self.usesIconCrossfade = (presentation.image !== presentation.selectedImage)
        captionLabel.text = presentation.title
        captionLabel.isHidden = (presentation.title?.isEmpty ?? true)
        // contentProvider 存在時優先於 image（計畫書 §7）。
        let hidesIcons = contentView != nil
            || (presentation.image == nil && presentation.selectedImage == nil)
        iconView.isHidden = hidesIcons
        selectedIconView.isHidden = hidesIcons || !usesIconCrossfade
        iconView.image = normalImage?.withRenderingMode(.alwaysTemplate)
        selectedIconView.image = selectedImage?.withRenderingMode(.alwaysTemplate)

        isEnabled = presentation.isEnabled
        accessibilityIdentifier = presentation.accessibilityIdentifier
        accessibilityLabel = presentation.accessibilityLabel
        applyBadge(presentation.badge)
        applyVisualState()
        updateAccessibilityTraits()
        setNeedsLayout()
    }

    private func setHostedContentView(_ contentView: UIView?) {
        if let existing = hostedContentView, existing !== contentView {
            existing.removeFromSuperview()
        }
        hostedContentView = contentView
        guard let contentView else { return }
        contentView.isUserInteractionEnabled = false
        if contentView.superview !== self {
            contentView.removeFromSuperview()
            insertSubview(contentView, at: 0)
        }
    }

    private func applyBadge(_ badge: TeroTabBadge?) {
        guard let badge else {
            badgeView.isHidden = true
            accessibilityValue = nil
            return
        }
        badgeView.isHidden = false
        badgeView.configure(with: badge, defaults: badgeAppearance)
        // Badge 併入 accessibilityValue，播報原始值（計畫書 §49）。
        // `.dot` 沒有原始值可播報，且套件不得內建字串（ADR-0007），
        // 因此圓點的語意須由 consumer 自行以 accessibilityLabel 表達。
        accessibilityValue = badgeView.resolved?.spokenValue
    }

    internal override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            updateAccessibilityTraits()
        }
    }

    private func updateAccessibilityTraits() {
        var traits: UIAccessibilityTraits = .button
        if isSelected { traits.insert(.selected) }
        if !isEnabled { traits.insert(.notEnabled) }
        accessibilityTraits = traits
    }

    internal override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.35 }
    }

    /// 只留選取格的最小化：非選取格隨進度淡出到看不見、也摸不到（issue #93）。1 是完全可見。
    internal func applyMinimizedVisibility(_ fraction: CGFloat) {
        let clamped = min(max(fraction, 0), 1)
        alpha = (isEnabled ? 1 : 0.35) * clamped
        isHidden = clamped <= 0.001
    }

    // MARK: - Selection progress

    /// 由 Bar 在轉場的每一幀呼叫。
    ///
    /// - Parameters:
    ///   - progress: 這一格自己的選取程度（0…1）。
    ///   - transition: 整段轉場的進度（0…1），決定縮放曲線走到哪。
    ///   - phase: 這一格在這段轉場裡的角色。
    internal func applySelection(progress: CGFloat, transition: CGFloat, phase: SelectionPhase) {
        selectionProgress = min(max(progress, 0), 1)
        transitionProgress = min(max(transition, 0), 1)
        selectionPhase = phase
        applyVisualState()
    }

    /// 重複點擊選取中的 Tab 的回饋：內容輕輕縮一下再彈回（補充規格 §12）。
    ///
    /// 只動 `transform`，不碰 `selectionProgress`——重複點擊不改變選取狀態。
    internal func playReselectFeedback(duration: TimeInterval) {
        guard TeroAccessibility.resolvedAnimated(true) else { return }
        var targets: [UIView] = [iconView, selectedIconView]
        if let hostedContentView { targets.append(hostedContentView) }
        let pressed = CGAffineTransform(scaleX: 0.88, y: 0.88)

        UIView.animate(
            withDuration: duration / 2,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            targets.forEach { $0.transform = pressed }
        } completion: { _ in
            UIView.animate(
                withDuration: duration / 2,
                delay: 0,
                usingSpringWithDamping: 0.5,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                targets.forEach { $0.transform = .identity }
            }
        }
    }

    private var contentScale: CGFloat {
        switch selectionPhase {
        case .incoming:
            return TeroTabSelectionInterpolation.scale(
                transition: transitionProgress,
                rest: appearance.selectionIconScale,
                bump: appearance.selectionIconOvershoot
            )
        case .outgoing:
            return TeroTabSelectionInterpolation.scale(
                transition: transitionProgress,
                rest: 1,
                bump: appearance.selectionIconScale - 1
            )
        case .idle:
            return 1
        }
    }

    private func applyVisualState() {
        let progress = selectionProgress

        if usesIconCrossfade {
            // 交叉淡入本身就完成了 tint 的插補：兩層各自著色，疊起來即為中間色。
            iconView.alpha = 1 - progress
            selectedIconView.alpha = progress
            iconView.tintColor = appearance.normalTintColor
            selectedIconView.tintColor = appearance.selectedTintColor
        } else {
            iconView.alpha = 1
            selectedIconView.alpha = 0
            iconView.tintColor = interpolatedTint(progress)
        }

        captionLabel.textColor = interpolatedTint(progress)
        // 字重在中點換，兩端才不會各走一半而看起來抖動。
        captionLabel.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: progress >= 0.5 ? appearance.selectedTitleFont : appearance.titleFont,
            compatibleWith: traitCollection
        )

        let scale = contentScale
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        iconView.transform = transform
        selectedIconView.transform = transform
        hostedContentView?.transform = transform
    }

    private func interpolatedTint(_ progress: CGFloat) -> UIColor {
        TeroTabSelectionInterpolation.color(
            from: appearance.normalTintColor,
            to: appearance.selectedTintColor,
            progress: progress,
            traits: traitCollection
        )
    }

    internal override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyVisualState()
        setNeedsLayout()
    }

    internal override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // UIControl 的 touchUpInside 也要接受 Bar 分派的擴充範圍。
        bounds.insetBy(dx: -max(0, (44 - bounds.width) / 2),
                       dy: -max(0, (44 - bounds.height) / 2)).contains(point)
    }

    internal override func layoutSubviews() {
        super.layoutSubviews()

        let hasTitle = !captionLabel.isHidden
        let hasCustomContent = hostedContentView != nil
        let hasImage = !iconView.isHidden || hasCustomContent
        let titleFraction = fadesTitle ? 1 - minimizationProgress : 1
        let baseFont = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: appearance.titleFont, compatibleWith: traitCollection)
        let titleHeight = hasTitle ? ceil(baseFont.lineHeight) * titleFraction : 0
        let spacing = (hasTitle && hasImage) ? appearance.titleSpacing * titleFraction : 0
        let p = minimizationProgress
        let expanded = appearance.contentSize
        let imageSize = hasImage ? CGSize(
            width: expanded.width + (min(expanded.width, minimizedIconSide) - expanded.width) * p,
            height: expanded.height + (min(expanded.height, minimizedIconSide) - expanded.height) * p
        ) : .zero
        let totalHeight = imageSize.height + spacing + titleHeight
        var top = ((bounds.height - totalHeight) / 2).rounded()

        var contentFrame = CGRect.zero
        if hasImage {
            contentFrame = CGRect(
                x: ((bounds.width - imageSize.width) / 2).rounded(),
                y: top,
                width: imageSize.width,
                height: imageSize.height
            )
            // 以 bounds + center 而非 frame 定位：這些視圖在轉場中帶著縮放，
            // 對帶 transform 的視圖設 frame 的結果沒有定義。
            for view in [iconView, selectedIconView] {
                view.bounds = CGRect(origin: .zero, size: contentFrame.size)
                view.center = CGPoint(x: contentFrame.midX, y: contentFrame.midY)
            }
            if let hostedContentView {
                hostedContentView.bounds = CGRect(origin: .zero, size: contentFrame.size)
                hostedContentView.center = CGPoint(x: contentFrame.midX, y: contentFrame.midY)
            }
            top += imageSize.height + spacing
        }
        if hasTitle {
            captionLabel.frame = CGRect(x: 0, y: top, width: bounds.width, height: titleHeight)
        }

        layoutBadge(anchoredTo: hasImage ? contentFrame : bounds.insetBy(dx: bounds.width / 4, dy: 0))
    }

    /// Badge 掛在內容的上緣外側角落；RTL 時水平鏡像。
    ///
    /// 錨點取的是內容**未縮放**的版面矩形：Badge 不隨 Icon 的轉場縮放起伏，
    /// 否則 `999+` 這種長 Badge 在每次切換時都會抖一下。
    private func layoutBadge(anchoredTo anchor: CGRect) {
        guard !badgeView.isHidden, let resolved = badgeView.resolved else { return }

        let isRTL = layoutDirection == .rightToLeft
        let anchorX = isRTL ? anchor.minX : anchor.maxX
        let offsetX = isRTL ? -resolved.offset.x : resolved.offset.x
        let size = resolved.size

        // 與內容上緣略為重疊，而不是以上緣為中心——後者會讓 Badge 一半跑到 Bar 外面。
        let rawX = anchorX - size.width / 2 + offsetX
        let rawY = anchor.minY - size.height * 0.35 + resolved.offset.y

        // 夾在 Item 自己的 bounds 內，Badge 才不會被畫到 Bar 之外。
        badgeView.frame = CGRect(
            x: rawX.clamped(to: 0...max(0, bounds.width - size.width)).rounded(),
            y: rawY.clamped(to: 0...max(0, bounds.height - size.height)).rounded(),
            width: size.width,
            height: size.height
        )
    }
}


private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
