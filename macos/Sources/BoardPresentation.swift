import Foundation
import GNUbgNative

enum PlayerColorChoice: String, CaseIterable, Identifiable {
    case alternating, ivory, charcoal, random
    var id: String { rawValue }
    var label: String { L10n.text("color." + rawValue) }
    func player(after previous: Int) -> Int {
        switch self {
        case .alternating: return 1 - previous
        case .ivory: return 0
        case .charcoal: return 1
        case .random: return Int.random(in: 0...1)
        }
    }
}

struct TurnPresentation {
    let player: Int
    let dice: [Int]
    let move: Move
    init(_ turn: gnubg_native_turn) {
        player = Int(turn.player)
        dice = [Int(turn.dice.0), Int(turn.dice.1)]
        move = Move(turn.move, id: -1)
    }
}

extension Move {
    /// Track moved checkers through chained steps, excluding intermediate points.
    var finalDestinations: [Int: Int] {
        var counts: [Int: Int] = [:]
        for step in steps {
            if counts[step.from, default: 0] > 0 { counts[step.from, default: 0] -= 1 }
            counts[step.to, default: 0] += 1
        }
        return counts.filter { $0.value > 0 }
    }
}
