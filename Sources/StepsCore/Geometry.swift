import CoreGraphics
import Foundation

public enum Geometry {
    /// Maps a global point into 0...1 coordinates (top-left origin) of `bounds`; nil if outside.
    public static func normalize(_ p: CGPoint, in bounds: CGRect) -> CGPoint? {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(p) else { return nil }
        return CGPoint(x: (p.x - bounds.minX) / bounds.width, y: (p.y - bounds.minY) / bounds.height)
    }
}
