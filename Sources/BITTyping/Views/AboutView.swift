import SwiftUI

// MARK: - Showing App Information

/// About sheet with brand, version, website, and contributor cards.
/// Mirrors `AboutPage` in `main.py`.
struct AboutView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(state.t("about_bit_typing"))
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button(state.t("close")) { dismiss() }
                    .buttonStyle(.appSecondary)
            }
            .padding(20)
            ScrollView {
                VStack(spacing: 10) {
                    Image(nsImage: NSImage.bitAppIcon)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    Text("BIT Typing")
                        .font(.system(size: 26, weight: .bold))
                    Text("\(state.t("version")) 2.0.0")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.muted(scheme))
                    Text(state.t("about_description"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted(scheme))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                    Button {
                        if let url = URL(string: "https://bitiskola.github.io/bit-typing") {
                            openURL(url)
                        }
                    } label: {
                        Label("\(state.t("website")): bitiskola.github.io/bit-typing", systemImage: "globe")
                    }
                    .buttonStyle(.appSecondary)
                    .padding(.bottom, 8)
                    Text(state.t("developers_contributors"))
                        .font(.system(size: 18, weight: .bold))
                    HStack(spacing: 12) {
                        TeamCard(name: "micr0softstore", role: state.t("maintainer_developer"), initials: "MS")
                        TeamCard(name: "cacto.tsx", role: state.t("icon_designer"), initials: "C")
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 620, height: 600)
        .background(Theme.background(scheme))
    }
}

// MARK: - Private

private struct TeamCard: View {
    @Environment(\.colorScheme) private var scheme
    var name: String
    var role: String
    var initials: String

    var body: some View {
        Card {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Theme.panel2(scheme))
                        .frame(width: 84, height: 84)
                    Text(initials)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.ink(scheme))
                }
                .padding(.top, 14)
                Text(name)
                    .font(.system(size: 16, weight: .bold))
                Text(role)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted(scheme))
                    .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(name), \(role)"))
    }
}
