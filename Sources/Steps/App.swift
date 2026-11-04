import AppKit
import StepsCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in Recorder.shared.checkOnLaunch() }
    }
}

@main
struct StepsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var recorder = Recorder.shared

    var body: some Scene {
        MenuBarExtra("Steps", systemImage: recorder.state == .recording ? "record.circle.fill" : "record.circle") {
            MenuView(perms: recorder.permissions).environmentObject(recorder)
        }
    }
}

struct MenuView: View {
    @EnvironmentObject var rec: Recorder
    @ObservedObject var perms: Permissions

    var body: some View {
        switch rec.state {
        case .idle, .picking:
            Button("New guide… (⌥⌘R)") { rec.startNew() }
        case .recording:
            Text("Recording – \(rec.steps.count) steps")
            Button("Stop & review (⌥⌘R)") { rec.stop() }
        case .reviewing:
            Text("Reviewing guide…")
        }
        if let m = rec.message { Text(m) }
        if !perms.ready {
            Divider()
            Button("Finish setup…") { rec.showOnboarding() }
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

struct ReviewView: View {
    @EnvironmentObject var rec: Recorder

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Guide title", text: $rec.title).textFieldStyle(.roundedBorder).font(.title3)
                Button(rec.polishing ? "Polishing…" : "Polish with AI") { rec.polishCaptions() }
                    .disabled(rec.polishing || rec.steps.isEmpty)
                if rec.steps.contains(where: { $0.originalCaption != nil }) {
                    Button("Revert") { rec.revertPolish() }.disabled(rec.polishing)
                }
                Button("Export PDF…") { rec.exportPDF() }.keyboardShortcut("e")
                Button("Done") { rec.finishReview() }
            }
            if rec.steps.isEmpty {
                Text("No steps were recorded.").foregroundStyle(.secondary).frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach($rec.steps) { $step in
                        StepRow(step: $step,
                                number: (rec.steps.firstIndex { $0.id == step.id } ?? 0) + 1,
                                dir: rec.sessionDir) {
                            rec.steps.removeAll { $0.id == step.id }
                        }
                    }
                    .onMove { rec.steps.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            if let m = rec.message { Text(m).foregroundStyle(.red) }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 480)
    }
}

struct StepRow: View {
    @Binding var step: Step
    let number: Int
    let dir: URL
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number).").font(.headline).frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                TextField("Caption", text: $step.caption, axis: .vertical).textFieldStyle(.roundedBorder)
                if let f = step.imageFile, let img = NSImage(contentsOf: dir.appendingPathComponent(f)) {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 160)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.quaternary))
                }
            }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
