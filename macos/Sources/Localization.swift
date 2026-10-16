import Foundation
import GNUbgNative

/// Bundle localization follows macOS language preferences; English is the fallback.
enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: Locale.current, arguments: arguments)
    }

    static func player(_ player: Int) -> String {
        text(player == 0 ? "player.ivory" : "player.charcoal")
    }

    static func result(_ result: gnubg_native_result) -> String {
        switch result {
        case GNUBG_NATIVE_INVALID_ARGUMENT: return text("error.invalid_argument")
        case GNUBG_NATIVE_NOT_READY: return text("error.not_ready")
        case GNUBG_NATIVE_ILLEGAL_MOVE: return text("error.illegal_move")
        case GNUBG_NATIVE_CANCELLED: return text("status.cancelled")
        default: return text("error.engine")
        }
    }

    static func engineMessage(_ message: String) -> String {
        switch message {
        case "GNU Backgammon match equity table is missing": return text("error.data_missing")
        case "Position analysis failed": return text("error.analysis")
        default: return text("error.engine")
        }
    }
}
