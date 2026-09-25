import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Which data plane an install belongs to. Production reporting shows `.production`; `.sandbox`
/// (TestFlight, Xcode, debug, ad-hoc/enterprise, simulator) is kept out of it.
enum SDKEnvironment: String {
    case production
    case sandbox

    /// True when the build carries an embedded provisioning profile. Development, ad-hoc, enterprise and
    /// TestFlight builds all embed one and the App Store strips it, so its presence means "not an App
    /// Store build".
    private static var isNonAppStoreBuild: Bool {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
    }

    /// Synchronous best guess, used as the fallback for `resolve()`.
    static var current: SDKEnvironment {
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        #if DEBUG
        return .sandbox
        #else
        if isNonAppStoreBuild { return .sandbox }                                    // dev / ad-hoc / enterprise / TestFlight
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" { return .sandbox } // TestFlight
        return .production                                                           // App Store distribution
        #endif
        #endif
    }

    /// Authoritative environment, awaited before the install is registered: only a genuine App Store
    /// build reaches AppTransaction, which confirms production.
    static func resolve() async -> SDKEnvironment {
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        #if DEBUG
        return .sandbox
        #else
        if isNonAppStoreBuild { return .sandbox }
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" { return .sandbox }
        #if canImport(StoreKit)
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            if case .verified(let appTx)? = try? await AppTransaction.shared {
                return appTx.environment == .production ? .production : .sandbox
            }
        }
        #endif
        return .production
        #endif
        #endif
    }
}

/// App metadata captured once at install registration.
struct AppContext {
    let environment: SDKEnvironment
    let version: String?     // CFBundleShortVersionString — marketing version, e.g. "11.2"
    let build: String?       // CFBundleVersion — build number, e.g. "2"
    let installedAt: Date?   // App Store download date, from AppTransaction or the legacy receipt
    let osVersion: String?
    /// The DEVICE's region setting, not the App Store storefront; kept separate from Apple's own answer.
    let region: String?
    /// Base64 PKCS#7, only below iOS 16 where there is no AppTransaction. Read on the server.
    let legacyReceipt: String?
    /// Hardware identifier, e.g. "iPhone11,2", reported raw so the server can name it.
    let deviceModel: String?
    /// AppTransaction's signed JWS (iOS 16+), forwarded as Apple issued it.
    let appTransactionJws: String?
}

extension SDKEnvironment {
    /// The hardware identifier — "iPhone11,2", "iPad13,1", "arm64" on the simulator. No permission and
    /// no required-reason API; millions of identical devices report the same string.
    static func deviceModel() -> String? {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) { String(cString: $0) }
        }
        return machine.isEmpty ? nil : machine
    }

    /// The device's own region, read fresh each time: ad impressions need where the user is, not where
    /// they signed up.
    static func currentRegion() -> String? {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            return Locale.current.region?.identifier
        }
        return Locale.current.regionCode
    }

    /// Resolve the environment and read the app version and install date in one pass.
    static func appContext() async -> AppContext {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        var installedAt: Date?
        var legacyReceipt: String?
        var appTransactionJws: String?
        let region = currentRegion()
        #if canImport(StoreKit)
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            // The VerificationResult is kept, not just the value: `jwsRepresentation` lives on the wrapper.
            if let result = try? await AppTransaction.shared, case .verified(let appTx) = result {
                installedAt = appTx.originalPurchaseDate
                appTransactionJws = result.jwsRepresentation
            }
        }
        #endif
        // Below iOS 16 there is no AppTransaction, so the install date comes from the legacy receipt.
        // It is sent as-is and read on the server rather than parsed on device.
        if installedAt == nil, let url = Bundle.main.appStoreReceiptURL,
           let receipt = try? Data(contentsOf: url), !receipt.isEmpty {
            legacyReceipt = receipt.base64EncodedString()
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        return AppContext(environment: await resolve(), version: version, build: build, installedAt: installedAt,
                          osVersion: os, region: region, legacyReceipt: legacyReceipt,
                          deviceModel: deviceModel(), appTransactionJws: appTransactionJws)
    }
}
