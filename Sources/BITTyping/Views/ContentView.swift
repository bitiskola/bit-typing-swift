import AppKit
import SwiftUI

// MARK: - Showing the Main Window

/// App shell: native sidebar + detail. The sidebar is a plain `List` of
/// `NavigationLink`s — no buttons, no title — so the system draws the
/// Liquid Glass sidebar itself, traffic lights floating over it.
/// Ports `TypingApp._build()` in `main.py`.
struct ContentView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var state: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: selectionBinding) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    NavigationLink(value: tab) {
                        Label(tabTitle(tab), systemImage: iconName(tab))
                    }
                }
            }
            .listStyle(.sidebar)
            // Hidden title bar: rows start below the floating traffic
            // lights while the sidebar glass runs full height behind them.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 30)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 204, max: 280)
        } detail: {
            detailView
        }
        .background {
            if #available(macOS 26, *) {
                // Liquid Glass window: leave the system background alone so
                // the native toolbar and glass controls blend into it.
                Color.clear
            } else {
                Theme.background(scheme)
            }
        }
        .environment(\.speedUnit, state.speedUnit)
        .sheet(isPresented: $state.showingOptions) { OptionsView(state: state) }
        .sheet(isPresented: $state.showingAbout) { AboutView(state: state) }
        .sheet(item: $state.resultsAttempt) { attempt in ResultsView(state: state, attempt: attempt) }
        .sheet(isPresented: $state.showingWellDone) {
            WellDoneView(state: state)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $state.showingSetup) { SetupView(state: state) }
        .alert(item: $state.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
        .alert(item: $state.loadFailure) { failure in
            Alert(
                title: Text(state.t("lesson_load_failed_title")),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .frame(minWidth: 1050, minHeight: 760)
        .onAppear {
            // No native titlebar to grab, so the background itself drags.
            NSApp.windows.forEach { $0.isMovableByWindowBackground = true }
        }
    }

    // MARK: - Private

    private var selectionBinding: Binding<AppTab?> {
        Binding(get: { state.selectedTab }, set: { if let tab = $0 { state.selectedTab = tab } })
    }

    /// Detail fills the window with its own opaque background — deliberately
    /// no `backgroundExtensionEffect()`, so lesson colors (keyboard tints)
    /// never bleed through the sidebar or toolbar glass. Those stay clean
    /// system surfaces.
    private var detailView: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconName(_ tab: AppTab) -> String {
        switch tab {
        case .lesson: return "keyboard"
        case .stats: return "chart.bar"
        case .editor: return "square.and.pencil"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.selectedTab {
        case .lesson:
            LessonView(state: state)
        case .stats:
            StatsView(state: state)
        case .editor:
            EditorView(state: state)
        }
    }

    private func tabTitle(_ tab: AppTab) -> String {
        switch tab {
        case .lesson: return state.t("current_lesson")
        case .stats: return state.t("student_statistics")
        case .editor: return state.t("lesson_editor")
        }
    }
}

// MARK: - Private

private struct Notice: Identifiable {
    var id: String { title + message }
    var title: String
    var message: String
}

private extension AppState {
    var notice: Notice? {
        get {
            guard let key = noticeTitleKey, let message = noticeMessage else { return nil }
            return Notice(title: t(key), message: message)
        }
        set {
            if newValue == nil {
                noticeTitleKey = nil
                noticeMessage = nil
            }
        }
    }

    var loadFailure: Notice? {
        get {
            guard let message = loadError else { return nil }
            return Notice(title: "load", message: message)
        }
        set {
            if newValue == nil { loadError = nil }
        }
    }
}
