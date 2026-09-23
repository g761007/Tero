# Demo

專案檔以 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 產生，因此 repo 只保留 `project.yml`。

~~~bash
cd Demo/SwiftDemo && xcodegen generate && open SwiftDemo.xcodeproj
~~~

`SwiftDemo` 從容器核心那個切片起就必須保持可跑——它是這個專案的持續驗證載體。
真實 App 已於 2.0 期間接入，但 Demo 仍是唯一能在
沒有那個 App 的機器上重現每一種互動的地方。


## Navigation／Chrome Interaction Lab

以 `--lab` 啟動 Swift Demo，Home 是 UITableView，Video 是 UICollectionView。頁面保留自身 delegate，表頭含水平 carousel，並支援下拉更新。

- 點一列／卡片 push 到明確 hidden 的 Detail，再側滑返回，分別完成與取消。
- 滑桿可調方向鎖、收合門檻、收合／恢復時長與高度；Action 可即時切換。
- Custom Header 使用自己的 60pt 進度，底部使用 Tero 的方向鎖／位移門檻。
- 收合中切換 Tab、旋轉或調整 iPad 視窗，檢查 Selection、Badge 與 Action。
- 開啟 Reduce Motion／Reduce Transparency／Accessibility 字級後重試。

真機效能：以相同裝置與 OS 比較變更前後；各取 60Hz／120Hz 裝置的 Animation Hitches 與 Time Profiler，紀錄 device、OS、build、操作與 trace。本機 Simulator 測試不能替代這項量測。
