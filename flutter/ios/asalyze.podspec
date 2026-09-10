Pod::Spec.new do |s|
  s.name             = 'asalyze'
  s.version          = '3.1.5'
  s.summary          = 'Apple Search Ads ROAS tracking for iOS Flutter apps.'
  s.description      = 'Self-contained Flutter plugin: AdServices attribution + StoreKit 2 revenue + ad revenue. The native Asalyze SDK sources are vendored under Classes/native and compiled into this pod — no external dependency.'
  s.homepage         = 'https://asalyze.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Malik Ahsan Ali' => 'malikahsan@codematics.co' }
  s.source           = { :path => '.' }
  # Includes the plugin bridge (Classes/*.swift) AND the vendored native SDK (Classes/native/**).
  s.source_files     = 'Classes/**/*.swift'
  s.resource_bundles = { 'asalyze' => ['Classes/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  # AdServices (attribution) + StoreKit (revenue) are Apple system frameworks — weak-linked so the app
  # still runs on OS versions/simulators where AdServices is unavailable.
  s.weak_frameworks  = 'AdServices', 'StoreKit'
  s.frameworks       = 'Security'
  s.platform = :ios, '15.0'
  s.swift_version = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'SWIFT_VERSION' => '5.9' }
end
