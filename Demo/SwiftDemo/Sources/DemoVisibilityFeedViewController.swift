import UIKit
import Tero

/// Consumer 自己的 Scroll delegate／Header；與底部採不同的門檻與進度。
final class DemoVisibilityFeedViewController: UIViewController, TeroScrollProviding,
                                               TeroTabBarScrollBehaviorProviding,
    UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let usesCollection: Bool
    private let header = UILabel()
    private var scroll: UIScrollView!
    var teroTrackingScrollView: UIScrollView? { scroll }
    var preferredTeroTabBarScrollBehavior: TeroTabBarScrollBehavior { .minimizeOnScrollDown }

    init(collection: Bool = false) {
        usesCollection = collection
        super.init(nibName: nil, bundle: nil)
        title = collection ? "Collection" : "Feed"
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        if usesCollection {
            let layout = UICollectionViewFlowLayout()
            layout.itemSize = CGSize(width: 140, height: 100)
            let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
            collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "card")
            collection.dataSource = self
            collection.delegate = self
            scroll = collection
        } else {
            let table = UITableView()
            table.dataSource = self
            table.delegate = self
            table.rowHeight = 72
            let carousel = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 90))
            carousel.contentSize = CGSize(width: 1000, height: 90)
            for index in 0..<8 {
                let card = UILabel(frame: CGRect(x: 12 + index * 120, y: 8, width: 108, height: 72))
                card.text = "Carousel \(index + 1)"
                card.textAlignment = .center
                card.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.35)
                carousel.addSubview(card)
            }
            table.tableHeaderView = carousel
            scroll = table
        }
        scroll.backgroundColor = .clear
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.accessibilityIdentifier = "lab.feed"
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshFeed(_:)), for: .valueChanged)
        scroll.refreshControl = refresh
        header.text = "Custom Header · 下滑收合／回頂恢復"
        header.font = .preferredFont(forTextStyle: .caption1)
        header.backgroundColor = .secondarySystemBackground
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            header.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    @objc private func refreshFeed(_ sender: UIRefreshControl) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak sender] in sender?.endRefreshing() }
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let distance = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        let progress = min(1, distance / 60)
        header.alpha = 1 - progress
        header.transform = CGAffineTransform(translationX: 0, y: -30 * progress)
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 60 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "row")
        cell.textLabel?.text = "Feed \(indexPath.row + 1)"
        cell.detailTextLabel?.text = "點擊隱藏 Tab Bar；側滑返回可取消"
        cell.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.35)
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { pushDetail() }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 80 }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "card", for: indexPath)
        var content = UIListContentConfiguration.cell()
        content.text = "Card \(indexPath.item + 1)"
        content.image = UIImage(systemName: "photo")
        cell.contentConfiguration = content
        cell.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.4)
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) { pushDetail() }
    private func pushDetail() { navigationController?.pushViewController(DemoVisibilityDetailViewController(), animated: true) }
}

private final class DemoVisibilityDetailViewController: UIViewController, TeroTabVisibilityProviding {
    var preferredTeroTabVisibilityPolicy: TeroTabVisibilityPolicy { .hidden }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Detail · Tab Bar Hidden"
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "從左側滑回，拖到一半取消。\nTab Bar 應跟隨返回並還原。"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
