import SwiftUI
import AppKit
import GNUbgNative

private let ink = Color(red: 0.13, green: 0.21, blue: 0.23)
private let teal = Color(red: 0.12, green: 0.43, blue: 0.41)

struct Triangle: Shape {
    let top: Bool
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: top ? 0 : rect.height))
            path.addLine(to: CGPoint(x: rect.width, y: top ? 0 : rect.height))
            path.addLine(to: CGPoint(x: rect.midX, y: top ? rect.height : 0))
            path.closeSubpath()
        }
    }
}

struct PointView: View {
    let point: Int
    let top: Bool
    let state: Position
    @ObservedObject var model: EngineModel
    private var ownPoint: Int { state.player == 0 ? point : 23 - point }
    private var owner: Int { state.points[0][point] > 0 ? 0 : 1 }
    private var count: Int { max(state.points[0][point], state.points[1][23 - point]) }
    private var destination: Bool { model.nextSteps.contains { $0.from == model.source && $0.to == ownPoint } }
    private var selectable: Bool { model.nextSteps.contains { $0.from == ownPoint } }
    var body: some View {
        Button { model.select(ownPoint) } label: {
            VStack(spacing: 3) {
                if top { Text("\(point + 1)").font(.caption2.monospacedDigit()) }
                ZStack(alignment: top ? .top : .bottom) {
                    Triangle(top: top)
                        .fill(point.isMultiple(of: 2) ? teal.opacity(0.8) : Color(red: 0.75, green: 0.44, blue: 0.28))
                        .padding(.horizontal, 1)
                    VStack(spacing: 2) {
                        ForEach(0..<min(count, 5), id: \.self) { index in
                            Circle().fill(owner == 0 ? Color(red: 0.98, green: 0.94, blue: 0.82) : ink)
                                .overlay(Circle().stroke(.black.opacity(0.2), lineWidth: 1))
                                .overlay {
                                    if index == 4 && count > 5 {
                                        Text("\(count)").font(.caption.bold()).foregroundColor(owner == 0 ? ink : .white)
                                    }
                                }
                                .frame(maxWidth: 34, maxHeight: 34)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }.padding(4)
                    if destination {
                        RoundedRectangle(cornerRadius: 6).stroke(Color.yellow, lineWidth: 3)
                    } else if model.source == ownPoint {
                        RoundedRectangle(cornerRadius: 6).stroke(Color.white, lineWidth: 3)
                    } else if selectable && model.staged.isEmpty {
                        RoundedRectangle(cornerRadius: 6).stroke(teal.opacity(0.5), lineWidth: 1)
                    }
                }
                if !top { Text("\(point + 1)").font(.caption2.monospacedDigit()) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("board.point_accessibility", point + 1, count, L10n.player(owner)))
        .help(L10n.text("board.coordinate", L10n.player(state.player), ownPoint + 1))
    }
}

struct BoardView: View {
    @ObservedObject var model: EngineModel
    let position: Position
    var body: some View {
        let preview = position.preview(model.staged)
        VStack(spacing: 12) {
            HStack {
                Label(L10n.text("board.score", L10n.player(0), position.scores[0]), systemImage: "circle.fill")
                Spacer()
                Text(L10n.text("board.game", position.raw.game_number, position.raw.match_length, position.raw.crawford != 0 ? L10n.text("board.crawford") : ""))
                Spacer()
                Label(L10n.text("board.score", L10n.player(1), position.scores[1]), systemImage: "circle")
            }.font(.subheadline.weight(.semibold))
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(12..<24, id: \.self) { point in
                        PointView(point: point, top: true, state: preview, model: model)
                        if point == 17 { Divider().overlay(ink).padding(.horizontal, 5) }
                    }
                }
                HStack {
                    Button(L10n.text("board.bar", preview.bars[0], preview.bars[1])) { model.select(24) }
                        .tint(model.source == 24 ? .orange : teal)
                    Spacer()
                    Text(position.raw.dice.0 > 0 ? "⚄  \(position.raw.dice.0)   \(position.raw.dice.1)" : L10n.text("board.awaiting_roll"))
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Spacer()
                    Button(L10n.text("board.off", preview.off[0], preview.off[1])) { model.select(-1) }
                        .tint(model.nextSteps.contains { $0.from == model.source && $0.to == -1 } ? .orange : teal)
                }.font(.caption)
                HStack(spacing: 4) {
                    ForEach(Array((0..<12).reversed()), id: \.self) { point in
                        PointView(point: point, top: false, state: preview, model: model)
                        if point == 6 { Divider().overlay(ink).padding(.horizontal, 5) }
                    }
                }
            }
            .padding(14)
            .background(Color(red: 0.91, green: 0.86, blue: 0.73), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ink.opacity(0.25), lineWidth: 5))
            HStack {
                Text(L10n.text("board.instructions", L10n.player(position.player)))
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button(L10n.text("board.undo")) { model.staged = []; model.source = nil }.disabled(model.staged.isEmpty && model.source == nil)
                Button(L10n.text("board.confirm")) { if let move = model.completeMove { model.play(move) } }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(model.completeMove == nil || model.busy)
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var model: EngineModel
    init() { _model = StateObject(wrappedValue: EngineModel()) }
    init(model: EngineModel) { _model = StateObject(wrappedValue: model) }
    @State private var confirmNew = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GNUbg Apple").font(.largeTitle.bold()).foregroundColor(ink)
                    Text(L10n.text("app.tagline")).foregroundColor(.secondary)
                }
                Spacer()
                Picker(L10n.text("match.label"), selection: $model.matchLength) {
                    ForEach([1, 3, 5, 7, 11], id: \.self) { Text(L10n.text("match.points", $0)).tag($0) }
                }.frame(width: 160)
                Toggle(L10n.text("match.computer"), isOn: $model.computer).toggleStyle(.checkbox)
                Button(L10n.text("match.new")) { confirmNew = true }.disabled(model.busy)
            }
            HStack(alignment: .top, spacing: 22) {
                if let position = model.position {
                    BoardView(model: model, position: position)
                        .disabled(model.busy || position.raw.game_over != 0 || position.raw.computer_turn != 0)
                } else {
                    ProgressView(L10n.text("board.preparing")).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                sidebar.frame(width: 245)
            }
            HStack(spacing: 10) {
                Circle().fill(model.busy ? Color.orange : teal).frame(width: 8, height: 8)
                Text(model.status).font(.callout).textSelection(.enabled)
                Spacer()
                Text(L10n.text("app.offline", String(cString: gnubg_native_version()))).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 1060, minHeight: 720)
        .background(Color(red: 0.97, green: 0.96, blue: 0.93))
        .tint(teal)
        .preferredColorScheme(.light)
        .confirmationDialog(L10n.text("match.confirm_new"), isPresented: $confirmNew) {
            Button(L10n.text("match.start")) { model.newMatch() }
            Button(L10n.text("app.cancel"), role: .cancel) {}
        }
    }
    @ViewBuilder private var sidebar: some View {
        let p = model.position?.raw
        let playing = p?.game_over == 0
        let human = p?.computer_turn == 0
        let decision = p?.doubled != 0 || p?.resignation != 0
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("panel.table")).font(.caption.weight(.bold)).foregroundColor(teal)
            Text(model.turnDescription).font(.headline)
            HStack {
                Text(L10n.text("cube.value", p?.cube_value ?? 1)).font(.title2.bold())
                Spacer()
                Text(p?.cube_owner == -1 ? L10n.text("cube.centered") : L10n.text("cube.owner", L10n.player(Int(p?.cube_owner ?? 0)))).font(.caption)
            }
            if p?.doubled != 0 {
                HStack {
                    Button(L10n.text("cube.take")) { model.act(GNUBG_NATIVE_TAKE) }
                    Button(L10n.text("cube.drop")) { model.act(GNUBG_NATIVE_DROP) }
                }.disabled(model.busy || !human)
            } else if p?.resignation != 0 {
                HStack {
                    Button(L10n.text("resign.accept")) { model.act(GNUBG_NATIVE_ACCEPT_RESIGNATION) }
                    Button(L10n.text("resign.reject")) { model.act(GNUBG_NATIVE_REJECT_RESIGNATION) }
                }.disabled(model.busy || !human)
            } else if p?.game_over != 0 {
                Button(L10n.text("match.next_game")) { model.act(GNUBG_NATIVE_NEXT_GAME) }
                    .disabled(model.busy || p?.match_over != 0)
            } else {
                HStack {
                    Button(L10n.text("game.roll")) { model.roll() }.buttonStyle(.borderedProminent)
                        .disabled(model.busy || !human || p?.dice.0 != 0)
                    Button(L10n.text("cube.double")) { model.act(GNUBG_NATIVE_DOUBLE) }
                        .disabled(model.busy || !human || p?.can_double == 0)
                }
                HStack {
                    Button(L10n.text("game.hint")) { model.hint() }.disabled(model.busy || !human || model.moves.isEmpty)
                    Menu(L10n.text("game.resign")) {
                        ForEach(1...3, id: \.self) { points in Button(L10n.text("resign.points", points)) { model.resign(points) } }
                    }.disabled(model.busy || !human)
                }
                if !human {
                    Button(L10n.text("game.computer_turn")) { model.act(GNUBG_NATIVE_COMPUTER_TURN) }.disabled(model.busy)
                }
            }
            Divider()
            Text(L10n.text("panel.analysis")).font(.caption.weight(.bold)).foregroundColor(teal)
            Text(model.analysisText).font(.callout.monospacedDigit()).textSelection(.enabled)
            Picker(L10n.text("analysis.trials"), selection: $model.trials) {
                ForEach([36, 1296, 5184], id: \.self) { Text(L10n.text("analysis.trial_count", $0)).tag($0) }
            }.disabled(model.busy)
            HStack {
                Button(L10n.text("analysis.evaluate")) { model.analyse(rollout: false) }
                Button(L10n.text("analysis.rollout")) { model.analyse(rollout: true) }
            }.disabled(model.busy || !playing || decision)
            if model.analysing {
                ProgressView(value: model.progress)
                Button(L10n.text("analysis.cancel")) { model.cancel() }
            }
            Divider()
            Text(L10n.text("panel.legal_moves", model.moves.count)).font(.caption.weight(.bold)).foregroundColor(teal)
            Text(L10n.text("move.instructions"))
                .font(.caption).foregroundColor(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(model.moves) { move in
                        Button(move.label) { model.play(move) }
                            .font(.caption.monospacedDigit()).buttonStyle(.plain)
                            .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                            .background(teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                            .disabled(model.busy || !human)
                    }
                }
            }.frame(maxHeight: .infinity)
        }
    }
}

struct GNUbgApp: App {
    var body: some Scene {
        Window("GNUbg Apple", id: "main") { ContentView() }
        .windowStyle(.titleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@main enum Launcher {
    static func main() {
        if CommandLine.arguments.contains("--localization-smoke") {
            runLocalizationSmoke()
        } else if CommandLine.arguments.contains("--model-smoke") {
            runUISmoke(render: false)
        } else if CommandLine.arguments.contains("--ui-smoke") {
            runUISmoke()
        } else if CommandLine.arguments.contains("--smoke") {
            let data = Bundle.main.resourceURL!.appendingPathComponent("engine").path
            setenv("GNUBG_NATIVE_DATA_DIR", data, 1)
            guard let engine = gnubg_native_create(GNUBG_NATIVE_STANDARD, nil) else { fatalError("create failed") }
            precondition(gnubg_native_start_match(engine, 1, GNUBG_NATIVE_COMPUTER, GNUBG_NATIVE_COMPUTER) == GNUBG_NATIVE_OK)
            var position = gnubg_native_position()
            var turns = 0
            repeat {
                precondition(gnubg_native_act(engine, GNUBG_NATIVE_COMPUTER_TURN) == GNUBG_NATIVE_OK)
                precondition(gnubg_native_snapshot(engine, &position) == GNUBG_NATIVE_OK)
                turns += 1; precondition(turns < 2000)
            } while position.match_over == 0
            gnubg_native_destroy(engine)
            print("Swift bundled-engine smoke OK: \(turns) turns, \(position.score.0)-\(position.score.1)")
        } else {
            GNUbgApp.main()
        }
    }
}
