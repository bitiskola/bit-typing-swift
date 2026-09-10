import AppKit
import SwiftUI

// MARK: - Capturing Physical Keystrokes

/// Window-level key monitors that forward physical key events to the typing
/// engine. Monitors see events before the responder chain, so typing keeps
/// working after clicking toolbar buttons. Events stay untouched while a
/// text field, the editor, or any sheet owns focus, and unconsumed events
/// (e.g. with auto-start off) pass through to the normal responder chain.
struct KeyCaptureView: NSViewRepresentable {
    var onEvent: (KeyInput) -> Bool
    var onRestart: () -> Void = {}

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.onEvent = onEvent
        context.coordinator.onRestart = onRestart
        context.coordinator.install()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.onRestart = onRestart
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Internal

    final class Coordinator {
        var onEvent: ((KeyInput) -> Bool)? = nil
        var onRestart: (() -> Void)? = nil
        private var monitors: [Any] = []

        func install() {
            uninstall()
            monitors.append(
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    // Command+R restarts the lesson (Tk `<Control-r>` binding).
                    if event.modifierFlags.contains(.command),
                        event.charactersIgnoringModifiers?.lowercased() == "r"
                    {
                        self.onRestart?()
                        return nil
                    }
                    if Self.isEditingOnMain() { return event }
                    // Escape pauses/resumes.
                    if event.keyCode == 53 {
                        return self.consume(.escape) ? nil : event
                    }
                    // Backspace (delete / forward-delete).
                    if event.keyCode == 51 || event.keyCode == 117 {
                        return self.consume(.backspace) ? nil : event
                    }
                    // Return / keypad-enter produce a newline character.
                    if event.keyCode == 36 || event.keyCode == 76 {
                        return self.consume(.character("\n")) ? nil : event
                    }
                    // Tab lesson character.
                    if event.keyCode == 48 {
                        return self.consume(.character("\t")) ? nil : event
                    }
                    if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                        return event
                    }
                    guard let chars = event.characters, !chars.isEmpty else { return event }
                    let text = chars == "\r" ? "\n" : chars
                    return self.consume(.character(text)) ? nil : event
                } as Any
            )
            monitors.append(
                NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                    guard let self, !Self.isEditingOnMain() else { return event }
                    let name: String? = switch event.keyCode {
                    case 56, 60: "Shift_L"
                    case 58, 61: "Alt_L"
                    case 59, 62: "Control_L"
                    case 55: "Command"
                    default: nil
                    }
                    if let name, self.consume(.systemKey(name)) { return nil }
                    return event
                } as Any
            )
        }

        func uninstall() {
            for monitor in monitors { NSEvent.removeMonitor(monitor) }
            monitors.removeAll()
        }

        deinit {
            uninstall()
        }

        // MARK: - Private

        private func consume(_ input: KeyInput) -> Bool {
            onEvent?(input) ?? false
        }

        /// True when a real editor owns focus — the engine must not steal keys.
        /// Local monitors always fire on the main thread, so assuming the
        /// main actor here is safe.
        private static func isEditingOnMain() -> Bool {
            MainActor.assumeIsolated(isEditing)
        }

        @MainActor
        private static func isEditing() -> Bool {
            guard let window = NSApp.keyWindow, let responder = window.firstResponder as? NSView else {
                return false
            }
            var view: NSView? = responder
            while let current = view {
                if current is NSTextView || current is NSTextField { return true }
                view = current.superview
            }
            return false
        }
    }
}
