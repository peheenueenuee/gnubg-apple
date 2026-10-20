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

/// Assign dice to the actual legal step sequence, including oversized bearoffs.
/// Searching the whole move avoids consuming a die needed by a later step.
enum DiceUsage {
    static func expanded(_ dice: [Int]) -> [Int] {
        guard dice.count == 2, dice.allSatisfy({ (1...6).contains($0) }) else { return dice }
        return dice[0] == dice[1] ? Array(repeating: dice[0], count: 4) : dice
    }
    static func assignment(position: Position, steps: [Step], dice: [Int]) -> [Int]? {
        let values = expanded(dice)
        let player = position.player
        guard (0...1).contains(player) else { return nil }
        func search(_ board: Position, _ stepIndex: Int, _ used: [Int]) -> [Int]? {
            if stepIndex == steps.count { return used }
            let step = steps[stepIndex]
            guard (0...24).contains(step.from), (-1...23).contains(step.to) else { return nil }
            let sourceCount = step.from == 24 ? board.bars[player] : board.points[player][step.from]
            guard sourceCount > 0 else { return nil }
            // A single playable die must use the higher value when both fit.
            let indices = values.indices.sorted { values[$0] == values[$1] ? $0 < $1 : values[$0] > values[$1] }
            for index in indices where !used.contains(index) {
                let die = values[index]
                if step.to >= 0 {
                    guard step.from - step.to == die else { continue }
                } else {
                    guard step.from < 6, board.bars[player] == 0,
                          !board.points[player][6..<24].contains(where: { $0 > 0 }),
                          die >= step.from + 1 else { continue }
                    if die > step.from + 1 && board.points[player][(step.from + 1)..<24].contains(where: { $0 > 0 }) { continue }
                }
                if let result = search(board.preview([step]), stepIndex + 1, used + [index]) { return result }
            }
            return nil
        }
        return search(position, 0, [])
    }
}
