import CoreGraphics
import Foundation
import StepsCore

// Lightweight self-checks that run with Command Line Tools only (no XCTest needed): `swift run CoreChecks`.
var failures = 0
func check<T: Equatable>(_ name: String, _ got: T, _ want: T) {
    if got == want { print("ok   \(name)") } else { failures += 1; print("FAIL \(name)\n  got:  \(got)\n  want: \(want)") }
}

func el(_ role: String, _ title: String? = nil, menu: [String] = []) -> ElementInfo {
    ElementInfo(role: role, title: title, appName: "Safari", menuPath: menu)
}

check("button", CaptionEngine.caption(for: .click(kind: .left, element: el("AXButton", "Save"))), "Click the “Save” button")
check("menu path", CaptionEngine.caption(for: .click(kind: .left, element: el("AXMenuItem", "Save", menu: ["File", "Save"]))), "Choose “File” ▸ “Save”")
check("typing merges", CaptionEngine.steps(from: [.click(kind: .left, element: el("AXSearchField", "Search")), .typed("hello")]).map(\.caption),
      ["Click the “Search” field and type “hello”"])
check("password hidden", CaptionEngine.steps(from: [.click(kind: .left, element: el("AXSecureTextField")), .typed("secret")]).map(\.caption),
      ["Click the password field and enter the password"])
check("dupes dropped", CaptionEngine.steps(from: [.click(kind: .left, element: el("AXButton", "Go")), .click(kind: .left, element: el("AXButton", "Go")), .shortcut("⌘S")]).map(\.caption),
      ["Click the “Go” button", "Press ⌘S"])
let p = CGPoint(x: 300, y: 200)
check("normalize", Geometry.normalize(p, in: CGRect(x: 100, y: 100, width: 400, height: 200)), CGPoint(x: 0.5, y: 0.5))
check("normalize moved window", Geometry.normalize(p, in: CGRect(x: 150, y: 100, width: 400, height: 200)), CGPoint(x: 0.375, y: 0.5))
check("outside nil", Geometry.normalize(CGPoint(x: 10, y: 10), in: CGRect(x: 100, y: 100, width: 400, height: 200)) == nil, true)

let orig = "Click the “Save” button"
check("guard accepts", CaptionGuard.accept(original: orig, polished: "3. Select the “Save” button to continue.\nExtra"), "Select the “Save” button to continue.")
check("guard rejects lost name", CaptionGuard.accept(original: orig, polished: "Click the save button") == nil, true)
check("guard rejects empty", CaptionGuard.accept(original: orig, polished: "  ") == nil, true)

exit(failures == 0 ? 0 : 1)
