import XCTest
@testable import Tero

private final class VisibilityPage: UIViewController, TeroTabVisibilityProviding, TeroScrollProviding {
    var policy: TeroTabVisibilityPolicy = .inherit
    let scroll = UIScrollView()
    var preferredTeroTabVisibilityPolicy: TeroTabVisibilityPolicy { policy }
    var teroTrackingScrollView: UIScrollView? { scroll }
}

/// Public transition-coordinator seam: deterministically exercises preview and cancellation.
private final class NavigationContext: NSObject, UIViewControllerTransitionCoordinator {
    var isAnimated = true
    var presentationStyle: UIModalPresentationStyle = .none
    var initiallyInteractive = true
    var isInterruptible = true
    var isInteractive = true
    var isCancelled = false
    var transitionDuration: TimeInterval = 0.3
    var percentComplete: CGFloat = 0.5
    var completionVelocity: CGFloat = 0
    var completionCurve: UIView.AnimationCurve = .easeInOut
    let containerView = UIView()
    var targetTransform: CGAffineTransform = .identity
    var source: UIViewController?
    var destination: UIViewController?
    var completions: [(UIViewControllerTransitionCoordinatorContext) -> Void] = []
    var registrationCount = 0
    weak var alongsideView: UIView?
    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
        key == .from ? source : destination
    }
    func view(forKey key: UITransitionContextViewKey) -> UIView? { nil }
    func animate(alongsideTransition animation: ((UIViewControllerTransitionCoordinatorContext) -> Void)?, completion: ((UIViewControllerTransitionCoordinatorContext) -> Void)? = nil) -> Bool {
        registrationCount += 1
        animation?(self)
        if let completion { completions.append(completion) }
        return true
    }
    func animateAlongsideTransition(in view: UIView?, animation: ((UIViewControllerTransitionCoordinatorContext) -> Void)?, completion: ((UIViewControllerTransitionCoordinatorContext) -> Void)? = nil) -> Bool {
        alongsideView = view
        return animate(alongsideTransition: animation, completion: completion)
    }
    func notifyWhenInteractionEnds(_ handler: @escaping (UIViewControllerTransitionCoordinatorContext) -> Void) {}
    func notifyWhenInteractionChanges(_ handler: @escaping (UIViewControllerTransitionCoordinatorContext) -> Void) {}
    func finish(cancelled: Bool) {
        isCancelled = cancelled
        isInteractive = false
        completions.forEach { $0(self) }
    }
}

private final class TestNavigation: UINavigationController {
    var context: NavigationContext?
    override var transitionCoordinator: UIViewControllerTransitionCoordinator? { context ?? super.transitionCoordinator }
}

final class NavigationVisibilityTests: TeroTabBarControllerTestCase {
    func test_policyDoesNotSetProgrammaticLockAndReturningToRootRestores() {
        let root = VisibilityPage()
        let detail = VisibilityPage()
        detail.policy = .hidden
        let nav = UINavigationController(rootViewController: root)
        let controller = setup(nav)
        nav.pushViewController(detail, animated: false)
        controller.coordinateNavigationTransition(nav, to: detail, animated: false)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)
        XCTAssertFalse(controller.isPresentationStateLocked)
        controller.applyScrollDrivenPresentationState(.expanded, animated: false)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)
        nav.popViewController(animated: false)
        controller.coordinateNavigationTransition(nav, to: root, animated: false)
        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    func test_interactivePreviewCancelRestoresStateInsetsAndDoesNotEmitCommit() {
        let root = VisibilityPage()
        root.policy = .hidden
        let detail = VisibilityPage()
        let nav = TestNavigation(rootViewController: root)
        let controller = setup(nav)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)
        let inset = nav.additionalSafeAreaInsets.bottom
        let context = NavigationContext()
        context.source = root
        context.destination = detail
        nav.context = context
        controller.coordinateNavigationTransition(nav, to: detail, animated: true)
        controller.coordinateNavigationTransition(nav, to: detail, animated: true)
        XCTAssertEqual(context.registrationCount, 1)
        XCTAssertIdentical(context.alongsideView, controller.view)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden, "preview 不改 logical state")
        XCTAssertEqual(controller.tabBar.presentationState, .expanded)
        XCTAssertEqual(nav.additionalSafeAreaInsets.bottom, inset)
        context.finish(cancelled: true)
        XCTAssertEqual(controller.tabBar.presentationState, .hidden)
        XCTAssertEqual(nav.additionalSafeAreaInsets.bottom, inset)
    }

    func test_completionCommitsDestinationButProgrammaticLockWins() {
        let root = VisibilityPage()
        let detail = VisibilityPage()
        detail.policy = .hidden
        let nav = TestNavigation(rootViewController: root)
        let controller = setup(nav)
        let context = NavigationContext()
        context.source = root
        context.destination = detail
        nav.context = context
        controller.coordinateNavigationTransition(nav, to: detail, animated: true)
        context.finish(cancelled: false)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)
        XCTAssertFalse(controller.isPresentationStateLocked)
        controller.setTabBarPresentationState(.hidden, animated: false)
        controller.refreshScrollTracking()
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)
        XCTAssertTrue(controller.isPresentationStateLocked)
        XCTAssertFalse(controller.tabBar.isUserInteractionEnabled)
        XCTAssertTrue(controller.tabBar.accessibilityElementsHidden)
    }

    func test_staleCompletionAfterTabSwitchIsIgnored() {
        let root = VisibilityPage()
        let detail = VisibilityPage()
        detail.policy = .hidden
        let nav = TestNavigation(rootViewController: root)
        let controller = setup(nav)
        let context = NavigationContext()
        context.source = root
        context.destination = detail
        nav.context = context
        controller.coordinateNavigationTransition(nav, to: detail, animated: true)
        controller.selectTab(withIdentifier: "other", animated: false)
        context.finish(cancelled: false)
        XCTAssertEqual(controller.selectedTab?.identifier, "other")
        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
        XCTAssertEqual(controller.tabBar.presentationState, .expanded)
    }

    func test_resolverPriority() {
        let resolver = TeroTabVisibilityResolver()
        XCTAssertEqual(resolver.resolve(locked: true, navigation: .expanded, policy: .expanded, scroll: .minimized), .hidden)
        XCTAssertEqual(resolver.resolve(locked: false, navigation: .minimized, policy: .hidden, scroll: .expanded), .minimized)
        XCTAssertEqual(resolver.resolve(locked: false, policy: .hidden, scroll: .expanded), .hidden)
    }

    private func setup(_ nav: UINavigationController) -> TeroTabBarController {
        let controller = makeController()
        let item = TeroTabItem(title: "Feed", image: nil, selectedImage: nil)
        controller.setTabs([TeroTab(identifier: "feed", viewController: nav, item: item), makeTab("other")], selectedIdentifier: "feed", animated: false)
        present(controller)
        return controller
    }
}
