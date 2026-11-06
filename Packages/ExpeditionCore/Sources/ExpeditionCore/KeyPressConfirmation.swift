import Foundation

/// A key can be retried only when a readable destination provably did not change.
public enum KeyPressConfirmation: Equatable, Sendable {
    case confirmed, missed, changed
    public static func assess(before: String, expected: String, actual: String?, sameFocus: Bool) -> Self {
        guard sameFocus, let actual else { return .changed }
        if actual == expected { return .confirmed }
        return actual == before ? .missed : .changed
    }
}
