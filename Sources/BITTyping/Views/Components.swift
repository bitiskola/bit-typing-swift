import AppKit
import SwiftUI

// MARK: - Styling Primary Buttons

/// Native SwiftUI buttons with a Liquid Glass look.
///
/// Every tappable control in the app is a SwiftUI `Button` using one of
/// three presets — `.appPrimary` (ink), `.appSecondary` (neutral),
/// `.appBrand` (blue, for progress-linked actions like Pause / Next).
/// Same ergonomics as `.borderedProminent` / `.bordered`.
/// Capsule pills (fully rounded), 32pt default height, SF Pro
/// Regular (secondary) / Medium (primary, brand).
///
/// - macOS 26+: real Liquid Glass via `glassEffect(_:in:)`, tinted per
///   preset (ink / neutral / blue), `.interactive()` so press states come
///   from the system.
/// - Older macOS: monochrome pill fallback that approximates the same
///   hierarchy (solid fills, same heights/corner radius).
///
/// The style reads `colorScheme`, `isEnabled`, and `controlSize` from the
/// environment and owns all visual details; callers only pick the preset.
struct AppButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var hovering = false
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(macOS 26, *) {
                GlassButtonLabel(
                    configuration: configuration,
                    kind: kind,
                    scheme: scheme,
                    font: labelFont,
                    height: controlHeight
                )
            } else {
                LegacyButtonLabel(
                    configuration: configuration,
                    kind: kind,
                    scheme: scheme,
                    font: labelFont,
                    height: controlHeight
                )
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        // Pressed: shrink slightly. Hovered: lift the fill a touch. Both
        // animate so every button in the app feels tactile.
        .scaleEffect(configuration.isPressed ? 0.97 : hovering && isEnabled ? 1.02 : 1)
        .brightness(hovering && isEnabled && !configuration.isPressed ? 0.08 : 0)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }

    // MARK: - Private

    private var controlHeight: Double {
        switch controlSize {
        case .mini: return 26
        case .small: return 30
        case .large: return 36
        default: return 32
        }
    }

    fileprivate var labelFont: Font {
        switch kind {
        case .primary, .brand:
            return .system(size: 13, weight: .medium)
        case .secondary:
            return .system(size: 13, weight: .regular)
        }
    }
}

/// Liquid Glass rendering (macOS 26+). Tint carries the preset hierarchy:
/// ink-tinted for primary, neutral glass for secondary, blue for brand.
@available(macOS 26, *)
private struct GlassButtonLabel: View {
    var configuration: AppButtonStyle.Configuration
    var kind: AppButtonStyle.Kind
    var scheme: ColorScheme
    var font: Font
    var height: Double

    var body: some View {
        configuration.label
            .font(font)
            .padding(.horizontal, 14)
            .frame(height: height)
            .foregroundStyle(labelColor)
            .glassEffect(glass, in: .capsule)
    }

    private var labelColor: Color {
        switch kind {
        case .primary:
            return scheme == .dark ? .black : .white
        case .secondary:
            return Theme.ink(scheme)
        case .brand:
            return .white
        }
    }

    private var glass: Glass {
        switch kind {
        case .primary:
            // Ink-tinted glass keeps the monochrome hierarchy in glass.
            .regular.tint((scheme == .dark ? Color.white : Color.black).opacity(0.55)).interactive()
        case .secondary:
            .regular.interactive()
        case .brand:
            .regular.tint(Theme.brand(scheme)).interactive()
        }
    }
}

/// Pre-macOS 26 fallback: solid monochrome pills, same metrics as glass.
private struct LegacyButtonLabel: View {
    var configuration: AppButtonStyle.Configuration
    var kind: AppButtonStyle.Kind
    var scheme: ColorScheme
    var font: Font
    var height: Double

    var body: some View {
        configuration.label
            .font(font)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(fill(pressed: configuration.isPressed))
            .foregroundStyle(labelColor)
            .clipShape(Capsule())
    }

    private var labelColor: Color {
        switch kind {
        case .primary:
            return scheme == .dark ? .black : .white
        case .secondary:
            return Theme.ink(scheme)
        case .brand:
            return .white
        }
    }

    private func fill(pressed: Bool) -> Color {
        let base: Color = switch kind {
        case .primary: Theme.ink(scheme)
        case .secondary: Theme.panel2(scheme)
        case .brand: Theme.brand(scheme)
        }
        return pressed ? base.opacity(0.75) : base
    }
}

// MARK: - AppButtonStyle Kind

extension AppButtonStyle {
    enum Kind {
        case primary
        case secondary
        case brand
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var appPrimary: AppButtonStyle { AppButtonStyle(kind: .primary) }
    static var appSecondary: AppButtonStyle { AppButtonStyle(kind: .secondary) }
    static var appBrand: AppButtonStyle { AppButtonStyle(kind: .brand) }
}

// MARK: - Showing Cards

/// Prescriptive container: grouped card with a hairline border.
/// Callers own the content; the card owns structure. Background can be
/// overridden with `.cardBackgroundStyle(_:)` — any `ShapeStyle` (Color,
/// gradient, material) — with the closest modifier winning; unset falls
/// back to the theme panel.
///
/// - macOS 26+: frosted Liquid Glass (`glassEffect(.regular)`) when no
///   explicit background style is set; an explicit style renders as a
///   tinted glass fill so custom cards stay glassy too.
/// - Older macOS: solid theme panel + hairline border.
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.cardBackgroundStyle) private var backgroundStyle
    private let bordered: Bool
    private let content: Content

    init(bordered: Bool = true, @ViewBuilder content: () -> Content) {
        self.bordered = bordered
        self.content = content()
    }

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                content
                    .background(glassBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(stroke)
            } else {
                content
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(stroke)
            }
        }
    }

    @ViewBuilder
    private var stroke: some View {
        if bordered {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border(scheme), lineWidth: 1)
        }
    }

    private var cardBackground: AnyShapeStyle {
        if let backgroundStyle {
            AnyShapeStyle(backgroundStyle)
        } else {
            AnyShapeStyle(Theme.panel(scheme))
        }
    }

    @available(macOS 26, *)
    private var glassBackground: some View {
        Group {
            if let backgroundStyle {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AnyShapeStyle(backgroundStyle))
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.panel(scheme))
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
        }
    }
}

extension EnvironmentValues {
    var cardBackgroundStyle: (any ShapeStyle)? {
        get { self[CardBackgroundStyleKey.self] }
        set { self[CardBackgroundStyleKey.self] = newValue }
    }
}

private struct CardBackgroundStyleKey: EnvironmentKey {
    static let defaultValue: (any ShapeStyle)? = nil
}

extension View {
    /// Override the `Card` background. Follows normal environment
    /// precedence: closest modifier wins, unset uses the theme panel.
    func cardBackgroundStyle(_ style: some ShapeStyle) -> some View {
        environment(\.cardBackgroundStyle, style)
    }

    /// One-liner card background for existing call sites.
    /// Prefer `Card { ... }` for new code so structure is explicit.
    func card() -> some View {
        modifier(CardModifier())
    }
}

struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.cardBackgroundStyle) private var backgroundStyle

    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26, *) {
                content
                    .background(glassBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.border(scheme), lineWidth: 1)
                    )
            } else {
                content
                    .background(background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.border(scheme), lineWidth: 1)
                    )
            }
        }
    }

    private var background: AnyShapeStyle {
        if let backgroundStyle {
            AnyShapeStyle(backgroundStyle)
        } else {
            AnyShapeStyle(Theme.panel(scheme))
        }
    }

    @available(macOS 26, *)
    private var glassBackground: some View {
        Group {
            if let backgroundStyle {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AnyShapeStyle(backgroundStyle))
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.panel(scheme))
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Acting with Glass Buttons

/// System Liquid Glass button with a theme tint: prominent actions default
/// to the brand blue, secondary actions stay neutral unless given a `tint`.
/// Pre-26 falls back to the bordered styles with the same hierarchy.
struct GlassActionButton: View {
    @Environment(\.colorScheme) private var scheme
    var title: String
    var systemImage: String? = nil
    var prominent: Bool = false
    var tint: Color? = nil
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                if prominent {
                    Button(action: action) { buttonLabel() }
                        .buttonStyle(.glassProminent)
                        .tint(tint ?? Theme.brand(scheme))
                } else if let tint {
                    Button(action: action) { buttonLabel() }
                        .buttonStyle(.glass)
                        .tint(tint)
                } else {
                    Button(action: action) { buttonLabel() }
                        .buttonStyle(.glass)
                }
            } else if prominent {
                Button(action: action) { buttonLabel() }
                    .buttonStyle(.borderedProminent)
                    .tint(tint ?? Theme.brand(scheme))
            } else {
                Button(action: action) { buttonLabel() }
                    .buttonStyle(.bordered)
                    .tint(tint ?? Theme.ink(scheme))
            }
        }
        .disabled(disabled)
    }

    @ViewBuilder
    private func buttonLabel() -> some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

// MARK: - Applying Toolbar Priorities

/// Pushes SwiftUI toolbar order into the native `NSToolbarItem`
/// `visibilityPriority` (SwiftUI exposes no such modifier — the same-named
/// knob lives on the native item these `ToolbarItem`s become), so a narrow
/// window collapses low-priority items into the overflow menu first.
/// Skips when the window toolbar isn't installed yet or the item count
/// doesn't match, and no-ops when priorities are already correct (views
/// re-render often, so repeated calls must be cheap).
struct ToolbarPrioritySetter: NSViewRepresentable {
    var priorities: [NSToolbarItem.VisibilityPriority]

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { Self.apply(priorities, from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(priorities, from: nsView) }
    }

    static func apply(_ priorities: [NSToolbarItem.VisibilityPriority], from view: NSView) {
        guard let items = view.window?.toolbar?.items, items.count == priorities.count else { return }
        for (item, priority) in zip(items, priorities) where item.visibilityPriority != priority {
            item.visibilityPriority = priority
        }
    }
}

// MARK: - Choosing Speed Units

/// Speed unit for statistics. Persisted in UserDefaults and shared through
/// the environment so every speed readout stays consistent.
enum SpeedUnit: String, Sendable, CaseIterable {
    case wpm
    case cpm

    /// WPM counts 5-character words; char/min counts raw characters.
    var factor: Double {
        self == .cpm ? 5 : 1
    }

    /// Short unit label key (`wpm_unit` / `cpm_unit` in the lang packs).
    var unitKey: String {
        self == .cpm ? "cpm_unit" : "wpm_unit"
    }

    /// Segmented-control label key (`wpm_unit` / `cpm_name` in the lang packs).
    var nameKey: String {
        self == .cpm ? "cpm_name" : "wpm_unit"
    }

    func format(_ wpm: Double) -> String {
        String(format: "%.1f", wpm * factor)
    }
}

extension EnvironmentValues {
    var speedUnit: SpeedUnit {
        get { self[SpeedUnitKey.self] }
        set { self[SpeedUnitKey.self] = newValue }
    }
}

private struct SpeedUnitKey: EnvironmentKey {
    static let defaultValue: SpeedUnit = .wpm
}

// MARK: - Switching Views in a Pill

/// One segment option. `title` stays `String` (not `LocalizedStringResource`)
/// because this app localizes through its own `lang/*.json` packs via
/// `AppState.t(_:)`, not through String Catalogs.
struct CapsuleSwitchOption<Value: Hashable & Sendable>: Sendable {
    var value: Value
    var title: String
    var iconName: String
}

/// Prescriptive segmented pill: the form is fixed (options are always
/// icon + label segments in a capsule), so callers configure it with data,
/// not appearance flags. Selection is a `Binding` because the caller owns
/// it; nothing else is mutable from outside.
struct CapsuleSwitcher<Value: Hashable & Sendable>: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: Value
    var options: [CapsuleSwitchOption<Value>]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.iconName)
                            .font(.system(size: 12))
                            .accessibilityHidden(true)
                        Text(option.title)
                            .font(.system(size: 12, weight: isSelected(option) ? .medium : .regular))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(isSelected(option) ? Theme.ink(scheme) : .clear, in: Capsule())
                    .foregroundStyle(
                        isSelected(option)
                            ? (scheme == .dark ? Color.black : Color.white)
                            : Theme.muted(scheme)
                    )
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(3)
        .background(Theme.panel2(scheme), in: Capsule())
    }

    // MARK: - Private

    private func isSelected(_ option: CapsuleSwitchOption<Value>) -> Bool {
        option.value == selection
    }
}

// MARK: - Showing Toolbar Metrics

/// Small `TIME 0:00 / ACCURACY 100% / SPEED` readout used in the lesson
/// toolbar. Label sits beside the value (not above) so the trio breathes.
///
/// Leaf view. `title`/`value` stay `String` (not `LocalizedStringResource`)
/// because this app localizes through its own `lang/*.json` packs via
/// `AppState.t(_:)`, not through String Catalogs.
struct MetricView: View {
    @Environment(\.colorScheme) private var scheme
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted(scheme))
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink(scheme))
                .monospacedDigit()
        }
        .frame(minWidth: 76)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title), \(value)"))
    }
}

// MARK: - Showing Score Gauges

/// Native `Gauge` in the linear-capacity style with the app's label/value
/// columns. Prescriptive: structure is fixed, only the fill can vary.
/// Pass any `ShapeStyle` as `tint` (Color, gradient); nil falls back to
/// the monochrome ink. Precedence: explicit `tint` argument wins.
struct GaugeView: View {
    @Environment(\.colorScheme) private var scheme
    var label: String
    var display: String
    var quality: Double
    var tint: AnyShapeStyle? = nil

    /// Backward-compatible flag-based init. Prefer `tint:` with an
    /// explicit `ShapeStyle`.
    init(label: String, display: String, quality: Double, accented: Bool) {
        self.label = label
        self.display = display
        self.quality = quality
        self.tint = nil
        self.accentedFallback = accented
    }

    init(label: String, display: String, quality: Double) {
        self.label = label
        self.display = display
        self.quality = quality
        self.tint = nil
        self.accentedFallback = false
    }

    init<S: ShapeStyle>(label: String, display: String, quality: Double, tint: S) {
        self.label = label
        self.display = display
        self.quality = quality
        self.tint = AnyShapeStyle(tint)
        self.accentedFallback = false
    }

    private var accentedFallback: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.muted(scheme))
                .frame(width: 145, alignment: .leading)
            Gauge(value: min(1, max(0, quality)), in: 0...1) {
                EmptyView()
            }
            .gaugeStyle(.linearCapacity)
            .tint(resolvedTint)
            Text(display)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink(scheme))
                .frame(width: 115, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label), \(display)"))
    }

    private var resolvedTint: AnyShapeStyle {
        if let tint { return tint }
        if accentedFallback { return AnyShapeStyle(Theme.brand(scheme)) }
        return AnyShapeStyle(Theme.ink(scheme))
    }
}

// MARK: - Showing Star Ratings

/// Display-only 1–5 star rating for a 0–100 lesson score.
/// Prescriptive: always stars (SF Symbols, filled vs. outline so color is
/// never the only differentiator). Invalid states are unrepresentable:
/// `rating` is clamped to `1...maximum`.
struct StarsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    private let rating: Int
    private let maximum: Int

    /// Primary init: already-normalized rating.
    init(rating: Int, maximum: Int = 5) {
        self.maximum = max(1, maximum)
        self.rating = min(self.maximum, max(1, rating))
    }

    /// Convenience: map a 0–100 overall score to 1–5 stars.
    init(score: Double) {
        let maximum = 5
        self.maximum = maximum
        self.rating = max(1, min(maximum, Int((score / 20).rounded())))
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<maximum, id: \.self) { index in
                Image(systemName: index < rating ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(index < rating ? Theme.brand(scheme) : Theme.pending(scheme))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(rating) of \(maximum) stars"))
        .accessibilityValue(Text("\(rating)"))
    }
}
