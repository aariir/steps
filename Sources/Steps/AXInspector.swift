import ApplicationServices
import AppKit
import StepsCore

enum AXInspector {
    struct Hit {
        var info: ElementInfo
        var pid: pid_t
    }

    static func element(at point: CGPoint) -> Hit? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success,
              let el = found else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "the app"
        let role = string(el, kAXRoleAttribute) ?? ""

        var title = nonEmpty(string(el, kAXTitleAttribute))
        var label = nonEmpty(string(el, kAXDescriptionAttribute))
        if title == nil, let ui = attr(el, kAXTitleUIElementAttribute) {
            title = nonEmpty(string(ui as! AXUIElement, kAXValueAttribute))
        }
        if title == nil && label == nil { label = nonEmpty(string(el, kAXHelpAttribute)) }
        if title == nil && label == nil && role == "AXStaticText" { title = nonEmpty(string(el, kAXValueAttribute)) }

        // Clicking an icon/image/group inside a titled button: use the nearest titled ancestor.
        var effectiveRole = role
        if title == nil && label == nil {
            var cur = el
            for _ in 0..<3 {
                guard let parent = attr(cur, kAXParentAttribute) else { break }
                cur = parent as! AXUIElement
                let t = nonEmpty(string(cur, kAXTitleAttribute)) ?? nonEmpty(string(cur, kAXDescriptionAttribute))
                if let t {
                    title = t
                    effectiveRole = string(cur, kAXRoleAttribute) ?? role
                    break
                }
            }
        }

        var menuPath: [String] = []
        if role == "AXMenuItem", let name = title ?? label {
            var cur = el
            while let parent = attr(cur, kAXParentAttribute) {
                cur = parent as! AXUIElement
                if string(cur, kAXRoleAttribute) == "AXMenuBarItem", let t = nonEmpty(string(cur, kAXTitleAttribute)) {
                    menuPath = [t, name]
                    break
                }
            }
        }

        let window = attr(el, kAXWindowAttribute).flatMap { string($0 as! AXUIElement, kAXTitleAttribute) }
        let info = ElementInfo(role: effectiveRole, title: title, label: label, appName: appName,
                               windowTitle: window, menuPath: menuPath)
        return Hit(info: info, pid: pid)
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String? {
        attr(el, name) as? String
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
