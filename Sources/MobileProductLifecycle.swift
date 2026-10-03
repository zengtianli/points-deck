import Foundation

// Product allowlist and release channel; shared lifecycle code owns transfer/checking.
@MainActor
enum MobileProductLifecycle {
    static var channel: MobileUpdateChannel {
        #if os(macOS)
        return .privateCloud(channel: "private")
        #else
        return .appStore(id: "6806799638")
        #endif
    }
    static let configuration: AppConfiguration? = nil
}
