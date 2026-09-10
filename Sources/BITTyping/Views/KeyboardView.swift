import SwiftUI

// MARK: - Showing the Virtual Keyboard

/// Full-size touch-typing keyboard: number row, Tab / Caps / Shift /
/// Enter / Backspace, bottom modifier row, and a wide space bar — keys
/// offset and proportioned exactly like physical hardware (1u letters,
/// 1.5u Tab, 1.75u Caps, 2–2.75u shifts, 6.25u space). Each row fills the
/// board edge to edge with proportional widths, so rows align like sheet
/// metal, not staggered approximations. The next expected key (letter,
/// space, Tab, or Enter) fills with ink, mirroring `highlight_key()` in
/// `main.py`.
struct KeyboardView: View {
    var layout: KeyboardLayout
    var activeChar: String

    /// Fixed board width in key units — the ANSI/ISO 15u standard.
    private let totalUnits = 15.0

    var body: some View {
        GeometryReader { proxy in
            let boardWidth = min(proxy.size.width, 920)
            let rows = boardRows
            let metrics = Metrics(boardWidth: boardWidth)
            VStack(spacing: metrics.rowGap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    // Each row sums to 15u by construction; the unit divides
                    // the board minus this row's gaps so rows align exactly.
                    let unit = (boardWidth - metrics.gap * Double(max(0, row.count - 1))) / totalUnits
                    HStack(spacing: metrics.gap) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, spec in
                            Keycap(
                                spec.label,
                                kind: spec.kind,
                                zone: spec.zone,
                                isActive: isActive(spec),
                                width: max(0, spec.units * unit),
                                height: metrics.keyHeight,
                                fontSize: spec.kind == .modifier
                                    ? metrics.modifierFont : metrics.fontSize
                            )
                        }
                    }
                    .frame(width: boardWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
    }

    // MARK: - Private

    private func isActive(_ spec: KeySpec) -> Bool {
        guard let expected = spec.expects, !activeChar.isEmpty else { return false }
        return expected.lowercased() == activeChar.lowercased()
    }

    /// Five hardware rows built from the layout's four letter rows plus a
    /// fixed bottom modifier row. Trailing widths absorb each row to
    /// exactly 15u; a 13-key QWERTY row widens its final `|\` key to 1.5u
    /// like real ANSI hardware instead of adding a sliver key.
    private var boardRows: [[KeySpec]] {
        let letterRows = layout.rows
        guard letterRows.count >= 4 else { return [] }
        let numbers = letterRows[0]
        let upper = letterRows[1]
        let home = letterRows[2]
        let lower = letterRows[3]

        var rows: [[KeySpec]] = []

        // Number row + 2u Backspace.
        rows.append(
            letterKeys(numbers, row: 0)
                + [KeySpec("Backspace", units: totalUnits - Double(numbers.count), zone: .pinky, kind: .modifier)]
        )

        // Tab row: 1.5u Tab, then letters. A 13-key row (ANSI `|\`) widens
        // its final key to 1.5u like real hardware; otherwise a plain
        // trailing key fills the row to 15u.
        var upperSpecs = [KeySpec("Tab", units: 1.5, zone: .pinky, kind: .modifier, expects: "\t")]
        var upperLetters = letterKeys(upper, row: 1)
        var upperTrailing = totalUnits - 1.5 - Double(upper.count)
        if upperTrailing < 1.25, !upperLetters.isEmpty {
            upperLetters[upperLetters.count - 1].units = 1.5
            upperTrailing = totalUnits - 1.5 - (Double(upperLetters.count) - 1) - 1.5
        }
        upperSpecs += upperLetters
        if upperTrailing > 0.01 {
            upperSpecs.append(KeySpec("", units: upperTrailing, zone: .pinky, kind: .modifier))
        }
        rows.append(upperSpecs)

        // Home row: 1.75u Caps, letters, Enter fills the rest.
        rows.append(
            [KeySpec("Caps", units: 1.75, zone: .pinky, kind: .modifier)]
                + letterKeys(home, row: 2)
                + [KeySpec("Enter", units: totalUnits - 1.75 - Double(home.count), zone: .pinky, kind: .modifier, expects: "\n")]
        )

        // Bottom letter row: 2.25u Shift, letters, wide right Shift.
        rows.append(
            [KeySpec("Shift", units: 2.25, zone: .pinky, kind: .modifier)]
                + letterKeys(lower, row: 3)
                + [KeySpec("Shift", units: totalUnits - 2.25 - Double(lower.count), zone: .pinky, kind: .modifier)]
        )

        // Modifier row: Ctrl Win Alt | space | Alt Win Menu Ctrl.
        let edge = 1.25
        let edges = edge * 7
        rows.append([
            KeySpec("Ctrl", units: edge, zone: .pinky, kind: .modifier),
            KeySpec("Win", units: edge, zone: .pinky, kind: .modifier),
            KeySpec("Alt", units: edge, zone: .pinky, kind: .modifier),
            KeySpec(
                layout.spaceLabel.isEmpty ? "SPACE" : layout.spaceLabel,
                units: totalUnits - edges,
                zone: .thumb,
                kind: .space,
                expects: " "
            ),
            KeySpec("Alt", units: edge, zone: .pinky, kind: .modifier),
            KeySpec("Win", units: edge, zone: .pinky, kind: .modifier),
            KeySpec("Menu", units: edge, zone: .pinky, kind: .modifier),
            KeySpec("Ctrl", units: edge, zone: .pinky, kind: .modifier),
        ])

        return rows
    }

    private func letterKeys(_ keys: [String], row: Int) -> [KeySpec] {
        keys.enumerated().map { column, key in
            KeySpec(
                key.uppercased(),
                units: 1,
                zone: fingerZone(row: row, column: column, count: keys.count),
                kind: .key,
                expects: key
            )
        }
    }

    private struct Metrics {
        var gap: Double
        var rowGap: Double
        var keyHeight: Double
        var fontSize: Double
        var modifierFont: Double

        init(boardWidth: Double) {
            self.gap = 6.0
            self.rowGap = 7
            // Nominal unit off a full 15-key row; heights stay uniform.
            let unit = max(20, (boardWidth - gap * 14) / 15.0)
            self.keyHeight = min(42, max(30, unit * 0.66))
            self.fontSize = min(16, max(10, keyHeight * 0.42))
            self.modifierFont = min(12, max(9, keyHeight * 0.3))
        }
    }
}

// MARK: - Describing Physical Keys

/// One hardware key: display label, width in key units, finger zone, and
/// which lesson character (if any) lights it up.
private struct KeySpec {
    var label: String
    var units: Double
    var zone: FingerZone
    var kind: KeyKind
    var expects: String?

    init(_ label: String, units: Double, zone: FingerZone, kind: KeyKind, expects: String? = nil) {
        self.label = label
        self.units = units
        self.zone = zone
        self.kind = kind
        self.expects = expects
    }
}

// MARK: - Mapping Fingers

/// Touch-typing finger (left/right share a tint — the classic 4-color
/// tutor scheme — plus the thumb on the space bar).
enum FingerZone {
    case pinky
    case ring
    case middle
    case index
    case thumb
}

/// Subtle pastel per finger (neutral keycap for the thumb/space bar),
/// shared by the keycaps and the legend in `LessonView`.
func fingerTint(_ zone: FingerZone, scheme: ColorScheme) -> Color {
    let light = scheme == .light
    switch zone {
    case .pinky: return light ? Color(red: 0.843, green: 0.902, blue: 0.969) : Color(red: 0.169, green: 0.235, blue: 0.322)
    case .ring: return light ? Color(red: 0.839, green: 0.929, blue: 0.867) : Color(red: 0.161, green: 0.251, blue: 0.204)
    case .middle: return light ? Color(red: 0.957, green: 0.925, blue: 0.824) : Color(red: 0.290, green: 0.259, blue: 0.153)
    case .index: return light ? Color(red: 0.949, green: 0.855, blue: 0.824) : Color(red: 0.306, green: 0.200, blue: 0.169)
    case .thumb: return Theme.keycap(scheme)
    }
}
/// Standard finger per key position. Exact maps for the usual 4-row
/// shapes; proportional fallback for anything else (e.g. custom layouts
/// with different row lengths) so every key still gets a sensible zone.
private func fingerZone(row: Int, column: Int, count: Int) -> FingerZone {
    let standard: [[FingerZone]] = [
        [.pinky, .pinky, .ring, .middle, .index, .index, .index, .index, .middle, .ring, .pinky, .pinky, .pinky],
        [.pinky, .ring, .middle, .index, .index, .index, .index, .middle, .ring, .pinky, .pinky, .pinky, .pinky],
        [.pinky, .ring, .middle, .index, .index, .index, .index, .middle, .ring, .pinky, .pinky],
        [.pinky, .ring, .middle, .index, .index, .index, .index, .middle, .ring, .pinky],
    ]
    if row < standard.count, standard[row].count == count {
        return standard[row][column]
    }
    guard count > 1 else { return .index }
    let position = Double(column) / Double(count - 1)
    switch position {
    case ..<0.125: return .pinky
    case ..<0.25: return .ring
    case ..<0.375: return .middle
    case ..<0.625: return .index
    case ..<0.75: return .middle
    case ..<0.875: return .ring
    default: return .pinky
    }
}

// MARK: - Private

/// Single keycap tinted by finger zone. Leaf view with dedicated
/// initializers per role instead of combinable boolean flags:
/// `.key` shows a finger tint, `.space` stays neutral, `.modifier` uses
/// the plain keycap surface. `isActive` (the next expected key) overrides
/// the tint with the ink fill.
private struct Keycap: View {
    @Environment(\.colorScheme) private var scheme
    var label: String
    var kind: KeyKind
    var zone: FingerZone
    var isActive: Bool
    var width: Double
    var height: Double
    var fontSize: Double

    init(
        _ label: String,
        kind: KeyKind = .key,
        zone: FingerZone = .index,
        isActive: Bool,
        width: Double,
        height: Double,
        fontSize: Double
    ) {
        self.label = label
        self.kind = kind
        self.zone = zone
        self.isActive = isActive
        self.width = width
        self.height = height
        self.fontSize = fontSize
    }

    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: isActive ? .bold : .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(
                isActive
                    ? (scheme == .dark ? Color.black : Color.white)
                    : (kind == .key ? Theme.ink(scheme) : Theme.muted(scheme))
            )
            .frame(width: width, height: height)
            // Square keycaps: no corner radius, no hairline, no shadow —
            // just the flat finger tint so the board reads as one open
            // surface. The next key is the ink fill.
            .background(isActive ? Theme.ink(scheme) : fill)
            .accessibilityHidden(!isActive)
            .accessibilityLabel(isActive ? Text("Next key \(label)") : Text(label))
    }

    /// Subtle pastel per finger; neutral surfaces for space and modifiers.
    private var fill: Color {
        if kind == .key { return fingerTint(zone, scheme: scheme) }
        if kind == .space { return Theme.keycap(scheme) }
        return Theme.panel2(scheme)
    }
}

// MARK: - Keycap Kind

enum KeyKind {
    case key
    case space
    case modifier
}
