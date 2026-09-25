// C bridge from Unity (C#) to the SDK's Objective-C surface, called via [DllImport("__Internal")].
// Requires the pod integrated as a framework — see the package README.

#import <Foundation/Foundation.h>
#import <Asalyze/Asalyze-Swift.h>

static NSString *AZStr(const char *s) { return s != NULL ? [NSString stringWithUTF8String:s] : nil; }

/// Same, but an EMPTY string means absent. C# marshals a null string as an empty buffer, so without
/// this an omitted productId or currency would arrive as "" — a value the backend would store as a
/// real, blank product rather than treating it as missing.
static NSString *AZStrOrNil(const char *s)
{
    NSString *v = AZStr(s);
    return (v.length > 0) ? v : nil;
}

extern "C" {

void AsalyzeConfigure(const char *apiKey, const char *appId, const char *endpoint)
{
    [AsalyzeBridge configureWithApiKey:AZStr(apiKey) appId:AZStr(appId) endpoint:AZStr(endpoint)];
}

// Fills `buffer` (caller-owned, size bytes) with the install id UTF-8 + NUL. Empty string if unavailable.
void AsalyzeInstallId(char *buffer, int size)
{
    if (buffer == NULL || size <= 0) return;
    NSString *iid = [AsalyzeBridge installId];
    const char *utf8 = (iid != nil) ? [iid UTF8String] : "";
    strncpy(buffer, utf8, (size_t)(size - 1));
    buffer[size - 1] = '\0';
}

void AsalyzeSetUserId(const char *userId)
{
    [AsalyzeBridge setUserId:AZStr(userId)];
}

void AsalyzeTrackAdRevenue(double valueUsd, const char *format, const char *currency)
{
    [AsalyzeBridge trackAdRevenueWithValueUsd:valueUsd format:AZStr(format) currency:AZStr(currency)];
}

void AsalyzeTrackEvent(const char *name, double valueUsd, bool hasValue)
{
    [AsalyzeBridge trackEvent:AZStr(name) valueUsd:(hasValue ? @(valueUsd) : nil)];
}


} // extern "C"
