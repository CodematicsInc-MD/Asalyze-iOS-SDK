// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Asalyze",
    platforms: [
        .iOS(.v15), // StoreKit 2 + AdServices (the real target)
        .macOS(.v12) // host build/test support only
    ],
    products: [
        .library(name: "Asalyze", targets: ["Asalyze"])
    ],
    targets: [
        .target(
            name: "Asalyze",
            path: "Sources/Asalyze",
            // Apple requires a privacy manifest from every SDK. Unbundled it protects nobody: the host
            // app is the one that receives ITMS-91053 at upload for an API it did not call.
            resources: [.copy("PrivacyInfo.xcprivacy")]
        )
    ]
)
