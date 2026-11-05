import Foundation

/// Decides which steps go on which PDF page.
public enum PagePacker {
    public static let maxScreenshotsPerPage = 2
    public static let maxRowsPerPage = 4

    /// Packs steps in order into pages. `hasImage[i]` says whether step `i` has a screenshot.
    /// Each page holds at most `maxScreenshots` screenshot steps and `maxRows` steps in total.
    /// Returns the step indices of each page; a step is never split across pages.
    public static func pack(hasImage: [Bool],
                            maxScreenshots: Int = maxScreenshotsPerPage,
                            maxRows: Int = maxRowsPerPage) -> [[Int]] {
        var pages: [[Int]] = []
        var current: [Int] = []
        var shots = 0
        for (i, isShot) in hasImage.enumerated() {
            if !current.isEmpty && (current.count >= maxRows || (isShot && shots >= maxScreenshots)) {
                pages.append(current); current = []; shots = 0
            }
            current.append(i)
            if isShot { shots += 1 }
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }
}
