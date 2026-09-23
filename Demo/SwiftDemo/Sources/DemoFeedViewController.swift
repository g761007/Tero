import UIKit
import Tero

/// 長清單頁面，用來實測捲動驅動的 Presentation State。
///
/// 它自己保有 `UITableView` 的 delegate 與 dataSource——套件不會碰它們。
final class DemoFeedViewController: UIViewController,
                                    TeroScrollProviding,
                                    TeroTabBarScrollBehaviorProviding,
                                    UITableViewDataSource,
                                    UITableViewDelegate {

    private let tableView = UITableView()
    private let journal: DemoJournal
    private let behavior: TeroTabBarScrollBehavior

    /// 本頁面明確表達偏好，覆蓋設定中的行為。
    var teroTrackingScrollView: UIScrollView? { tableView }
    var preferredTeroTabBarScrollBehavior: TeroTabBarScrollBehavior { behavior }

    init(journal: DemoJournal, behavior: TeroTabBarScrollBehavior) {
        self.journal = journal
        self.behavior = behavior
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Feed"
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// 供自動化截圖使用：不經手勢就捲到指定位置。
    func scrollProgrammatically(to offset: CGFloat) {
        view.layoutIfNeeded()
        tableView.contentOffset = CGPoint(x: 0, y: -tableView.adjustedContentInset.top + offset)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 60 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "row")
        cell.textLabel?.text = "第 \(indexPath.row + 1) 列"
        cell.detailTextLabel?.text = "往下捲動看 Tab Bar 收合，回到頂部它一定回來"
        return cell
    }

    /// 套件不會替換這個 delegate——這裡的回呼仍然屬於 App 自己。
    func scrollViewDidScroll(_ scrollView: UIScrollView) {}
}
