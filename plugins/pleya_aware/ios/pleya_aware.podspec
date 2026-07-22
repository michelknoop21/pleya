Pod::Spec.new do |s|
  s.name             = 'pleya_aware'
  s.version          = '0.1.0'
  s.summary          = 'Wi-Fi Aware transport for Pleya Share.'
  s.description      = 'In-repo plugin exposing the iOS 26 WiFiAware framework as a byte-stream transport.'
  s.homepage         = 'https://pleya.app'
  s.license          = { :type => 'GPL-3.0' }
  s.author           = { 'Michel Knoop' => 'info@michelknoop.nl' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
