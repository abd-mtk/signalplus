const notificationServiceSwift = r'''
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  private let lock = NSLock()
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var content: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    content = request.content.mutableCopy() as? UNMutableNotificationContent

    guard let url = imageURL(in: request.content.userInfo) else { return finish() }

    URLSession.shared.downloadTask(with: url) { location, response, _ in
      guard let location, (response as? HTTPURLResponse)?.statusCode == 200 else { return self.finish() }
      self.finish(with: self.attachment(from: location, response: response))
    }.resume()
  }

  override func serviceExtensionTimeWillExpire() {
    finish()
  }

  private func finish(with attachment: UNNotificationAttachment? = nil) {
    lock.lock()
    defer { lock.unlock() }
    guard let contentHandler, let content else { return }
    if let attachment { content.attachments = [attachment] }
    self.contentHandler = nil
    contentHandler(content)
  }

  private func imageURL(in userInfo: [AnyHashable: Any]) -> URL? {
    let fcmImage = (userInfo["fcm_options"] as? [String: Any])?["image"] as? String
    guard let value = fcmImage ?? (userInfo["image"] as? String),
          let url = URL(string: value),
          url.scheme == "https" || url.scheme == "http" else { return nil }
    return url
  }

  private func attachment(from location: URL, response: URLResponse?) -> UNNotificationAttachment? {
    let fileExtension = response?.suggestedFilename.map { ($0 as NSString).pathExtension } ?? ""
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(fileExtension.isEmpty ? "jpg" : fileExtension)
    do {
      try FileManager.default.moveItem(at: location, to: file)
      return try UNNotificationAttachment(identifier: "image", url: file)
    } catch {
      return nil
    }
  }
}
''';

const notificationServiceInfoPlist = r'''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>NotificationService</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.usernotifications.service</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).NotificationService</string>
	</dict>
</dict>
</plist>
''';

const notificationServiceXcconfig = '''
#include? "../Flutter/Generated.xcconfig"
''';

const addTargetRubyScript = r'''
require 'xcodeproj'

project_path = ARGV.fetch(0)
ios_dir = File.dirname(project_path)
name = 'NotificationService'
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |target| target.name == 'Runner' } or abort('Runner target not found.')

def add_extension(project, app, name)
  if project.targets.any? { |target| target.name == name }
    puts "#{name}: already set up."
    return
  end

  deployment_target = (app.build_configurations + project.build_configurations)
    .map { |config| config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] }
    .compact
    .first || '15.0'

  extension = project.new_target(:app_extension, name, :ios, deployment_target, nil, :swift)

  group = project.main_group.new_group(name, name)
  source = group.new_reference('NotificationService.swift')
  group.new_reference('Info.plist')
  xcconfig = group.new_reference('NotificationService.xcconfig')
  extension.add_file_references([source])

  app.build_configurations.each do |app_config|
    app_settings = app_config.build_settings
    bundle_id = app_settings['PRODUCT_BUNDLE_IDENTIFIER'] or abort("PRODUCT_BUNDLE_IDENTIFIER is not set for #{app_config.name}.")
    config = extension.build_configurations.find { |candidate| candidate.name == app_config.name } ||
             extension.add_build_configuration(app_config.name, app_config.name == 'Debug' ? :debug : :release)

    config.base_configuration_reference = xcconfig
    settings = config.build_settings
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{bundle_id}.#{name}"
    settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
    settings['INFOPLIST_FILE'] = "#{name}/Info.plist"
    settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
    settings['SWIFT_VERSION'] = '5.0'
    settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    settings['SKIP_INSTALL'] = 'YES'
    settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
    settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
    settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
    %w[DEVELOPMENT_TEAM CODE_SIGN_STYLE CODE_SIGN_IDENTITY].each do |key|
      settings[key] = app_settings[key] if app_settings[key]
    end
  end

  app.add_dependency(extension)
  embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
  embed.add_file_reference(extension.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

  thin_binary = app.build_phases.index { |phase| phase.display_name == 'Thin Binary' }
  app.build_phases.move(embed, thin_binary) if thin_binary
  puts "#{name}: added, for notification images."
end

# Push Notifications: aps-environment in the Runner entitlements. Xcode signs release builds with production.
def add_push(project, app, ios_dir)
  relative = app.build_configurations.map { |config| config.build_settings['CODE_SIGN_ENTITLEMENTS'] }.compact.first ||
             'Runner/Runner.entitlements'
  path = File.join(ios_dir, relative)
  entitlements = File.exist?(path) ? Xcodeproj::Plist.read_from_path(path) : {}
  changed = !File.exist?(path) || !entitlements.key?('aps-environment')
  entitlements['aps-environment'] ||= 'development'
  Xcodeproj::Plist.write_to_path(entitlements, path) if changed

  app.build_configurations.each do |config|
    next if config.build_settings['CODE_SIGN_ENTITLEMENTS']
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = relative
    changed = true
  end
  runner = project.main_group.find_subpath('Runner', false)
  if runner && runner.files.none? { |file| file.path == File.basename(relative) }
    runner.new_reference(File.basename(relative))
    changed = true
  end
  puts(changed ? 'Push Notifications: turned on.' : 'Push Notifications: already on.')
end

# Background Modes → Remote notifications, for the pushes that arrive while the app is closed.
def add_background_mode(app, ios_dir)
  relative = app.build_configurations.map { |config| config.build_settings['INFOPLIST_FILE'] }.compact.first ||
             'Runner/Info.plist'
  path = File.join(ios_dir, relative)
  info = Xcodeproj::Plist.read_from_path(path)
  modes = info['UIBackgroundModes'] || []
  if modes.include?('remote-notification')
    puts 'Background Modes: already on.'
    return
  end
  info['UIBackgroundModes'] = modes + ['remote-notification']
  Xcodeproj::Plist.write_to_path(info, path)
  puts 'Background Modes: turned on remote notifications.'
end

add_extension(project, app, name)
add_push(project, app, ios_dir)
add_background_mode(app, ios_dir)
project.save
''';
