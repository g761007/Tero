import XCTest
@testable import Tero

/// 對應 ticket #37 的滑動選取。
///
/// 決策邏輯抽成了純值型別，因此門檻、方向與 RTL 都能單獨驗證，
/// 不必模擬真實觸控——與捲動狀態機同樣的處理。
final class SwipeSelectionResolverTests: XCTestCase {

    private let resolver = TeroTabSwipeSelectionResolver()

    // MARK: drag 進行中每格的進度

    private let centres: [CGFloat] = [50, 150, 250, 350]

    func test_weightsAreOneOnASlotCentre() {
        for (index, centre) in centres.enumerated() {
            let weights = resolver.slotWeights(fingerX: centre, slotCenters: centres)
            XCTAssertEqual(weights[index], 1, accuracy: 0.001, "第 \(index) 格中心")
            XCTAssertEqual(weights.reduce(0, +), 1, accuracy: 0.001, "總和恆為 1")
        }
    }

    func test_weightsSplitBetweenTwoSlots() {
        let weights = resolver.slotWeights(fingerX: 175, slotCenters: centres)

        XCTAssertEqual(weights[1], 0.75, accuracy: 0.001)
        XCTAssertEqual(weights[2], 0.25, accuracy: 0.001)
        XCTAssertEqual(weights[0], 0)
        XCTAssertEqual(weights[3], 0)
    }

    func test_weightsClampAtBothEnds() {
        let before = resolver.slotWeights(fingerX: -999, slotCenters: centres)
        let after = resolver.slotWeights(fingerX: 9999, slotCenters: centres)

        XCTAssertEqual(before[0], 1)
        XCTAssertEqual(after[3], 1)
        XCTAssertEqual(before.reduce(0, +), 1, accuracy: 0.001)
        XCTAssertEqual(after.reduce(0, +), 1, accuracy: 0.001)
    }

    func test_aSingleSlotAlwaysCarriesEverything() {
        XCTAssertEqual(resolver.slotWeights(fingerX: 9999, slotCenters: [100]), [1])
        XCTAssertEqual(resolver.slotWeights(fingerX: 0, slotCenters: []), [])
    }

    // MARK: 拖曳中透鏡的形變

    func test_deformationIsNeutralWhenTheFingerIsStill() {
        let still = TeroTabSelectionInterpolation.lensDeformation(
            speed: 0, reference: 2000, intensity: 0.35
        )

        XCTAssertEqual(still.horizontal, 1, accuracy: 0.001)
        XCTAssertEqual(still.vertical, 1, accuracy: 0.001)
    }

    /// 兩軸相乘恆為 1——那是 squash-and-stretch，也是果凍讀起來像果凍的原因。
    func test_deformationPreservesVolumeAtEverySpeed() {
        for speed: CGFloat in [0, 200, 900, 2000, 9999] {
            let shape = TeroTabSelectionInterpolation.lensDeformation(
                speed: speed, reference: 2000, intensity: 0.35
            )
            XCTAssertEqual(shape.horizontal * shape.vertical, 1, accuracy: 0.001,
                           "speed=\(speed)")
        }
    }

    func test_deformationGrowsWithSpeedAndSaturates() {
        let slow = TeroTabSelectionInterpolation.lensDeformation(
            speed: 400, reference: 2000, intensity: 0.35
        )
        let fast = TeroTabSelectionInterpolation.lensDeformation(
            speed: 1600, reference: 2000, intensity: 0.35
        )
        let beyond = TeroTabSelectionInterpolation.lensDeformation(
            speed: 9999, reference: 2000, intensity: 0.35
        )

        XCTAssertGreaterThan(fast.horizontal, slow.horizontal)
        XCTAssertLessThan(fast.vertical, slow.vertical, "拉長的同時要壓扁")
        XCTAssertEqual(beyond.horizontal, 1.35, accuracy: 0.001, "封頂在 intensity")
    }

    func test_deformationIgnoresDirection() {
        let right = TeroTabSelectionInterpolation.lensDeformation(
            speed: 800, reference: 2000, intensity: 0.35
        )
        let left = TeroTabSelectionInterpolation.lensDeformation(
            speed: -800, reference: 2000, intensity: 0.35
        )

        XCTAssertEqual(right.horizontal, left.horizontal, accuracy: 0.001,
                       "往左拖和往右拖該一樣形變")
    }

    // MARK: drag 進行中外框在哪

    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 56)
    private let startFrame = CGRect(x: 10, y: 4, width: 60, height: 48)

    /// 跟的是手指的**位置**，不是位移量。
    ///
    /// 原本的實作是「手勢開始時的外框 ＋ translation」：選取在 A、手指按在 D 拖 10pt，
    /// 外框從 A 偏移 10pt 而不是跟著 D 走。只有手勢剛好從選取那格起手時兩者才相等，
    /// 那也是它一直沒被發現的原因——文件三處都寫「連續跟隨手指」。
    func test_theIndicatorCentresOnTheFingerRegardlessOfWhereItStarted() {
        for finger: CGFloat in [80, 200, 330] {
            let frame = resolver.indicatorFrame(
                followingCenterX: finger, startFrame: startFrame, in: bounds
            )
            XCTAssertEqual(frame.midX, finger, accuracy: 0.001,
                           "手指在 \(finger) 外框中心就該在 \(finger)")
        }
    }

    func test_theIndicatorKeepsItsSizeAndVerticalPositionWhileDragging() {
        let frame = resolver.indicatorFrame(
            followingCenterX: 250, startFrame: startFrame, in: bounds
        )

        XCTAssertEqual(frame.size, startFrame.size, "只有 x 跟手")
        XCTAssertEqual(frame.minY, startFrame.minY)
    }

    func test_theIndicatorStaysInsideTheCapsuleAtBothEnds() {
        let atLeading = resolver.indicatorFrame(
            followingCenterX: -500, startFrame: startFrame, in: bounds
        )
        let atTrailing = resolver.indicatorFrame(
            followingCenterX: 9999, startFrame: startFrame, in: bounds
        )

        XCTAssertEqual(atLeading.minX, bounds.minX, accuracy: 0.001)
        XCTAssertEqual(atTrailing.maxX, bounds.maxX, accuracy: 0.001)
    }

    /// 膠囊比外框還窄時夾限不得算出負寬度的空間。
    func test_aCapsuleNarrowerThanTheIndicatorPinsItToTheLeadingEdge() {
        let narrow = CGRect(x: 0, y: 0, width: 30, height: 56)

        let frame = resolver.indicatorFrame(
            followingCenterX: 200, startFrame: startFrame, in: narrow
        )

        XCTAssertEqual(frame.minX, narrow.minX, accuracy: 0.001)
    }

    // MARK: drag 的吸附

    func test_nearestSlotPicksTheClosestCentre() {
        let centres: [CGFloat] = [50, 150, 250, 350]

        XCTAssertEqual(resolver.nearestSlot(toCenterX: 60, slotCenters: centres), 0)
        XCTAssertEqual(resolver.nearestSlot(toCenterX: 149, slotCenters: centres), 1)
        XCTAssertEqual(resolver.nearestSlot(toCenterX: 201, slotCenters: centres), 2)
        XCTAssertEqual(resolver.nearestSlot(toCenterX: 9999, slotCenters: centres), 3)
    }

    func test_nearestSlotWithNoSlotsIsNil() {
        XCTAssertNil(resolver.nearestSlot(toCenterX: 100, slotCenters: []))
    }

    // MARK: swipe 的門檻

    func test_belowBothThresholdsDoesNothing() {
        XCTAssertNil(resolver.adjacentSlot(
            from: 1, translation: 20, velocity: 100,
            layoutDirection: .leftToRight, selectableSlotCount: 4
        ))
    }

    func test_translationThresholdAloneIsEnough() {
        XCTAssertEqual(resolver.adjacentSlot(
            from: 1, translation: -50, velocity: 0,
            layoutDirection: .leftToRight, selectableSlotCount: 4
        ), 2)
    }

    func test_velocityThresholdAloneIsEnough() {
        XCTAssertEqual(resolver.adjacentSlot(
            from: 1, translation: -5, velocity: -500,
            layoutDirection: .leftToRight, selectableSlotCount: 4
        ), 2)
    }

    // MARK: 方向

    func test_leftToRightDirections() {
        // 往左滑 → 下一個
        XCTAssertEqual(resolver.adjacentSlot(
            from: 1, translation: -60, velocity: 0,
            layoutDirection: .leftToRight, selectableSlotCount: 4
        ), 2)
        // 往右滑 → 上一個
        XCTAssertEqual(resolver.adjacentSlot(
            from: 1, translation: 60, velocity: 0,
            layoutDirection: .leftToRight, selectableSlotCount: 4
        ), 0)
    }

    func test_rightToLeftMirrorsDirections() {
        XCTAssertEqual(resolver.adjacentSlot(
            from: 1, translation: 60, velocity: 0,
            layoutDirection: .rightToLeft, selectableSlotCount: 4
        ), 2, "RTL 下往右滑是往下一個")
        XCTAssertEqual(resolver.adjacentSlot(
            from: 1, translation: -60, velocity: 0,
            layoutDirection: .rightToLeft, selectableSlotCount: 4
        ), 0)
    }

    // MARK: 邊界

    func test_atFirstSlotCannotGoBack() {
        XCTAssertNil(resolver.adjacentSlot(
            from: 0, translation: 60, velocity: 0,
            layoutDirection: .leftToRight, selectableSlotCount: 4
        ))
    }

    func test_atLastSlotCannotGoForward() {
        XCTAssertNil(resolver.adjacentSlot(
            from: 3, translation: -60, velocity: 0,
            layoutDirection: .leftToRight, selectableSlotCount: 4
        ))
    }

    /// More 是最後一格但不是 Tab，因此 `selectableSlotCount` 不含它——
    /// 從最後一個 Tab 往前滑不會滑到 More。
    func test_moreIsNotASwipeTarget() {
        // 3 個 Tab + More：selectableSlotCount 為 3
        XCTAssertNil(resolver.adjacentSlot(
            from: 2, translation: -60, velocity: 0,
            layoutDirection: .leftToRight, selectableSlotCount: 3
        ))
    }

    func test_fromMoreCanGoBackToTheLastTab() {
        // 選取落在 More（slot 3），往回滑
        XCTAssertEqual(resolver.adjacentSlot(
            from: 3, translation: 60, velocity: 0,
            layoutDirection: .leftToRight, selectableSlotCount: 3
        ), 2)
    }
}

/// 手勢是否啟用、以及模式如何從設定傳到 Bar。
final class SwipeSelectionModeTests: TeroTabBarControllerTestCase {

    /// `.drag` 的驅動者是零秒 long press，不是 pan——pan 的 slop 讓「按住不動」沒反應。
    private func dragRecognizer(in controller: TeroTabBarController) -> UILongPressGestureRecognizer? {
        func search(_ view: UIView) -> UILongPressGestureRecognizer? {
            if let found = view.gestureRecognizers?
                .compactMap({ $0 as? UILongPressGestureRecognizer }).first {
                return found
            }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return search(controller.tabBar)
    }

    private func panRecognizer(in controller: TeroTabBarController) -> UIPanGestureRecognizer? {
        func search(_ view: UIView) -> UIPanGestureRecognizer? {
            if let found = view.gestureRecognizers?.compactMap({ $0 as? UIPanGestureRecognizer }).first {
                return found
            }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return search(controller.tabBar)
    }

    private func makeController(mode: TeroTabSwipeSelectionMode) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.swipeSelectionMode = mode
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<3).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    func test_defaultIsDisabled() {
        XCTAssertEqual(TeroTabBarConfiguration.defaultConfiguration().swipeSelectionMode, .disabled)
    }

    func test_disabledLeavesBothGesturesOff() {
        let controller = makeController(mode: .disabled)
        XCTAssertEqual(panRecognizer(in: controller)?.isEnabled, false)
        XCTAssertEqual(dragRecognizer(in: controller)?.isEnabled, false)
    }

    /// 兩種模式用兩個不同的驅動者，而且互斥。
    func test_dragEnablesTheLongPressAndLeavesPanOff() {
        let controller = makeController(mode: .drag)
        XCTAssertEqual(dragRecognizer(in: controller)?.isEnabled, true,
                       "零秒 long press：touch-down 就開始跟手")
        XCTAssertEqual(panRecognizer(in: controller)?.isEnabled, false,
                       "pan 的 slop 讓按住不動沒反應，所以不給 .drag 用")
    }

    func test_swipeEnablesPanAndLeavesTheLongPressOff() {
        let controller = makeController(mode: .swipe)
        XCTAssertEqual(panRecognizer(in: controller)?.isEnabled, true)
        XCTAssertEqual(dragRecognizer(in: controller)?.isEnabled, false)
    }

    /// long press 零秒又掛在整個容器上，不同時辨識就會吃掉 Tab 的點擊。
    func test_theDragGestureRecognisesAlongsideOthers() throws {
        let controller = makeController(mode: .drag)
        let drag = try XCTUnwrap(dragRecognizer(in: controller))
        let other = UITapGestureRecognizer()

        XCTAssertEqual(
            drag.delegate?.gestureRecognizer?(drag, shouldRecognizeSimultaneouslyWith: other),
            true
        )
    }

    func test_modeSurvivesConfigurationCopy() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.swipeSelectionMode = .drag

        let copy = configuration.copy() as! TeroTabBarConfiguration

        XCTAssertEqual(copy.swipeSelectionMode, .drag)
    }

    func test_modeCanBeChangedAtRuntime() {
        let controller = makeController(mode: .disabled)
        XCTAssertEqual(dragRecognizer(in: controller)?.isEnabled, false)

        let update = controller.currentConfiguration()
        update.swipeSelectionMode = .drag
        controller.applyConfiguration(update, animated: false)

        XCTAssertEqual(dragRecognizer(in: controller)?.isEnabled, true)
    }

    func test_tapStillWorksWhileSwipeIsEnabled() {
        let controller = makeController(mode: .drag)

        tapTabBarItem("t1", in: controller)

        XCTAssertEqual(controller.selectedTab?.identifier, "t1", "啟用滑動不該讓點擊失效")
    }
}
// MARK: - 呼叫端有沒有真的用那個算術

/// 可以被指定 state 與位置的 pan 辨識器。
///
/// 存在的理由：合成觸控驅動不了真的 pan（slop 之前 state 一直是 Possible），
/// 但 `handleDrag` 的**內容**只依賴 `state` 與 `location(in:)`，那兩個可以覆寫。
/// 與正式驅動者同型別（零秒 long press）。它**沒有** `translation`，所以跟位移量的
/// 舊實作連編譯都過不了，更不可能矇混過去。
private final class FakeDragRecognizer: UILongPressGestureRecognizer {
    var stubbedState: UIGestureRecognizer.State = .began
    var stubbedLocation: CGPoint = .zero
    override var state: UIGestureRecognizer.State {
        get { stubbedState }
        set { stubbedState = newValue }
    }
    override func location(in view: UIView?) -> CGPoint { stubbedLocation }
}

/// 上一次的修正只有 resolver 落地、呼叫端沒改，而建置、594 個測試、六道守門**全綠**——
/// 因為測試直接叫 resolver，從不經過 `handleDrag`。抽出純運算解掉「算術對不對」，
/// 卻留下「呼叫端有沒有用它」這個新的沒覆蓋的東西。這個檔案釘住後者。
/// 一格掛一個，所以不必假設 `makeContentView()` 的呼叫順序對應格子順序。
private final class RecordingInteractiveProvider: NSObject, TeroTabInteractiveContentProvider {
    var lastProgress: CGFloat?
    var lastAnimated: Bool?

    func makeContentView() -> UIView { UIView() }

    func updateContentView(_ contentView: UIView, selectionProgress: CGFloat, animated: Bool) {
        lastProgress = selectionProgress
        lastAnimated = animated
    }
}

final class DragCallSiteTests: TeroTabBarControllerTestCase {

    private var isFloatingAvailable: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    private func makeDragController(
        providers: [TeroTabContentProvider] = [],
        tabCount: Int = 4
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.itemAppearance.selectionIndicatorStyle = .always
        configuration.swipeSelectionMode = .drag
        let controller = makeController(configuration: configuration)
        let tabs = (0..<tabCount).map { index -> TeroTab in
            let item = TeroTabItem(title: "T\(index)", image: nil, selectedImage: nil)
            item.accessibilityIdentifier = "tab.t\(index)"
            item.contentProvider = providers.indices.contains(index) ? providers[index] : nil
            return TeroTab(identifier: "t\(index)", viewController: UIViewController(), item: item)
        }
        controller.setTabs(tabs, selectedIdentifier: "t0", animated: false)
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    private func indicator(in controller: TeroTabBarController) -> TeroTabSelectionIndicatorView? {
        func search(_ view: UIView) -> TeroTabSelectionIndicatorView? {
            if let found = view as? TeroTabSelectionIndicatorView, !found.isHidden { return found }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return search(controller.tabBar)
    }

    /// 拖曳中的透鏡是 Bar 的**直接** subview；靜止的選取外框巢在膠囊裡面。
    private func lens(in controller: TeroTabBarController) -> TeroTabSelectionIndicatorView? {
        controller.tabBar.subviews.compactMap { $0 as? TeroTabSelectionIndicatorView }.first
    }

    /// 膠囊是外框往上第一個 `UIVisualEffectView`——使用者眼中的那一條 Bar。
    private func capsule(above view: UIView) -> UIVisualEffectView? {
        var node = view.superview
        while let current = node {
            if let effect = current as? UIVisualEffectView { return effect }
            node = current.superview
        }
        return nil
    }

    /// 手勢真實的取樣間隔是 8ms 上下；同步連打兩次的間隔小於 1ms，速度會被當成 0。
    private func waitOneGestureFrame() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    /// 按下的當下就要跟到手指底下，不必先移動。
    ///
    /// 這是零秒 long press 換掉 pan 的理由：pan 要跨過約 10pt 的 slop 才 `.began`，
    /// 所以「手指按住不動」在舊實作下完全沒反應，與 `.drag` 的契約不符。
    func test_pressingDownMovesTheIndicatorUnderTheFingerImmediately() throws {
        let controller = makeDragController()
        let indicatorView = try XCTUnwrap(indicator(in: controller))
        let startCentre = indicatorView.frame.midX

        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: startCentre + 120, y: 20)
        controller.tabBar.simulateDrag(recognizer)

        XCTAssertNotEqual(indicatorView.frame.midX, startCentre, accuracy: 0.5,
                          "touch-down 當下就該跟到手指底下")
    }

    /// `.drag` 以外的模式按下去不該有任何反應——那道守門住在派送點裡。
    func test_theDragDispatcherIgnoresOtherModes() throws {
        let controller = makeDragController()
        let update = controller.currentConfiguration()
        update.swipeSelectionMode = .swipe
        controller.applyConfiguration(update, animated: false)
        let indicatorView = try XCTUnwrap(indicator(in: controller))
        let startCentre = indicatorView.frame.midX

        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: startCentre + 120, y: 20)
        controller.tabBar.simulateDrag(recognizer)

        XCTAssertEqual(indicatorView.frame.midX, startCentre, accuracy: 0.5)
    }

    func test_theCallSiteUsesTheResolversArithmetic() throws {
        let controller = makeDragController()
        let indicatorView = try XCTUnwrap(indicator(in: controller))
        let container = try XCTUnwrap(indicatorView.superview)
        let finger = container.bounds.midX + 40

        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: finger, y: 20)
        controller.tabBar.simulateDrag(recognizer)
        let afterBegan = indicatorView.frame

        recognizer.stubbedState = .changed
        recognizer.stubbedLocation = CGPoint(x: finger + 60, y: 20)
        controller.tabBar.simulateDrag(recognizer)

        let expected = TeroTabSwipeSelectionResolver().indicatorFrame(
            followingCenterX: finger + 60, startFrame: afterBegan, in: container.bounds
        )
        XCTAssertEqual(indicatorView.frame.midX, expected.midX, accuracy: 0.5,
                       "呼叫端要走 resolver 的算術，不是自己另算一份")
    }
    // MARK: - 放開之後停在哪

    private func slotCentres(in controller: TeroTabBarController) throws -> [CGFloat] {
        let centres = (0..<4).compactMap { index in
            tabBarControl(for: "t\(index)", in: controller)?.frame.midX
        }
        // 查不到就明確失敗。用 compactMap 的結果直接索引會讓整個 run 崩在
        // 「Index out of range」，那個訊息完全指不出是哪裡錯。
        XCTAssertEqual(centres.count, 4, "四個 Tab 的控制項都要找得到")
        guard centres.count == 4 else { throw XCTSkip("前提不成立") }
        return centres
    }

    private func drag(
        _ controller: TeroTabBarController, from start: CGFloat, to end: CGFloat
    ) {
        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: start, y: 20)
        controller.tabBar.simulateDrag(recognizer)
        recognizer.stubbedState = .changed
        recognizer.stubbedLocation = CGPoint(x: end, y: 20)
        controller.tabBar.simulateDrag(recognizer)
        recognizer.stubbedState = .ended
        controller.tabBar.simulateDrag(recognizer)
    }

    func test_releasingOnAnotherSlotSettlesOnThatSlot() throws {
        let controller = makeDragController()
        let centres = try slotCentres(in: controller)
        let indicatorView = try XCTUnwrap(indicator(in: controller))

        drag(controller, from: centres[0], to: centres[2])
        waitUntil("吸附落定") { !controller.tabBar.isSelectionTransitionRunningForTesting }

        XCTAssertEqual(controller.selectedIndex, 2)
        XCTAssertEqual(indicatorView.frame.midX, centres[2], accuracy: 2.0,
                       "放開之後要坐在格子上，不是停在格與格之間")
    }

    /// 回報的案例：吸附結果**就是目前選取**時。
    func test_releasingBackOnTheCurrentSlotStillSettlesOnIt() throws {
        let controller = makeDragController()
        let centres = try slotCentres(in: controller)
        let indicatorView = try XCTUnwrap(indicator(in: controller))

        // 往右拖一點但沒過半，最近的仍是第 0 格。
        let between = centres[0] + (centres[1] - centres[0]) * 0.3
        drag(controller, from: centres[0], to: between)
        waitUntil("吸附落定") { !controller.tabBar.isSelectionTransitionRunningForTesting }

        XCTAssertEqual(controller.selectedIndex, 0, "選取沒變")
        XCTAssertEqual(indicatorView.frame.midX, centres[0], accuracy: 2.0,
                       "選取沒變也要回到格子上——這是回報的那個案例")
    }

    // MARK: - 拖曳中失去作用中狀態

    /// 兩條獨立的卡死路徑：吸附動畫在背景被暫停、以及 `.cancelled` 沒送到時
    /// `isDraggingIndicator` 永遠是 true。後者守著 `updateSelection` 與
    /// `renderSelectionGeometry`，所以外框會**永久**鎖在手指離開的地方。
    func test_losingActiveStateMidDragPutsTheIndicatorBackOnTheSelectedSlot() throws {
        let controller = makeDragController()
        let centres = try slotCentres(in: controller)
        let indicatorView = try XCTUnwrap(indicator(in: controller))

        // 拖到格與格之間就停手——不送 .ended，模擬被系統接走。
        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: centres[0], y: 20)
        controller.tabBar.simulateDrag(recognizer)
        recognizer.stubbedState = .changed
        recognizer.stubbedLocation = CGPoint(x: (centres[1] + centres[2]) / 2, y: 20)
        controller.tabBar.simulateDrag(recognizer)
        XCTAssertNotEqual(indicatorView.frame.midX, centres[0], accuracy: 2.0, "前提：已經離開格子")

        NotificationCenter.default.post(
            name: UIApplication.willResignActiveNotification, object: nil
        )

        XCTAssertEqual(indicatorView.frame.midX, centres[0], accuracy: 2.0,
                       "回到 model 的選取位置，不吸附到最近的格")
        XCTAssertEqual(controller.selectedIndex, 0, "切走不是完成操作，選取不得被改掉")
    }

    /// 放棄之後版面不得再被鎖住——這是 `isDraggingIndicator` 卡住的真正代價。
    // MARK: - 拖曳中的進度

    /// 拖曳中每一格的進度必須跟著手指走。
    ///
    /// 不跟的話放開時協調器從陳舊的進度起跑，第一個 callback 把外框拉回起點那一格，
    /// 使用者看到「閃回去再滑過來」。這裡從公開的 `TeroTabInteractiveContentProvider`
    /// 觀察，因為那正是 consumer 能看到這份進度的地方。
    func test_draggingFeedsProgressToInteractiveContentBeforeTheFingerLifts() throws {
        let recorders = (0..<4).map { _ in RecordingInteractiveProvider() }
        let controller = makeDragController(providers: recorders)
        let indicatorView = try XCTUnwrap(indicator(in: controller))
        let container = try XCTUnwrap(indicatorView.superview)

        let slots = (0..<4).compactMap { index in
            container.subviews.first { $0.accessibilityIdentifier == "tab.t\(index)" }
        }
        XCTAssertEqual(slots.count, 4, "找不到格子就測不到東西")
        recorders.forEach { $0.lastProgress = nil }

        // 手指停在第 0 與第 1 格正中間。
        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(
            x: (slots[0].frame.midX + slots[1].frame.midX) / 2, y: 20
        )
        controller.tabBar.simulateDrag(recognizer)

        XCTAssertEqual(try XCTUnwrap(recorders[0].lastProgress), 0.5, accuracy: 0.02,
                       "停在中間，兩格各拿一半")
        XCTAssertEqual(try XCTUnwrap(recorders[1].lastProgress), 0.5, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(recorders[3].lastProgress), 0, accuracy: 0.001,
                       "離手指最遠的那格不該有進度")
    }

    /// 放棄拖曳要把**進度**也收回去，不只幾何。
    ///
    /// 只重算幾何的話，幾何是照進度算的，而進度還停在手指那裡——外框會留在原地。
    func test_abandoningADragTakesTheProgressBackToTheSelectedSlot() throws {
        let recorders = (0..<4).map { _ in RecordingInteractiveProvider() }
        let controller = makeDragController(providers: recorders)
        let indicatorView = try XCTUnwrap(indicator(in: controller))
        let container = try XCTUnwrap(indicatorView.superview)

        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: container.bounds.maxX - 20, y: 20)
        controller.tabBar.simulateDrag(recognizer)
        XCTAssertGreaterThan(try XCTUnwrap(recorders[3].lastProgress), 0.5,
                             "前置條件：手指在最後一格上，它該有進度")

        NotificationCenter.default.post(
            name: UIApplication.willResignActiveNotification, object: nil
        )

        XCTAssertEqual(try XCTUnwrap(recorders[0].lastProgress), 1, accuracy: 0.001,
                       "選取仍然是 t0，進度就該全部回到 t0")
        XCTAssertEqual(try XCTUnwrap(recorders[3].lastProgress), 0, accuracy: 0.001)
    }

    // MARK: - 拖曳中的透鏡

    /// 透鏡要比 Bar 高，溢出上下緣——那是它看起來像一塊獨立的玻璃、而不是 Bar 裡面
    /// 一個色塊的原因（原生的設計）。
    func test_theDragLensOverflowsTheBarVertically() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeDragController()
        let indicatorView = try XCTUnwrap(indicator(in: controller))
        let bar = try XCTUnwrap(capsule(above: indicatorView))

        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: indicatorView.frame.midX + 60, y: 20)
        controller.tabBar.simulateDrag(recognizer)

        let lensView = try XCTUnwrap(lens(in: controller))
        XCTAssertFalse(lensView.isHidden, "拖曳中該看到玻璃")
        XCTAssertGreaterThan(lensView.bounds.height, bar.bounds.height * 1.2,
                             "透鏡的高度要明顯大於 Bar，才會溢出上下緣")
        XCTAssertEqual(lensView.center.y, bar.frame.midY, accuracy: 1,
                       "溢出要上下對稱，所以中心對齊 Bar 的中線")
        XCTAssertEqual(lensView.layer.cornerRadius,
                       min(lensView.bounds.width, lensView.bounds.height) / 2, accuracy: 0.5,
                       "圓角取短邊；取長邊的一半會讓 CALayer 把矩形畫成橢圓")
    }

    /// 開啟「減少動態效果」時，按下去不能有動畫。
    ///
    /// ADR-0006 寫的是「本套件內部**所有**動畫一律視為關閉」。轉場協調器那條路徑有守，
    /// 但拖曳這兩處（按下的第一步、放開的吸附）是自己建動畫器的，原本各自繞過了它。
    func test_reduceMotionRemovesTheDragAnimationsButKeepsThePosition() throws {
        overrideAccessibility(reduceMotion: true)
        let controller = makeDragController()
        let indicatorView = try XCTUnwrap(indicator(in: controller))
        let container = try XCTUnwrap(indicatorView.superview)
        // 離邊緣遠一點：外框會被夾在膠囊內，貼邊時中心到不了手指（另有測試釘住）。
        let target = container.bounds.midX + 60

        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: target, y: 20)
        controller.tabBar.simulateDrag(recognizer)

        XCTAssertTrue(indicatorView.layer.animationKeys()?.isEmpty ?? true,
                      "減少動態效果時不得有動畫")
        XCTAssertEqual(indicatorView.frame.midX, target, accuracy: 2,
                       "不動畫不等於不動：位置仍要到手指底下")
    }

    /// 拖曳中轉給 provider 的 `animated` 必須是 `false`。
    ///
    /// 它原本用的是 `segmentAnimated`，而那個值只在 `beginSelectionSegment` 設定——
    /// 拖曳從不走那裡，所以送出去的是**上一次轉場**留下的旗標。拖曳的每一次回呼都是
    /// 手指的當下位置，不是一段動畫。
    func test_dragReportsProgressAsNotAnimated() throws {
        let recorders = (0..<4).map { _ in RecordingInteractiveProvider() }
        let controller = makeDragController(providers: recorders)
        // 先跑一次有動畫的轉場，把 segmentAnimated 留成 true。
        controller.selectTab(withIdentifier: "t2", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        recorders.forEach { $0.lastAnimated = nil }

        let indicatorView = try XCTUnwrap(indicator(in: controller))
        let container = try XCTUnwrap(indicatorView.superview)
        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: container.bounds.midX, y: 20)
        controller.tabBar.simulateDrag(recognizer)

        XCTAssertEqual(try XCTUnwrap(recorders[1].lastAnimated), false,
                       "拖曳中的進度不是動畫出來的")
    }

    /// 透鏡一定是**橫躺**的膠囊，格子再窄也一樣。
    ///
    /// 溢出原本只加在高度上，隱含「格比 Bar 高度寬」。3–5 格時成立，6 格就反過來
    /// （格寬 49.7 < Bar 高 56），於是透鏡變成 49.7 寬 × 80.6 高的**直立**的蛋，
    /// 而且 `cornerRadius = height / 2` 大於半寬，CALayer 直接畫成橢圓——方向與原生
    /// 正好相反。協作專案在真機上抓到，4 格的測試看不到：4 格時寬 80.5、高 80.6，
    /// 剛好是一顆正圓，兩種寫法都過。
    func test_theDragLensStaysAHorizontalCapsuleWhenSlotsAreNarrow() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeDragController(tabCount: 6)
        let indicatorView = try XCTUnwrap(indicator(in: controller))
        let container = try XCTUnwrap(indicatorView.superview)
        let bar = try XCTUnwrap(capsule(above: indicatorView))

        // 前置條件：格子要比透鏡的高度窄。透鏡比 Bar 高，所以只要格寬小於 Bar 高的
        // 1.4 倍上下，舊規則（溢出只加在高度上）就會得到一顆直立的蛋。
        XCTAssertLessThan(indicatorView.bounds.width, bar.bounds.height * 1.4,
                          "格子不夠窄就測不到這個缺陷")

        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: container.bounds.midX, y: 20)
        controller.tabBar.simulateDrag(recognizer)

        let lensView = try XCTUnwrap(lens(in: controller))
        XCTAssertGreaterThan(lensView.bounds.width, lensView.bounds.height,
                             "橫躺：寬要大於高，不是直立的蛋")
        XCTAssertGreaterThan(lensView.bounds.width, indicatorView.bounds.width * 1.5,
                             "要比格子明顯寬，左右壓在鄰格上")
        XCTAssertEqual(lensView.layer.cornerRadius, lensView.bounds.height / 2, accuracy: 0.5,
                       "橫躺時短邊是高，圓角取它")
    }

    /// 按下去的第一步要用動畫把外框帶過來，不能瞬移。
    ///
    /// 原本不加動畫的理由是 pan 的 slop——`.began` 在手指移動十幾 pt 之後才到，讀起來
    /// 是吸過去。驅動者換成零秒 long press 之後完全沒有 slop，理由失效而決定留著：
    /// 選取在第一格、手指按最後一格時外框是瞬移的。
    func test_pressingDownAnimatesTheIndicatorAcrossInsteadOfTeleporting() throws {
        let controller = makeDragController()
        let indicatorView = try XCTUnwrap(indicator(in: controller))
        let container = try XCTUnwrap(indicatorView.superview)

        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: container.bounds.maxX - 30, y: 20)
        controller.tabBar.simulateDrag(recognizer)

        XCTAssertFalse(indicatorView.layer.animationKeys()?.isEmpty ?? true,
                       "第一次移動要掛著動畫；沒有動畫就是瞬移")
    }

    /// 跟手時透鏡要有果凍感：沿移動方向拉長、另一軸收縮（體積守恆）。
    func test_theDragLensDeformsWithTheFingerSpeed() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeDragController()
        let indicatorView = try XCTUnwrap(indicator(in: controller))
        let container = try XCTUnwrap(indicatorView.superview)

        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: container.bounds.midX - 80, y: 20)
        controller.tabBar.simulateDrag(recognizer)

        let lensView = try XCTUnwrap(lens(in: controller))
        XCTAssertEqual(lensView.transform.a, 1, accuracy: 0.001,
                       "按下的瞬間還沒有速度，不該先變形")

        waitOneGestureFrame()
        recognizer.stubbedState = .changed
        recognizer.stubbedLocation = CGPoint(x: container.bounds.midX + 80, y: 20)
        controller.tabBar.simulateDrag(recognizer)

        XCTAssertGreaterThan(lensView.transform.a, 1.15,
                            "快速跟手要沿水平拉長；identity 表示形變根本沒接上")
        XCTAssertEqual(lensView.transform.a * lensView.transform.d, 1, accuracy: 0.001,
                       "兩軸相乘守恆，否則透鏡會整塊變大")
    }

    /// 兩層疊在同一個位置會亮成一塊：交棒給透鏡時實色外框要退場。
    func test_theSolidIndicatorStepsBackWhileTheLensIsUp() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeDragController()
        let indicatorView = try XCTUnwrap(indicator(in: controller))

        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: indicatorView.frame.midX + 60, y: 20)
        controller.tabBar.simulateDrag(recognizer)

        XCTAssertEqual(indicatorView.alpha, 0, accuracy: 0.001)
    }

    func test_theIndicatorFollowsLayoutAgainAfterAbandoningADrag() throws {
        let controller = makeDragController()
        let centres = try slotCentres(in: controller)
        let indicatorView = try XCTUnwrap(indicator(in: controller))

        let recognizer = FakeDragRecognizer()
        recognizer.stubbedState = .began
        recognizer.stubbedLocation = CGPoint(x: centres[2], y: 20)
        controller.tabBar.simulateDrag(recognizer)
        NotificationCenter.default.post(
            name: UIApplication.willResignActiveNotification, object: nil
        )

        controller.selectTab(withIdentifier: "t3", animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(indicatorView.frame.midX, centres[3], accuracy: 2.0,
                       "拖曳的守門若沒解開，外框會永久鎖在手指離開的地方")
    }

}
