import SwiftUI
import UniformTypeIdentifiers

// MARK: - Editing Lessons

/// Custom lesson editor: name field over a Liquid Glass text panel, with
/// the title and all actions in the native window toolbar (same pattern as
/// the lesson and stats pages).
/// Mirrors `_editor_ui()` in `main.py`.
struct EditorView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var state: AppState
    @State private var showingImporter = false
    @State private var pendingReplace = false

    var body: some View {
        VStack(spacing: 14) {
            // Plain page title — in content, not the toolbar, so no glass
            // pill ever sits behind it.
            Text(state.t("lesson_editor"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                TextField(state.t("lesson_name"), text: $state.editorName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                Spacer()
            }
            editorPanel
        }
        .padding(20)
        .toolbar {
            ToolbarItem {
                Button(action: state.newEditorLesson) {
                    Label(state.t("new"), systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { showingImporter = true } label: {
                    Label(state.t("import_custom_lesson"), systemImage: "square.and.arrow.down")
                }
            }
            ToolbarItem {
                Button(action: state.loadEditorFromSelection) {
                    Label(state.t("load_selected"), systemImage: "folder")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                GlassActionButton(title: state.t("save_lesson"), systemImage: "checkmark", prominent: true, action: save)
            }
        }
        .background(
            ToolbarPrioritySetter(priorities: [.standard, .standard, .standard, .user])
                .frame(width: 0, height: 0)
        )
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText, .text],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                state.importCourses(urls: urls)
                state.selectedTab = .editor
                state.loadEditorFromSelection()
            }
        }
        .confirmationDialog(
            state.t("replace_lesson_title"),
            isPresented: $pendingReplace,
            titleVisibility: .visible
        ) {
            Button(state.t("save_lesson")) { _ = state.saveEditorLesson(confirmReplace: false, alreadyConfirmed: true) }
            Button(state.t("cancel"), role: .cancel) {}
        } message: {
            Text(state.t("replace_lesson_body", args: ["name": state.editorName + ".txt"]))
        }
    }

    // MARK: - Private

    /// The text surface is the one glass element here: frosted panel, no
    /// hairline. Everything around it stays open.
    private var editorPanel: some View {
        TextEditor(text: $state.editorText)
            .font(.system(size: 15, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if #available(macOS 26, *) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.panel(scheme).opacity(0.6))
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.panel(scheme))
                }
            }
    }

    private func save() {
        // saveEditorLesson returns false without a notice when the name
        // already exists and confirmation is required.
        let ok = state.saveEditorLesson(confirmReplace: true)
        if !ok, state.noticeTitleKey == nil {
            pendingReplace = true
        }
    }
}
