import Foundation

// Product allowlist and release channel; shared lifecycle code owns transfer/checking.
@MainActor
enum MobileProductLifecycle {
    static var channel: MobileUpdateChannel {
        #if os(macOS)
        #if APP_LIFECYCLE_KVS
        return .sandboxCloud(channel: "private")
        #else
        return .privateCloud(channel: "private")
        #endif
        #else
        return .appStore(id: "6806799638")
        #endif
    }
    static let configuration: AppConfiguration? = TreasuryPreferences.shared.configuration
}
