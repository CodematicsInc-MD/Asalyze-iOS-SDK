import Foundation
#if canImport(AdServices)
import AdServices
#endif

/// Captures Apple's AdServices attribution token, exchanged server-side for the campaign, ad group and
/// keyword. No IDFA, no ATT prompt.
enum AttributionManager {
    /// The AdServices token, plus WHY there isn't one when there isn't.
    ///
    /// Apple's error is captured rather than discarded, and sent with the install. A device that could
    /// not produce a token is otherwise indistinguishable from one that was never asked, so a gap in
    /// attribution can be traced to a cause instead of guessed at.
    static func attributionToken() -> (token: String?, error: String?) {
        #if canImport(AdServices)
        if #available(iOS 14.3, *) {
            do {
                return (try AAAttribution.attributionToken(), nil)
            } catch {
                // Apple's AttributionError is an NSError underneath; domain+code is stable and small,
                // where a localizedDescription is localised and useless to group on.
                let ns = error as NSError
                return (nil, "\(ns.domain):\(ns.code)")
            }
        }
        return (nil, "os_below_14_3")
        #else
        return (nil, "framework_unavailable")
        #endif
    }
}
