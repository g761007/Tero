import UIKit

/// Demo 用的 Tab 內容。把自己的 lifecycle 事件寫進共用紀錄，
/// 讓「切換 Tab 產生正確的 appearance 序列」在畫面上看得到。
final class DemoContentViewController: UIViewController {

    private let name: String
    private let tint: UIColor
    private let journal: DemoJournal

    private let titleLabel = UILabel()
    private let pushCountLabel = UILabel()

    init(name: String, tint: UIColor, journal: DemoJournal) {
        self.name = name
        self.tint = tint
        self.journal = journal
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = tint.withAlphaComponent(0.12)

        titleLabel.text = name
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = tint

        pushCountLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        pushCountLabel.textColor = .secondaryLabel
        pushCountLabel.numberOfLines = 0

        let pushButton = UIButton(type: .system)
        pushButton.setTitle("push 一層（驗證 navigation stack 保留）", for: .normal)
        pushButton.addTarget(self, action: #selector(pushDeeper), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, pushCountLabel, pushButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])

        updateStackDepth()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        journal.record("\(name).viewWillAppear")
        updateStackDepth()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        journal.record("\(name).viewDidAppear")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        journal.record("\(name).viewWillDisappear")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        journal.record("\(name).viewDidDisappear")
    }

    private func updateStackDepth() {
        let depth = navigationController?.viewControllers.count ?? 0
        pushCountLabel.text = "navigation stack 深度：\(depth)"
    }

    @objc private func pushDeeper() {
        let deeper = DemoContentViewController(
            name: "\(name) 的下一層",
            tint: tint,
            journal: journal
        )
        navigationController?.pushViewController(deeper, animated: true)
    }
}
