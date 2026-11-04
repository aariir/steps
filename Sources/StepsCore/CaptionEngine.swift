import Foundation

/// Pure, rule-based caption generator. Keep free of AppKit so it is unit-testable.
public enum CaptionEngine {
    public static func caption(for event: RawEvent) -> String {
        switch event {
        case .click(let kind, let el): return clickCaption(kind, el)
        case .typed(let text): return "Type “\(text)”"
        case .shortcut(let s): return "Press \(s)"
        case .key(let k): return "Press \(k)"
        case .scroll(let down): return down ? "Scroll down" : "Scroll up"
        }
    }

    static func verb(_ kind: ClickKind) -> String {
        switch kind {
        case .left: return "Click"
        case .double: return "Double-click"
        case .right: return "Right-click"
        }
    }

    static func clickCaption(_ kind: ClickKind, _ el: ElementInfo) -> String {
        let v = verb(kind)
        let name = el.name
        func q(_ s: String) -> String { "“\(s)”" }

        if el.role == "AXSecureTextField" { return "\(v) the password field" }

        switch el.role {
        case "AXMenuItem", "AXMenuBarItem":
            if el.menuPath.count > 1 { return "Choose " + el.menuPath.map(q).joined(separator: " ▸ ") }
            if let name { return el.role == "AXMenuBarItem" ? "Open the \(q(name)) menu" : "Choose \(q(name))" }
        case "AXButton", "AXMenuButton":
            if let name { return "\(v) the \(q(name)) button" }
        case "AXCheckBox":
            if let name { return "Toggle the \(q(name)) checkbox" }
        case "AXRadioButton":
            if let name { return "Select \(q(name))" }
        case "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox":
            if let name { return "\(v) the \(q(name)) field" }
            return "\(v) the text field"
        case "AXLink":
            if let name { return "\(v) the \(q(name)) link" }
        case "AXTab":
            if let name { return "Open the \(q(name)) tab" }
        case "AXPopUpButton":
            if let name { return "Open the \(q(name)) drop-down" }
        case "AXSlider":
            if let name { return "Adjust the \(q(name)) slider" }
        default: break
        }
        if let name { return "\(v) \(q(name))" }
        return "\(v) the highlighted area in \(el.appName)"
    }

    /// Convenience for tests/batch use.
    public static func steps(from events: [RawEvent]) -> [(caption: String, appName: String, isClick: Bool)] {
        var b = StepBuilder()
        var out: [(caption: String, appName: String, isClick: Bool)] = []
        for e in events {
            switch b.handle(e) {
            case .newStep(let c, let app, let click): out.append((c, app, click))
            case .appendToLast(let suffix): out[out.count - 1].caption += suffix
            case .ignore: break
            }
        }
        return out
    }
}

public enum StepAction: Equatable {
    case newStep(caption: String, appName: String, isClick: Bool)
    case appendToLast(String)
    case ignore
}

/// Stateful: merges typing into the preceding field click, drops duplicate
/// clicks, and never records text typed into secure fields.
public struct StepBuilder {
    var lastClick: ElementInfo?
    var lastCaption: String?
    var lastWasClick = false
    var lastApp: String?

    public init() {}

    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]

    public mutating func handle(_ e: RawEvent) -> StepAction {
        switch e {
        case .click(_, let el):
            let cap = CaptionEngine.caption(for: e)
            if lastWasClick, lastCaption == cap { return .ignore }
            lastClick = el; lastCaption = cap; lastWasClick = true
            lastApp = el.appName
            return .newStep(caption: cap, appName: el.appName, isClick: true)
        case .typed(let text):
            let wasClick = lastWasClick
            lastWasClick = false
            if let el = lastClick, wasClick {
                if el.role == "AXSecureTextField" { return .appendToLast(" and enter the password") }
                if Self.textRoles.contains(el.role) { return .appendToLast(" and type “\(text)”") }
            }
            return .newStep(caption: CaptionEngine.caption(for: e), appName: lastApp ?? "", isClick: false)
        default:
            lastWasClick = false
            return .newStep(caption: CaptionEngine.caption(for: e), appName: lastApp ?? "", isClick: false)
        }
    }
}
