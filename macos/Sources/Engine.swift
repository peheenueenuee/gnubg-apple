import Foundation
import SwiftUI
import GNUbgNative

struct Step: Equatable {
    let from: Int
    let to: Int
    var label: String { "\(from == 24 ? L10n.text("move.bar") : String(from + 1))/\(to < 0 ? L10n.text("move.off") : String(to + 1))" }
}
struct Move: Identifiable {
    let id: Int
    let native: gnubg_native_move
    let steps: [Step]
    init(_ value: gnubg_native_move, id: Int) {
        self.id = id
        native = value
        let bytes = withUnsafeBytes(of: value.steps) { Array($0.bindMemory(to: Int8.self)) }
        steps = (0..<Int(value.step_count)).map { Step(from: Int(bytes[$0 * 2]), to: Int(bytes[$0 * 2 + 1])) }
    }
    var label: String { steps.map(\.label).joined(separator: "  ") }
}
struct Position {
    let raw: gnubg_native_position
    var points: [[Int]]
    var bars: [Int]
    var off: [Int]
    let scores: [Int]
    init(_ value: gnubg_native_position) {
        raw = value
        let bytes = withUnsafeBytes(of: value.points) { Array($0) }
        points = [Array(bytes[0..<24]).map(Int.init), Array(bytes[24..<48]).map(Int.init)]
        bars = [Int(value.bar.0), Int(value.bar.1)]
        off = [Int(value.borne_off.0), Int(value.borne_off.1)]
        scores = [Int(value.score.0), Int(value.score.1)]
    }
    var player: Int { Int(raw.board_player) }
    func preview(_ steps: [Step]) -> Position {
        var copy = self
        guard player >= 0 else { return copy }
        for step in steps {
            if step.from == 24 { copy.bars[player] -= 1 }
            else { copy.points[player][step.from] -= 1 }
            if step.to < 0 { copy.off[player] += 1 }
            else {
                copy.points[player][step.to] += 1
                let hit = 23 - step.to
                if copy.points[1 - player][hit] == 1 {
                    copy.points[1 - player][hit] = 0
                    copy.bars[1 - player] += 1
                }
            }
        }
        return copy
    }
}

// GNUbg binds scratch buffers to the bootstrap OS thread. A serial GCD queue
// can switch OS threads, so every engine operation uses this fixed worker.
private final class EngineWorker {
    private let condition = NSCondition()
    private var jobs: [() -> Void] = []
    init() {
        let thread = Thread { [self] in
            while true {
                condition.lock()
                while jobs.isEmpty { condition.wait() }
                let job = jobs.removeFirst()
                condition.unlock()
                autoreleasepool { job() }
            }
        }
        thread.name = "GNUbg engine"
        thread.qualityOfService = .userInitiated
        thread.start()
    }
    func async(_ job: @escaping () -> Void) {
        condition.lock(); jobs.append(job); condition.signal(); condition.unlock()
    }
}

final class EngineModel: ObservableObject {
    @Published var position: Position?
    @Published var moves: [Move] = []
    @Published var staged: [Step] = []
    @Published var source: Int?
    @Published var busy = true
    @Published var analysing = false
    @Published var progress: Double = 0
    @Published var status = L10n.text("status.starting")
    @Published var analysisText = L10n.text("analysis.empty")
    @Published var matchLength = 3
    @Published var computer = true
    @Published var trials = 36
    @Published var colorChoice: PlayerColorChoice = .alternating
    @Published private(set) var humanPlayer = 0
    @Published private(set) var activeComputer = true
    @Published private(set) var hoveredMove: Move?
    @Published private(set) var lastTurns: [TurnPresentation?] = [nil, nil]
    private struct MatchConfiguration {
        let humanPlayer: Int
        let computer: Bool
    }
    private let queue = EngineWorker()
    private var handle: OpaquePointer?
    private var cancellationHandle: OpaquePointer? // main-thread copy; handle lives until process exit

    init() {
        queue.async {
            let data = Bundle.main.resourceURL!.appendingPathComponent("engine").path
            setenv("GNUBG_NATIVE_DATA_DIR", data, 1)
            var callbacks = gnubg_native_callbacks()
            callbacks.context = Unmanaged.passUnretained(self).toOpaque()
            callbacks.message = { context, message in
                guard let context, let message else { return }
                let model = Unmanaged<EngineModel>.fromOpaque(context).takeUnretainedValue()
                let text = String(cString: message)
                fputs("GNUbg: \(text)\n", stderr)
                DispatchQueue.main.async { model.status = L10n.engineMessage(text) }
            }
            callbacks.progress = { context, completed, total in
                guard let context else { return }
                let model = Unmanaged<EngineModel>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async {
                    model.progress = total == 0 ? 0 : Double(completed) / Double(total)
                    model.status = L10n.text("status.rollout", completed, total)
                }
            }
            callbacks.analysis = { context, result in
                guard let context, let result else { return }
                let model = Unmanaged<EngineModel>.fromOpaque(context).takeUnretainedValue()
                let value = result.pointee
                let outputs = withUnsafeBytes(of: value.outputs) { Array($0.bindMemory(to: Float.self)) }
                let errors = withUnsafeBytes(of: value.standard_errors) { Array($0.bindMemory(to: Float.self)) }
                let text = L10n.text("analysis.summary", L10n.player(Int(value.player)),
                    outputs[0] * 100, outputs[1] * 100, outputs[5],
                    value.trials > 0 ? L10n.text("analysis.rollout_detail", errors[5], L10n.text("analysis.completed_trials", value.trials))
                                    : L10n.text("analysis.normal_detail"))
                DispatchQueue.main.async { model.analysisText = text }
            }
            self.handle = gnubg_native_create(GNUBG_NATIVE_STANDARD, &callbacks)
            guard let handle = self.handle else {
                DispatchQueue.main.async { self.busy = false; self.status = L10n.text("error.startup") }
                return
            }
            DispatchQueue.main.async { self.cancellationHandle = handle }
            let result = gnubg_native_start_match(handle, 3, GNUBG_NATIVE_HUMAN, GNUBG_NATIVE_COMPUTER)
            self.finish(result)
        }
    }
    private func finish(_ result: gnubg_native_result, hint: Move? = nil, configuration: MatchConfiguration? = nil) {
        var snapshot = gnubg_native_position()
        let valid = gnubg_native_snapshot(handle, &snapshot) == GNUBG_NATIVE_OK
        var count: UInt32 = 0
        var legal: [gnubg_native_move] = []
        if gnubg_native_legal_moves(handle, nil, 0, &count) == GNUBG_NATIVE_OK && count > 0 {
            legal = Array(repeating: gnubg_native_move(), count: Int(count))
            _ = legal.withUnsafeMutableBufferPointer { gnubg_native_legal_moves(handle, $0.baseAddress, count, &count) }
        }
        var turns: [TurnPresentation?] = [nil, nil]
        for player in 0...1 {
            var turn = gnubg_native_turn()
            if gnubg_native_last_turn(handle, Int8(player), &turn) == GNUBG_NATIVE_OK {
                turns[player] = TurnPresentation(turn)
            }
        }
        let state = valid ? Position(snapshot) : nil
        let choices = legal.enumerated().map { Move($0.element, id: $0.offset) }
        let error = L10n.result(result)
        DispatchQueue.main.async {
            if result == GNUBG_NATIVE_OK, let configuration {
                self.humanPlayer = configuration.humanPlayer
                self.activeComputer = configuration.computer
            }
            self.lastTurns = turns
            self.hoveredMove = nil
            self.position = state
            self.moves = choices
            self.staged = []; self.source = nil
            self.busy = false; self.analysing = false
            if result == GNUBG_NATIVE_CANCELLED { self.status = L10n.text("status.cancelled") }
            else if result != GNUBG_NATIVE_OK { self.status = L10n.text("status.failed", error) }
            else if let hint { self.status = L10n.text("status.hint", hint.label) }
            else { self.status = self.turnDescription }
            if result == GNUBG_NATIVE_OK && state?.raw.computer_turn != 0 && state?.raw.game_over == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if !self.busy && self.position?.raw.computer_turn != 0 {
                        self.act(GNUBG_NATIVE_COMPUTER_TURN)
                    }
                }
            }
        }
    }
    var turnDescription: String {
        guard let p = position else { return L10n.text("error.unavailable") }
        if p.raw.match_over != 0 { return L10n.text("status.match_complete", L10n.player(p.scores[0] > p.scores[1] ? 0 : 1)) }
        if p.raw.game_over != 0 { return L10n.text("status.game_complete") }
        let name = L10n.player(Int(p.raw.turn))
        if p.raw.doubled != 0 { return L10n.text("status.cube_response", name) }
        if p.raw.resignation != 0 { return L10n.text("status.resign_response", name, p.raw.resignation) }
        return L10n.text("status.turn", name, p.raw.computer_turn != 0 ? L10n.text("status.computer") : "")
    }
    private func run(analysis: Bool = false, configuration: MatchConfiguration? = nil, _ action: @escaping (OpaquePointer) -> gnubg_native_result) {
        guard !busy, cancellationHandle != nil else { return }
        busy = true; analysing = analysis; staged = []; source = nil; hoveredMove = nil
        if !analysis { analysisText = L10n.text("analysis.empty") }
        if analysis { progress = 0; status = L10n.text("status.analysing") }
        queue.async {
            guard let handle = self.handle else { return }
            self.finish(action(handle), configuration: configuration)
        }
    }
    func newMatch() {
        guard !busy else { return }
        let length = UInt32(matchLength)
        let side = colorChoice.player(after: humanPlayer)
        let enabled = computer
        let player0 = enabled && side == 1 ? GNUBG_NATIVE_COMPUTER : GNUBG_NATIVE_HUMAN
        let player1 = enabled && side == 0 ? GNUBG_NATIVE_COMPUTER : GNUBG_NATIVE_HUMAN
        run(configuration: MatchConfiguration(humanPlayer: side, computer: enabled)) {
            gnubg_native_start_match($0, length, player0, player1)
        }
    }
    func roll() { run { gnubg_native_roll($0) } }
    func act(_ action: gnubg_native_action) { run { gnubg_native_act($0, action) } }
    func resign(_ points: Int) { run { gnubg_native_resign($0, UInt8(points)) } }
    func play(_ move: Move) {
        run { handle in var value = move.native; return gnubg_native_play(handle, &value) }
    }
    func hint() {
        guard !busy else { return }
        busy = true; hoveredMove = nil
        queue.async {
            var value = gnubg_native_move()
            let result = gnubg_native_hint(self.handle, &value)
            self.finish(result, hint: result == GNUBG_NATIVE_OK ? Move(value, id: -1) : nil)
        }
    }
    func analyse(rollout: Bool) {
        let count = rollout ? UInt32(trials) : 0
        run(analysis: true) { handle in
            var settings = gnubg_native_analysis_settings(trials: count, plies: 0, deterministic: 1)
            return gnubg_native_analyse(handle, &settings)
        }
    }
    func cancel() { gnubg_native_cancel(cancellationHandle) }
    var candidates: [Move] { moves.filter { Array($0.steps.prefix(staged.count)) == staged } }
    var nextSteps: [Step] { candidates.compactMap { $0.steps.count > staged.count ? $0.steps[staged.count] : nil } }
    func select(_ point: Int) {
        guard canInteractBoard else { return }
        hoveredMove = nil
        if let source, let step = nextSteps.first(where: { $0.from == source && $0.to == point }) {
            staged.append(step); self.source = nil
        } else if nextSteps.contains(where: { $0.from == point }) { source = point }
        else { source = nil }
    }
    var canInteractBoard: Bool {
        guard let p = position?.raw else { return false }
        return !busy && p.game_over == 0 && p.computer_turn == 0 &&
            p.doubled == 0 && p.resignation == 0 && p.dice.0 > 0
    }
    func canRoll(player: Int) -> Bool {
        guard let p = position?.raw else { return false }
        return !busy && p.game_over == 0 && p.computer_turn == 0 &&
            Int(p.turn) == player && p.dice.0 == 0 && p.doubled == 0 && p.resignation == 0
    }
    var displayPosition: Position? { position?.preview(hoveredMove?.steps ?? staged) }
    var lastOpponentTurn: TurnPresentation? { lastTurns[1 - humanPlayer] }
    func highlightedCheckers(player: Int, point: Int) -> Int {
        guard hoveredMove == nil, staged.isEmpty, let turn = lastOpponentTurn,
              turn.player == player else { return 0 }
        return turn.move.finalDestinations[point, default: 0]
    }
    func diceValues(player: Int) -> [Int]? {
        guard let p = position?.raw else { return nil }
        if Int(p.board_player) == player && p.dice.0 > 0 && p.game_over == 0 {
            return [Int(p.dice.0), Int(p.dice.1)]
        }
        return lastTurns[player]?.dice
    }
    func diceAreCurrent(player: Int) -> Bool {
        guard let p = position?.raw else { return false }
        return Int(p.board_player) == player && p.dice.0 > 0 && p.game_over == 0
    }
    func hover(_ move: Move, active: Bool) {
        if active {
            guard canInteractBoard, moves.contains(where: { $0.id == move.id && $0.steps == move.steps }) else { return }
            hoveredMove = move
        } else if hoveredMove?.id == move.id { hoveredMove = nil }
    }
    func undoSelection() { staged = []; source = nil; hoveredMove = nil }
    var completeMove: Move? { candidates.first { $0.steps == staged && !staged.isEmpty } }
}
