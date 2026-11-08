Pod::Spec.new do |s|
  s.name             = 'signalplus'
  s.version          = '0.6.2'
  s.summary          = 'Makes FlutterAppDelegate the notification center delegate for signalplus.'
  s.description      = 'Makes FlutterAppDelegate the notification center delegate for signalplus.'
  s.homepage         = 'https://github.com/abd-mtk/signalplus'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Abdallah Al-Tamimi' => 'eng.abd.mtk@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'signalplus/Sources/signalplus/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
