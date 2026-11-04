import FoundationModels
import StepsCore

/// Rewrites rule-based captions into friendlier sentences with the on-device model.
enum CaptionPolisher {
    static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This Mac doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in System Settings."
            case .modelNotReady: return "The on-device model is still downloading. Try again later."
            @unknown default: return "The on-device model is unavailable."
            }
        }
    }

    private static let instructions = """
    You edit step captions for an IT support how-to guide for non-technical users. \
    Rewrite the given caption as one short, clear, friendly instruction in the imperative mood. \
    Keep every name in “curly quotes” exactly as written, including the quotes. \
    Do not add steps, details or numbering. Reply with the rewritten caption only.
    """

    /// Returns the polished caption, or nil if the model's answer was unusable.
    static func polish(_ caption: String, appName: String) async -> String? {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "App: \(appName)\nCaption: \(caption)"
        guard let reply = try? await session.respond(to: prompt) else { return nil }
        return CaptionGuard.accept(original: caption, polished: reply.content)
    }
}
