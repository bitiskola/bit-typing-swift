import Charts
import SwiftUI

// MARK: - Celebrating Completion

/// Three-second "Well done!" overlay shown while results are prepared.
/// Mirrors `WellDoneDialog` in `main.py`.
struct WellDoneView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.ink(scheme))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(scheme == .dark ? .black : .white)
            }
            Text(state.t("well_done"))
                .font(.system(size: 28, weight: .bold))
            Text(state.t("results_loading"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted(scheme))
        }
        .frame(width: 480, height: 330)
        .background(Theme.panel(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border(scheme), lineWidth: 1))
    }
}

// MARK: - Showing Lesson Results

/// Score header, gauge rows, and Overview / Details / Errors tabs with
/// per-character speed chart and colored error transcript.
/// Mirrors `ResultsPage` in `main.py`.
struct ResultsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.speedUnit) private var speedUnit
    @Bindable var state: AppState
    var attempt: Attempt

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            gauges
            tabPicker
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 760, height: 620)
        .background(Theme.background(scheme))
        // Analysis always reads in CPM, regardless of the global WPM/CPM
        // switcher — gauges and the speed chart below both resolve through
        // `speedUnit`.
        .environment(\.speedUnit, .cpm)
    }

    // MARK: - Private

    private var score: Double { state.overallScore(for: attempt) }

    private var header: some View {
        HStack {
            Text(state.t("lesson_results"))
                .font(.system(size: 24, weight: .bold))
            Spacer()
            Text(String(format: "%.0f%%", score))
                .font(.system(size: 20, weight: .bold))
            StarsView(score: score)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var gauges: some View {
        Card {
            VStack(spacing: 2) {
                GaugeView(
                    label: state.t("overall_score"), display: String(format: "%.0f%%", score),
                    quality: score / 100, tint: Theme.brand(scheme)
                )
                GaugeView(
                    label: state.t("speed").capitalized,
                    display: "\(speedUnit.format(attempt.wpm)) \(state.t(speedUnit.unitKey))",
                    quality: min(1, attempt.wpm / max(1, state.settings.goalWpm))
                )
                GaugeView(
                    label: state.t("accuracy").capitalized, display: String(format: "%.1f%%", attempt.accuracy),
                    quality: attempt.accuracy / 100
                )
                GaugeView(
                    label: state.t("slowdown"), display: String(format: "%.1f%%", attempt.slowdown),
                    quality: 1 - attempt.slowdown / 100
                )
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 24)
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Button { selectedTab = index } label: {
                    Label(tabName(index), systemImage: tabIcon(index))
                }
                .buttonStyle(index == selectedTab ? .appPrimary : .appSecondary)
            }
        }
        .padding(.vertical, 10)
    }

    private func tabName(_ index: Int) -> String {
        switch index {
        case 0: return state.t("overview")
        case 1: return state.t("detailed_statistics")
        default: return state.t("errors_overview")
        }
    }

    private func tabIcon(_ index: Int) -> String {
        switch index {
        case 0: return "doc.text"
        case 1: return "chart.bar"
        default: return "exclamationmark.triangle"
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0: overviewTab
        case 1: detailsTab
        default: errorsTab
        }
    }

    private var overviewTab: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(attempt.passed ? state.t("passed_tip") : state.t("retry_tip"))
                    .font(.system(size: 16, weight: .bold))
                Text(
                    "\(state.t("characters")): \(attempt.characters)     \(state.t("words")): \(attempt.words)     "
                        + "\(state.t("errors")): \(attempt.errors)     \(state.t("timeouts")): \(attempt.timeouts)\n"
                        + "\(state.t("fixed_characters")): \(attempt.fixedCharacters)     "
                        + "\(state.t("fixed_words")): \(attempt.fixedWords)     "
                        + "\(state.t("backspaces")): \(attempt.backspaces)     "
                        + "\(state.t("duration")): \(String(format: "%.1fs", attempt.duration))"
                )
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted(scheme))
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .padding(.horizontal, 24)
    }

    private var detailsTab: some View {
        Card {
            PerCharacterChart(state: state, attempt: attempt)
                .padding(18)
        }
        .padding(.horizontal, 24)
    }

    private var errorsTab: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                legend
                ScrollView {
                    errorTranscript
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            ForEach(legendItems, id: \.0) { color, label in
                Text("●").foregroundStyle(color).font(.system(size: 16, weight: .bold))
                Text(label).font(.system(size: 13))
                Spacer().frame(width: 12)
            }
        }
    }

    private var legendItems: [(Color, String)] {
        [
            (Theme.ink(scheme), state.t("legend_correct")),
            (Theme.muted(scheme), state.t("legend_slow")),
            (Theme.error(scheme), state.t("legend_error")),
            (Theme.errorTimeout(scheme), state.t("legend_error_slow")),
        ]
    }

    private var errorTranscript: Text {
        attempt.text.enumerated().reduce(Text("")) { partial, pair in
            let color: Color = switch attempt.state(at: pair.offset) {
            case .timeout: Theme.muted(scheme)
            case .error: Theme.error(scheme)
            case .errorTimeout: Theme.errorTimeout(scheme)
            default: Theme.ink(scheme)
            }
            return partial + Text(String(pair.element)).foregroundStyle(color)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                state.resultsAttempt = nil
                state.returnToLesson()
            } label: {
                Label(state.t("return_home"), systemImage: "keyboard")
            }
            .buttonStyle(.appSecondary)
            if let next = state.nextLessonURL(for: attempt) {
                Button {
                    state.resultsAttempt = nil
                    state.openLesson(url: next)
                } label: {
                    Label(state.t("next_lesson"), systemImage: "arrow.right")
                }
                .buttonStyle(.appBrand)
            }
        }
        .padding(16)
    }
}

// MARK: - Charting Report Metrics

/// Chart metric switchable from the dropdown above the chart.
private enum ChartMetric: String, CaseIterable {
    case speed
    case accuracyChar
    case accuracyWord
}

/// Native Swift Charts bar chart with a metric dropdown: per-character
/// speed (correctly converted to the selected WPM/CPM unit), accuracy per
/// character, or accuracy per word (worst first). Characters typed with
/// errors stay red; the noisy per-series legend is hidden.
private struct PerCharacterChart: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.speedUnit) private var speedUnit
    @Bindable var state: AppState
    var attempt: Attempt

    @State private var metric: ChartMetric = .speed

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("", selection: $metric) {
                    ForEach(ChartMetric.allCases, id: \.self) { mode in
                        Text(metricLabel(mode)).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 240)
                Spacer()
            }
            if rows.isEmpty {
                Text("—").foregroundStyle(Theme.muted(scheme))
            } else {
                Chart {
                    ForEach(cleanRows) { row in
                        BarMark(
                            x: .value("Item", row.label),
                            y: .value(yLabel, row.value)
                        )
                        .foregroundStyle(by: .value("Item", row.label))
                        .annotation(position: .top) {
                            Text(row.display)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.muted(scheme))
                        }
                    }
                    ForEach(errorRows) { row in
                        BarMark(
                            x: .value("Item", row.label),
                            y: .value(yLabel, row.value)
                        )
                        .foregroundStyle(Theme.error(scheme))
                        .annotation(position: .top) {
                            Text(row.display)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.error(scheme))
                        }
                    }
                }
                .chartYAxisLabel(yLabel)
                .chartLegend(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 6) {
                    Text("●").foregroundStyle(Theme.error(scheme))
                    Text(state.t("legend_error")).font(.system(size: 12))
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private struct Row: Identifiable {
        var id: String { label }
        var label: String
        var value: Double
        var display: String
        var hasErrors: Bool
    }

    private var cleanRows: [Row] { rows.filter { !$0.hasErrors } }
    private var errorRows: [Row] { rows.filter(\.hasErrors) }

    private var rows: [Row] {
        switch metric {
        case .speed: return speedRows
        case .accuracyChar: return accuracyCharRows
        case .accuracyWord: return accuracyWordRows
        }
    }

    private var yLabel: String {
        metric == .speed ? state.t(speedUnit.unitKey) : "%"
    }

    private func metricLabel(_ mode: ChartMetric) -> String {
        switch mode {
        case .speed:
            return state.t("speed").capitalized
        case .accuracyChar:
            return "\(state.t("accuracy").capitalized) · \(state.t("characters"))"
        case .accuracyWord:
            return "\(state.t("accuracy").capitalized) · \(state.t("words"))"
        }
    }

    /// Per-character speed. The base is CPM (60 / avg delay in seconds),
    /// so WPM display divides by 5 — the shared `factor` converts the
    /// other way (WPM base to CPM) and must not be used here.
    private var speedRows: [Row] {
        let strokes = attempt.strokes.filter { !$0.systemKey && !$0.expected.isEmpty }
        var groups: [String: [Stroke]] = [:]
        var order: [String] = []
        for stroke in strokes {
            if groups[stroke.expected] == nil { order.append(stroke.expected) }
            groups[stroke.expected, default: []].append(stroke)
        }
        let factor = speedUnit == .cpm ? 1.0 : 0.2
        return Array(order.prefix(18)).map { char in
            let charStrokes = groups[char] ?? []
            let avg = charStrokes.map(\.delay).reduce(0, +) / Double(max(1, charStrokes.count))
            let value = 60 / max(0.01, avg) * factor
            return Row(
                label: prettyChar(char),
                value: value,
                display: String(format: "%.0f", value),
                hasErrors: charStrokes.contains { !$0.correct }
            )
        }
    }

    /// Accuracy per character, worst first.
    private var accuracyCharRows: [Row] {
        let strokes = attempt.strokes.filter { !$0.systemKey && !$0.expected.isEmpty }
        var groups: [String: [Stroke]] = [:]
        for stroke in strokes {
            groups[stroke.expected, default: []].append(stroke)
        }
        return groups.map { char, charStrokes in
            let correct = charStrokes.filter(\.correct).count
            let value = Double(correct) / Double(max(1, charStrokes.count)) * 100
            return Row(
                label: prettyChar(char),
                value: value,
                display: String(format: "%.0f%%", value),
                hasErrors: correct < charStrokes.count
            )
        }
        .sorted { $0.value < $1.value }
        .prefix(18)
        .map { $0 }
    }

    /// Accuracy per word (occurrences aggregated), worst first.
    private var accuracyWordRows: [Row] {
        let chars = Array(attempt.text)
        var totals: [String: (total: Int, bad: Int)] = [:]
        var word = ""
        var indices: [Int] = []
        func flush() {
            guard !word.isEmpty else { return }
            let bad = indices.filter { attempt.state(at: $0) == .error || attempt.state(at: $0) == .errorTimeout }.count
            totals[word, default: (0, 0)].total += indices.count
            totals[word, default: (0, 0)].bad += bad
            word = ""
            indices = []
        }
        for (offset, char) in chars.enumerated() {
            if char.isWhitespace {
                flush()
            } else {
                word.append(char)
                indices.append(offset)
            }
        }
        flush()
        return totals.map { text, counts in
            let value = Double(counts.total - counts.bad) / Double(max(1, counts.total)) * 100
            let label = text.count > 12 ? String(text.prefix(12)) + "…" : text
            return Row(
                label: label,
                value: value,
                display: String(format: "%.0f%%", value),
                hasErrors: counts.bad > 0
            )
        }
        .sorted { $0.value < $1.value }
        .prefix(18)
        .map { $0 }
    }

    private func prettyChar(_ char: String) -> String {
        char == " " ? "␠" : char == "\n" ? "↵" : char == "\t" ? "⇥" : char
    }
}
