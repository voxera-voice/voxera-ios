Pod::Spec.new do |spec|
  spec.name = "VoxeraSDK"
  spec.version = "1.1.42"
  spec.summary = "Native iOS client for the Voxera realtime voice and video platform."
  spec.description = <<-DESC
    VoxeraSDK connects an iOS application to Voxera using Socket.IO,
    mediasoup, and a single shared WebRTC runtime.
  DESC
  spec.homepage = "https://github.com/voxera-voice/voxera-ios"
  spec.license = { :type => "Commercial", :text => "Copyright Avrioc Technologies. All rights reserved." }
  spec.author = { "Voxera" => "support@voxera.ai" }
  spec.source = {
    :git => "https://github.com/voxera-voice/voxera-ios.git",
    :tag => spec.version.to_s
  }

  spec.platform = :ios, "15.0"
  spec.swift_version = "5.9"
  spec.static_framework = true
  spec.module_name = "VoxeraSDK"

  spec.source_files = [
    "Sources/RocsSDK/**/*.swift",
    "Sources/VoxeraCocoaPods/**/*.swift",
    "mediasoup-client-swift/Sources/Mediasoup/**/*.swift"
  ]
  spec.dependency "WebRTC-lib", "= 149.0.0"
  spec.dependency "Socket.IO-Client-Swift", "= 16.1.0"
  # Socket.IO 16.1.0 allows Starscream 4.0.x, but Starscream 4.0.8 raises
  # its deployment target while the Socket.IO pod target remains on iOS 11.
  # Match the SPM lockfile and keep the pair buildable for CocoaPods.
  spec.dependency "Starscream", "= 4.0.6"

  spec.frameworks = ["AVFoundation", "AudioToolbox", "VideoToolbox"]
  spec.pod_target_xcconfig = {
    "BUILD_LIBRARY_FOR_DISTRIBUTION" => "YES",
    "DEFINES_MODULE" => "YES"
  }
end
