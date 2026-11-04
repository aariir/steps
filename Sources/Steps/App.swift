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
    @FocusState private var focused: UUID?

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
                Text("No steps yet.").foregroundStyle(.secondary)
                AddStepButton { focused = rec.insertTextStep(at: 0) }
                Spacer()
            } else {
                List {
                    ForEach(Array($rec.steps.enumerated()), id: \.element.id) { index, $step in
                        AddStepButton { focused = rec.insertTextStep(at: index) }
                        StepRow(step: $step, number: StepList.number(at: index), dir: rec.sessionDir,
                                focused: $focused,
                                onRemoveImage: { rec.removeScreenshot(of: step.id) }) {
                            rec.steps.removeAll { $0.id == step.id }
                        }
                    }
                    AddStepButton { focused = rec.insertTextStep(at: rec.steps.count) }
                }
            }
            if let m = rec.message { Text(m).foregroundStyle(.red) }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 480)
    }
}

struct AddStepButton: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: action) { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .help("Add a text step here")
            Spacer()
        }
    }
}

struct StepRow: View {
    @Binding var step: Step
    let number: Int
    let dir: URL
    var focused: FocusState<UUID?>.Binding
    let onRemoveImage: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number).").font(.headline).frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                TextField(step.hasImage ? "Caption" : "Type the text for this step",
                          text: $step.caption, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused(focused, equals: step.id)
                if let f = step.imageFile, let img = NSImage(contentsOf: dir.appendingPathComponent(f)) {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 160)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.quaternary))
                    Button("Delete screenshot", action: onRemoveImage).buttonStyle(.link)
                }
            }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Delete this step")
        }
        .padding(.vertical, 4)
    }
}
