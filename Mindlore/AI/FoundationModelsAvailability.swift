import Foundation
import FoundationModels

nonisolated enum FoundationModelsAvailability {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { true } else { false }
    }
}
