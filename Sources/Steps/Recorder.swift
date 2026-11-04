import AppKit
import ScreenCaptureKit
import StepsCore
import SwiftUI

@MainActor
final class Recorder: NSObject, ObservableObject, SCContentSharingPickerObserver {
    static let shared = Recorder()

    enum State { case idle, picking, recording, reviewing }

    @Published var state = State.idle
    @Published var steps: [Step] = []
    @Published var title = "How-to guide"
    @Published var message: String?
    @Published var polishing = false

    func polishCaptions() {
        if let why = CaptionPolisher.availabilityMessage { message = why; return }
        guard !polishing else { return }
        polishing = true
        message = nil
        Task {
            var failed = 0
            for id in steps.map(\.id) {
                guard let i = steps.firstIndex(where: { $0.id == id }) else { continue }
                let step = steps[i]
                if step.originalCaption != nil || !step.canPolish { continue }
                if let better = await CaptionPolisher.polish(step.caption, appName: step.appName),
                   let j = steps.firstIndex(where: { $0.id == id }) {
                    steps[j].originalCaption = steps[j].caption
                    steps[j].caption = better
                } else {
                    failed += 1
                }
            }
            polishing = false
            if failed > 0 { message = "\(failed) caption(s) kept as-is (model answer unusable)." }
        }
    }

    func insertTextStep(at index: Int) -> UUID {
        StepList.insertTextStep(into: &steps, at: index)
    }

    func removeScreenshot(of id: UUID) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        if let f = steps[i].imageFile { try? FileManager.default.removeItem(at: sessionDir.appendingPathComponent(f)) }
        steps[i].removeImage()
    }

    func revertPolish() {
        for i in steps.indices {
            if let o = steps[i].originalCaption { steps[i].caption = o; steps[i].originalCaption = nil }
        }
    }
    private let capture = CaptureEngine()
    private let monitor = EventMonitor()
    private var builder = StepBuilder()
    private(set) var sessionDir = FileManager.default.temporaryDirectory
    private var reviewWindow: NSWindow?

    // MARK: Permissions

    let permissions = Permissions()

    func checkOnLaunch() {
        permissions.refresh()
        if !permissions.ready { showOnboarding() }
    }

    func showOnboarding() {
        OnboardingWindow.show(permissions: permissions) { [weak self] in self?.startNew() }
    }

    // MARK: Flow

    func startNew() {
        permissions.refresh()
        guard permissions.ready else { showOnboarding(); return }
        message = nil
        let picker = SCContentSharingPicker.shared
        var cfg = SCContentSharingPickerConfiguration()
        cfg.allowedPickerModes = [.singleWindow, .singleDisplay]
        picker.defaultConfiguration = cfg
        picker.add(self)
        picker.isActive = true
        state = .picking
        picker.present()
    }

    func toggle() {
        if state == .recording { stop() } else if state == .idle { startNew() }
    }

    private func begin(filter: SCContentFilter) async {
        SCContentSharingPicker.shared.isActive = false
        SCContentSharingPicker.shared.remove(self)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        sessionDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Steps/\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        steps = []
        builder = StepBuilder()
        capture.onStop = { [weak self] in
            Task { @MainActor in
                if self?.state == .recording { self?.stop() }
            }
        }
        do {
            try await capture.start(filter: filter)
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                permissions.screenRecordingNeeded = true
                showOnboarding()
            } else {
                message = "Could not start capture: \(error.localizedDescription)"
            }
            state = .idle
            return
        }
        monitor.onEvent = { [weak self] e in self?.handle(e) }
        monitor.onToggleHotkey = { [weak self] in self?.toggle() }
        guard monitor.start() else {
            permissions.refresh()
            showOnboarding()
            await capture.stop()
            state = .idle
            return
        }
        state = .recording
    }

    func stop() {
        monitor.stop()
        Task {
            await capture.stop()
            state = .reviewing
            showReview()
        }
    }

    // MARK: Event handling

    private func handle(_ e: MonitorEvent) {
        guard state == .recording else { return }
        switch e {
        case .click(let kind, let point, let time):
            var info = ElementInfo(role: "", appName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "the app")
            if let hit = AXInspector.element(at: point) {
                if hit.pid == getpid() { return }
                info = hit.info
            }
            apply(builder.handle(.click(kind: kind, element: info)), point: point, time: time)
        case .typed(let t): apply(builder.handle(.typed(t)))
        case .shortcut(let s): apply(builder.handle(.shortcut(s)))
        case .key(let k): apply(builder.handle(.key(k)))
        case .scroll(let down): apply(builder.handle(.scroll(down: down)))
        }
    }

    private func apply(_ action: StepAction, point: CGPoint? = nil, time: TimeInterval = 0) {
        switch action {
        case .ignore: break
        case .appendToLast(let suffix):
            if !steps.isEmpty { steps[steps.count - 1].caption += suffix }
        case .newStep(let caption, let app, let isClick):
            var step = Step(caption: caption, appName: app)
            if isClick, let point, let captured = capture.frame(before: time) {
                let n = Geometry.normalize(point, in: captured.bounds)
                let file = String(format: "step-%03d.png", steps.count + 1)
                Annotator.savePNG(Annotator.ring(on: captured.image, at: n), to: sessionDir.appendingPathComponent(file))
                step.imageFile = file
                step.clickX = n.map { Double($0.x) }
                step.clickY = n.map { Double($0.y) }
            }
            steps.append(step)
        }
    }

    // MARK: Picker observer

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            picker.isActive = false
            picker.remove(self)
            state = .idle
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await begin(filter: filter) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in
            message = error.localizedDescription
            state = .idle
        }
    }

    // MARK: Review / export

    private func showReview() {
        if reviewWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "Review guide"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: ReviewView().environmentObject(self))
            w.center()
            reviewWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        reviewWindow?.makeKeyAndOrderFront(nil)
    }

    func finishReview() {
        reviewWindow?.close()
        state = .idle
    }

    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = title + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PDFExporter.export(title: title, steps: steps, sessionDir: sessionDir, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            message = "PDF export failed."
        }
    }
}
