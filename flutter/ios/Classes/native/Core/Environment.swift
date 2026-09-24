import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Which data plane an install belongs to. Production reporting shows `.production`; `.sandbox`
/// (TestFlight, Xcode, debug, ad-hoc/enterprise, simulator) is kept out of it.
enum SDKEnvironment: String {
    case production
    case sandbox

    /// True when the build carries an embedded provisioning profile. Development, ad-hoc, enterprise, and
    /// TestFlight builds all embed one; the App Store STRIPS it during processing. So its presence is a
    /// reliable "this is NOT an App Store production build" signal — the piece a receipt/AppTransaction
    /// check alone misses for a Release-configured build installed directly (ad-hoc / Xcode Release).
    private static var isNonAppStoreBuild: Bool {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
    }

    /// Synchronous best-guess (fallback for `resolve()`), now robust to ad-hoc/Release-direct builds.
    static var current: SDKEnvironment {
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        #if DEBUG
        return .sandbox
        #else
        if isNonAppStoreBuild { return .sandbox }                                    // dev / ad-hoc / enterprise / TestFlight
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" { return .sandbox } // TestFlight (belt-and-suspenders)
        return .production                                                           // App Store distribution
        #endif
        #endif
    }

    /// Authoritative environment. Any build with an embedded provisioning profile is NOT from the App
    /// Store → sandbox, regardless of anything else. Only a genuine App Store build reaches AppTransaction,
    /// which confirms production. Async, awaited before the install is registered.
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
        return .production // App Store build with no embedded profile and no sandbox receipt
        #endif
        #endif
    }
}

/// App metadata captured once at install registration: the exact app version (from the bundle — the only
/// place the marketing version exists; Apple never sends it server-side) and the true install date.
struct AppContext {
    let environment: SDKEnvironment
    let version: String?     // CFBundleShortVersionString — marketing version, e.g. "11.2"
    let build: String?       // CFBundleVersion — build number, e.g. "2"
    let installedAt: Date?   // the real App Store download date — AppTransaction, or the legacy receipt
    // iOS version. Not cosmetic: AppTransaction is iOS 16+, so an install with no date is almost
    // certainly an older OS, and without this the diagnosis is inference rather than measurement.
    let osVersion: String?
    // The DEVICE's region. Apple only returns a country for installs it attributed, so for an organic
    // install — the large majority — the backend has no geography at all. This is not the App Store
    // storefront and will disagree for someone travelling or living abroad; it is reported as the
    // device's own setting and the backend keeps it separate from Apple's answer rather than merging.
    let region: String?
    // Base64 PKCS#7, only when installedAt is nil (pre-iOS 16). The backend extracts the date.
    let legacyReceipt: String?
    // Hardware identifier, e.g. "iPhone11,2". Reported RAW — turning it into "iPhone XS" would bake a
    // lookup table into the SDK that goes stale with every Apple release and could only be corrected by
    // shipping a new SDK. The server can name it, and be corrected, at any time.
    let deviceModel: String?
    // AppTransaction's signed JWS (iOS 16+). Carries more than the date — see appContext().
    let appTransactionJws: String?
}

extension SDKEnvironment {
    /// The hardware identifier — "iPhone11,2", "iPad13,1", "arm64" on the simulator.
    ///
    /// `uname` rather than UIDevice: `UIDevice.model` says only "iPhone", and `utsname.machine` is the
    /// specific model. No permission, no required-reason API, nothing user-identifying — the same string
    /// is reported by millions of identical devices.
    ///
    /// Worth having because OS version alone cannot say which hardware an install or a purchase came from.
    static func deviceModel() -> String? {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) { String(cString: $0) }
        }
        return machine.isEmpty ? nil : machine
    }

    /// The device's own region. Read fresh each time rather than captured once at install, because ad
    /// impressions need where the user IS, not where they signed up.
    ///
    /// regionCode is deprecated on iOS 16+ but is the only form available below it, and this SDK still
    /// runs on those devices — the same ones AppTransaction cannot serve.
    static func currentRegion() -> String? {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            return Locale.current.region?.identifier
        }
        return Locale.current.regionCode
    }

    /// Resolve environment + read the exact app version and install date in one pass.
    static func appContext() async -> AppContext {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        var installedAt: Date?
        var legacyReceipt: String?
        var appTransactionJws: String?
        let region = currentRegion()
        #if canImport(StoreKit)
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            // The VerificationResult is kept, not just the unwrapped value: jwsRepresentation lives on
            // the wrapper, and it is the signed original we want to forward.
            if let result = try? await AppTransaction.shared, case .verified(let appTx) = result {
                installedAt = appTx.originalPurchaseDate
                // The signed JWS as Apple issued it. originalPurchaseDate alone answers one question;
                // the record also carries originalAppVersion, appTransactionID, originalPlatform and
                // signedDate — fields we cannot ask for later, because AppTransaction lives on the
                // device. Sent whole so the server can read what it needs without an SDK release each
                // time, and because a field Apple signed is worth more than one the app retyped.
                appTransactionJws = result.jwsRepresentation
            }
        }
        #endif
        // Below iOS 16 there is no AppTransaction, and StoreKit 2 offers no other app-level record —
        // Transaction.all is purchase history, empty for a free app and about a product rather than the
        // app. So those devices reported no install date at all: measured 2026-08-21, 539 of the last 620
        // undated installs were a CURRENT build on an old OS, a flat ~1.8% that never self-healed.
        //
        // The legacy receipt closes it. appStoreReceiptURL is Foundation (iOS 7+), not StoreKit, so
        // reading it is unaffected by using StoreKit 2, and it carries the same originalPurchaseDate.
        // Apple deprecated it but documents this exact exception: use the receipt if your app "needs the
        // receipt to validate the app download because it can't use AppTransaction". Deprecation costs
        // nothing here — this path only runs below iOS 16, and those devices can never reach an OS where
        // it might be removed.
        //
        // The receipt is PKCS#7 and is NOT parsed on device — it is sent as-is and read on the server,
        // which keeps the parser in one place instead of shipped inside every app.
        //
        // The server READS it; it does not verify Apple's signature. That is a deliberate choice made
        // there, with its reasons, and this comment said "verify" until 2026-08-21 — which would have
        // led someone to treat the date as cryptographically trusted when it is not.
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
