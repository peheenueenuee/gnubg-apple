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

func runUISmoke(render: Bool = true) {
    if render { _ = NSApplication.shared }
    let model = EngineModel()
    waitForIdle(model)
    model.computer = false
    model.newMatch()
    waitForIdle(model)
    guard let move = model.moves.first else { fatalError("No opening legal moves") }
    for step in move.steps {
        model.select(step.from)
        model.select(step.to)
    }
    precondition(model.completeMove?.steps == move.steps, "Checker selection failed")
    model.play(model.completeMove!)
    waitForIdle(model)
    model.analyse(rollout: false)
    waitForIdle(model)
    precondition(model.analysisText.contains("Equity"))
    model.trials = 4
    model.analyse(rollout: true)
    waitForIdle(model)
    precondition(model.analysisText.contains("4 trials"))
    model.trials = 100000
    model.analyse(rollout: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { model.cancel() }
    waitForIdle(model)
    precondition(model.status.contains("cancelled"), model.status)
    model.analyse(rollout: false)
    waitForIdle(model)
    precondition(model.analysisText.contains("Equity"))
    model.trials = 36
    model.trials = 4
    model.analyse(rollout: true)
    waitForIdle(model)
    precondition(model.analysisText.contains("4 trials"))
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
