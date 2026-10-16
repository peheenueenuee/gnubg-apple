import SwiftUI
import AppKit
import GNUbgNative

let ink = Color(red: 0.13, green: 0.21, blue: 0.23)
let teal = Color(red: 0.12, green: 0.43, blue: 0.41)

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
                Picker(L10n.text("color.label"), selection: $model.colorChoice) {
                    ForEach(PlayerColorChoice.allCases) { choice in Text(choice.label).tag(choice) }
                }.frame(width: 170).help(L10n.text("color.next_match"))
                Toggle(L10n.text("match.computer"), isOn: $model.computer).toggleStyle(.checkbox)
                Button(L10n.text("match.new")) { confirmNew = true }.disabled(model.busy)
            }
            HStack(alignment: .top, spacing: 22) {
                if let position = model.position {
                    BoardView(model: model, position: position)
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
                            .onHover { model.hover(move, active: $0) }
                            .onDisappear { model.hover(move, active: false) }
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
