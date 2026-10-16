import SwiftUI
import AppKit
import GNUbgNative

private func waitForIdle(_ model: EngineModel, timeout: TimeInterval = 60) {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        precondition(Date() < deadline, "UI engine operation timed out: \(model.status)")
    } while model.busy
    precondition(model.position != nil, model.status)
}

private func waitForHuman(_ model: EngineModel) {
    let deadline = Date().addingTimeInterval(60)
    repeat {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        precondition(Date() < deadline, "Computer turn timed out")
    } while model.busy || model.position?.raw.computer_turn != 0
}

private func fixtureMove(_ steps: [Step]) -> Move {
    var value = gnubg_native_move()
    value.step_count = UInt8(steps.count)
    withUnsafeMutableBytes(of: &value.steps) { bytes in
        let points = bytes.bindMemory(to: Int8.self)
        for (index, step) in steps.enumerated() {
            points[index * 2] = Int8(step.from)
            points[index * 2 + 1] = Int8(step.to)
        }
    }
    return Move(value, id: -10)
}

private func checkPresentationFixtures() {
    let chained = fixtureMove([Step(from: 12, to: 6), Step(from: 6, to: 0)])
    precondition(chained.finalDestinations == [0: 1], "Intermediate checker must not be highlighted")
    let split = fixtureMove([Step(from: 12, to: 6), Step(from: 12, to: 6)])
    precondition(split.finalDestinations == [6: 2])
    let off = fixtureMove([Step(from: 0, to: -1)])
    precondition(off.finalDestinations == [-1: 1])
    for player in 0...1 {
        var raw = gnubg_native_position()
        raw.board_player = Int8(player)
        raw.bar = player == 0 ? (1, 0) : (0, 1)
        withUnsafeMutableBytes(of: &raw.points) { bytes in
            bytes[(1 - player) * 24 + 5] = 1
        }
        let original = Position(raw)
        let entered = original.preview([Step(from: 24, to: 18)])
        precondition(original.bars[player] == 1 && original.points[player][18] == 0)
        precondition(entered.bars[player] == 0 && entered.bars[1 - player] == 1)
        precondition(entered.points[player][18] == 1 && entered.points[1 - player][5] == 0)
        precondition(entered.preview([Step(from: 18, to: -1)]).off[player] == 1)
    }
}

private func checkHover(_ model: EngineModel, move: Move) {
    let original = model.position!
    model.hover(move, active: true)
    precondition(model.hoveredMove?.id == move.id)
    precondition(model.displayPosition?.points == original.preview(move.steps).points)
    precondition(model.position?.points == original.points && model.position?.bars == original.bars)
    model.hover(move, active: false)
    precondition(model.hoveredMove == nil && model.displayPosition?.points == original.points)
    if let step = move.steps.first {
        model.select(step.from); model.select(step.to)
        let staged = model.staged
        model.hover(move, active: true)
        precondition(model.staged == staged)
        model.hover(move, active: false)
        precondition(model.displayPosition?.points == original.preview(staged).points)
        model.undoSelection()
    }
}

func runUISmoke(render: Bool = true) {
    if render { _ = NSApplication.shared }
    checkPresentationFixtures()
    let model = EngineModel()
    waitForIdle(model)
    model.computer = false
    model.newMatch()
    waitForIdle(model)
    precondition(model.humanPlayer == 1, "The next match should alternate to charcoal")
    guard let move = model.moves.first else { fatalError("No opening legal moves") }
    checkHover(model, move: move)
    let openingPlayer = model.position!.player
    let openingDice = model.diceValues(player: openingPlayer)
    for step in move.steps {
        model.select(step.from)
        model.select(step.to)
    }
    precondition(model.completeMove?.steps == move.steps, "Checker selection failed")
    model.play(model.completeMove!)
    waitForIdle(model)
    precondition(model.lastTurns[openingPlayer]?.dice == openingDice)
    precondition(model.lastTurns[openingPlayer]?.move.steps == move.steps)
    // Complete the other player's turn, so both dice histories and opponent
    // highlights are covered regardless of who won the opening roll.
    if model.position?.raw.dice.0 == 0 { model.roll(); waitForIdle(model) }
    precondition(!model.moves.isEmpty)
    model.play(model.moves[0]); waitForIdle(model)
    precondition(model.lastTurns.allSatisfy { $0 != nil })
    let opponent = model.lastOpponentTurn!
    precondition(opponent.player == 1 - model.humanPlayer)
    precondition(model.diceValues(player: opponent.player) == opponent.dice)
    for (point, count) in opponent.move.finalDestinations {
        precondition(model.highlightedCheckers(player: opponent.player, point: point) == count)
    }
    model.analyse(rollout: false)
    waitForIdle(model)
    precondition(model.analysisText.contains(L10n.text("analysis.normal_detail")))
    model.trials = 4
    model.analyse(rollout: true)
    waitForIdle(model)
    precondition(model.analysisText.contains(L10n.text("analysis.completed_trials", UInt32(4))))
    model.trials = 100000
    model.analyse(rollout: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { model.cancel() }
    waitForIdle(model)
    precondition(model.status == L10n.text("status.cancelled"), model.status)
    model.analyse(rollout: false)
    waitForIdle(model)
    precondition(model.analysisText.contains(L10n.text("analysis.normal_detail")))
    model.trials = 4
    model.analyse(rollout: true)
    waitForIdle(model)
    precondition(model.analysisText.contains(L10n.text("analysis.completed_trials", UInt32(4))))
    model.trials = 36
    // End a match through the same actions used by the SwiftUI controls.
    model.matchLength = 1
    model.newMatch()
    waitForIdle(model)
    model.resign(1)
    waitForIdle(model)
    precondition(model.position?.raw.resignation == 1)
    model.act(GNUBG_NATIVE_ACCEPT_RESIGNATION)
    waitForIdle(model)
    precondition(model.position?.raw.match_over != 0)
    precondition(model.position?.raw.resignation == 0)
    model.matchLength = 3
    model.newMatch()
    waitForIdle(model)
    model.colorChoice = .ivory
    model.newMatch(); waitForIdle(model)
    precondition(model.humanPlayer == 0)
    model.colorChoice = .charcoal
    precondition(model.humanPlayer == 0, "Color preference must not rotate an active match")
    model.newMatch(); waitForIdle(model)
    precondition(model.humanPlayer == 1)
    model.colorChoice = .alternating
    model.newMatch(); waitForIdle(model)
    precondition(model.humanPlayer == 0)
    model.computer = true
    model.colorChoice = .charcoal
    model.newMatch(); waitForHuman(model)
    precondition(model.humanPlayer == 1 && model.position?.raw.turn == 1)
    if model.position?.raw.dice.0 == 0 { model.roll(); waitForIdle(model) }
    precondition(!model.moves.isEmpty)
    model.play(model.moves[0]); waitForHuman(model)
    precondition(model.lastOpponentTurn?.player == 0)
    precondition(model.lastOpponentTurn!.dice.allSatisfy { (1...6).contains($0) })
    print("Interaction model OK: hover isolation, bar/hit/off previews, last move/dice, alternating/fixed colors, charcoal vs computer")
    print("UI model smoke OK: checker selection, analysis, rollout, cancellation, recovery, full match")
    if !render { return }
    let view = NSHostingView(rootView: ContentView(model: model))
    view.frame = NSRect(x: 0, y: 0, width: 1180, height: 820)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.contentView = view
    window.title = "GNUbg Apple — UI smoke"
    window.makeKeyAndOrderFront(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
    let output = ProcessInfo.processInfo.environment["GNUBG_PREVIEW_PATH"] ?? "/tmp/gnubg-apple-preview.png"
    do { try png.write(to: URL(fileURLWithPath: output)) } catch { fatalError("\(error)") }
    print("SwiftUI smoke OK: checker interaction, analysis, rollout, cancellation, recovery; preview: \(output)")
    window.orderOut(nil)
}
