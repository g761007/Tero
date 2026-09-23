import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    /// iOS 26 SDK 要求 scene lifecycle；window 因此由 `SceneDelegate` 建立。
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// 啟動參數決定進哪個畫面，讓自動化截圖不必點 UI。預設仍是原本的 Demo。
    static func makeRootViewController() -> UIViewController {
        if let name = DemoLaunchOptions.referenceCaseName,
           let referenceCase = DemoReferenceCase(rawValue: name.lowercased()) {
            return DemoReferenceCaseViewController(referenceCase: referenceCase)
        }
        if DemoLaunchOptions.opensInteractionLab {
            return InteractionLabViewController()
        }
        if DemoLaunchOptions.opensInstagramDemo {
            return InstagramDemoViewController()
        }
        return DemoHostViewController()
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = AppDelegate.makeRootViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
