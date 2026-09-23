import XCTest
import UIKit
@testable import Tero

/// Phase 8：安全區域帳本。
///
/// 只碰 `additionalSafeAreaInsets`，不需要 window 或 runloop——落在 seam 2 的邊界上。
final class SafeAreaLedgerTests: XCTestCase {

    private func child(top: CGFloat = 0, bottom: CGFloat = 0) -> UIViewController {
        let vc = UIViewController()
        vc.additionalSafeAreaInsets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        return vc
    }

    // MARK: - 只增減自己的貢獻

    func test_applyingAddsToWhateverTheConsumerAlreadySet() {
        var ledger = TeroSafeAreaLedger(edge: .top)
        let page = child(top: 10)

        ledger.apply(96, to: page)

        XCTAssertEqual(page.additionalSafeAreaInsets.top, 106, "保留 Consumer 的 10，不是覆蓋成 96")
    }

    func test_applyingTwiceOnlyMovesTheDifference() {
        var ledger = TeroSafeAreaLedger(edge: .top)
        let page = child(top: 10)

        ledger.apply(96, to: page)
        ledger.apply(44, to: page)

        XCTAssertEqual(page.additionalSafeAreaInsets.top, 54, "10 + 44，不是 10 + 96 + 44")
    }

    func test_releasingGivesBackOnlyWhatItContributed() {
        var ledger = TeroSafeAreaLedger(edge: .top)
        let page = child(top: 10)
        ledger.apply(96, to: page)

        ledger.release(page)

        XCTAssertEqual(page.additionalSafeAreaInsets.top, 10, "Consumer 自己的 10 要留著")
    }

    func test_releasingAnUnknownChildDoesNothing() {
        var ledger = TeroSafeAreaLedger(edge: .top)
        let page = child(top: 10)

        ledger.release(page)

        XCTAssertEqual(page.additionalSafeAreaInsets.top, 10)
    }

    // MARK: - 軸擁有權

    func test_aTopLedgerNeverTouchesTheBottomEdge() {
        var ledger = TeroSafeAreaLedger(edge: .top)
        let page = child(top: 0, bottom: 34)

        ledger.apply(96, to: page)

        XCTAssertEqual(page.additionalSafeAreaInsets.top, 96)
        XCTAssertEqual(page.additionalSafeAreaInsets.bottom, 34, "另一向由別的容器負責，不得轉寫")
    }

    func test_aBottomLedgerNeverTouchesTheTopEdge() {
        var ledger = TeroSafeAreaLedger(edge: .bottom)
        let page = child(top: 47, bottom: 0)

        ledger.apply(56, to: page)

        XCTAssertEqual(page.additionalSafeAreaInsets.bottom, 56)
        XCTAssertEqual(page.additionalSafeAreaInsets.top, 47)
    }

    func test_twoLedgersOnDifferentEdgesCoexistOnOneChild() {
        var top = TeroSafeAreaLedger(edge: .top)
        var bottom = TeroSafeAreaLedger(edge: .bottom)
        let page = child()

        top.apply(96, to: page)
        bottom.apply(56, to: page)

        XCTAssertEqual(page.additionalSafeAreaInsets.top, 96, "兩層容器疊起來，各寫各的軸")
        XCTAssertEqual(page.additionalSafeAreaInsets.bottom, 56)

        top.release(page)

        XCTAssertEqual(page.additionalSafeAreaInsets.top, 0)
        XCTAssertEqual(page.additionalSafeAreaInsets.bottom, 56, "歸還一向不影響另一向")
    }

    // MARK: - 回報是否真的改動

    func test_applyingTheSameValueReportsNoChange() {
        var ledger = TeroSafeAreaLedger(edge: .top)
        let page = child()
        ledger.apply(96, to: page)

        XCTAssertFalse(ledger.apply(96, to: page), "值沒變就不該回報改動——呼叫端據此決定要不要抑制捲動")
    }

    func test_applyingADifferentValueReportsChange() {
        var ledger = TeroSafeAreaLedger(edge: .top)
        let page = child()
        ledger.apply(96, to: page)

        XCTAssertTrue(ledger.apply(44, to: page))
    }

    func test_contributionReportsWhatWasApplied() {
        var ledger = TeroSafeAreaLedger(edge: .bottom)
        let page = child(bottom: 20)

        ledger.apply(56, to: page)

        XCTAssertEqual(ledger.contribution(for: page), 56, "回報的是自己的貢獻，不含 Consumer 的 20")
    }
    // MARK: - Phase 15 A2：頁面自己指派 inset 之後，帳本還算得準嗎

    /// 帳本用差量記帳（`insets.top += value - previous`），從不重讀 child 的現值。
    /// 頁面若在 `viewDidLoad` 裡**指派**（而非累加）`additionalSafeAreaInsets`，
    /// 容器記下的那筆貢獻就被抹掉了，而帳本仍然相信它在。
    func test_afterThePageAssignsItsOwnInsets_theLedgerStillRestoresTheContribution() {
        var ledger = TeroSafeAreaLedger(edge: .bottom)
        let child = UIViewController()

        ledger.apply(56, to: child)
        XCTAssertEqual(child.additionalSafeAreaInsets.bottom, 56)

        // 頁面自己指派——這是 consumer 寫得出來的最自然寫法。
        child.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)

        ledger.apply(56, to: child)

        XCTAssertEqual(child.additionalSafeAreaInsets.bottom, 76,
                       "容器的 56 要和頁面自己的 20 疊加；差量記帳會在這裡短路，貢獻永遠補不回來")
    }

    func test_releasingNeverDrivesTheInsetNegative() {
        var ledger = TeroSafeAreaLedger(edge: .bottom)
        let child = UIViewController()
        ledger.apply(56, to: child)
        child.additionalSafeAreaInsets = .zero

        ledger.release(child)

        XCTAssertGreaterThanOrEqual(child.additionalSafeAreaInsets.bottom, 0,
                                    "歸還一筆已經不存在的貢獻不該讓 inset 變負")
    }

}
