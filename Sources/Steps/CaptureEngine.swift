import AppKit
import CoreImage
import QuartzCore
import ScreenCaptureKit

/// Keeps the last few frames so a click can be paired with the screen as it looked just BEFORE the click.
/// Each frame stores the on-screen bounds of the captured content at that moment, so clicks stay
/// correctly mapped even if the recorded window is moved or resized.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    struct Captured {
        var image: CGImage
        var bounds: CGRect   // global, top-left origin, points
    }

    var onStop: (() -> Void)?

    private var stream: SCStream?
    private var config: SCStreamConfiguration?
    private var frames: [(t: TimeInterval, buffer: CVPixelBuffer, bounds: CGRect?)] = []
    private let lock = NSLock()
    private let ci = CIContext()
    private var staticRect = CGRect.zero
    private var windowID: CGWindowID?
    private var scale: CGFloat = 2
    private var configuredSize = CGSize.zero
    private var lastSeenSize = CGSize.zero

    func start(filter: SCContentFilter) async throws {
        scale = CGFloat(filter.pointPixelScale)
        staticRect = filter.contentRect
        if filter.includedWindows.count == 1 { windowID = filter.includedWindows.first?.windowID } else { windowID = nil }
        configuredSize = staticRect.size
        lastSeenSize = configuredSize

        let cfg = SCStreamConfiguration()
        cfg.width = max(1, Int(configuredSize.width * scale))
        cfg.height = max(1, Int(configuredSize.height * scale))
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = true
        cfg.queueDepth = 6
        config = cfg

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "steps.frames"))
        try await s.startCapture()
        stream = s
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        clearFrames()
    }

    private func clearFrames() {
        lock.lock(); frames.removeAll(); lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let pixels = CMSampleBufferGetImageBuffer(sb) else { return }

        var bounds: CGRect? = staticRect
        if let windowID {
            bounds = Self.windowBounds(windowID)
            if let b = bounds { resizeIfStable(to: b.size) }
        }
        lock.lock()
        frames.append((CACurrentMediaTime(), pixels, bounds))
        if frames.count > 4 { frames.removeFirst() }
        lock.unlock()
    }

    /// Latest frame at least ~80 ms older than `time` (falls back to the oldest kept frame).
    func frame(before time: TimeInterval) -> Captured? {
        lock.lock()
        let pick = frames.last(where: { $0.t <= time - 0.08 }) ?? frames.first
        lock.unlock()
        guard let pick, let bounds = pick.bounds else { return nil }
        let image = CIImage(cvPixelBuffer: pick.buffer)
        guard let cg = ci.createCGImage(image, from: image.extent) else { return nil }
        return Captured(image: cg, bounds: bounds)
    }

    // The window was resized: once the size is stable for two frames, resize the stream output.
    private func resizeIfStable(to size: CGSize) {
        defer { lastSeenSize = size }
        guard size == lastSeenSize, size != configuredSize, size.width > 1, size.height > 1,
              let stream, let config else { return }
        configuredSize = size
        config.width = Int(size.width * scale)
        config.height = Int(size.height * scale)
        Task { try? await stream.updateConfiguration(config) }
    }

    private static func windowBounds(_ id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let dict = list.first?[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dict as CFDictionary),
              rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }
}
