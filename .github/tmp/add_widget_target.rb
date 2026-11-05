# 一次性：给 Runner.xcodeproj 加 LyraWidget 小组件扩展（灵动岛 / 锁屏实时活动）。跑完即删。
require 'xcodeproj'

proj = Xcodeproj::Project.open('ios/Runner.xcodeproj')
abort 'LyraWidget already exists' if proj.targets.any? { |t| t.name == 'LyraWidget' }
app = proj.targets.find { |t| t.name == 'Runner' }

ext = proj.new_target(:app_extension, 'LyraWidget', :ios, '16.1', nil, :swift)

wgroup = proj.main_group.new_group('LyraWidget', 'LyraWidget')
sgroup = proj.main_group.new_group('Shared', 'Shared')
bundle = wgroup.new_file('LyraWidgetBundle.swift')
live = wgroup.new_file('LyraLiveActivity.swift')
wgroup.new_file('Info.plist')
attrs = sgroup.new_file('LyraActivityAttributes.swift')
ext.add_file_references([bundle, live, attrs])

rgroup = proj.main_group.children.find { |g| g.display_name == 'Runner' }
island = rgroup.new_file('LiveIsland.swift')
app.add_file_references([island, attrs])

xc = ->(name) { proj.files.find { |f| f.path == "Flutter/#{name}.xcconfig" } }
puts "ext configs: #{ext.build_configurations.map(&:name).inspect}"
proj.build_configurations.map(&:name).each do |n|
  next if ext.build_configurations.any? { |c| c.name == n }
  src = ext.build_configurations.find { |c| c.name == 'Release' }
  c = proj.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  c.name = n
  c.build_settings = src.build_settings.dup
  ext.build_configuration_list.build_configurations << c
end
ext.build_configurations.each do |c|
  c.base_configuration_reference = xc.call(c.name == 'Debug' ? 'Debug' : 'Release') # FLUTTER_BUILD_NAME / NUMBER
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'app.lyra.lyra.LyraWidget'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'LyraWidget/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '16.1'
  s['SWIFT_VERSION'] = '5.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['SKIP_INSTALL'] = 'YES'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
end

# 嵌入扩展：放在 Thin Binary 之前（放在后面 Xcode 15+ 报构建环路）
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
app.build_phases.delete(embed)
thin = app.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
app.build_phases.insert(thin || app.build_phases.length, embed)
app.add_dependency(ext)

# App 最低 iOS 15：ActivityKit 弱链接，iOS 15 上启动不会因为找不到框架崩溃
app.build_configurations.each do |c|
  c.build_settings['OTHER_LDFLAGS'] = ['$(inherited)', '-weak_framework', 'ActivityKit']
end

attrs_ta = proj.root_object.attributes['TargetAttributes'] ||= {}
attrs_ta[ext.uuid] = { 'CreatedOnToolsVersion' => '15.1' }

proj.save
puts app.build_phases.map(&:display_name).inspect
puts ext.build_phases.map(&:display_name).inspect
