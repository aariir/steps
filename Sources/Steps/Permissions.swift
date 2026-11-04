import AppKit
import SwiftUI

/// Tracks the permissions the app really needs, checked by behaviour rather than preflight flags.
@MainActor
final class Permissions: ObservableObject {
    @Published var accessibility = AXIsProcessTrusted()
    @Published var eventTap = false
    /// Set when starting capture failed because Screen Recording access is missing.
    @Published var screenRecordingNeeded = false
    @Published var screenRecording = CGPreflightScreenCaptureAccess()

    private var timer: Timer?

    var ready: Bool { accessibility && eventTap && !screenRecordingNeeded }
    /// Input Monitoring only matters when Accessibility is on but the click listener still can't start.
    var needsInputMonitoring: Bool { accessibility && !eventTap }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        eventTap = accessibility && EventMonitor.canCreateTap()
        screenRecording = CGPreflightScreenCaptureAccess()
        if screenRecordingNeeded && screenRecording { screenRecordingNeeded = false }
    }

    func startPolling() {
        stopPolling()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
        case screenRecording = "Privacy_ScreenCapture"
    }

    func open(_ pane: Pane) {
        switch pane {
        case .inputMonitoring: CGRequestListenEventAccess()
        case .screenRecording: CGRequestScreenCaptureAccess()
        case .accessibility: requestAccessibility()
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Relaunches the app (some grants only take effect in a fresh process).
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; /usr/bin/open -n \"\(Bundle.main.bundleURL.path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}

@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?

    static func show(permissions: Permissions, onStart: @escaping () -> Void) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Set up Steps"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.contentViewController = NSHostingController(rootView: OnboardingView(perms: permissions) {
            window?.close()
            onStart()
        })
        permissions.startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    @ObservedObject var perms: Permissions
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Privacy permissions").font(.title2.bold())
            Text("Steps needs the permission below. Turn it on in System Settings")
                .foregroundStyle(.secondary)

            PermissionRow(
                done: perms.accessibility,
                title: "Accessibility",
                detail: "Lets the app read button and menu names to write captions.",
                button: "Open Accessibility settings") { perms.open(.accessibility) }

            if perms.needsInputMonitoring {
                PermissionRow(
                    done: perms.eventTap,
                    title: "Input Monitoring",
                    detail: "Needed to notice your clicks and key presses. If it stays unchecked after you enable it, use Restart.",
                    button: "Open Input Monitoring settings") { perms.open(.inputMonitoring) }
            }

            if perms.screenRecordingNeeded {
                PermissionRow(
                    done: perms.screenRecording,
                    title: "Screen Recording",
                    detail: "macOS asked for this to capture screenshots. After enabling it, use Restart.",
                    button: "Open Screen Recording settings") { perms.open(.screenRecording) }
            }

            Text("When you pick a window or screen to record, macOS may also ask to share it. That is normal. Choose Allow.")
                .font(.callout).foregroundStyle(.secondary)

            Spacer()

            if perms.ready {
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("All set!").font(.headline)
                    Spacer()
                    Button("Start recording", action: onStart).keyboardShortcut(.defaultAction)
                }
            } else if perms.needsInputMonitoring || perms.screenRecordingNeeded {
                HStack {
                    Text("Changes not picked up?").foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Steps") { Permissions.relaunch() }
                }
            }
        }
        .padding(24)
        .frame(width: 460, height: 420)
    }
}

struct PermissionRow: View {
    let done: Bool
    let title: String
    let detail: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if !done { Button(button, action: action) }
            }
        }
    }
}
