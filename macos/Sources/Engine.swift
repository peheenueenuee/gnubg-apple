import Foundation
import SwiftUI
import GNUbgNative

struct Step: Equatable {
    let from: Int
    let to: Int
    var label: String { "\(from == 24 ? "Bar" : String(from + 1))/\(to < 0 ? "Off" : String(to + 1))" }
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
    @Published var status = "Starting engine…"
    @Published var analysisText = "Run an evaluation or rollout to inspect the position."
    @Published var matchLength = 3
    @Published var computer = true
    @Published var trials = 36
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
                DispatchQueue.main.async { model.status = text }
            }
            callbacks.progress = { context, completed, total in
                guard let context else { return }
                let model = Unmanaged<EngineModel>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async {
                    model.progress = total == 0 ? 0 : Double(completed) / Double(total)
                    model.status = "Rollout: \(completed) / \(total)"
                }
            }
            callbacks.analysis = { context, result in
                guard let context, let result else { return }
                let model = Unmanaged<EngineModel>.fromOpaque(context).takeUnretainedValue()
                let value = result.pointee
                let outputs = withUnsafeBytes(of: value.outputs) { Array($0.bindMemory(to: Float.self)) }
                let errors = withUnsafeBytes(of: value.standard_errors) { Array($0.bindMemory(to: Float.self)) }
                let text = String(format: "%@ · Win %.1f%% · Gammon %.1f%%\nEquity %.3f%@",
                    value.player == 0 ? "Ivory" : "Charcoal", outputs[0] * 100, outputs[1] * 100,
                    outputs[5], value.trials > 0 ? String(format: " ± %.3f SE · %u trials", errors[5], value.trials) : " · 0-ply")
                DispatchQueue.main.async { model.analysisText = text }
            }
            self.handle = gnubg_native_create(GNUBG_NATIVE_STANDARD, &callbacks)
            guard let handle = self.handle else {
                DispatchQueue.main.async { self.busy = false; self.status = "Engine could not start. Check bundled resources." }
                return
            }
            DispatchQueue.main.async { self.cancellationHandle = handle }
            let result = gnubg_native_start_match(handle, 3, GNUBG_NATIVE_HUMAN, GNUBG_NATIVE_COMPUTER)
            self.finish(result)
        }
    }
    private func finish(_ result: gnubg_native_result, hint: Move? = nil) {
        var snapshot = gnubg_native_position()
        let valid = gnubg_native_snapshot(handle, &snapshot) == GNUBG_NATIVE_OK
        var count: UInt32 = 0
        var legal: [gnubg_native_move] = []
        if gnubg_native_legal_moves(handle, nil, 0, &count) == GNUBG_NATIVE_OK && count > 0 {
            legal = Array(repeating: gnubg_native_move(), count: Int(count))
            _ = legal.withUnsafeMutableBufferPointer { gnubg_native_legal_moves(handle, $0.baseAddress, count, &count) }
        }
        let state = valid ? Position(snapshot) : nil
        let choices = legal.enumerated().map { Move($0.element, id: $0.offset) }
        let error = String(cString: gnubg_native_result_string(result))
        DispatchQueue.main.async {
            self.position = state
            self.moves = choices
            self.staged = []; self.source = nil
            self.busy = false; self.analysing = false
            if result == GNUBG_NATIVE_CANCELLED { self.status = "Analysis cancelled. Ready." }
            else if result != GNUBG_NATIVE_OK { self.status = "Could not complete action: \(error)" }
            else if let hint { self.status = "Hint: \(hint.label)" }
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
        guard let p = position else { return "Engine unavailable" }
        if p.raw.match_over != 0 { return "Match complete — \(p.scores[0] > p.scores[1] ? "Ivory" : "Charcoal") wins" }
        if p.raw.game_over != 0 { return "Game complete. Start the next game." }
        let name = p.raw.turn == 0 ? "Ivory" : "Charcoal"
        if p.raw.doubled != 0 { return "\(name): take or drop the cube" }
        if p.raw.resignation != 0 { return "\(name): accept or reject resignation (\(p.raw.resignation))" }
        return "\(name) to play\(p.raw.computer_turn != 0 ? " · Computer" : "")"
    }
    private func run(analysis: Bool = false, _ action: @escaping (OpaquePointer) -> gnubg_native_result) {
        guard !busy, cancellationHandle != nil else { return }
        busy = true; analysing = analysis; staged = []; source = nil
        if !analysis { analysisText = "Run an evaluation or rollout to inspect the position." }
        if analysis { progress = 0; status = "Analysing…" }
        queue.async {
            guard let handle = self.handle else { return }
            self.finish(action(handle))
        }
    }
    func newMatch() {
        let length = UInt32(matchLength), opponent = computer ? GNUBG_NATIVE_COMPUTER : GNUBG_NATIVE_HUMAN
        analysisText = "Run an evaluation or rollout to inspect the position."
        run { gnubg_native_start_match($0, length, GNUBG_NATIVE_HUMAN, opponent) }
    }
    func roll() { run { gnubg_native_roll($0) } }
    func act(_ action: gnubg_native_action) { run { gnubg_native_act($0, action) } }
    func resign(_ points: Int) { run { gnubg_native_resign($0, UInt8(points)) } }
    func play(_ move: Move) {
        run { handle in var value = move.native; return gnubg_native_play(handle, &value) }
    }
    func hint() {
        guard !busy else { return }
        busy = true
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
        guard !busy, position?.raw.computer_turn == 0 else { return }
        if let source, let step = nextSteps.first(where: { $0.from == source && $0.to == point }) {
            staged.append(step); self.source = nil
        } else if nextSteps.contains(where: { $0.from == point }) { source = point }
        else { source = nil }
    }
    var completeMove: Move? { candidates.first { $0.steps == staged && !staged.isEmpty } }
}
