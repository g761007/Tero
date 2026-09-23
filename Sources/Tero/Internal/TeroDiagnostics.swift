import Foundation

/// 依計畫書 §54：programming error 在 Debug 觸發 assert，在 Release 採安全 fallback。
///
/// 以可替換的 handler 表示，讓「Release 的 fallback 行為」本身可以被測試——
/// 否則在 Debug 下跑測試會直接 crash，那條規則就永遠沒被驗證過。
internal enum TeroDiagnostics {

    internal static var reportHandler: (String, StaticString, UInt) -> Void = { message, file, line in
        assertionFailure(message, file: file, line: line)
    }

    internal static func report(
        _ message: String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        reportHandler(message, file, line)
    }

    internal static func assertMainThread(
        _ function: StaticString = #function,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        guard !Thread.isMainThread else { return }
        report("\(function) 必須在 main thread 呼叫", file: file, line: line)
    }
}
