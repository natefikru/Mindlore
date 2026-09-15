import Foundation
import FoundationModels

nonisolated enum FoundationModelsAvailability {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { true } else { false }
    }

    static var unavailableReason: OnDeviceModelError {
        switch SystemLanguageModel.default.availability {
        case .available: .generationFailed
        case .unavailable(let reason): .unavailable(FoundationModelsTextGenerator.reason(reason))
        }
    }
}
