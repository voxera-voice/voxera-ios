/// Preferred Voxera names when the SDK is integrated through CocoaPods.
///
/// CocoaPods compiles the legacy implementation and these aliases into the
/// single `VoxeraSDK` module. Swift Package Manager keeps the implementation
/// and compatibility facade as separate targets.
public typealias VoxeraClient = RocsClient
public typealias VoxeraClientDelegate = RocsClientDelegate
public typealias VoxeraConfig = RocsConfig
public typealias VoxeraConfigUpdate = RocsConfigUpdate
public typealias VoxeraViewModel = RocsViewModel
public typealias VoxeraError = RocsError
public typealias VoxeraErrorCode = RocsErrorCode
