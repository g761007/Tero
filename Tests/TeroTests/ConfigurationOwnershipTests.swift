import XCTest
@testable import Tero

/// 對應計畫書 §24：controller 不持有 consumer 傳入的 mutable reference。
final class ConfigurationOwnershipTests: TeroTabBarControllerTestCase {

    func test_configurationIsDeepCopiedAtInit() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.compact.maximumVisibleItems = 4

        let controller = TeroTabBarController(configuration: configuration)

        // 建立之後修改原本那份物件
        configuration.style = .classic
        configuration.compact.maximumVisibleItems = 2
        configuration.itemAppearance.normalTintColor = .magenta

        XCTAssertEqual(controller.requestedStyle, .floatingGlass, "不該被事後修改影響")
        let snapshot = controller.currentConfiguration()
        XCTAssertEqual(snapshot.compact.maximumVisibleItems, 4)
        XCTAssertNotEqual(snapshot.itemAppearance.normalTintColor, .magenta)
    }

    func test_currentConfigurationReturnsSnapshotThatCannotWriteBack() {
        let controller = makeController()
        let snapshot = controller.currentConfiguration()

        snapshot.style = .floatingGlass
        snapshot.compact.maximumVisibleItems = 3
        snapshot.classicAppearance.barHeight = 999

        let fresh = controller.currentConfiguration()
        XCTAssertNotEqual(fresh.style, .floatingGlass)
        XCTAssertNotEqual(fresh.compact.maximumVisibleItems, 3)
        XCTAssertNotEqual(fresh.classicAppearance.barHeight, 999)
    }

    func test_currentConfigurationReturnsDistinctInstancesEachCall() {
        let controller = makeController()

        let first = controller.currentConfiguration()
        let second = controller.currentConfiguration()

        XCTAssertFalse(first === second)
        XCTAssertFalse(first.compact === second.compact, "layout 設定也必須是深拷貝")
        XCTAssertFalse(first.moreItem === second.moreItem, "More 也必須是深拷貝")
    }

    func test_defaultConfigurationReturnsFreshInstance() {
        let first = TeroTabBarConfiguration.defaultConfiguration()
        let second = TeroTabBarConfiguration.defaultConfiguration()

        XCTAssertFalse(first === second)
        first.compact.maximumVisibleItems = 2
        XCTAssertNotEqual(second.compact.maximumVisibleItems, 2)
    }

    func test_maximumVisibleItemsBelowTwoIsClampedAndReported() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()

        configuration.compact.maximumVisibleItems = 1

        XCTAssertEqual(configuration.compact.maximumVisibleItems, 2, "Release 應採安全 fallback")
        XCTAssertEqual(reportedDiagnostics.count, 1)
    }

    func test_objectiveCTintColorProxiesForwardToItemAppearance() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()

        configuration.normalTintColor = .systemPink
        configuration.selectedTintColor = .systemTeal

        XCTAssertEqual(configuration.itemAppearance.normalTintColor, .systemPink)
        XCTAssertEqual(configuration.itemAppearance.selectedTintColor, .systemTeal)
        XCTAssertEqual(configuration.normalTintColor, .systemPink)
    }

    func test_compactAndRegularHaveIndependentLimits() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()

        configuration.compact.maximumVisibleItems = 5
        configuration.regular.maximumVisibleItems = 7

        XCTAssertEqual(configuration.compact.maximumVisibleItems, 5)
        XCTAssertEqual(configuration.regular.maximumVisibleItems, 7)
    }

    func test_objectiveCMotionProxiesForwardToMotion() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()

        configuration.motionSelectionDuration = 0.9
        configuration.motionSelectionDampingRatio = 0.5
        configuration.motionSelectionStretch = 0.2
        configuration.motionMinimizeDuration = 0.11
        configuration.motionRestoreDuration = 0.12
        configuration.motionReselectDuration = 0.13
        configuration.motionContentTransitionDuration = 0.14
        configuration.motionAllowsInterruptibleTransition = false
        configuration.motionReduceMotionBehavior = .instant

        XCTAssertEqual(configuration.motion.selectionDuration, 0.9)
        XCTAssertEqual(configuration.motion.selectionDampingRatio, 0.5)
        XCTAssertEqual(configuration.motion.selectionStretch, 0.2)
        XCTAssertEqual(configuration.motion.minimizeDuration, 0.11)
        XCTAssertEqual(configuration.motion.restoreDuration, 0.12)
        XCTAssertEqual(configuration.motion.reselectDuration, 0.13)
        XCTAssertEqual(configuration.motion.contentTransitionDuration, 0.14)
        XCTAssertFalse(configuration.motion.allowsInterruptibleTransition)
        XCTAssertEqual(configuration.motion.reduceMotionBehavior, .instant)
    }

    func test_objectiveCMotionProxiesReadBackWhatSwiftSet() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()

        configuration.motion.selectionDuration = 0.77
        configuration.motion.reduceMotionBehavior = .instant

        XCTAssertEqual(configuration.motionSelectionDuration, 0.77)
        XCTAssertEqual(configuration.motionReduceMotionBehavior, .instant)
    }

    func test_zeroMotionSelectionResponseMeansUnspecified() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()

        // Objective-C 看不到 Optional，因此以 0 表示「不用彈簧 response，改用 duration」。
        configuration.motionSelectionResponse = 0

        XCTAssertNil(configuration.motion.selectionResponse, "0 要落到 nil，而不是一個 0 秒的彈簧")
        XCTAssertEqual(configuration.motionSelectionResponse, 0, "讀回來仍是 0")

        configuration.motionSelectionResponse = 0.3

        XCTAssertEqual(configuration.motion.selectionResponse, 0.3)
        XCTAssertEqual(configuration.motionSelectionResponse, 0.3)
    }

    func test_motionProxiesSurviveTheConfigurationDeepCopy() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.motionSelectionDuration = 0.66
        configuration.motionReduceMotionBehavior = .instant

        guard let copy = configuration.copy() as? TeroTabBarConfiguration else {
            return XCTFail("copy 應回傳 TeroTabBarConfiguration")
        }
        configuration.motionSelectionDuration = 0.1

        XCTAssertEqual(copy.motionSelectionDuration, 0.66, "深拷貝後改原件不應影響複本")
        XCTAssertEqual(copy.motionReduceMotionBehavior, .instant)
    }

    // MARK: - Objective-C 的其餘三組轉發屬性（issue #92）

    func test_objectiveCScrollProxiesForwardToScrollConfiguration() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()

        configuration.scrollBehavior = .hideOnScrollDown
        configuration.scrollDownwardTranslationThreshold = 55
        configuration.scrollUpwardTranslationThreshold = 33
        configuration.scrollDirectionLockDistance = 11
        configuration.scrollVelocityThreshold = 222

        XCTAssertEqual(configuration.scrollConfiguration.behavior, .hideOnScrollDown)
        XCTAssertEqual(configuration.scrollConfiguration.downwardTranslationThreshold, 55)
        XCTAssertEqual(configuration.scrollConfiguration.upwardTranslationThreshold, 33)
        XCTAssertEqual(configuration.scrollConfiguration.directionLockDistance, 11)
        XCTAssertEqual(configuration.scrollConfiguration.velocityThreshold, 222)
        XCTAssertEqual(configuration.scrollBehavior, .hideOnScrollDown, "讀回來要一致")
    }

    func test_objectiveCClassicProxiesForwardToClassicAppearance() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()

        configuration.classicBarHeight = 64
        configuration.classicContentInsets = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
        configuration.classicBackgroundColor = .systemPink
        configuration.classicUsesBlurEffect = false
        configuration.classicBlurEffectStyle = .systemThinMaterial
        configuration.classicSeparatorColor = nil
        configuration.classicActionSize = CGSize(width: 50, height: 50)

        XCTAssertEqual(configuration.classicAppearance.barHeight, 64)
        XCTAssertEqual(configuration.classicAppearance.contentInsets, UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4))
        XCTAssertEqual(configuration.classicAppearance.backgroundColor, .systemPink)
        XCTAssertFalse(configuration.classicAppearance.usesBlurEffect)
        XCTAssertEqual(configuration.classicAppearance.blurEffectStyle, .systemThinMaterial)
        XCTAssertNil(configuration.classicAppearance.separatorColor, "nil 要能表達「不畫分隔線」")
        XCTAssertEqual(configuration.classicAppearance.actionSize, CGSize(width: 50, height: 50))
    }

    func test_objectiveCFloatingGlassProxiesForwardToFloatingGlassAppearance() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()

        configuration.floatingGlassExpandedHeight = 60
        configuration.floatingGlassMinimizedHeight = 40
        configuration.floatingGlassHorizontalInset = 20
        configuration.floatingGlassBottomInset = 30
        configuration.floatingGlassActionSpacing = 10
        configuration.floatingGlassActionSize = CGSize(width: 52, height: 52)
        configuration.floatingGlassContainerSpacing = 14
        configuration.floatingGlassCornerRadius = 26
        configuration.floatingGlassMinimizedCornerRadius = 16
        configuration.floatingGlassHidesTitlesWhenMinimized = false
        configuration.floatingGlassTintMode = .tinted
        configuration.floatingGlassTintColor = .systemTeal

        let appearance = configuration.floatingGlassAppearance
        XCTAssertEqual(appearance.expandedHeight, 60)
        XCTAssertEqual(appearance.minimizedHeight, 40)
        XCTAssertEqual(appearance.horizontalInset, 20)
        XCTAssertEqual(appearance.bottomInset, 30)
        XCTAssertEqual(appearance.actionSpacing, 10)
        XCTAssertEqual(appearance.actionSize, CGSize(width: 52, height: 52))
        XCTAssertEqual(appearance.glassContainerSpacing, 14)
        XCTAssertEqual(appearance.cornerRadius, 26)
        XCTAssertEqual(appearance.minimizedCornerRadius, 16)
        XCTAssertFalse(appearance.hidesTitlesWhenMinimized)
        XCTAssertEqual(appearance.glassTintMode, .tinted)
        XCTAssertEqual(appearance.glassTintColor, .systemTeal)
    }

    func test_appearanceProxiesSurviveTheConfigurationDeepCopy() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.scrollBehavior = .minimizeOnScrollDown
        configuration.classicBarHeight = 61
        configuration.floatingGlassBottomInset = 29

        guard let copy = configuration.copy() as? TeroTabBarConfiguration else {
            return XCTFail("copy 應回傳 TeroTabBarConfiguration")
        }
        configuration.scrollBehavior = .none
        configuration.classicBarHeight = 1
        configuration.floatingGlassBottomInset = 1

        XCTAssertEqual(copy.scrollBehavior, .minimizeOnScrollDown)
        XCTAssertEqual(copy.classicBarHeight, 61)
        XCTAssertEqual(copy.floatingGlassBottomInset, 29)
    }
}
