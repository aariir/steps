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

var list = [Step(caption: "A", appName: "X"), Step(caption: "B", appName: "X")]
let newID = StepList.insertTextStep(into: &list, at: 1)
check("insert middle", list.map(\.caption), ["A", "", "B"])
check("insert id", list[1].id == newID && !list[1].hasImage, true)
StepList.insertTextStep(into: &list, at: 0)
StepList.insertTextStep(into: &list, at: 99)
check("insert ends", [list.first?.caption, list.last?.caption].count == 2 && list.count == 5, true)
list.removeAll { $0.id == newID }
check("renumber after delete", list.indices.map { StepList.number(at: $0) }, [1, 2, 3, 4])
var shot = Step(caption: "A", imageFile: "a.png", clickX: 0.1, clickY: 0.2, appName: "X")
shot.removeImage()
check("remove image", shot.imageFile == nil && shot.clickX == nil && shot.clickY == nil && shot.caption == "A", true)
check("text step not polished", Step.textOnly(caption: "Wait").canPolish, false)
check("recorded step polished", Step(caption: "Click", appName: "X").canPolish, true)
check("guard empty original", CaptionGuard.accept(original: "", polished: "") == nil, true)

check("pack empty", PagePacker.pack(hasImage: []), [])
check("pack text only", PagePacker.pack(hasImage: Array(repeating: false, count: 9)), [[0, 1, 2, 3], [4, 5, 6, 7], [8]])
check("pack many shots", PagePacker.pack(hasImage: Array(repeating: true, count: 5)), [[0, 1], [2, 3], [4]])
check("pack mixed", PagePacker.pack(hasImage: [true, false, true, false, false, true]), [[0, 1, 2, 3], [4, 5]])
check("pack shot limit with text", PagePacker.pack(hasImage: [true, true, true, false]), [[0, 1], [2, 3]])
check("pack text fills then shot", PagePacker.pack(hasImage: [false, false, false, false, true]), [[0, 1, 2, 3], [4]])

exit(failures == 0 ? 0 : 1)
