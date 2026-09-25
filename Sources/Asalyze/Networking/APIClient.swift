import Foundation

/// Thin HTTP client for the ingest plane. Authenticates with the per-app api key. All calls are
/// best-effort fire-and-forget from the caller's perspective (failures are logged, not thrown).
actor APIClient {
    private let config: Config
    private let session: URLSession

    init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Ingest event variants → POST /v1/event. Ad revenue only: purchases are observed automatically.
    enum Event {
        /// `region` travels with the impression, not the install — eCPM follows where the ad was served.
        case ad(installId: String, value: Double, currency: String, format: AdFormat, region: String?)
    }

    func registerInstall(installId: String, attributionToken: String?, environment: String, isReinstall: Bool = false,
                         appVersion: String? = nil, appBuild: String? = nil, installedAt: Date? = nil,
                         deviceRegion: String? = nil, osVersion: String? = nil, legacyReceipt: String? = nil,
                         appTransactionJws: String? = nil, sdkVersion: String? = nil,
                         tokenError: String? = nil, userId: String? = nil, deviceModel: String? = nil) async {
        var body: [String: Any] = ["installId": installId, "environment": environment]
        if let attributionToken { body["attributionToken"] = attributionToken }
        if isReinstall { body["isReinstall"] = true }
        if let appVersion { body["appVersion"] = appVersion }
        if let appBuild { body["appBuild"] = appBuild }
        if let installedAt { body["installedAt"] = ISO8601DateFormatter().string(from: installedAt) }
        if let deviceRegion { body["deviceRegion"] = deviceRegion }
        if let osVersion { body["osVersion"] = osVersion }
        if let deviceModel { body["deviceModel"] = deviceModel }
        if let legacyReceipt { body["legacyReceipt"] = legacyReceipt }
        if let appTransactionJws { body["appTransactionJws"] = appTransactionJws }
        if let sdkVersion { body["sdkVersion"] = sdkVersion }
        // Only when the app has already set one; this endpoint is fill-only server-side.
        if let userId { body["userId"] = userId }
        // Only when there is no token — a reason beside a working token would read as a failure.
        if attributionToken == nil, let tokenError { body["tokenError"] = tokenError }
        await post("/v1/install", body)
    }

    func recordEvent(_ event: Event) async {
        switch event {
        case let .ad(installId, value, currency, format, region):
            var body: [String: Any] = ["installId": installId, "type": "ad", "value": value,
                                       "currency": currency, "adFormat": format.rawValue]
            if let region { body["region"] = region }
            await post("/v1/event", body)
        }
    }

    func recordCustomEvent(installId: String, name: String, value: Double?) async {
        var body: [String: Any] = ["installId": installId, "name": name]
        if let value { body["value"] = value }
        await post("/v1/custom-event", body)
    }

    /// Returns whether the report landed (2xx), so the caller marks the transaction sent only on
    /// success and a failed POST replays from `Transaction.all` next launch.
    @discardableResult
    func recordSubscription(_ tx: ObservedTransaction, installId: String) async -> Bool {
        var body: [String: Any] = ["installId": installId, "originalTxnId": tx.originalTxnId,
                                    "transactionId": tx.transactionId,
                                    "productId": tx.productId, "type": tx.type.rawValue,
                                    "environment": tx.environment, "purchaseType": tx.purchaseType]
        if let price = tx.priceUsd { body["price"] = price }
        if let currency = tx.currency { body["currency"] = currency }
        if let occurredAt = tx.occurredAt {
            body["occurredAt"] = ISO8601DateFormatter().string(from: occurredAt)
        }
        return await post("/v1/subscription", body)
    }

    /// "The app was opened" → POST /v1/ping, so last-seen means last use rather than last cold launch.
    /// It does not detect uninstalls. `userId` is sent only when the app has set one; an empty string
    /// means signed out, which is why `nil` ("nothing to say") and "" are kept apart.
    func ping(installId: String, userId: String? = nil) async {
        var body: [String: Any] = ["installId": installId]
        if let userId { body["userId"] = userId }
        _ = await post("/v1/ping", body)
    }

    /// Best-effort POST. Returns `true` only on a 2xx response so callers can decide whether to persist
    /// the item for retry. Network errors and non-2xx responses return `false` (and are logged).
    @discardableResult
    private func post(_ path: String, _ body: [String: Any]) async -> Bool {
        guard let url = URL(string: path, relativeTo: config.endpoint) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        // Checked rather than attempted: JSONSerialization raises an ObjC exception on a value it cannot
        // encode, which `try?` cannot catch and which would terminate the host app.
        guard JSONSerialization.isValidJSONObject(body),
              let payload = try? JSONSerialization.data(withJSONObject: body) else {
            NSLog("[Asalyze] POST \(path) skipped: body could not be encoded as JSON")
            return false
        }
        req.httpBody = payload
        do {
            let (_, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) { return true }
            NSLog("[Asalyze] POST \(path) → HTTP \(code)")
            return false
        } catch {
            NSLog("[Asalyze] POST \(path) failed: \(error.localizedDescription)")
            return false
        }
    }
}
