import SwiftUI

// MARK: - Managing Course Packs

/// Course pack manager, ported from `repos_page` in the Rust version:
/// every configured pack with its lesson count and a remove action, plus
/// Add / Refresh all in the window toolbar. The built-in pack (★) can't be
/// removed. Lessons are filtered by the active keyboard layout.
struct ReposView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var state: AppState
    @State private var showingAdd = false
    @State private var pendingRemoval: RepoSummary? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.t("course_repos"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink(scheme))
            // No `.fixedSize(vertical:)` here: inside this full-height
            // frame it gives the split view an unbounded ideal height and
            // the whole window (sidebar included) renders blank.
            Text(state.t("course_repos_tip"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted(scheme))
            if !state.repoStatus.isEmpty {
                Text(state.repoStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted(scheme))
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            List(state.repoSummaries) { repo in
                RepoRow(state: state, repo: repo) { pendingRemoval = repo }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.panel(scheme))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItem {
                Button(action: state.refreshRepos) {
                    if state.refreshingRepos {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(state.t("refresh_all"), systemImage: "arrow.clockwise")
                    }
                }
                .disabled(state.refreshingRepos)
                .help(state.t("refresh_all"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.repoStatus = ""
                    showingAdd = true
                } label: {
                    Label(state.t("add_repo"), systemImage: "plus")
                }
                .disabled(state.refreshingRepos)
            }
        }
        .background(
            ToolbarPrioritySetter(priorities: [.standard, .user])
                .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $showingAdd) {
            AddRepoSheet(state: state)
        }
        .confirmationDialog(
            state.t("remove"),
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { repo in
            Button(state.t("remove"), role: .destructive) { state.removeRepo(repo.url) }
            Button(state.t("cancel"), role: .cancel) {}
        } message: { repo in
            Text("\(repo.name)\n\(repo.url)")
        }
    }
}

// MARK: - Private

private struct RepoRow: View {
    @Environment(\.colorScheme) private var scheme
    var state: AppState
    var repo: RepoSummary
    var onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: repo.isDefault ? "star.fill" : "shippingbox")
                .foregroundStyle(repo.isDefault ? Theme.brand(scheme) : Theme.muted(scheme))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink(scheme))
                    if !repo.creator.isEmpty {
                        Text("· \(repo.creator)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted(scheme))
                    }
                }
                Text(repo.url)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted(scheme))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(countText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted(scheme))
            }
            Spacer()
            Button(action: onRemove) {
                Label(state.t("remove"), systemImage: "trash")
            }
            .buttonStyle(.appSecondary)
            .controlSize(.small)
            .disabled(repo.isDefault || state.refreshingRepos)
            .help(repo.isDefault ? state.t("repo_default_locked") : state.t("remove"))
        }
        .padding(.vertical, 6)
    }

    private var countText: String {
        guard repo.downloaded else { return state.t("repo_not_downloaded") }
        return state.t("repo_lessons", args: [
            "count": "\(repo.matchingCount)",
            "layout": state.settings.keyboardLayout,
            "total": "\(repo.totalCount)",
        ])
    }
}

/// URL prompt. Stays open with the error when cloning fails, closes on success.
private struct AddRepoSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AppState
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.t("add_repo"))
                .font(.system(size: 20, weight: .bold))
            TextField(state.t("repo_url_hint"), text: $url)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
                .disabled(state.refreshingRepos)
            if state.refreshingRepos {
                ProgressView()
                    .controlSize(.small)
            } else if !state.repoStatus.isEmpty {
                Text(state.repoStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.error(scheme))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(state.t("cancel")) { dismiss() }
                    .buttonStyle(.appSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(action: add) {
                    Label(state.t("add_repo"), systemImage: "plus")
                }
                .buttonStyle(.appPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(state.refreshingRepos || url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(Theme.background(scheme))
        .onAppear { state.repoStatus = "" }
    }

    private func add() {
        Task {
            if await state.addRepo(url) { dismiss() }
        }
    }
}
