Pod::Spec.new do |s|
  s.name             = 'Asalyze'
  s.version          = '3.2.0'
  s.summary          = 'Apple Search Ads ROAS tracking for iOS — attribution + revenue.'
  s.description      = <<-DESC
    First-party Apple Search Ads attribution for ROAS.
  DESC
  s.homepage         = 'https://asalyze.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Malik Ahsan Ali' => 'malikahsan@codematics.co' }
  s.source           = { :git => 'https://github.com/CodematicsInc-MD/Asalyze-iOS-SDK.git', :tag => "v#{s.version}" }
  s.source_files     = 'Sources/Asalyze/**/*.swift'
  s.resource_bundles = { 'Asalyze' => ['Sources/Asalyze/PrivacyInfo.xcprivacy'] }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
  # Apple system frameworks — weak-linked so the app still runs where AdServices is unavailable.
  s.weak_frameworks  = 'AdServices', 'StoreKit'
  s.frameworks       = 'Security'
end
