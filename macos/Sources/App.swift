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
        .accessibilityLabel("Point \(point + 1), \(count) \(owner == 0 ? "ivory" : "charcoal") checkers")
        .help("\(state.player == 0 ? "Ivory" : "Charcoal") coordinate: \(ownPoint + 1)")
    }
}

struct BoardView: View {
    @ObservedObject var model: EngineModel
    let position: Position
    var body: some View {
        let preview = position.preview(model.staged)
        VStack(spacing: 12) {
            HStack {
                Label("Ivory  \(position.scores[0])", systemImage: "circle.fill")
                Spacer()
                Text("Game \(position.raw.game_number) · \(position.raw.match_length) points\(position.raw.crawford != 0 ? " · Crawford" : "")")
                Spacer()
                Label("Charcoal  \(position.scores[1])", systemImage: "circle")
            }.font(.subheadline.weight(.semibold))
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(12..<24, id: \.self) { point in
                        PointView(point: point, top: true, state: preview, model: model)
                        if point == 17 { Divider().overlay(ink).padding(.horizontal, 5) }
                    }
                }
                HStack {
                    Button("Bar · Ivory \(preview.bars[0]) / Charcoal \(preview.bars[1])") { model.select(24) }
                        .tint(model.source == 24 ? .orange : teal)
                    Spacer()
                    Text(position.raw.dice.0 > 0 ? "⚄  \(position.raw.dice.0)   \(position.raw.dice.1)" : "Awaiting roll")
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Spacer()
                    Button("Off · Ivory \(preview.off[0]) / Charcoal \(preview.off[1])") { model.select(-1) }
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
                Text("\(position.player == 0 ? "Ivory" : "Charcoal"): select a checker, then a highlighted destination.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Undo selection") { model.staged = []; model.source = nil }.disabled(model.staged.isEmpty && model.source == nil)
                Button("Confirm move") { if let move = model.completeMove { model.play(move) } }
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
                    Text("A quiet place to play and explore.").foregroundColor(.secondary)
                }
                Spacer()
                Picker("Match", selection: $model.matchLength) {
                    ForEach([1, 3, 5, 7, 11], id: \.self) { Text("\($0) points").tag($0) }
                }.frame(width: 160)
                Toggle("Computer opponent", isOn: $model.computer).toggleStyle(.checkbox)
                Button("New match") { confirmNew = true }.disabled(model.busy)
            }
            HStack(alignment: .top, spacing: 22) {
                if let position = model.position {
                    BoardView(model: model, position: position)
                        .disabled(model.busy || position.raw.game_over != 0 || position.raw.computer_turn != 0)
                } else {
                    ProgressView("Preparing board…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                sidebar.frame(width: 245)
            }
            HStack(spacing: 10) {
                Circle().fill(model.busy ? Color.orange : teal).frame(width: 8, height: 8)
                Text(model.status).font(.callout).textSelection(.enabled)
                Spacer()
                Text("Offline · GNUbg \(String(cString: gnubg_native_version()))").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 1060, minHeight: 720)
        .background(Color(red: 0.97, green: 0.96, blue: 0.93))
        .tint(teal)
        .preferredColorScheme(.light)
        .confirmationDialog("Start a new match? Current match progress will be discarded.", isPresented: $confirmNew) {
            Button("Start new match") { model.newMatch() }
        }
    }
    @ViewBuilder private var sidebar: some View {
        let p = model.position?.raw
        let playing = p?.game_over == 0
        let human = p?.computer_turn == 0
        let decision = p?.doubled != 0 || p?.resignation != 0
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR TABLE").font(.caption.weight(.bold)).foregroundColor(teal)
            Text(model.turnDescription).font(.headline)
            HStack {
                Text("Cube \(p?.cube_value ?? 1)").font(.title2.bold())
                Spacer()
                Text(p?.cube_owner == -1 ? "Centered" : (p?.cube_owner == 0 ? "Ivory owns" : "Charcoal owns")).font(.caption)
            }
            if p?.doubled != 0 {
                HStack {
                    Button("Take") { model.act(GNUBG_NATIVE_TAKE) }
                    Button("Drop") { model.act(GNUBG_NATIVE_DROP) }
                }.disabled(model.busy || !human)
            } else if p?.resignation != 0 {
                HStack {
                    Button("Accept") { model.act(GNUBG_NATIVE_ACCEPT_RESIGNATION) }
                    Button("Reject") { model.act(GNUBG_NATIVE_REJECT_RESIGNATION) }
                }.disabled(model.busy || !human)
            } else if p?.game_over != 0 {
                Button("Next game") { model.act(GNUBG_NATIVE_NEXT_GAME) }
                    .disabled(model.busy || p?.match_over != 0)
            } else {
                HStack {
                    Button("Roll dice") { model.roll() }.buttonStyle(.borderedProminent)
                        .disabled(model.busy || !human || p?.dice.0 != 0)
                    Button("Double") { model.act(GNUBG_NATIVE_DOUBLE) }
                        .disabled(model.busy || !human || p?.can_double == 0)
                }
                HStack {
                    Button("Hint") { model.hint() }.disabled(model.busy || !human || model.moves.isEmpty)
                    Menu("Resign") {
                        ForEach(1...3, id: \.self) { points in Button("\(points) × cube") { model.resign(points) } }
                    }.disabled(model.busy || !human)
                }
                if !human {
                    Button("Play computer turn") { model.act(GNUBG_NATIVE_COMPUTER_TURN) }.disabled(model.busy)
                }
            }
            Divider()
            Text("ANALYSIS").font(.caption.weight(.bold)).foregroundColor(teal)
            Text(model.analysisText).font(.callout.monospacedDigit()).textSelection(.enabled)
            Picker("Trials", selection: $model.trials) {
                ForEach([36, 1296, 5184], id: \.self) { Text("\($0)").tag($0) }
            }.disabled(model.busy)
            HStack {
                Button("Evaluate") { model.analyse(rollout: false) }
                Button("Rollout") { model.analyse(rollout: true) }
            }.disabled(model.busy || !playing || decision)
            if model.analysing {
                ProgressView(value: model.progress)
                Button("Cancel analysis") { model.cancel() }
            }
            Divider()
            Text("LEGAL MOVES · \(model.moves.count)").font(.caption.weight(.bold)).foregroundColor(teal)
            Text("Choose a complete move here, or use the board. Points in this list use the moving player's coordinates.")
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
        if CommandLine.arguments.contains("--model-smoke") {
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
