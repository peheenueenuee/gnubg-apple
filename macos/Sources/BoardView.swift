import SwiftUI

struct CheckerView: View {
    let player: Int
    var highlighted = false
    var body: some View {
        Circle()
            .fill(player == 0 ? Color(red: 0.98, green: 0.94, blue: 0.82) : ink)
            .overlay(Circle().stroke(highlighted ? Color.orange : .black.opacity(0.3), lineWidth: highlighted ? 3 : 1))
            .shadow(color: highlighted ? .orange.opacity(0.65) : .black.opacity(0.12), radius: highlighted ? 4 : 1)
            .frame(width: 32, height: 32)
            .fixedSize()
    }
}

struct PointView: View {
    let point: Int // Coordinates from the viewer's side, independent of checker color.
    let top: Bool
    let state: Position
    @ObservedObject var model: EngineModel
    private var viewer: Int { model.humanPlayer }
    private var ownPoint: Int { state.player == viewer ? point : 23 - point }
    private var owner: Int { state.points[viewer][point] > 0 ? viewer : 1 - viewer }
    private var ownerPoint: Int { owner == viewer ? point : 23 - point }
    private var count: Int { state.points[owner][ownerPoint] }
    private var destination: Bool { model.nextSteps.contains { $0.from == model.source && $0.to == ownPoint } }
    private var selectable: Bool { model.canInteractBoard && model.nextSteps.contains { $0.from == ownPoint } }
    private var highlighted: Int { model.highlightedCheckers(player: owner, point: ownerPoint) }
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
                            CheckerView(player: owner, highlighted: highlighted > 0 && index >= min(count, 5) - min(highlighted, 5))
                                .overlay {
                                    if index == 4 && count > 5 {
                                        Text("\(count)").font(.caption.bold()).foregroundColor(owner == 0 ? ink : .white)
                                    }
                                }
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
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canInteractBoard)
        .accessibilityLabel(L10n.text("board.point_accessibility", point + 1, count, L10n.player(owner)))
        .help(L10n.text("board.coordinate", L10n.player(state.player), ownPoint + 1))
    }
}

struct DieFace: View {
    let value: Int?
    let player: Int
    var used = false
    private var pips: [(CGFloat, CGFloat)] {
        switch value {
        case 1: return [(0.5, 0.5)]
        case 2: return [(0.25, 0.25), (0.75, 0.75)]
        case 3: return [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)]
        case 4: return [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
        case 5: return [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)]
        case 6: return [(0.25, 0.25), (0.75, 0.25), (0.25, 0.5), (0.75, 0.5), (0.25, 0.75), (0.75, 0.75)]
        default: return []
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(used ? Color.gray.opacity(0.3) : (player == 0 ? Color.white : ink))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 2)
                ForEach(pips.indices, id: \.self) { index in
                    Circle().fill(used ? Color.gray : (player == 0 ? ink : Color.white))
                        .frame(width: 7, height: 7)
                        .position(x: geometry.size.width * pips[index].0, y: geometry.size.height * pips[index].1)
                }
                if value == nil { Text("–").foregroundColor(player == 0 ? ink : .white) }
            }
        }
        .frame(width: 42, height: 42)
        .opacity(used ? 0.6 : 1)
        .accessibilityLabel(value.map { L10n.text(used ? "dice.used_value" : "dice.value", $0) } ?? L10n.text("board.awaiting_roll"))
    }
}

struct DicePanel: View {
    @ObservedObject var model: EngineModel
    let player: Int
    private var values: [Int]? { model.diceValues(player: player) }
    var body: some View {
        VStack(spacing: 6) {
            Text(L10n.text(player == model.humanPlayer ? "dice.you" : "dice.opponent", L10n.player(player)))
                .font(.caption.weight(.bold))
            ZStack {
                HStack(spacing: 8) {
                    ForEach(model.displayedDice(player: player).indices, id: \.self) { index in
                        DieFace(value: model.displayedDice(player: player)[index], player: player,
                                used: model.diceAreCurrent(player: player) && model.usedDiceIndices.contains(index))
                    }
                }
                .accessibilityHidden(model.canRoll(player: player))
                if model.canRoll(player: player) {
                    Button(L10n.text("game.roll")) { model.roll() }
                        .buttonStyle(.borderedProminent)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                }
            }.frame(height: 48)
            Text(L10n.text(model.diceAreCurrent(player: player) ? "dice.current" : (values == nil ? "board.awaiting_roll" : "dice.previous")))
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

struct BarView: View {
    @ObservedObject var model: EngineModel
    let state: Position
    private func stack(player: Int) -> some View {
        Button { model.select(24) } label: {
            VStack(spacing: 4) {
                ForEach(0..<min(state.bars[player], 4), id: \.self) { _ in
                    CheckerView(player: player)
                }
                if state.bars[player] == 0 {
                    Circle().stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3]))
                        .frame(width: 32, height: 32)
                }
                Text("\(state.bars[player])").font(.caption.monospacedDigit()).foregroundColor(.white)
            }
            .padding(4)
            .background(state.player == player && model.source == 24 ? Color.orange.opacity(0.6) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!model.canInteractBoard || state.player != player || state.bars[player] == 0)
        .accessibilityLabel(L10n.text("bar.checkers", L10n.player(player), state.bars[player]))
    }
    var body: some View {
        VStack(spacing: 6) {
            stack(player: 1 - model.humanPlayer)
            Spacer(minLength: 6)
            CubeView(model: model, state: state)
            Spacer(minLength: 6)
            stack(player: model.humanPlayer)
        }
        .padding(.vertical, 12)
        .frame(width: 54)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.32, green: 0.23, blue: 0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}

// Stored checkers are shown edge-on, like the rack on a physical board.
struct OffTray: View {
    @ObservedObject var model: EngineModel
    let state: Position
    private func rack(_ player: Int) -> some View {
        VStack(spacing: 5) {
            Text(L10n.player(player)).font(.caption2).foregroundColor(.white.opacity(0.8))
            VStack(spacing: 3) {
                ForEach(0..<state.off[player], id: \.self) { _ in
                    Capsule()
                        .fill(player == 0 ? Color(red: 0.98, green: 0.94, blue: 0.82) : ink)
                        .overlay(Capsule().stroke(.black.opacity(0.4), lineWidth: 1))
                        .frame(width: 32, height: 7)
                }
                Spacer(minLength: 0)
            }.frame(height: 150)
            Text("\(state.off[player]) / 15").font(.caption2.monospacedDigit()).foregroundColor(.white)
        }
        .padding(.vertical, 10).frame(width: 52)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(
            (model.canBearOff && state.player == player) || model.highlightedCheckers(player: player, point: -1) > 0
                ? Color.orange : Color.white.opacity(0.15), lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("tray.checkers", L10n.player(player), state.off[player]))
    }
    @ViewBuilder private func storage(_ player: Int) -> some View {
        if model.canBearOff && state.player == player {
            Button { model.select(-1) } label: { rack(player) }
                .buttonStyle(.plain).help(L10n.text("move.off"))
        } else {
            rack(player)
        }
    }
    var body: some View {
        VStack(spacing: 8) {
            storage(1 - model.humanPlayer)
            Spacer(minLength: 8)
            storage(model.humanPlayer)
        }
        .padding(6)
        .background(Color(red: 0.32, green: 0.23, blue: 0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BoardView: View {
    @ObservedObject var model: EngineModel
    let position: Position
    private var preview: Position { model.displayPosition ?? position }
    private func row(_ points: [Int], top: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(points, id: \.self) { point in
                PointView(point: point, top: top, state: preview, model: model)
            }
        }.frame(minHeight: 195)
    }
    private var board: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                row(Array(12..<18), top: true)
                DicePanel(model: model, player: 1 - model.humanPlayer).frame(height: 100)
                row(Array((6..<12).reversed()), top: false)
            }
            BarView(model: model, state: preview)
            VStack(spacing: 8) {
                row(Array(18..<24), top: true)
                DicePanel(model: model, player: model.humanPlayer).frame(height: 100)
                row(Array((0..<6).reversed()), top: false)
            }
            OffTray(model: model, state: preview)
        }
        .padding(14)
        .background(Color(red: 0.91, green: 0.86, blue: 0.73), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ink.opacity(0.25), lineWidth: 5))
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(L10n.text("board.score", L10n.player(1 - model.humanPlayer), position.scores[1 - model.humanPlayer]))
                Spacer()
                Text(L10n.text("board.game", position.raw.game_number, position.raw.match_length, position.raw.crawford != 0 ? L10n.text("board.crawford") : ""))
                Spacer()
                Text(L10n.text("board.score", L10n.player(model.humanPlayer), position.scores[model.humanPlayer]))
            }.font(.subheadline.weight(.semibold))
            board
        }
    }
}
