Pod::Spec.new do |s|
  s.name             = 'Tero'
  s.version          = '2.0.0'
  s.summary          = 'A hand-built tab bar and navigation container for iOS.'
  s.description      = <<~DESC
    Replaces UITabBarController and UINavigationController so that tab navigation
    behaves the way this package decides rather than the way the OS version decides.
    Tab content can be any UIView, and the package ships no resources.
  DESC
  s.homepage         = 'https://github.com/g761007/Tero'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = 'Daniel Hsieh'

  # 刻意只走 git，不上 CocoaPods trunk。
  #
  # Trunk 於 2026-12-02 永久唯讀——之後連「既有 pod 的新版本」都不再接受。上架等於把
  # 這個套件永遠凍在那一版，而它還在往 2.0.0 之後走。那比沒有 pod 更糟：留下一個看起來
  # 官方、實際上悄悄過期的管道。`:git` 不經 trunk，不受影響。
  #
  # 用法（Podfile）：
  #   pod 'Tero', :git => 'https://github.com/g761007/Tero.git', :tag => '2.0.0'
  s.source           = { :git => 'https://github.com/g761007/Tero.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  # 與 Package.swift 的 swiftLanguageMode(.v5) 一致。
  s.swift_versions   = ['5.0']
  s.source_files     = 'Sources/Tero/**/*.swift'
  s.frameworks       = 'UIKit'

  # 沒有 resource_bundles 是刻意的，見 ADR-0007：套件內不得出現任何資源檔引用。
end
