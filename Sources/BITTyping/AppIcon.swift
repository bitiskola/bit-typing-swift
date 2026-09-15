import AppKit
import Foundation

// MARK: - Loading the Brand Icon

extension NSImage {
    /// Bundled `favico.png`, shared by the top bar, setup, and about views.
    @MainActor static var bitAppIcon: NSImage {
        if let cached = Cache.icon { return cached }
        // NOTE: `Bundle.module` fatalErrors when the resource bundle is
        // missing (relocated .app); use the optional lookup so a missing
        // icon degrades to empty instead of crashing at launch.
        if let url = AppResources.url(forResource: "favico", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        {
            Cache.icon = image
            return image
        }
        let empty = NSImage()
        Cache.icon = empty
        return empty
    }

    // MARK: - Private

    private enum Cache {
        nonisolated(unsafe) static var icon: NSImage? = nil
    }
}
