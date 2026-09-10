import SwiftUI

// MARK: - Reviewing Student Statistics

/// Attempt history table with summary, clear, and review actions.
/// Title, speed switcher, and actions live in the native window toolbar
/// (same pattern as the lesson page); the content itself stays matte —
/// summary line plus table, no glass panels.
/// Mirrors `_stats_ui()` / `refresh_stats()` in `main.py`.
struct StatsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.speedUnit) private var speedUnit
    @Bindable var state: AppState
    @State private var showingClearConfirm = false

    var body: some View {
        VStack(spacing: 12) {
            // Plain page title — in content, not the toolbar, so no glass
            // pill ever sits behind it.
            Text(state.t("your_progress"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(state.historySummary)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            Table(historyRows, selection: $state.selectedHistoryID) {
                TableColumn(state.t("date"), value: \.dateString)
                TableColumn(state.t("lesson"), value: \.lesson)
                TableColumn(state.t(speedUnit.unitKey)) { row in Text(row.speedString) }
                TableColumn(state.t("accuracy")) { row in Text(row.accuracyString) }
                TableColumn(state.t("done")) { row in Text(row.doneString) }
                TableColumn(state.t("errors")) { row in Text("\(row.attempt.errors)") }
            }
            .onDoubleClick {
                openSelected()
            }
        }
        .padding(20)
        .toolbar {
            ToolbarItem {
                Picker("", selection: Binding(get: { state.speedUnit }, set: { state.setSpeedUnit($0) })) {
                    Text(state.t(SpeedUnit.wpm.unitKey)).tag(SpeedUnit.wpm)
                    Text(state.t(SpeedUnit.cpm.unitKey)).tag(SpeedUnit.cpm)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: openSelected) {
                    Label(state.t("review_selected"), systemImage: "magnifyingglass")
                }
                .disabled(state.selectedHistoryID == nil)
            }
            ToolbarItem {
                Button { showingClearConfirm = true } label: {
                    Label(state.t("clear_history"), systemImage: "trash")
                }
                .disabled(state.history.isEmpty)
            }
        }
        .background(
            ToolbarPrioritySetter(priorities: [.standard, .user, .low])
                .frame(width: 0, height: 0)
        )
        .confirmationDialog(
            state.t("clear_history_title"),
            isPresented: $showingClearConfirm,
            titleVisibility: .visible
        ) {
            Button(state.t("clear_history"), role: .destructive, action: state.clearHistory)
            Button(state.t("cancel"), role: .cancel) {}
        } message: {
            Text(state.t("clear_history_body"))
        }
    }

    // MARK: - Private

    private var historyRows: [HistoryRow] {
        state.history.reversed().map { attempt in
            HistoryRow(
                id: attempt.id,
                dateString: attempt.finishedAt.replacingOccurrences(of: "T", with: " "),
                lesson: attempt.lesson,
                speedString: speedUnit.format(attempt.wpm),
                accuracyString: String(format: "%.1f%%", attempt.accuracy),
                doneString: String(format: "%.0f%%", attempt.done),
                attempt: attempt
            )
        }
    }

    private func openSelected() {
        guard let id = state.selectedHistoryID,
            let attempt = state.history.first(where: { $0.id == id })
        else { return }
        state.resultsAttempt = attempt
    }
}

// MARK: - Private

private struct HistoryRow: Identifiable {
    var id: UUID
    var dateString: String
    var lesson: String
    var speedString: String
    var accuracyString: String
    var doneString: String
    var attempt: Attempt
}

private extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            TapGesture(count: 2).onEnded(action)
        )
    }
}
