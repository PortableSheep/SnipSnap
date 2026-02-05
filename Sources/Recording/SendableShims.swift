// Temporary shims to silence Sendable warnings for AVFoundation types used on background queues.
@preconcurrency import AVFoundation

extension AVAssetWriter: @unchecked @retroactive Sendable {}
extension AVAssetExportSession: @unchecked @retroactive Sendable {}
