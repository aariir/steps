import Foundation

public enum ClickKind: String, Codable {
    case left, double, right
}

/// What the Accessibility API told us about the element under the cursor.
public struct ElementInfo: Codable, Equatable {
    public var role: String
    public var title: String?
    public var label: String?
    public var value: String?
    public var appName: String
    public var windowTitle: String?
    /// For menu items: titles of the menu path, e.g. ["File", "Save"].
    public var menuPath: [String]

    public init(role: String, title: String? = nil, label: String? = nil, value: String? = nil,
                appName: String, windowTitle: String? = nil, menuPath: [String] = []) {
        self.role = role; self.title = title; self.label = label; self.value = value
        self.appName = appName; self.windowTitle = windowTitle; self.menuPath = menuPath
    }

    /// Best human-readable name of the element.
    public var name: String? {
        [title, label].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// Raw input recorded by the event tap, before captioning.
public enum RawEvent: Equatable {
    case click(kind: ClickKind, element: ElementInfo)
    case typed(String)
    case shortcut(String)      // e.g. "⌘S"
    case key(String)           // e.g. "Return", "Tab", "Escape"
    case scroll(down: Bool)
}

public struct Step: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var caption: String
    public var imageFile: String?       // file name inside session folder
    public var clickX: Double?          // normalized 0...1 within image (top-left origin)
    public var clickY: Double?
    public var appName: String
    /// Rule-based caption kept when the caption was AI-polished, so it can be reverted.
    public var originalCaption: String?

    public init(caption: String, imageFile: String? = nil, clickX: Double? = nil,
                clickY: Double? = nil, appName: String) {
        self.caption = caption; self.imageFile = imageFile
        self.clickX = clickX; self.clickY = clickY; self.appName = appName
    }
}
