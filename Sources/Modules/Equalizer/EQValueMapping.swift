import Foundation

enum EQValueMapping {
    static let maxDecibels: Float = 12

    static func decibels(normalized: Float) -> Float {
        let db = normalized * self.maxDecibels
        return min(max(db, -self.maxDecibels), self.maxDecibels)
    }

    static func normalized(decibels: Float) -> Float {
        let clamped = min(max(decibels, -self.maxDecibels), self.maxDecibels)
        return clamped / self.maxDecibels
    }
}
