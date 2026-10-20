import SwiftUI

struct StatusPanel: View {
    @ObservedObject var model: EngineModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("panel.status")).font(.caption.bold()).foregroundColor(teal)
            if let result = model.matchResult {
                Label(result, systemImage: model.didHumanWin == true ? "trophy.fill" : "flag.checkered")
                    .font(.title2.bold())
                    .foregroundColor(model.didHumanWin == true ? teal : ink)
            } else if model.position != nil {
                Text(model.turnDescription).font(.headline)
            }
            if model.busy && !model.analysing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(model.position == nil ? model.status : L10n.text("status.working"))
                }.font(.callout)
            } else if model.status != model.turnDescription {
                Text(model.status).font(.callout).textSelection(.enabled)
            }
            if model.hoveredMove != nil {
                Label(L10n.text("move.preview"), systemImage: "eye").font(.caption).foregroundColor(teal)
            }
            if let turn = model.lastOpponentTurn {
                Divider()
                Text(L10n.text("move.last_opponent", turn.move.steps.isEmpty ? L10n.text("move.pass") : turn.move.label))
                    .font(.caption).foregroundColor(.secondary).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}

struct CubeView: View {
    @ObservedObject var model: EngineModel
    let state: Position
    private var owner: Int { Int(state.raw.cube_owner) }
    private var ownership: String {
        owner < 0 ? L10n.text("cube.centered") : L10n.text("cube.owner", L10n.player(owner))
    }
    var body: some View {
        VStack(spacing: 4) {
            Triangle(top: false)
                .fill(owner == 1 - model.humanPlayer ? Color.orange : Color.white.opacity(owner < 0 ? 0.45 : 0.08))
                .frame(width: 16, height: 8)
            Text("\(state.raw.cube_value)")
                .font(.title3.bold().monospacedDigit())
                .foregroundColor(ink)
                .frame(width: 36, height: 36)
                .background(Color(red: 0.98, green: 0.94, blue: 0.82), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.3)))
                .overlay(alignment: .topTrailing) {
                    if state.raw.doubled != 0 {
                        Circle().fill(Color.orange).frame(width: 8, height: 8).offset(x: 3, y: -3)
                    }
                }
            Triangle(top: true)
                .fill(owner == model.humanPlayer ? Color.orange : Color.white.opacity(owner < 0 ? 0.45 : 0.08))
                .frame(width: 16, height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("cube.description", state.raw.cube_value, ownership))
        .help(state.raw.doubled != 0
              ? L10n.text("cube.offered", Int(state.raw.cube_value) * 2, ownership)
              : L10n.text("cube.description", state.raw.cube_value, ownership))
    }
}
